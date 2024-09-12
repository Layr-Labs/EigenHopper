// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Script.sol";

import "eigenlayer-contracts/script/utils/ExistingDeploymentParser.sol";

import "test/ProgrammaticIncentives.t.sol";

interface IEigenDAStakeRegistry {

    function strategyParamsByIndex(uint8 quorumNumber, uint256 index) external view returns(address, uint96);

    function strategyParamsLength(uint8 quorumNumber) external view returns(uint256);
}

// forge script script/Deploy_ProgrammaticIncentives_Mainnet.s.sol:Deploy_ProgrammaticIncentives_Mainnet -vvvv --private-key $PRIVATE_KEY --broadcast
contract Deploy_ProgrammaticIncentives_Mainnet is Script, ProgrammaticIncentivesTests {
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

    // Hopper config
    // GMT: Thursday, August 15, 2024 12:00:00 AM
    uint32 public hopperConfig_firstSubmissionStartTimestamp = 1723680000;
    // GMT: Saturday, October 5, 2024 12:00:00 AM
    uint256 public hopperConfig_firstSubmissionTriggerCutoff = 1728086400;
    // GMT: Thursday, September 5, 2024 12:00:00 AM
    uint256 public hopperConfig_startTime = 1725494400;
    // GMT: Thursday, March 27, 2025 12:00:00 AM
    uint256 public hopperConfig_expirationTimestamp = 1743033600;

    uint256 public hopperConfig_cooldownSeconds = 1 weeks;

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
        cheats.prank(EIGEN_ProxyAdmin.owner());
        EIGEN_ProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(eigen))), address(eigenImpl));
        cheats.prank(bEIGEN_ProxyAdmin.owner());
        bEIGEN_ProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(beigen))), address(beigenImpl));
        cheats.prank(eigenLayerProxyAdmin.owner());
        eigenLayerProxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(rewardsCoordinator))), address(rewardsCoordinatorImpl));

        // set up strategy arrays and amounts array
        _amounts[0] = 321_855_128_516_280_769_230_770;
        _amounts[1] = 965_565_385_548_842_307_692_308;
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
        for (uint256 i = 0; i < deployedStrategyArray.length; ++i) {
            emit log_named_uint("i", i);
            emit log_named_address("address(_strategiesAndMultipliers[1][i].strategy)", address(_strategiesAndMultipliers[1][i].strategy));
            emit log_named_uint("_strategiesAndMultipliers[1][i].multiplier", _strategiesAndMultipliers[1][i].multiplier);
            require(_strategiesAndMultipliers[1][i].multiplier != 0, "multiplier has not been set");
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
