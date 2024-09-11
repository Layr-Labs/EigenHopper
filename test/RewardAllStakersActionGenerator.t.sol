// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Test.sol";

import "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";

import "src/RewardAllStakersActionGenerator.sol";

contract RewardsCoordinatorMock {
    function CALCULATION_INTERVAL_SECONDS() external pure returns (uint32) {
        return 7 days;
    }
}

contract RewardAllStakersActionGeneratorTests is Test {
    Vm cheats = Vm(VM_ADDRESS);

    address public initialOwner = address(this);

    RewardAllStakersActionGenerator public actionGenerator;

    // RewardsCoordinator config
    uint32 public GENESIS_REWARDS_TIMESTAMP = 1710979200;

    // Action Generator config
    uint32 public _firstSubmissionStartTimestamp = uint32(GENESIS_REWARDS_TIMESTAMP + 50 weeks);
    uint256 public _firstSubmissionTriggerCutoff = _firstSubmissionStartTimestamp + 5 weeks;
    IRewardsCoordinator.StrategyAndMultiplier[][2] public strategiesAndMultipliers;
    uint256[2] public amounts;
    RewardsCoordinatorMock public rewardsCoordinatorMock;
    IERC20 public _bEIGEN;
    IERC20 public _EIGEN;

    function setUp() public {
        rewardsCoordinatorMock = new RewardsCoordinatorMock();

        _bEIGEN = IERC20(address(1000));
        _EIGEN = IERC20(address(1001));
    }

    function test_deployRevertsWithZeroAddresses() public {
        rewardsCoordinatorMock = RewardsCoordinatorMock(address(0));
        cheats.expectRevert("RewardAllStakersActionGenerator: rewardsCoordinator cannot be zero address");
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: IRewardsCoordinator(address(rewardsCoordinatorMock)),
            _firstSubmissionStartTimestamp: _firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: _firstSubmissionTriggerCutoff,
            _amounts: amounts,
            _strategiesAndMultipliers: strategiesAndMultipliers,
            _bEIGEN: _bEIGEN,
            _EIGEN: _EIGEN
        });
        rewardsCoordinatorMock = new RewardsCoordinatorMock();

        _bEIGEN = IERC20(address(0));
        cheats.expectRevert("RewardAllStakersActionGenerator: bEIGEN cannot be zero address");
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: IRewardsCoordinator(address(rewardsCoordinatorMock)),
            _firstSubmissionStartTimestamp: _firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: _firstSubmissionTriggerCutoff,
            _amounts: amounts,
            _strategiesAndMultipliers: strategiesAndMultipliers,
            _bEIGEN: _bEIGEN,
            _EIGEN: _EIGEN
        });
        _bEIGEN = IERC20(address(1000));

        _EIGEN = IERC20(address(0));
        cheats.expectRevert("RewardAllStakersActionGenerator: EIGEN cannot be zero address");
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: IRewardsCoordinator(address(rewardsCoordinatorMock)),
            _firstSubmissionStartTimestamp: _firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: _firstSubmissionTriggerCutoff,
            _amounts: amounts,
            _strategiesAndMultipliers: strategiesAndMultipliers,
            _bEIGEN: _bEIGEN,
            _EIGEN: _EIGEN
        });
        _EIGEN = IERC20(address(1001));
    }

    function test_deployRevertsWithBadFirstSubmissionStart() public {
        _firstSubmissionStartTimestamp = 1;
        cheats.expectRevert("RewardAllStakersActionGenerator: RewardsSubmissions must start at a multiple of CALCULATION_INTERVAL_SECONDS");
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: IRewardsCoordinator(address(rewardsCoordinatorMock)),
            _firstSubmissionStartTimestamp: _firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: _firstSubmissionTriggerCutoff,
            _amounts: amounts,
            _strategiesAndMultipliers: strategiesAndMultipliers,
            _bEIGEN: _bEIGEN,
            _EIGEN: _EIGEN
        });
    }

    function test_deployRevertsWithEmptyStrategies() public {
        cheats.expectRevert("RewardAllStakersActionGenerator: empty strategies array not allowed");
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: IRewardsCoordinator(address(rewardsCoordinatorMock)),
            _firstSubmissionStartTimestamp: _firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: _firstSubmissionTriggerCutoff,
            _amounts: amounts,
            _strategiesAndMultipliers: strategiesAndMultipliers,
            _bEIGEN: _bEIGEN,
            _EIGEN: _EIGEN
        });
    }

    function test_deployRevertsWithUnorderedStrategies() public {
        strategiesAndMultipliers[0].push(IRewardsCoordinator.StrategyAndMultiplier({
            strategy: IStrategy(address(_EIGEN)),
            multiplier: 1e18
        }));
        strategiesAndMultipliers[0].push(IRewardsCoordinator.StrategyAndMultiplier({
            strategy: IStrategy(address(_EIGEN)),
            multiplier: 1e18
        }));

        cheats.expectRevert("RewardAllStakersActionGenerator: strategies must be in ascending order for submission");
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: IRewardsCoordinator(address(rewardsCoordinatorMock)),
            _firstSubmissionStartTimestamp: _firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: _firstSubmissionTriggerCutoff,
            _amounts: amounts,
            _strategiesAndMultipliers: strategiesAndMultipliers,
            _bEIGEN: _bEIGEN,
            _EIGEN: _EIGEN
        });
    }
}
