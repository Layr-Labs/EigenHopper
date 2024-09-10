// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Script.sol";

import "eigenlayer-contracts/script/utils/ExistingDeploymentParser.sol";

import "test/ProgrammaticIncentives.t.sol";

// forge script script/Deploy_ProgrammaticIncentives_PreProd.s.sol:Deploy_ProgrammaticIncentives_PreProd -vvvv --private-key $PRIVATE_KEY --broadcast
contract Deploy_ProgrammaticIncentives_PreProd is Script, ProgrammaticIncentivesTests {

    // strategies deployed
    uint256 public numStrategiesDeployed;
    StrategyBase[] public deployedStrategyArray;
    IStrategy public eigenStrategy;

    string public deploymentPath = "lib/eigenlayer-contracts/script/configs/holesky/eigenlayer_addresses_preprod.config.json";
    uint256 public currentChainId;

    // config
    // TODO: move config to file?
    // GMT: Thursday, August 15, 2024 12:00:00 AM
    uint32 public config_firstSubmissionStartTimestamp = 1723680000;
    // GMT: Thursday, October 3, 2024 12:00:00 AM
    uint256 public config_firstSubmissionTriggerCutoff = 1727913600;
    // GMT: Thursday, September 5, 2024 12:00:00 AM
    uint256 public config_startTime = 1725494400;
    // GMT: Thursday, March 27, 2025 12:00:00 AM
    uint256 public config_expirationTimestamp = 1743033600;

    uint256 public config_cooldownSeconds = 1 weeks;

    function setUp() public override {
        string memory forkUrl = vm.envString("RPC_HOLESKY");
        uint256 forkId = vm.createFork(forkUrl);
        vm.selectFork(forkId);

        // read and log the chainID
        currentChainId = block.chainid;
        emit log_named_uint("You are parsing on ChainID", currentChainId);

        // load existing, deployed addresses
        _parseDeployedContracts(deploymentPath);

        // deploy implementations
        beigenImpl = IBackingEigen(deployContractFromBytecode(
            abi.encodePacked(beigenCreationBytecode, abi.encode(address(eigen)))
        ));
        eigenImpl = IEigen(deployContractFromBytecode(
            abi.encodePacked(eigenCreationBytecode, abi.encode(address(beigen)))
        ));

        // upgrade proxies
        cheats.startPrank(proxyAdmin.owner());
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(eigen))), address(eigenImpl));
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(beigen))), address(beigenImpl));
        cheats.stopPrank();

        // set up strategy arrays and amounts array
        _amounts[0] = 1e24;
        _amounts[1] = 2e26;
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

        // give tokenHopper bEIGEN minting permission and disable transfer restrictions
        cheats.startPrank(Ownable(address(beigen)).owner());
        beigen.disableTransferRestrictions();
        beigen.setIsMinter(address(tokenHopper), true);
        cheats.stopPrank();

        // disable EIGEN transfer restrictions
        cheats.startPrank(Ownable(address(eigen)).owner());
        eigen.disableTransferRestrictions();
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
            _firstSubmissionStartTimestamp: config_firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: config_firstSubmissionTriggerCutoff,
            _amounts: _amounts,
            _strategiesAndMultipliers: _strategiesAndMultipliers,
            _bEIGEN: beigen,
            _EIGEN: eigen
        });

        ITokenHopper.HopperConfiguration memory hopperConfiguration = ITokenHopper.HopperConfiguration({
            token: address(eigen),
            startTime: config_startTime,
            cooldownSeconds: config_cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: config_expirationTimestamp 
        });
        tokenHopper = new TokenHopper({
            config: hopperConfiguration,
            initialOwner: initialOwner
        });
    }

    function test_ProgrammaticIncentives_Deployment() public {
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
