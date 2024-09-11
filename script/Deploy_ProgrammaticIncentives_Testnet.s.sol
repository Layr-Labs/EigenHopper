// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Script.sol";

import "eigenlayer-contracts/script/utils/ExistingDeploymentParser.sol";

import "test/ProgrammaticIncentives.t.sol";

// forge script script/Deploy_ProgrammaticIncentives_Testnet.s.sol:Deploy_ProgrammaticIncentives_Testnet -vvvv --private-key $PRIVATE_KEY --broadcast
contract Deploy_ProgrammaticIncentives_Testnet is Script, ProgrammaticIncentivesTests {

    // strategies deployed
    uint256 public numStrategiesDeployed;
    StrategyBase[] public deployedStrategyArray;
    IStrategy public eigenStrategy;

    string public deploymentPath = "lib/eigenlayer-contracts/script/configs/holesky/eigenlayer_addresses.config.json";
    uint256 public currentChainId;

    // Hopper config
    // GMT: Thursday, August 15, 2024 12:00:00 AM
    uint32 public hopperConfig_firstSubmissionStartTimestamp = 1723680000;
    // GMT: Saturday, September 14, 2024 12:00:00 AM
    uint256 public hopperConfig_firstSubmissionTriggerCutoff = 1726272000;
    // GMT: Thursday, September 5, 2024 12:00:00 AM
    uint256 public hopperConfig_startTime = 1725494400;
    // GMT: Thursday, March 27, 2025 12:00:00 AM
    uint256 public hopperConfig_expirationTimestamp = 1743033600;

    uint256 public hopperConfig_cooldownSeconds = 1 weeks;

    function setUp() public override {
        string memory forkUrl = vm.envString("RPC_HOLESKY");
        uint256 forkId = vm.createFork(forkUrl);
        vm.selectFork(forkId);

        // read and log the chainID
        currentChainId = block.chainid;
        emit log_named_uint("You are parsing on ChainID", currentChainId);
        require(currentChainId == 17000, "script is only for holesky");

        // load existing, deployed addresses
        _parseDeployedContracts(deploymentPath);

        // deploy implementations
        beigenImpl = IBackingEigen(deployContractFromBytecode(
            abi.encodePacked(beigenCreationBytecode, abi.encode(address(eigen)))
        ));
        eigenImpl = IEigen(deployContractFromBytecode(
            abi.encodePacked(eigenCreationBytecode, abi.encode(address(beigen)))
        ));
        rewardsCoordinatorImpl = new RewardsCoordinator({
            _delegationManager: rewardsCoordinator.delegationManager(),
            _strategyManager: rewardsCoordinator.strategyManager(),
            _CALCULATION_INTERVAL_SECONDS: 1 weeks,
            _MAX_REWARDS_DURATION: 10 weeks, 
            _MAX_RETROACTIVE_LENGTH: 24 weeks,
            _MAX_FUTURE_LENGTH: 30 days,
            __GENESIS_REWARDS_TIMESTAMP: GENESIS_REWARDS_TIMESTAMP
        });

        // upgrade proxies
        cheats.startPrank(proxyAdmin.owner());
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(eigen))), address(eigenImpl));
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(beigen))), address(beigenImpl));
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(rewardsCoordinator))), address(rewardsCoordinatorImpl));
        cheats.stopPrank();

        // set up strategy arrays and amounts array
        // TODO: correct amounts
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
            _firstSubmissionStartTimestamp: hopperConfig_firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: hopperConfig_firstSubmissionTriggerCutoff,
            _amounts: _amounts,
            _strategiesAndMultipliers: _strategiesAndMultipliers,
            _bEIGEN: beigen,
            _EIGEN: eigen
        });

        ITokenHopper.HopperConfiguration memory hopperConfiguration = ITokenHopper.HopperConfiguration({
            token: address(eigen),
            startTime: hopperConfig_startTime,
            cooldownSeconds: hopperConfig_cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: hopperConfig_expirationTimestamp 
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
        // TODO: this is not in the testnet config file
        // emit log_named_string("- Last Updated", stdJson.readString(existingDeploymentData, ".lastUpdated"));

        // read all of the deployed addresses
        rewardsCoordinator = RewardsCoordinator(
            stdJson.readAddress(existingDeploymentData, ".addresses.rewardsCoordinator")
        );
        emptyContract = EmptyContract(stdJson.readAddress(existingDeploymentData, ".addresses.emptyContract"));

        // Strategies Deployed, load strategy list
        numStrategiesDeployed = stdJson.readUint(existingDeploymentData, ".addresses.numStrategiesDeployed");
        address[] memory unsortedArray = new address[](numStrategiesDeployed);
        for (uint256 i = 0; i < numStrategiesDeployed; ++i) {
            // Form the key for the current element
            string memory key = string.concat(".addresses.strategyAddresses[", vm.toString(i), "]");

            // Use the key and parse the strategy address
            address strategyAddress = abi.decode(stdJson.parseRaw(existingDeploymentData, key), (address));
            unsortedArray[i] = strategyAddress;
        }
        address[] memory sortedArray = _sortArrayAsc(unsortedArray);
        for (uint256 i = 0; i < numStrategiesDeployed; ++i) {
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
        proxyAdmin = ProxyAdmin(stdJson.readAddress(existingDeploymentData, ".addresses.token.tokenProxyAdmin"));
        eigen = IEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.EIGEN"));
        eigenImpl = IEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.EIGENImpl"));
        beigen = IBackingEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.bEIGEN"));
        beigenImpl = IBackingEigen(stdJson.readAddress(existingDeploymentData, ".addresses.token.bEIGENImpl"));
        eigenStrategy = EigenStrategy(stdJson.readAddress(existingDeploymentData, ".addresses.token.eigenStrategy"));
    }

    /// @dev Sort to ensure that the array is in ascending order for strategies
    function _sortArrayAsc(address[] memory arr) internal pure returns (address[] memory) {
        uint256 l = arr.length;
        for (uint256 i = 0; i < l; i++) {
            for (uint256 j = i + 1; j < l; j++) {
                if (address(arr[i]) > address(arr[j])) {
                    address temp = arr[i];
                    arr[i] = arr[j];
                    arr[j] = temp;
                }
            }
        }
        return arr;
    }
}
