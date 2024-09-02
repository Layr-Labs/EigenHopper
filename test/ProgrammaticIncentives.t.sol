// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IBackingEigen.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IEigen.sol";

import "eigenlayer-contracts/src/contracts/core/RewardsCoordinator.sol";

// import "../harnesses/EigenHarness.sol";
import "./BytecodeConstants.sol";

import "eigenlayer-contracts/src/test/mocks/DelegationManagerMock.sol";
import "eigenlayer-contracts/src/test/mocks/StrategyManagerMock.sol";
import "eigenlayer-contracts/src/test/mocks/EmptyContract.sol";

import "src/TokenHopper.sol";
import "src/RewardAllStakersActionGenerator.sol";

contract ProgrammaticIncentivesTests is BytecodeConstants, Test {
    Vm cheats = Vm(VM_ADDRESS);

    mapping(address => bool) public fuzzedOutAddresses;

    address public initialOwner = 0xbb00DDa2832850a43840A3A86515E3Fe226865F2;
    address public minterToSet = address(500);
    address public mintTo = address(12345);

    address public eigenImplAddress = address(999);
    address public beigenImplAddress = address(555);
    address public rewardsCoordinatorImplAddress = address(7777777);
    address public eigenAddress = 0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83;
    address public beigenAddress = 0x83E9115d334D248Ce39a6f36144aEaB5b3456e75;

    uint32 public _firstSubmissionStartTimestamp;
    uint256 public _firstSubmissionTriggerCutoff;
    uint256[2] public _amounts;
    IRewardsCoordinator.StrategyAndMultiplier[][2] public _strategiesAndMultipliers;

    ProxyAdmin public proxyAdmin;

    IEigen public eigenImpl;
    IEigen public eigen;

    IBackingEigen public beigenImpl;
    IBackingEigen public beigen;

    IRewardsCoordinator public rewardsCoordinatorImpl;
    IRewardsCoordinator public rewardsCoordinator;

    DelegationManagerMock public delegationManagerMock;
    StrategyManagerMock public strategyManagerMock;

    EmptyContract public emptyContract;

    TokenHopper public tokenHopper;
    RewardAllStakersActionGenerator public actionGenerator;

    function setUp() public {
        vm.startPrank(initialOwner);
        proxyAdmin = new ProxyAdmin();
        emptyContract = new EmptyContract();

        // deploy proxies
        eigen = IEigen(address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")));
        beigen = IBackingEigen(address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")));
        rewardsCoordinator = IRewardsCoordinator(address(new TransparentUpgradeableProxy(address(emptyContract), address(proxyAdmin), "")));

        // TODO: this block does NOT work as-is. might need to just avoid using this if that's workable.
        // etch proxies to fix addresses
        // address _logic = address(emptyContract);
        // address admin_ = address(proxyAdmin);
        // bytes memory _data;
        // cheats.etch(address(eigenAddress), address(eigen).code);
        // cheats.etch(address(beigenAddress), address(beigen).code);
        // eigen = IEigen(eigenAddress);
        // beigen = IBackingEigen(beigenAddress);

        // deploy mocks
        delegationManagerMock = new DelegationManagerMock();
        strategyManagerMock = new StrategyManagerMock();

        // deploy/etch implementations
        eigenImpl = IEigen(eigenImplAddress);
        cheats.etch(address(eigenImpl), eigenDeployedBytecode);
        beigenImpl = IBackingEigen(beigenImplAddress);
        cheats.etch(address(beigenImpl), beigenDeployedBytecode);
        rewardsCoordinatorImpl = IRewardsCoordinator(rewardsCoordinatorImplAddress);
        cheats.etch(address(rewardsCoordinatorImpl), rewardsCoordinatorDeployedBytecode);

        // upgrade proxies
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(eigen))), address(eigenImpl));
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(beigen))), address(beigenImpl));
        proxyAdmin.upgrade(TransparentUpgradeableProxy(payable(address(rewardsCoordinator))), address(rewardsCoordinatorImpl));

        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: rewardsCoordinator,
            _firstSubmissionStartTimestamp: _firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: _firstSubmissionTriggerCutoff,
            _amounts: _amounts,
            _strategiesAndMultipliers: _strategiesAndMultipliers,
            _bEIGEN: IERC20(beigenAddress),
            _EIGEN: IERC20(eigenAddress)
        });

        tokenHopper = new TokenHopper({
            initialOwner: initialOwner
        });

        ITokenHopper.HopperConfiguration memory hopperConfiguration = ITokenHopper.HopperConfiguration({
            token: eigenAddress,
            cooldownSeconds: (1 weeks - 15 minutes),
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: block.timestamp + 24 weeks 
        });

        tokenHopper.load(hopperConfiguration);

        vm.stopPrank();
    }

    function test_test_test() public {
        emit log_named_address("eigen.bEIGEN()", address(eigen.bEIGEN()));
        emit log_named_address("beigen.EIGEN()", address(beigen.EIGEN()));
    }
}
