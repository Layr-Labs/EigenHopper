// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

// import "eigenlayer-contracts/src/contracts/token/BackingEigen.sol";
// import "eigenlayer-contracts/src/contracts/token/Eigen.sol";

import "eigenlayer-contracts/script/utils/ExistingDeploymentParser.sol";
import "eigenlayer-contracts/script/deploy/mainnet/v0.4.3-upgrade_rewardsCoordinator.s.sol";
import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "src/TokenHopper.sol";
import "test/BytecodeConstants.sol";
import "src/RewardAllStakersActionGenerator.sol";



// # To deploy and verify our contract
// forge script script/sanity_checker.s.sol:FoundationIncentives_SanityChecker -vvv
contract FoundationIncentives_SanityChecker is ExistingDeploymentParser, BytecodeConstants {
    // Queued Transaction Proposal Data for Zero Delay
    bytes proposalDataForZeroDelay = hex"64d623530000000000000000000000000000000000000000000000000000000000000000";

    // NOTE: We assume that we are redeploying bEIGEN instead of using the previously queued deployment action

    // Timestamp at which timelock delay transaction was scheduled
    uint32 public bEIGENTimelockDelayScheduled = 1725344951; // September 3rd, 2024 11:29:11 AM PST 
    /// @dev At this time we will deploy EIGEN/BEIGEN, RC, and queue transactions
    uint32 public firstActionTime = 1726599600; // September 17th, 2024 12:00:00 PM PST
    uint32 public unlockTime = 1727290800; // September 25th, 2024 12:00:00 PM PST

    // Constants
    uint256 public newDelay = 0;

    // EIGEN Admin Addresses
    address public foundationMultisig = 0xbb00DDa2832850a43840A3A86515E3Fe226865F2;
    TimelockController public bEIGEN_TimelockController = TimelockController(payable(0xd6EC41E453C5E7dA5494f4d51A053Ab571712E6f));
    TimelockController public eigen_TimelockController = TimelockController(payable(0x2520C6b2C1FBE1813AB5c7c1018CDa39529e9FF2));

    // Token Addresses
    IBackingEigen public bEIGEN_proxy = IBackingEigen(0x83E9115d334D248Ce39a6f36144aEaB5b3456e75);
    IBackingEigen public bEIGEN_implementation = IBackingEigen(0xF2b225815F70c9b327DC9db758A36c92A4279b17);
    IEigen public EIGEN_proxy = IEigen(0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83);
    IEigen public EIGEN_implementation = IEigen(0x17f56E911C279bad67eDC08acbC9cf3DC4eF26A0);
    ProxyAdmin public eigen_ProxyAdmin = ProxyAdmin(0xB8915E195121f2B5D989Ec5727fd47a5259F1CEC);
    ProxyAdmin public bEIGEN_ProxyAdmin = ProxyAdmin(0x3f5Ab2D4418d38568705bFd6672630fCC3435CC9);
    IERC20 public bEIGEN_addressBefore = IERC20(0x83E9115d334D248Ce39a6f36144aEaB5b3456e75);
    IERC20 public EIGEN_addressBefore = IERC20(0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83);

    // Hopper config  
    TokenHopper public tokenHopper = TokenHopper(0xdc948c5f7f892aA80b8AEbe31C6813C28634b891);
    RewardAllStakersActionGenerator public actionGenerator = RewardAllStakersActionGenerator(0xF2eB394c4e04ff19422EB27411f78d00e216a88d);

    // Hopper config
    // GMT: Thursday, August 15, 2024 12:00:00 AM
    uint32 public constant hopperConfig_firstSubmissionStartTimestamp = 1723680000;
    // GMT: Thursday, October 3, 2024 12:00:00 AM
    uint256 public constant hopperConfig_firstSubmissionTriggerCutoff = 1727913600;
    // GMT: Thursday, September 26, 2024 12:00:00 AM
    uint256 public constant hopperConfig_startTime = 1727308800;
    // GMT: Thursday, August 14, 2025 12:00:00 AM -- 52 weeks after hopperConfig_firstSubmissionStartTimestamp
    uint256 public constant hopperConfig_expirationTimestamp = 1755129600;

    uint256 public constant hopperConfig_cooldownSeconds = 1 weeks;

    // EigenDA info
    uint8 public ETH_QUORUM_NUMBER = 0;
    IEigenDAStakeRegistry public eigenDAStakeRegistry = IEigenDAStakeRegistry(0x006124Ae7976137266feeBFb3F4D2BE4C073139D);

    uint256[2] public _amounts;
    IRewardsCoordinator.StrategyAndMultiplier[][2] public _strategiesAndMultipliers;

    function run() public {
        string memory forkUrl = vm.envString("RPC_MAINNET");
        uint256 forkId = vm.createFork(forkUrl);
        vm.selectFork(forkId);

        // Read and log the chain ID
        uint256 chainId = block.chainid;
        emit log_named_uint("You are on ChainID", chainId);

        if (chainId != 1) {
            revert("Chain not supported");
        }

        // These value set in two places, just sanity check
        assertEq(address(EIGEN_proxy), address(EIGEN_proxy));
        assertEq(address(bEIGEN_proxy), address(bEIGEN_proxy));


        _parseInitialDeploymentParams("lib/eigenlayer-contracts/script/configs/mainnet/mainnet-config.config.json");
        _parseDeployedContracts("lib/eigenlayer-contracts/script/configs/mainnet/mainnet-addresses.config.json");
        rewardsCoordinatorImplementation = RewardsCoordinator(0xb6738A8E7793D44c5895B6A6F2a62F6bF86Ba8d2);

        // 0. Warp to September 17th at 12pm PST
        vm.warp(firstActionTime);

        // commented out because this has been completed
        // 1. Deploy new implementations for bEIGEN and EIGEN
        // deploybEIGENAndEigen();

        // commented out because this has been completed
        // 2. Queue timelock delay reduction on EIGEN timelock controller
        // queueEigenTimelockDelay();

        // commented out because this has been completed
        // 3. Deploy Rewards Coordinator
        // deployRewardsCoordinator();

        // commented out because this has been completed
        // 4. Queue Upgrade for RewardsCoordinator + OpsMultisig setting
        // queueRewardsCoordinatorUpgradeAndOwnerChange();
        // actuallyQueueRCTransactions();

        // 5. Warp to Unlock Time
        // Note: We are now at September 25th, 2024 12:00:00 PM PST
        vm.warp(unlockTime);

        // 6. modify transfer restrictions
        modifyTransferRestrictions();

        // 7. Warp to firstActionTime + 11 days (This is past `bEIGENTimelockDelayScheduled` + 24 days)
        // Note: We set the EIGEN timelock delay here too `queueEigenTimelockDelay` was called
        // We are now at September 28th, 2024 12:00:00 PM PST
        vm.warp(firstActionTime + 11 days);

        // commented out because this will no longer be done
        // 8. Execute bEIGEN timelock delay reduction
        // executeBEIGENTimelockDelay();

        // commented out because this will no longer be done
        // 9. Execute EIGEN timelock delay reduction
        // executeEigenTimelockDelay();       

        // 10. Perform bEIGEN Upgrade
        upgradebEIGEN();

        // 11. Perform EIGEN Upgrade
        upgradeEIGEN();

        // Check token upgrade correctness
        checkUpgradeCorrectness();
        simulateWrapAndUnwrap();

        // 12. Execute RC actions
        executeRCActions();

        // commented out because this has been completed
        // 13. Deploy Token Hopper
        // deployHopperContracts();

        // 14. Make Token Hopper the minter
        giveHopperMintingRights();

        // 15. Give Hopper RewardsForAllRole
        giveHopperRewardsForAllRole();

        // 16. Press Button
        _test_pressButton();
        require(block.timestamp < hopperConfig_firstSubmissionTriggerCutoff, "Should have pressed button before September 30th");
    }

    function modifyTransferRestrictions() public {
        vm.startPrank(foundationMultisig);
        EIGEN_proxy.setAllowedFrom(address(tokenHopper), true);
        vm.stopPrank();
    }

    function upgradebEIGEN() public {
        // Upgrade bEIGEN
        uint256 delay = bEIGEN_TimelockController.getMinDelay();
        bytes memory data = abi.encodeWithSelector(
                ProxyAdmin.upgrade.selector,
                TransparentUpgradeableProxy(payable(address(bEIGEN_proxy))),
                bEIGEN_implementation
        );
        emit log_named_bytes("data for bEIGEN upgrade", data);

        vm.startPrank(foundationMultisig);
        // commented out because this has already been scheduled
        // bEIGEN_TimelockController.schedule({
        //     target: address(bEIGEN_ProxyAdmin),
        //     value: 0,
        //     data: data,
        //     predecessor: bytes32(0),
        //     salt: bytes32(0),
        //     delay: delay
        // });
        bEIGEN_TimelockController.execute({
            target: address(bEIGEN_ProxyAdmin),
            value: 0,
            payload: data,
            predecessor: bytes32(0),
            salt: bytes32(0)
        });
        vm.stopPrank();
    }

    function upgradeEIGEN() public {
        // Upgrade bEIGEN
        uint256 delay = bEIGEN_TimelockController.getMinDelay();
        bytes memory data = abi.encodeWithSelector(
                ProxyAdmin.upgrade.selector,
                TransparentUpgradeableProxy(payable(address(EIGEN_proxy))),
                EIGEN_implementation
        );
        emit log_named_bytes("data for EIGEN upgrade", data);

        vm.startPrank(foundationMultisig);
        // commented out because this has already been scheduled
        // eigen_TimelockController.schedule({
        //     target: address(eigen_ProxyAdmin),
        //     value: 0,
        //     data: data,
        //     predecessor: bytes32(0),
        //     salt: bytes32(0),
        //     delay: delay
        // });
        eigen_TimelockController.execute({
            target: address(eigen_ProxyAdmin),
            value: 0,
            payload: data,
            predecessor: bytes32(0),
            salt: bytes32(0)
        });
        vm.stopPrank();
    }

    function executeRCActions() public {
        address rewardsCoordinatorOwnerBefore = address(rewardsCoordinator.owner());
        address timelockTarget = executorMultisig;
        bytes memory timelockSignature;
        bytes memory final_calldata_to_executor_multisig = hex"6A76120200000000000000000000000040A2ACCBD92BCA938B02010E17A5B8929B49130D0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002E000000000000000000000000000000000000000000000000000000000000001648D80FF0A00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000112008B9566ADA63B64D1E1DCF1418B43FD1433B724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499A88EC40000000000000000000000007750D328B314EFFA365A0402CCFD489B80B0ADDA000000000000000000000000B6738A8E7793D44C5895B6A6F2A62F6BF86BA8D2007750D328B314EFFA365A0402CCFD489B80B0ADDA00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024F2FDE38B000000000000000000000000BE1685C81AA44FF9FB319DD389ADDD9374383E900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041000000000000000000000000A6DB1A8C5A981D1536266D2A393C5F8DDB210EAF00000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000";
        uint256 timelockEta = 1727474400;
        bytes memory calldata_to_timelock_executing_action = abi.encodeWithSelector(ITimelock.executeTransaction.selector,
            0x369e6F597e22EaB55fFb173C6d9cD234BD699111, //timelockTarget
            0, //timelockValue
            timelockSignature,
            final_calldata_to_executor_multisig,
            timelockEta
        );
        // bytes memory calldata_to_timelock_executing_action = hex"0825f38f000000000000000000000000369e6f597e22eab55ffb173c6d9cd234bd699111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e00000000000000000000000000000000000000000000000000000000066f72ae00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003646a76120200000000000000000000000040a2accbd92bca938b02010e17a5b8929b49130d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002e000000000000000000000000000000000000000000000000000000000000001648d80ff0a00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000112008b9566ada63b64d1e1dcf1418b43fd1433b724440000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004499a88ec40000000000000000000000007750d328b314effa365a0402ccfd489b80b0adda000000000000000000000000b6738a8e7793d44c5895b6a6f2a62f6bf86ba8d2007750d328b314effa365a0402ccfd489b80b0adda00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000024f2fde38b000000000000000000000000be1685c81aa44ff9fb319dd389addd9374383e900000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000041000000000000000000000000a6db1a8c5a981d1536266d2a393c5f8ddb210eaf0000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";
        vm.prank(operationsMultisig);
        (bool success, ) = address(timelock).call(calldata_to_timelock_executing_action);
        require(success, "Timelock executeTransaction failed");

        // Assert owner
        assertEq(address(rewardsCoordinator.owner()), address(operationsMultisig), "rewardsCoordinator owner is not operations multisig");
    }

    function giveHopperMintingRights() public {
        vm.prank(foundationMultisig);
        bEIGEN_proxy.setIsMinter(address(tokenHopper), true);

        assertTrue(ExtraTokenFuncs(address(bEIGEN_proxy)).isMinter(address(tokenHopper)));
    }

    function giveHopperRewardsForAllRole() public {
        vm.prank(operationsMultisig);
        rewardsCoordinator.setRewardsForAllSubmitter(address(tokenHopper), true);

        assertTrue(rewardsCoordinator.isRewardsForAllSubmitter(address(tokenHopper)));
    }

    function _setupHopperConfigs() public {
        _setupDeployedStrategiesArray();

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
            // emit log_named_uint("i", i);
            // emit log_named_address("address(_strategiesAndMultipliers[1][i].strategy)", address(_strategiesAndMultipliers[1][i].strategy));
            // emit log_named_uint("_strategiesAndMultipliers[1][i].multiplier", _strategiesAndMultipliers[1][i].multiplier);
            // TODO: fix this for mainnet. on testnet it appears that EigenDA does not use WETH & has 1e18 for all its multipliers
            _strategiesAndMultipliers[1][i].multiplier = 1e18;
            require(_strategiesAndMultipliers[1][i].multiplier != 0, "multiplier has not been set");
        }
    }

    function _setupDeployedStrategiesArray() internal {
        // Strategies Deployed, load strategy list
        address[] memory unsortedArray = new address[](numStrategiesDeployed);
        for (uint256 i = 0; i < deployedStrategyArray.length; ++i) {
            unsortedArray[i] = address(deployedStrategyArray[i]);
        }
        address[] memory sortedArray = _sortArrayAsc(unsortedArray);
        for (uint256 i = 0; i < numStrategiesDeployed; ++i) {
            deployedStrategyArray[i] = StrategyBase(sortedArray[i]);
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

    function checkUpgradeCorrectness() public view {
        require(eigen_ProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(EIGEN_proxy)))) == address(EIGEN_implementation),
            "implementation set incorrectly");
        require(EIGEN_proxy.bEIGEN() == bEIGEN_addressBefore,
            "bEIGEN address changed unexpectedly");
        require(bEIGEN_ProxyAdmin.getProxyImplementation(TransparentUpgradeableProxy(payable(address(bEIGEN_proxy)))) == address(bEIGEN_implementation),
            "implementation set incorrectly");
        require(bEIGEN_proxy.EIGEN() == EIGEN_addressBefore,
            "EIGEN address changed unexpectedly");
    }

    function simulateWrapAndUnwrap() public {
        uint256 amount = 1e18;
        vm.prank(address(EIGEN_proxy));
        bEIGEN_proxy.transfer(address(this), amount);

        bEIGEN_proxy.approve(address(EIGEN_proxy), amount);
        uint256 bEIGEN_balanceStart = bEIGEN_proxy.balanceOf(address(this));
        uint256 EIGEN_balanceStart = EIGEN_proxy.balanceOf(address(this));
        EIGEN_proxy.wrap(amount);
        uint256 bEIGEN_balanceMiddle = bEIGEN_proxy.balanceOf(address(this));
        uint256 EIGEN_balanceMiddle = EIGEN_proxy.balanceOf(address(this));
        EIGEN_proxy.unwrap(amount);
        uint256 bEIGEN_balanceAfter = bEIGEN_proxy.balanceOf(address(this));
        uint256 EIGEN_balanceAfter = EIGEN_proxy.balanceOf(address(this));

        require(bEIGEN_balanceMiddle + amount == bEIGEN_balanceStart, "wrapping did not transfer out bEIGEN");
        require(EIGEN_balanceMiddle == EIGEN_balanceStart + amount, "wrapping did not transfer in EIGEN");

        require(bEIGEN_balanceAfter == bEIGEN_balanceStart, "unwrapping did not transfer in bEIGEN");
        require(EIGEN_balanceAfter == EIGEN_balanceStart, "unwrapping did not transfer out EIGEN");
    }

    function deployContractFromBytecode(bytes memory bytecode) public returns (address) {
        address deployedContract;
        uint256 size = bytecode.length;
        uint256 location;
        assembly {
            // value, offset, size
            location := add(bytecode, 32)
        }
        assembly {
            /**
             * the create opcode takes args: value, offset, size
             * offset should start from the bytecode itself -- 'bytecode' refers to the location, and we skip the first
             * 32 bytes in the offset since these encode the length rather than the data itself
             */
            deployedContract := create(0, add(bytecode, 32), size)
        }
        return deployedContract;
    }

    function _test_pressButton() public {
        uint256 rewardsCoordinatorEigenBalanceBefore = EIGEN_proxy.balanceOf(address(rewardsCoordinator));
        uint256 eigenTotalSupplyBefore = EIGEN_proxy.totalSupply();
        uint256 beigenTotalSupplyBefore = bEIGEN_proxy.totalSupply();

        ITokenHopper.HopperConfiguration memory configuration = tokenHopper.getHopperConfiguration();
        uint256 currentNonce = rewardsCoordinator.submissionNonce(address(tokenHopper));
        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions;
        {
            IHopperActionGenerator.HopperAction[] memory actions =
                actionGenerator.generateHopperActions(address(tokenHopper), address(EIGEN_proxy));
            bytes memory rewardsSubmissionsRaw = this.sliceOffLeadingFourBytes(actions[4].callData);
            rewardsSubmissions = abi.decode(
                rewardsSubmissionsRaw,
                (IRewardsCoordinator.RewardsSubmission[])
            );
        }
        uint256 totalAmount;
        for (uint256 i = 0; i < rewardsSubmissions.length; ++i) {
            totalAmount += rewardsSubmissions[i].amount;
        }
        // event for minting
        vm.expectEmit(true, true, true, true, address(bEIGEN_proxy));
        emit Transfer(address(0), address(tokenHopper), totalAmount);
        // event for approving to wrap
        vm.expectEmit(true, true, true, true, address(bEIGEN_proxy));
        emit Approval(address(tokenHopper), address(EIGEN_proxy), totalAmount);
        // events from wrapping
        // spending approval
        vm.expectEmit(true, true, true, true, address(bEIGEN_proxy));
        emit Approval(address(tokenHopper), address(EIGEN_proxy), 0);
        // transferring in beigen
        vm.expectEmit(true, true, true, true, address(bEIGEN_proxy));
        emit Transfer(address(tokenHopper), address(EIGEN_proxy), totalAmount);
        // minting new eigen to hopper as last step of wrapping
        vm.expectEmit(true, true, true, true, address(EIGEN_proxy));
        emit Transfer(address(0), address(tokenHopper), totalAmount);
        // event for approving RewardsCoordinator to transfer
        vm.expectEmit(true, true, true, true, address(EIGEN_proxy));
        emit Approval(address(tokenHopper), address(rewardsCoordinator), totalAmount);

        // events for RewardsCoordinator performing the transfers
        uint256 remainingAllowance = totalAmount;
        for (uint256 i = 0; i < 1; ++i) {
            IRewardsCoordinator.RewardsSubmission memory rewardsSubmission = rewardsSubmissions[i];

            bytes32 rewardsSubmissionHash = keccak256(abi.encode(tokenHopper, currentNonce, rewardsSubmission));
            vm.expectEmit(true, true, true, true, address(rewardsCoordinator));
            emit RewardsSubmissionForAllEarnersCreated({
                submitter: address(tokenHopper),
                submissionNonce: currentNonce,
                rewardsSubmissionHash: rewardsSubmissionHash,
                rewardsSubmission: rewardsSubmission
            });
            // spending approval
            vm.expectEmit(true, true, true, true, address(EIGEN_proxy));
            remainingAllowance -= rewardsSubmission.amount;
            emit Approval(address(tokenHopper), address(rewardsCoordinator), remainingAllowance);
            // transferring into RewardsCoordinator
            vm.expectEmit(true, true, true, true, address(EIGEN_proxy));
            emit Transfer(address(tokenHopper), address(rewardsCoordinator), rewardsSubmission.amount);
           currentNonce++;
        }

        // event for pressing button
        vm.expectEmit(true, true, true, true, address(tokenHopper));
        uint256 newCooldownHorizon =
            ((block.timestamp - configuration.startTime) / configuration.cooldownSeconds + 1) * configuration.cooldownSeconds
            + configuration.startTime;
        emit ButtonPressed(address(this), newCooldownHorizon);

        tokenHopper.pressButton();

        uint256 rewardsCoordinatorEigenBalanceAfter = EIGEN_proxy.balanceOf(address(rewardsCoordinator));
        uint256 eigenTotalSupplyAfter = EIGEN_proxy.totalSupply();
        uint256 beigenTotalSupplyAfter = bEIGEN_proxy.totalSupply();

        assertEq(rewardsCoordinatorEigenBalanceAfter, rewardsCoordinatorEigenBalanceBefore + totalAmount,
            "rewardsCoordinator did not receive expected amount of EIGEN tokens");
        assertEq(eigenTotalSupplyAfter, eigenTotalSupplyBefore + totalAmount,
            "EIGEN totalSupply did not increase as expected");
        assertEq(beigenTotalSupplyAfter, beigenTotalSupplyBefore + totalAmount,
            "bEIGEN totalSupply did not increase as expected");
        require(!tokenHopper.canPress(), "should not be able to immediately press button again");
        assertEq(tokenHopper.latestPress(), block.timestamp,
            "latestPress not set correctly");
    }

    event RewardsSubmissionForAllEarnersCreated(
        address indexed submitter,
        uint256 indexed submissionNonce,
        bytes32 indexed rewardsSubmissionHash,
        IRewardsCoordinator.RewardsSubmission rewardsSubmission
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event HopperLoaded(ITokenHopper.HopperConfiguration config);
    event ButtonPressed(address indexed caller, uint256 newCooldownHorizon);
    event FundsRetrieved(uint256 amount);

    // @notice returns the `bytestring` with its first four bytes removed. used to slice off function sig
    function sliceOffLeadingFourBytes(bytes calldata bytestring) public pure returns (bytes memory) {
        return bytestring[4:];
    }
}

interface IEigenDAStakeRegistry {
    function strategyParamsByIndex(uint8 quorumNumber, uint256 index) external view returns(address, uint96);

    function strategyParamsLength(uint8 quorumNumber) external view returns(uint256);
}

interface ExtraTokenFuncs {
    function isMinter(address) external view returns (bool);
}