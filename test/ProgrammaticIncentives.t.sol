// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IBackingEigen.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IEigen.sol";

import "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";

import "eigenlayer-contracts/src/test/mocks/DelegationManagerMock.sol";
import "eigenlayer-contracts/src/test/mocks/StrategyManagerMock.sol";
import "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

import "src/TokenHopper.sol";
import "src/RewardAllStakersActionGenerator.sol";

import "./BytecodeConstants.sol";

interface IMinting {
    function isMinter(address) external view returns (bool);
}

contract ProgrammaticIncentivesTests is BytecodeConstants, Test {
    Vm cheats = Vm(VM_ADDRESS);

    event RewardsSubmissionForAllCreated(
        address indexed submitter,
        uint256 indexed submissionNonce,
        bytes32 indexed rewardsSubmissionHash,
        IRewardsCoordinator.RewardsSubmission rewardsSubmission
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    mapping(address => bool) public fuzzedOutAddresses;

    address public initialOwner = 0xbb00DDa2832850a43840A3A86515E3Fe226865F2;
    address public minterToSet = address(500);
    address public mintTo = address(12345);

    address public rewardsCoordinatorImplAddress = address(7777777);
    address public _rewardsUpdater = address(4444);
    IPauserRegistry public _pauserRegistry = IPauserRegistry(address(333));

    // RewardsCoordinator config
    uint32 GENESIS_REWARDS_TIMESTAMP = 1710979200;

    // Action Generator config
    uint32 public _firstSubmissionStartTimestamp = uint32(GENESIS_REWARDS_TIMESTAMP + 50 weeks);
    uint256 public _firstSubmissionTriggerCutoff = _firstSubmissionStartTimestamp + 1 weeks;
    uint256[2] public _amounts;
    IRewardsCoordinator.StrategyAndMultiplier[][2] public _strategiesAndMultipliers;

    // EIGEN token config
    address[] public minters;
    uint256[] public mintingAllowances;
    uint256[] public mintAllowedAfters;
    uint256 public constant INITIAL_EIGEN_SUPPLY = 1673646668284660000000000000;

    ProxyAdmin public proxyAdmin;

    IEigen public eigenImpl;
    IEigen public eigen;

    IBackingEigen public beigenImpl;
    IBackingEigen public beigen;

    RewardsCoordinator public rewardsCoordinatorImpl;
    RewardsCoordinator public rewardsCoordinator;

    DelegationManagerMock public delegationManagerMock;
    StrategyManagerMock public strategyManagerMock;

    EmptyContract public emptyContract;

    TokenHopper public tokenHopper;
    RewardAllStakersActionGenerator public actionGenerator;

    // utility function for deploying a contract from its creation bytecode
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

    function setUp() public {
        cheats.startPrank(initialOwner);
        proxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();

        // deploy proxies
        eigen = IEigen(address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")));
        beigen = IBackingEigen(address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")));
        rewardsCoordinator = RewardsCoordinator(address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")));

        // deploy mocks
        delegationManagerMock = new DelegationManagerMock();
        strategyManagerMock = new StrategyManagerMock();

        // deploy implementations
        beigenImpl = IBackingEigen(deployContractFromBytecode(
            abi.encodePacked(beigenCreationBytecode, abi.encode(address(eigen)))
        ));
        eigenImpl = IEigen(deployContractFromBytecode(
            abi.encodePacked(eigenCreationBytecode, abi.encode(address(beigen)))
        ));
        // deployed using mainnet values -- see https://etherscan.io/address/0x7750d328b314effa365a0402ccfd489b80b0adda
        rewardsCoordinatorImpl = new RewardsCoordinator({
            _delegationManager: delegationManagerMock,
            _strategyManager: strategyManagerMock,
            _CALCULATION_INTERVAL_SECONDS: 1 weeks,
            _MAX_REWARDS_DURATION: 10 weeks, 
            _MAX_RETROACTIVE_LENGTH: 24 weeks,
            _MAX_FUTURE_LENGTH: 30 days,
            __GENESIS_REWARDS_TIMESTAMP: GENESIS_REWARDS_TIMESTAMP
        });

        // upgrade proxies
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(eigen))), address(eigenImpl));
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(beigen))), address(beigenImpl));
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(rewardsCoordinator))), address(rewardsCoordinatorImpl));

        // deploy ActionGenerator & Hopper
        _amounts[0] = 100;
        _amounts[1] = 200;
        _strategiesAndMultipliers[0].push(IRewardsCoordinator.StrategyAndMultiplier({
            strategy: IStrategy(address(eigen)),
            multiplier: 1e18
        }));
        _strategiesAndMultipliers[1].push(IRewardsCoordinator.StrategyAndMultiplier({
            strategy: IStrategy(address(eigen)),
            multiplier: 1e18
        }));
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: rewardsCoordinator,
            _firstSubmissionStartTimestamp: _firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: _firstSubmissionTriggerCutoff,
            _amounts: _amounts,
            _strategiesAndMultipliers: _strategiesAndMultipliers,
            _bEIGEN: beigen,
            _EIGEN: eigen
        });

        tokenHopper = new TokenHopper({
            initialOwner: initialOwner
        });
        ITokenHopper.HopperConfiguration memory hopperConfiguration = ITokenHopper.HopperConfiguration({
            token: address(eigen),
            cooldownSeconds: 1 weeks,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: _firstSubmissionStartTimestamp + 24 weeks 
        });
        cheats.warp(_firstSubmissionStartTimestamp + 1 weeks);
        tokenHopper.load(hopperConfiguration);

        // initialize contracts
        // initialize eigen
        minters.push(initialOwner);
        mintingAllowances.push(INITIAL_EIGEN_SUPPLY);
        mintAllowedAfters.push(0);
        (bool success, /*bytes returndata*/) = address(eigen).call(abi.encodeWithSignature(
            "initialize(address,address[],uint256[],uint256[])",
            initialOwner,
            minters,
            mintingAllowances,
            mintAllowedAfters
        ));
        require(success, "eigen initialization failed");
        eigen.mint();
        eigen.disableTransferRestrictions();

        // initialize beigen
        (success, /*bytes returndata*/) = address(beigen).call(abi.encodeWithSignature("initialize(address)", initialOwner));
        require(success, "beigen initialization failed");
        beigen.disableTransferRestrictions();
        beigen.setIsMinter(address(tokenHopper), true);

        cheats.stopPrank();

        // initialize RewardsCoordinator
        rewardsCoordinator.initialize({
            initialOwner: initialOwner,
            _pauserRegistry: _pauserRegistry,
            initialPausedStatus: 0,
            _rewardsUpdater: _rewardsUpdater,
            _activationDelay: 1 weeks,
            _globalCommissionBips: 1000
        });
        cheats.prank(Ownable(address(rewardsCoordinator)).owner());
        rewardsCoordinator.setRewardsForAllSubmitter(address(tokenHopper), true);

        // initialize mocks
        strategyManagerMock.setStrategyWhitelist(IStrategy(address(eigen)), true);
    }

    function test_pressButton() public {
        uint256 rewardsCoordinatorEigenBalanceBefore = eigen.balanceOf(address(rewardsCoordinator));
        uint256 eigenTotalSupplyBefore = eigen.totalSupply();
        uint256 beigenTotalSupplyBefore = beigen.totalSupply();

        IHopperActionGenerator.HopperAction[] memory actions = actionGenerator.generateHopperActions(address(tokenHopper), address(eigen));
        uint256 currentNonce = 0;
        // TODO: need to get correct RewardSubmission data here
        // IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions = new IRewardsCoordinator.RewardsSubmission[](2);
        bytes memory rewardsSubmissionsRaw = this.sliceOffLeadingFourBytes(actions[4].callData);
        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions = abi.decode(
            rewardsSubmissionsRaw,
            (IRewardsCoordinator.RewardsSubmission[])
        );
        uint256 totalAmount;
        for (uint256 i = 0; i < rewardsSubmissions.length; ++i) {
            totalAmount += rewardsSubmissions[i].amount;
        }
        // event for minting
        cheats.expectEmit(true, true, true, true, address(beigen));
        emit Transfer(address(0), address(tokenHopper), totalAmount);
        // event for approving to wrap
        cheats.expectEmit(true, true, true, true, address(beigen));
        emit Approval(address(tokenHopper), address(eigen), totalAmount);
        // events from wrapping
        // spending approval
        cheats.expectEmit(true, true, true, true, address(beigen));
        emit Approval(address(tokenHopper), address(eigen), 0);
        // transferring in beigen
        cheats.expectEmit(true, true, true, true, address(beigen));
        emit Transfer(address(tokenHopper), address(eigen), totalAmount);
        // minting new eigen to hopper as last step of wrapping
        cheats.expectEmit(true, true, true, true, address(eigen));
        emit Transfer(address(0), address(tokenHopper), totalAmount);
        // event for approving RewardsCoordinator to transfer
        cheats.expectEmit(true, true, true, true, address(eigen));
        emit Approval(address(tokenHopper), address(rewardsCoordinator), totalAmount);

        uint256 remainingAllowance = totalAmount;
        // for (uint256 i = 0; i < rewardsSubmissions.length; ++i) {
        for (uint256 i = 0; i < 1; ++i) {
            IRewardsCoordinator.RewardsSubmission memory rewardsSubmission = rewardsSubmissions[i];

            bytes32 rewardsSubmissionHash = keccak256(abi.encode(tokenHopper, currentNonce, rewardsSubmission));
            cheats.expectEmit(true, true, true, true, address(rewardsCoordinator));
            emit RewardsSubmissionForAllCreated({
                submitter: address(tokenHopper),
                submissionNonce: currentNonce,
                rewardsSubmissionHash: rewardsSubmissionHash,
                rewardsSubmission: rewardsSubmission
            });
            // spending approval
            cheats.expectEmit(true, true, true, true, address(eigen));
            remainingAllowance -= rewardsSubmission.amount;
            emit Approval(address(tokenHopper), address(rewardsCoordinator), remainingAllowance);
            // transferring into RewardsCoordinator
            cheats.expectEmit(true, true, true, true, address(eigen));
            emit Transfer(address(tokenHopper), address(rewardsCoordinator), rewardsSubmission.amount);
           currentNonce++;
        }
        tokenHopper.pressButton();

        uint256 rewardsCoordinatorEigenBalanceAfter = eigen.balanceOf(address(rewardsCoordinator));
        uint256 eigenTotalSupplyAfter = eigen.totalSupply();
        uint256 beigenTotalSupplyAfter = beigen.totalSupply();

        assertEq(rewardsCoordinatorEigenBalanceAfter, rewardsCoordinatorEigenBalanceBefore + totalAmount,
            "rewardsCoordinator did not receive expected amount of EIGEN tokens");
        assertEq(eigenTotalSupplyAfter, eigenTotalSupplyBefore + totalAmount,
            "EIGEN totalSupply did not increase as expected");
        assertEq(beigenTotalSupplyAfter, beigenTotalSupplyBefore + totalAmount,
            "bEIGEN totalSupply did not increase as expected");
        require(!tokenHopper.canPress(), "should not be able to immediately press button again");
        assertEq(tokenHopper.cooldownHorizon(), block.timestamp + tokenHopper.getHopperConfiguration().cooldownSeconds,
            "cooldownHorizon not set correctly");
    }

    // @notice returns the `bytestring` with its first four bytes removed. used to slice off function sig
    function sliceOffLeadingFourBytes(bytes calldata bytestring) public pure returns (bytes memory) {
        return bytestring[4:];
    }
}
