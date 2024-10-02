// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Script.sol";

import "eigenlayer-contracts/script/utils/ExistingDeploymentParser.sol";

import "test/ProgrammaticIncentives.t.sol";

// forge script script/Deploy_ProgrammaticIncentives_PreProd_2.s.sol:Deploy_ProgrammaticIncentives_PreProd_2 -vvvv --private-key $PRIVATE_KEY --broadcast
contract Deploy_ProgrammaticIncentives_PreProd_2 is Script, ProgrammaticIncentivesTests {

    // strategies deployed
    uint256 public numStrategiesDeployed;
    StrategyBase[] public deployedStrategyArray;
    IStrategy public eigenStrategy;

    string public deploymentPath = "lib/eigenlayer-contracts/script/configs/holesky/eigenlayer_addresses_preprod.config.json";
    uint256 public currentChainId;

    // existing set of contracts with retrospective instead of prospective distributions
    RewardAllStakersActionGenerator public previousActionGenerator =
        RewardAllStakersActionGenerator(0x89ef1267996a3a93A31D4689dE15C9c6cc6612c7);
    TokenHopper public previousTokenHopper = TokenHopper(0x2B35f55ad87900Db6479AEdD9eB2c53C58cf85d9);

    function setUp() public override {
        string memory forkUrl = vm.envString("RPC_HOLESKY");
        uint256 forkId = vm.createFork(forkUrl);
        vm.selectFork(forkId);

        // read and log the chainID
        currentChainId = block.chainid;
        emit log_named_uint("You are parsing on ChainID", currentChainId);

        // load existing, deployed addresses
        _parseDeployedContracts(deploymentPath);

        // set up strategy arrays and amounts array
        _amounts[0] = previousActionGenerator.amounts(0);
        _amounts[1] = previousActionGenerator.amounts(1);
        _strategiesAndMultipliers[0].push(IRewardsCoordinator.StrategyAndMultiplier({
            strategy: eigenStrategy,
            multiplier: 1e18
        }));
        for (uint256 i = 0; i < deployedStrategyArray.length; ++i) {
            _strategiesAndMultipliers[1].push(IRewardsCoordinator.StrategyAndMultiplier({
                strategy: deployedStrategyArray[i],
                // TODO: correct multipliers!
                multiplier: 1e18
            }));
        }

        deployContracts();

        // give tokenHopper bEIGEN minting permission
        cheats.startPrank(Ownable(address(beigen)).owner());
        beigen.setIsMinter(address(tokenHopper), true);
        cheats.stopPrank();

        // give tokenHopper `isRewardsForAllSubmitter` status on RewardsCoordinator
        cheats.startPrank(Ownable(address(rewardsCoordinator)).owner());
        rewardsCoordinator.setRewardsForAllSubmitter(address(tokenHopper), true);
        cheats.stopPrank();
    }

    function run() public {
        cheats.startBroadcast();
        deployContracts();
        cheats.stopBroadcast();
    }

    function deployContracts() public {
        // deploy ActionGenerator & Hopper
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: rewardsCoordinator,
            _firstSubmissionStartTimestamp: previousActionGenerator.firstSubmissionStartTimestamp(),
            _firstSubmissionTriggerCutoff: previousActionGenerator.firstSubmissionTriggerCutoff(),
            _amounts: _amounts,
            _strategiesAndMultipliers: _strategiesAndMultipliers,
            _bEIGEN: beigen,
            _EIGEN: eigen
        });

        // fetch config from previous deployment, but replace the action generator
        ITokenHopper.HopperConfiguration memory hopperConfiguration = previousTokenHopper.getHopperConfiguration();
        hopperConfiguration.actionGenerator = address(actionGenerator);

        tokenHopper = new TokenHopper({
            config: hopperConfiguration,
            initialOwner: initialOwner
        });
    }

    function test_ProgrammaticIncentives_Deployment() public {
        // TODO: change this?
        cheats.warp(1727913601);

        IRewardsCoordinator.RewardsSubmission[] memory oldHopperRewardsSubmissions;
        IHopperActionGenerator.HopperAction[] memory oldHopperActions =
            previousActionGenerator.generateHopperActions(address(previousTokenHopper), address(eigen));
        bytes memory rewardsSubmissionsRaw = this.sliceOffLeadingFourBytes(oldHopperActions[4].callData);
        oldHopperRewardsSubmissions = abi.decode(
            rewardsSubmissionsRaw,
            (IRewardsCoordinator.RewardsSubmission[])
        );
        
        IRewardsCoordinator.RewardsSubmission[] memory newHopperRewardsSubmissions;
        IHopperActionGenerator.HopperAction[] memory newHopperActions =
            actionGenerator.generateHopperActions(address(tokenHopper), address(eigen));
        rewardsSubmissionsRaw = this.sliceOffLeadingFourBytes(newHopperActions[4].callData);
        newHopperRewardsSubmissions = abi.decode(
            rewardsSubmissionsRaw,
            (IRewardsCoordinator.RewardsSubmission[])
        );

        for (uint256 i = 0; i < newHopperRewardsSubmissions.length; ++i) {
            assertEq(newHopperRewardsSubmissions[i].amount, oldHopperRewardsSubmissions[i].amount,
                "amounts do not match");
            for (uint256 j = 0; j < newHopperRewardsSubmissions[i].strategiesAndMultipliers.length; ++j) {
                assertEq(uint256(
                    newHopperRewardsSubmissions[i].strategiesAndMultipliers[j].multiplier),
                    uint256(oldHopperRewardsSubmissions[i].strategiesAndMultipliers[j].multiplier),
                    "multipliers do not match"
                );
                assertEq(
                    address(newHopperRewardsSubmissions[i].strategiesAndMultipliers[j].strategy),
                    address(oldHopperRewardsSubmissions[i].strategiesAndMultipliers[j].strategy),
                    "strategies do not match"
                );
            }
            assertEq(address(newHopperRewardsSubmissions[i].token), address(oldHopperRewardsSubmissions[i].token),
                "tokens do not match");
            assertEq(newHopperRewardsSubmissions[i].duration, oldHopperRewardsSubmissions[i].duration,
                "durations do not match");
            assertEq(newHopperRewardsSubmissions[i].startTimestamp, oldHopperRewardsSubmissions[i].startTimestamp + 1 weeks,
                "start timestamps are not different by exactly one week");
        }

        // press button on new hopper and then old hopper
        // test_pressButton(); fails on preprod because an event has a bug in it in the old deployment
        test_pressButton();        
        TokenHopper newHopper = tokenHopper;
        RewardAllStakersActionGenerator newActionGenerator = actionGenerator;
        tokenHopper = previousTokenHopper;
        actionGenerator = previousActionGenerator;
        // test_pressButton(); fails on preprod because an event has a bug in it in the old deployment
        // tokenHopper.pressButton();
        test_pressButton();        
    }

    // taken from ExistingDeploymentParser; edited to resolve compiler errors due to duplicate storage with ProgrammaticIncentivesTests
    /// @notice use for parsing already deployed EigenLayer contracts
    function _parseDeployedContracts(string memory existingDeploymentInfoPath) internal virtual {

        // READ JSON CONFIG DATA
        string memory existingDeploymentData = vm.readFile(existingDeploymentInfoPath);

        // check that the chainID matches the one in the config
        uint256 configChainId = stdJson.readUint(existingDeploymentData, ".chainInfo.chainId");
        require(configChainId == currentChainId, "You are on the wrong chain for this config");

        emit log_named_string("Using addresses file", existingDeploymentInfoPath);
        // TODO: this is not in the preprod config file
        // emit log_named_string("- Last Updated", stdJson.readString(existingDeploymentData, ".lastUpdated"));

        // read all of the deployed addresses
        rewardsCoordinator = RewardsCoordinator(
            stdJson.readAddress(existingDeploymentData, ".addresses.rewardsCoordinator")
        );
        emptyContract = EmptyContract(stdJson.readAddress(existingDeploymentData, ".addresses.emptyContract"));

        // Strategies Deployed, load strategy list
        // numStrategiesDeployed = stdJson.readUint(existingDeploymentData, ".addresses.numStrategiesDeployed");
        // for (uint256 i = 0; i < numStrategiesDeployed; ++i) {
        //     // Form the key for the current element
        //     string memory key = string.concat(".addresses.strategyAddresses[", vm.toString(i), "]");

        //     // Use the key and parse the strategy address
        //     address strategyAddress = abi.decode(stdJson.parseRaw(existingDeploymentData, key), (address));
        //     deployedStrategyArray.push(StrategyBase(strategyAddress));
        // }
        // TODO: above is broken because array in config is empty -- this is the WETH Strategy address and "BeaconChainETH Strategy"
        deployedStrategyArray.push(StrategyBase(address(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0)));
        deployedStrategyArray.push(StrategyBase(address(0xD523267698C81a372191136e477fdebFa33D9FB4)));

        // check for ordering
        address currAddress = address(0);
        for (uint256 i = 0; i < deployedStrategyArray.length; ++i) {
            IStrategy strategy = deployedStrategyArray[i];
            require(
                currAddress < address(strategy),
                "strategies must be in ascending order for submission"
            );
            currAddress = address(strategy);
        }

        // token
        proxyAdmin = ProxyAdmin(stdJson.readAddress(existingDeploymentData, ".addresses.token.tokenProxyAdmin"));
        eigen = IEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.EIGEN"));
        eigenImpl = IEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.EIGENImpl"));
        beigen = IBackingEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.bEIGEN"));
        beigenImpl = IBackingEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.bEIGENImpl"));
        eigenStrategy = EigenStrategy(stdJson.readAddress(existingDeploymentData, ".addresses.token.eigenStrategy"));
    }
}
