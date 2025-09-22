// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import {EOADeployer} from "eigenlayer-contracts/lib/zeus-templates/src/templates/EOADeployer.sol";
import {ZEnvHelpers} from "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";
import {
    IRewardsCoordinatorTypes, IStrategy
} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {ITokenHopper, TokenHopper} from "src/TokenHopper.sol";
import {RewardAllStakersActionGenerator} from "src/RewardAllStakersActionGenerator.sol";
import {TimeUtils} from "test/utils/TimeUtils.t.sol";

contract Deploy is EOADeployer {
    using Env for *;
    using ZEnvHelpers for *;

    /// -----------------------------------------------------------------------
    /// Deployment Parameters
    /// -----------------------------------------------------------------------

    /// @dev The weekly distribution of EIGEN supply for EIGEN stakers.
    uint256 internal constant EIGEN_STAKERS_WEEKLY_DISTRIBUTION = 321855.12851628076923077 ether;

    /// @dev The weekly distribution of EIGEN supply for ETH stakers.
    uint256 internal constant ETH_STAKERS_WEEKLY_DISTRIBUTION = 965565.385548842307692308 ether;

    /// @dev The start timestamp of the first submission.
    /// Rewards submissions are prevented before this date.
    /// Must be a multiple of `CALCULATION_INTERVAL_SECONDS` (1 week).
    uint32 internal constant FIRST_SUBMISSION_START_TIMESTAMP = 1723680000; // Thu Aug 15 2024 00:00:00 GMT+0000

    /// @dev The cutoff timestamp of the first submission.
    /// Before this cutoff, the `RewardAllStakersActionGenerator` uses special "catch-up" logic that allows
    /// multiple weeks of rewards to be distributed in a single submission. This handles the case where
    /// the rewards distribution might start late (e.g., if deployed after `FIRST_SUBMISSION_START_TIMESTAMP`).
    /// After this cutoff, normal weekly distribution logic applies (one week of rewards per submission).
    uint256 internal constant FIRST_SUBMISSION_TRIGGER_CUTOFF = 1727913600; // Thu Oct 03 2024 00:00:00 GMT+0000

    /// -----------------------------------------------------------------------
    /// Deployment Test Parameters
    /// -----------------------------------------------------------------------

    uint256 internal constant yearlyPercentageEigenStakers = 0.01 ether;

    uint256 internal constant yearlyPercentageEthStakers = 0.03 ether;

    uint256 internal constant totalEigenSupply = 1673646668.28466 ether;

    /// -----------------------------------------------------------------------
    ///
    /// -----------------------------------------------------------------------

    TokenHopper public tokenHopper;
    RewardAllStakersActionGenerator public actionGenerator;
    IRewardsCoordinatorTypes.StrategyAndMultiplier[][2] public strategiesAndMultipliers;

    function _runAsEOA() internal override {
        constructArrays();
        deployContracts();
    }

    function testDeploy() public virtual {
        _runAsEOA();
    }

    function constructArrays() internal {
        TimeUtils.assertEq(FIRST_SUBMISSION_START_TIMESTAMP, "Thu Aug 15 2024 00:00:00 GMT+0000");
        TimeUtils.assertEq(FIRST_SUBMISSION_TRIGGER_CUTOFF, "Thu Oct 03 2024 00:00:00 GMT+0000");
        assertLt(
            EIGEN_STAKERS_WEEKLY_DISTRIBUTION,
            ETH_STAKERS_WEEKLY_DISTRIBUTION,
            "ETH stakers expected to get larger share of distribution"
        );
        assertApproxEqAbs({
            left: EIGEN_STAKERS_WEEKLY_DISTRIBUTION * 52,
            right: totalEigenSupply * yearlyPercentageEigenStakers / 1 ether,
            maxDelta: 100 wei
        });
        // error: "Total EIGEN supply distributed over 52 weeks to EIGEN stakers is incorrect"

        assertApproxEqAbs({
            left: ETH_STAKERS_WEEKLY_DISTRIBUTION * 52,
            right: totalEigenSupply * yearlyPercentageEthStakers / 1 ether,
            maxDelta: 100 wei
        });
        // error: "Total EIGEN supply distributed over 52 weeks to ETH stakers is incorrect"

        strategiesAndMultipliers[0].push(
            IRewardsCoordinatorTypes.StrategyAndMultiplier({
                strategy: IStrategy(address(Env.proxy.eigenStrategy())),
                multiplier: 1e18
            })
        );

        uint256 deployedStrategyCount = Env.instance.strategyBaseTVLLimits_Count();
        uint256[] memory deployedStrategyArray = new uint256[](deployedStrategyCount + 1);
        for (uint256 i = 0; i < deployedStrategyCount; ++i) {
            deployedStrategyArray[i] = uint256(uint160(address(Env.instance.strategyBaseTVLLimits(i))));
        }
        deployedStrategyArray[deployedStrategyCount] =
            uint256(uint160(address(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0)));
        deployedStrategyArray = vm.sort(deployedStrategyArray);

        // write sorted array and multipliers
        for (uint256 i = 0; i < deployedStrategyCount; ++i) {
            strategiesAndMultipliers[1].push(
                IRewardsCoordinatorTypes.StrategyAndMultiplier({
                    strategy: IStrategy(address(uint160(deployedStrategyArray[i]))),
                    // TODO: note that this is hard-coded -- should probably look values up somehow
                    multiplier: 1e18
                })
            );
        }

        assertNotEq(strategiesAndMultipliers[0].length, 0, "sanity");
        assertNotEq(strategiesAndMultipliers[1].length, 0, "sanity");
    }

    function deployContracts() internal {
        vm.startBroadcast();

        // 1) Deploy `RewardAllStakersActionGenerator`.
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: address(Env.proxy.rewardsCoordinator()),
            _firstSubmissionStartTimestamp: FIRST_SUBMISSION_START_TIMESTAMP,
            _firstSubmissionTriggerCutoff: FIRST_SUBMISSION_TRIGGER_CUTOFF,
            _amounts: [EIGEN_STAKERS_WEEKLY_DISTRIBUTION, ETH_STAKERS_WEEKLY_DISTRIBUTION],
            _strategiesAndMultipliers: strategiesAndMultipliers,
            _bEIGEN: Env.proxy.beigen(),
            _EIGEN: Env.proxy.eigen()
        });

        // 2) Deploy `TokenHopper`.
        tokenHopper = new TokenHopper({
            config: ITokenHopper.HopperConfiguration({
                token: address(Env.proxy.eigen()),
                startTime: FIRST_SUBMISSION_START_TIMESTAMP,
                cooldownSeconds: 1 weeks,
                actionGenerator: address(actionGenerator),
                doesExpire: false,
                expirationTimestamp: type(uint256).max
            }),
            initialOwner: address(0) // TODO: Is this wanted?
        });

        // 3) Update enviorment variables for `actionGenerator` and `tokenHopper`.
        zUpdate("actionGenerator", address(actionGenerator));
        zUpdate("tokenHopper", address(tokenHopper));

        vm.stopBroadcast();
    }
}
