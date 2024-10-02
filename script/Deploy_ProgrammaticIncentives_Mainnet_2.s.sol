// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Script.sol";

import "eigenlayer-contracts/script/utils/ExistingDeploymentParser.sol";

import "test/ProgrammaticIncentives.t.sol";

interface IEigenDAStakeRegistry {

    function strategyParamsByIndex(uint8 quorumNumber, uint256 index) external view returns(address, uint96);

    function strategyParamsLength(uint8 quorumNumber) external view returns(uint256);
}

// forge script script/Deploy_ProgrammaticIncentives_Mainnet_2.s.sol:Deploy_ProgrammaticIncentives_Mainnet_2 -vvvv --private-key $PRIVATE_KEY --broadcast
contract Deploy_ProgrammaticIncentives_Mainnet_2 is Script, ProgrammaticIncentivesTests {
    // system contracts
    ProxyAdmin public eigenLayerProxyAdmin;
    // TODO: only bEIGEN_ProxyAdmin is in mainnet config file
    ProxyAdmin public EIGEN_ProxyAdmin = ProxyAdmin(address(0xB8915E195121f2B5D989Ec5727fd47a5259F1CEC));
    ProxyAdmin public bEIGEN_ProxyAdmin = ProxyAdmin(address(0x3f5Ab2D4418d38568705bFd6672630fCC3435CC9));

    // strategies deployed
    uint256 public numStrategiesDeployed;
    StrategyBase[] public deployedStrategyArray;
    IStrategy public eigenStrategy;

    string public deploymentPath = "lib/eigenlayer-contracts/script/configs/mainnet/mainnet-addresses.config.json";
    uint256 public currentChainId;

    // weekly amounts
    uint256 public constant EIGEN_stakers_weekly_distribution = 321_855_128_516_280_769_230_770;
    uint256 public constant ETH_stakers_weekly_distribution = 965_565_385_548_842_307_692_308;

    uint256 public constant totalEigenSupply = 1673646668284660000000000000;
    uint256 public constant yearlyPercentageEigenStakers = 1;
    uint256 public constant yearlyPercentageEthStakers = 3;

    // existing set of contracts with retrospective instead of prospective distributions
    RewardAllStakersActionGenerator public previousActionGenerator =
        RewardAllStakersActionGenerator(0xF2eB394c4e04ff19422EB27411f78d00e216a88d);
    TokenHopper public previousTokenHopper = TokenHopper(0x708230Be53c08b270F43e068116EBacc4C13F577);

    // EigenDA info
    uint8 public ETH_QUORUM_NUMBER = 0;
    IEigenDAStakeRegistry public eigenDAStakeRegistry = IEigenDAStakeRegistry(0x006124Ae7976137266feeBFb3F4D2BE4C073139D);

    function setUp() public override {
        initialOwner = 0xbb00DDa2832850a43840A3A86515E3Fe226865F2;

        string memory forkUrl = vm.envString("RPC_MAINNET");
        uint256 forkId = vm.createFork(forkUrl);
        vm.selectFork(forkId);

        // read and log the chainID
        currentChainId = block.chainid;
        emit log_named_uint("You are parsing on ChainID", currentChainId);
        require(currentChainId == 1, "script is only for mainnet");

        // load existing, deployed addresses
        _parseDeployedContracts(deploymentPath);

        // set up strategy arrays and amounts array
        _amounts[0] = EIGEN_stakers_weekly_distribution;
        _amounts[1] = ETH_stakers_weekly_distribution;
        require(_amounts[0] < _amounts[1], "ETH stakers expected to get larger share of distribution");
        uint256 roundingMarginOfError = 100 wei;
        require(_amounts[0] * 52 < totalEigenSupply * yearlyPercentageEigenStakers / 100 + roundingMarginOfError,
            "EIGEN stakers getting too much");
        require(_amounts[0] * 52 > totalEigenSupply * yearlyPercentageEigenStakers / 100 - roundingMarginOfError,
            "EIGEN stakers getting too little");
        require(_amounts[1] * 52 < totalEigenSupply * yearlyPercentageEthStakers / 100 + roundingMarginOfError,
            "ETH stakers getting too much");
        require(_amounts[1] * 52 > totalEigenSupply * yearlyPercentageEthStakers / 100 - roundingMarginOfError,
            "ETH stakers getting too little");
        _strategiesAndMultipliers[0].push(IRewardsCoordinator.StrategyAndMultiplier({
            strategy: eigenStrategy,
            multiplier: 1e18
        }));
        for (uint256 i = 0; i < deployedStrategyArray.length; ++i) {
            _strategiesAndMultipliers[1].push(IRewardsCoordinator.StrategyAndMultiplier({
                strategy: deployedStrategyArray[i],
                multiplier: 0
            }));
        }

        // fetch multipliers from EigenDA's StakeRegistry
        uint256 strategyParamsLength = eigenDAStakeRegistry.strategyParamsLength(ETH_QUORUM_NUMBER);
        assertEq(strategyParamsLength, _strategiesAndMultipliers[1].length,
            "expected same number of strategies in ETH / LST bucket as EigenDA has in its config");
        for (uint256 i = 0; i < strategyParamsLength; ++i) {
            (address strategyAddress, uint96 multiplier) = eigenDAStakeRegistry.strategyParamsByIndex(ETH_QUORUM_NUMBER, i);
            for (uint256 j = 0; j < deployedStrategyArray.length; ++j) {
                // set the multiplier and break the inner loop if the strategies match
                if (strategyAddress == address(deployedStrategyArray[j])) {
                    _strategiesAndMultipliers[1][j].multiplier = multiplier;
                    break;
                }
            }
        }
        for (uint256 i = 0; i < _strategiesAndMultipliers.length; ++i) {
            for (uint256 j = 0; j < _strategiesAndMultipliers[i].length; ++j) {
                // emit log_named_uint("i", i);
                // emit log_named_uint("j", j);
                // emit log_named_address("address(_strategiesAndMultipliers[i][j].strategy)", address(_strategiesAndMultipliers[i][j].strategy));
                // emit log_named_uint("_strategiesAndMultipliers[i][j].multiplier", _strategiesAndMultipliers[i][j].multiplier);
                require(_strategiesAndMultipliers[i][j].multiplier != 0, "multiplier has not been set");
                require(_strategiesAndMultipliers[i][j].strategy != IStrategy(address(0)), "strategy address not set correctly");
            }
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
        test_pressButton();
        TokenHopper newHopper = tokenHopper;
        RewardAllStakersActionGenerator newActionGenerator = actionGenerator;
        tokenHopper = previousTokenHopper;
        actionGenerator = previousActionGenerator;
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
        emit log_named_string("- Last Updated", stdJson.readString(existingDeploymentData, ".lastUpdated"));

        // read all of the deployed addresses
        rewardsCoordinator = RewardsCoordinator(
            stdJson.readAddress(existingDeploymentData, ".addresses.rewardsCoordinator")
        );
        eigenLayerProxyAdmin = ProxyAdmin(stdJson.readAddress(existingDeploymentData, ".addresses.eigenLayerProxyAdmin"));
        emptyContract = EmptyContract(stdJson.readAddress(existingDeploymentData, ".addresses.emptyContract"));

        // Strategies Deployed, load strategy list
        numStrategiesDeployed = stdJson.readUint(existingDeploymentData, ".addresses.numStrategiesDeployed");
        address[] memory unsortedArray = new address[](numStrategiesDeployed + 1);
        for (uint256 i = 0; i < numStrategiesDeployed; ++i) {
            // Form the key for the current element
            string memory key = string.concat(".addresses.strategyAddresses[", vm.toString(i), "]");

            // Use the key and parse the strategy address
            address strategyAddress = abi.decode(stdJson.parseRaw(existingDeploymentData, key), (address));
            unsortedArray[i] = strategyAddress;
        }
        // push virtual "beacon chain ETH strategy" to array
        unsortedArray[unsortedArray.length - 1] = 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0;
        // sort array and push it to storage
        address[] memory sortedArray = _sortArrayAsc(unsortedArray);
        for (uint256 i = 0; i < sortedArray.length; ++i) {
            deployedStrategyArray.push(StrategyBase(sortedArray[i]));
        }
        require(deployedStrategyArray.length != 0, "reading from config is broken or config lacks strategy addresses");

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
        eigen = IEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.EIGEN"));
        eigenImpl = IEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.EIGENImpl"));
        beigen = IBackingEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.bEIGEN"));
        beigenImpl = IBackingEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.bEIGENImpl"));
        eigenStrategy = EigenStrategy(stdJson.readAddress(existingDeploymentData, ".addresses.token.eigenStrategy"));
    }
}
