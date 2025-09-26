// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import {HopperEnv} from "script/HopperEnv.sol";
import {EOADeployer} from "eigenlayer-contracts/lib/zeus-templates/src/templates/EOADeployer.sol";
import {ZEnvHelpers} from "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";
import {
    IRewardsCoordinatorTypes, IStrategy
} from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import {ITokenHopper, TokenHopper} from "src/TokenHopper.sol";
import {RewardAllStakersActionGenerator} from "src/RewardAllStakersActionGenerator.sol";
import {TimeUtils} from "test/utils/TimeUtils.t.sol";

contract Deploy is EOADeployer {
    using HopperEnv for *;
    using Env for *;
    using ZEnvHelpers for *;

    address internal constant OLD_TOKEN_HOPPER = 0x0ffC6AC10515EE0F83fEE71FCaf5Ea5805256563;
    address internal constant OLD_ACTION_GENERATOR = 0x99E6a294349072F9873081Cde9AC9eeb7Fd1F9dE;

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
    /// Storage
    /// -----------------------------------------------------------------------
    IRewardsCoordinatorTypes.StrategyAndMultiplier[][2] public strategiesAndMultipliers;

    function _runAsEOA() internal override {
        constructArrays();
        deployContracts();
    }

    function testDeploy() public virtual {
        _runAsEOA();

        // Verify critical configs match old deployment
        verifyConfigsMatch();
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

    function verifyConfigsMatch() internal view {
        // Store tokenHopper and actionGenerator addresses
        TokenHopper tokenHopper = HopperEnv.impl.tokenHopper();
        RewardAllStakersActionGenerator actionGenerator = HopperEnv.impl.actionGenerator();

        // Get old configs
        ITokenHopper.HopperConfiguration memory oldHopperConfig =
            ITokenHopper(OLD_TOKEN_HOPPER).getHopperConfiguration();
        RewardAllStakersActionGenerator oldActionGen = RewardAllStakersActionGenerator(OLD_ACTION_GENERATOR);

        // Get new configs
        ITokenHopper.HopperConfiguration memory newHopperConfig = tokenHopper.getHopperConfiguration();

        // Critical TokenHopper checks - these MUST match
        assertEq(oldHopperConfig.token, newHopperConfig.token, "Token address must match");
        assertEq(oldHopperConfig.cooldownSeconds, newHopperConfig.cooldownSeconds, "Cooldown must match");
        assertEq(oldHopperConfig.doesExpire, newHopperConfig.doesExpire, "Expiry setting must match");

        // Critical ActionGenerator checks - these MUST match
        assertEq(
            oldActionGen.rewardsCoordinator(), actionGenerator.rewardsCoordinator(), "RewardsCoordinator must match"
        );
        assertEq(address(oldActionGen.bEIGEN()), address(actionGenerator.bEIGEN()), "bEIGEN must match");
        assertEq(address(oldActionGen.EIGEN()), address(actionGenerator.EIGEN()), "EIGEN must match");

        // Verify strategies and multipliers match
        verifyStrategiesMatch(oldActionGen, actionGenerator);

        // Verify multipliers are within bounds: [1e18, 1.25e18]
        verifyMultipliersWithinBounds(actionGenerator);
    }

    function verifyStrategiesMatch(RewardAllStakersActionGenerator oldGen, RewardAllStakersActionGenerator newGen)
        internal
        view
    {
        // Verify EIGEN stakers strategies (index 0)
        assertEq(strategiesAndMultipliers[0].length, 1, "EIGEN strategies length");
        (IStrategy oldEigenStrat, uint96 oldEigenMult) = oldGen.strategiesAndMultipliers(0, 0);
        (IStrategy newEigenStrat, uint96 newEigenMult) = newGen.strategiesAndMultipliers(0, 0);
        assertEq(address(oldEigenStrat), address(newEigenStrat), "EIGEN strategy mismatch");
        assertEq(oldEigenMult, newEigenMult, "EIGEN multiplier mismatch");

        // Verify ETH stakers strategies (index 1) - should match what's in mainnet.toml
        for (uint256 i = 0; i < strategiesAndMultipliers[1].length; i++) {
            (IStrategy oldStrat,) = oldGen.strategiesAndMultipliers(1, i);
            (IStrategy newStrat,) = newGen.strategiesAndMultipliers(1, i);
            assertEq(address(oldStrat), address(newStrat), "ETH strategy mismatch");
        }
    }

    function verifyMultipliersWithinBounds(RewardAllStakersActionGenerator gen) internal view {
        // Eigen Strategy
        (, uint96 eigenMult) = gen.strategiesAndMultipliers(0, 0);
        assertGe(eigenMult, 1e18);

        // ETH Strategies
        for (uint256 i = 0; i < strategiesAndMultipliers[1].length; i++) {
            (, uint96 mult) = gen.strategiesAndMultipliers(1, i);
            assertGe(mult, 1e18);
            assertLe(mult, 1.25e18);
        }
    }

    /// -----------------------------------------------------------------------
    /// Deployment
    /// -----------------------------------------------------------------------

    function deployContracts() internal {
        vm.startBroadcast();

        // 1) Deploy `RewardAllStakersActionGenerator`.
        deployImpl({
            name: type(RewardAllStakersActionGenerator).name,
            deployedTo: address(
                new RewardAllStakersActionGenerator({
                    _rewardsCoordinator: address(Env.proxy.rewardsCoordinator()),
                    _firstSubmissionStartTimestamp: FIRST_SUBMISSION_START_TIMESTAMP,
                    _firstSubmissionTriggerCutoff: FIRST_SUBMISSION_TRIGGER_CUTOFF,
                    _amounts: [EIGEN_STAKERS_WEEKLY_DISTRIBUTION, ETH_STAKERS_WEEKLY_DISTRIBUTION],
                    _strategiesAndMultipliers: strategiesAndMultipliers,
                    _bEIGEN: Env.proxy.beigen(),
                    _EIGEN: Env.proxy.eigen()
                })
            )
        });

        // 2) Deploy `TokenHopper`.
        deployImpl({
            name: type(TokenHopper).name,
            deployedTo: address(
                new TokenHopper({
                    config: ITokenHopper.HopperConfiguration({
                        token: address(Env.proxy.eigen()),
                        startTime: FIRST_SUBMISSION_START_TIMESTAMP,
                        cooldownSeconds: 1 weeks,
                        actionGenerator: address(HopperEnv.impl.actionGenerator()),
                        doesExpire: false,
                        expirationTimestamp: type(uint256).max
                    }),
                    initialOwner: address(0)
                })
            )
        });

        vm.stopBroadcast();
    }
}
