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

    address internal constant OLD_TOKEN_HOPPER = 0x0ffC6AC10515EE0F83fEE71FCaf5Ea5805256563;

    /// -----------------------------------------------------------------------
    /// Deployment Parameters
    /// -----------------------------------------------------------------------

    /// @dev The weekly distribution of EIGEN supply for EIGEN stakers.
    /// Denominated in WAD (18 decimals).
    uint256 internal constant EIGEN_STAKERS_WEEKLY_DISTRIBUTION = 1346839.922406590295857988 ether;

    /// @dev The weekly distribution of EIGEN supply for ETH stakers.
    /// Denominated in WAD (18 decimals).
    uint256 internal constant ETH_STAKERS_WEEKLY_DISTRIBUTION = 1010129.941804942721893491 ether;

    /// @dev The unix start timestamp of the first submission.
    /// Rewards submissions are prevented before this date.
    /// Must be a multiple of `CALCULATION_INTERVAL_SECONDS` (1 week).
    uint32 internal constant FIRST_SUBMISSION_START_TIMESTAMP = 1759968000; // Thu Oct 09 2025 00:00:00 GMT+0000

    /// @dev The cutoff unix timestamp of the first submission.
    /// Before this cutoff, the `RewardAllStakersActionGenerator` uses special "catch-up" logic that allows
    /// multiple weeks of rewards to be distributed in a single submission. This handles the case where
    /// the rewards distribution might start late (e.g., if deployed after `FIRST_SUBMISSION_START_TIMESTAMP`).
    /// After this cutoff, normal weekly distribution logic applies (one week of rewards per submission).
    /// NOTE: PIV2 DOES NOT USE "CATCH-UP" LOGIC. Hence, this value is set to 0.
    uint256 internal constant FIRST_SUBMISSION_TRIGGER_CUTOFF = 0; // Thu Jan 01 1970 00:00:00 GMT+0000

    /// -----------------------------------------------------------------------
    /// Deployment Test Parameters
    /// -----------------------------------------------------------------------

    /// @dev The expected yearly percentage distribution of EIGEN supply for EIGEN stakers.
    /// Denominated in WAD (18 decimals).
    uint256 internal constant EXPECTED_YEARLY_EIGEN_STAKER_DISTRIBUTION = 0.04 ether;

    /// @dev The expected yearly percentage distribution of EIGEN supply for ETH stakers.
    /// Denominated in WAD (18 decimals).
    uint256 internal constant EXPECTED_YEARLY_ETH_STAKER_DISTRIBUTION = 0.03 ether;

    /// @dev The starting total supply of EIGEN.
    /// Denominated in WAD (18 decimals).
    uint256 internal constant STARTING_EIGEN_SUPPLY = 1750891899.128567384615384679 ether;

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
        TimeUtils.assertEq(FIRST_SUBMISSION_START_TIMESTAMP, "Thu Oct 09 2025 00:00:00 GMT+0000");
        TimeUtils.assertEq(FIRST_SUBMISSION_TRIGGER_CUTOFF, "Thu Jan 01 1970 00:00:00 GMT+0000");
        assertGt(
            EIGEN_STAKERS_WEEKLY_DISTRIBUTION,
            ETH_STAKERS_WEEKLY_DISTRIBUTION,
            "ETH stakers expected to get larger share of distribution"
        );
        assertApproxEqAbs({
            left: EIGEN_STAKERS_WEEKLY_DISTRIBUTION * 52,
            right: STARTING_EIGEN_SUPPLY * EXPECTED_YEARLY_EIGEN_STAKER_DISTRIBUTION / 1 ether,
            maxDelta: 100 wei
        });
        // error: "Total EIGEN supply distributed over 52 weeks to EIGEN stakers is incorrect"

        assertApproxEqAbs({
            left: ETH_STAKERS_WEEKLY_DISTRIBUTION * 52,
            right: STARTING_EIGEN_SUPPLY * EXPECTED_YEARLY_ETH_STAKER_DISTRIBUTION / 1 ether,
            maxDelta: 100 wei
        });
        // error: "Total EIGEN supply distributed over 52 weeks to ETH stakers is incorrect"

        string memory toml = vm.readFile("./script/mainnet.toml");
        address[] memory strategies = vm.parseTomlAddressArray(toml, ".strategies.strategies");
        uint256[] memory multipliers = vm.parseTomlUintArray(toml, ".multipliers.multipliers");

        strategiesAndMultipliers[0].push(
            IRewardsCoordinatorTypes.StrategyAndMultiplier({
                strategy: IStrategy(address(Env.proxy.eigenStrategy())),
                multiplier: 1e18
            })
        );

        // write sorted array and multipliers
        for (uint256 i = 0; i < strategies.length; ++i) {
            strategiesAndMultipliers[1].push(
                IRewardsCoordinatorTypes.StrategyAndMultiplier({
                    strategy: IStrategy(strategies[i]),
                    multiplier: uint96(multipliers[i])
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
            initialOwner: address(0) // No rights are conferred to owner (since hopper is non-expiring).
        });

        // 3) Update enviorment variables for `actionGenerator` and `tokenHopper`.
        zUpdate("actionGenerator", address(actionGenerator));
        zUpdate("tokenHopper", address(tokenHopper));

        vm.stopBroadcast();
    }
}
