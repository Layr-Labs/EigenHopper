// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.12;

import { IHopperActionGenerator } from "./interfaces/IHopperActionGenerator.sol";
import { IRewardsCoordinator } from "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

// We are going to use the standard OZ interfaces and implementations
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

/**
 * RewardAllStakersActionGenerator 
 *
 * An implementation of the action generator interface that will
 * use the RewardsCoordinator::createRewardsForAllSubmission() interface.
 *
 * This implementation gives the deployer the ability to pre-select the
 * RewardSubmission array that is passed into that API, with an end timestamp
 * that coincides with the end of the last completed rewards
 * epoch boundary.
 */
contract RewardAllStakersActionGenerator is IHopperActionGenerator {

    // one week in seconds. used in the RewardsCoordinator and as a duration in this contract
    uint32 public constant CALCULATION_INTERVAL_SECONDS = 604800;

    // the single RewardsCoordinator contract for EigenLayer
    IRewardsCoordinator public immutable rewardsCoordinator;
    // the bEIGEN token contract
    IERC20 public immutable bEIGEN;
    // the EIGEN token contract
    IERC20 public immutable EIGEN;

    // configuration set at construction, used in RewardsSubmissions
    IRewardsCoordinator.StrategyAndMultiplier[][2] public strategiesAndMultipliers;
    uint256[2] public amounts;

    // timestamps used for special logic for the first submission
    // defines the fixed start time of the first submission
    uint32 public firstSubmissionStartTimestamp;
    // defines the time period after which the special first submission logic will cease
    uint256 public firstSubmissionTriggerCutoff;

    constructor(
        IRewardsCoordinator _rewardsCoordinator,
        uint32 _firstSubmissionStartTimestamp,
        uint256 _firstSubmissionTriggerCutoff,
        uint256[2] memory _amounts,
        IRewardsCoordinator.StrategyAndMultiplier[][2] memory _strategiesAndMultipliers,
        IERC20 _bEIGEN,
        IERC20 _EIGEN
    )
    {
        // RewardsSubmissions must start at a multiple of CALCULATION_INTERVAL_SECONDS
        require(_firstSubmissionStartTimestamp % CALCULATION_INTERVAL_SECONDS == 0,
            "RewardStakersActionGenerator: RewardsSubmissions must start at a multiple of CALCULATION_INTERVAL_SECONDS");

        rewardsCoordinator = _rewardsCoordinator;

        firstSubmissionStartTimestamp = _firstSubmissionStartTimestamp;
        firstSubmissionTriggerCutoff = _firstSubmissionTriggerCutoff;

        amounts = _amounts;

        for (uint256 i = 0; i < 2; ++i) {
            for (uint256 j = 0; j < _strategiesAndMultipliers[i].length; ++j) {
                strategiesAndMultipliers[i].push(
                    IRewardsCoordinator.StrategyAndMultiplier({
                        strategy: _strategiesAndMultipliers[i][j].strategy,
                        multiplier: _strategiesAndMultipliers[i][j].multiplier
                    })
                );
            }
        }

        bEIGEN = _bEIGEN;
        EIGEN = _EIGEN;
    }

    function generateHopperActions(address hopper, address /*hopperToken*/) external view returns (HopperAction[] memory) {
        HopperAction[] memory actions = new HopperAction[](5); 

        uint256 totalAmount;
        uint32 startTimestamp;
        uint32 duration;
        uint256[2] memory amountsToUse;

        // special logic for first submission
        if (block.timestamp <= firstSubmissionTriggerCutoff) {
            uint32 multiple = (uint32(block.timestamp) - firstSubmissionStartTimestamp) / CALCULATION_INTERVAL_SECONDS;
            duration = CALCULATION_INTERVAL_SECONDS * multiple;

            startTimestamp = firstSubmissionStartTimestamp;

            amountsToUse[0] = amounts[0] * multiple;
            amountsToUse[1] = amounts[1] * multiple;
        // normal logic for all others
        } else {
            duration = CALCULATION_INTERVAL_SECONDS;

            // find the correct startTimestamp.
            // RewardsSubmissions must start at a multiple of CALCULATION_INTERVAL_SECONDS
            uint32 calculationIntervalNumber = uint32(block.timestamp) / CALCULATION_INTERVAL_SECONDS;
            // after rounding to the latest completed calculation interval to find the end, we subtract out the duration to get the start
            startTimestamp = (calculationIntervalNumber * CALCULATION_INTERVAL_SECONDS) - duration;

            amountsToUse[0] = amounts[0];
            amountsToUse[1] = amounts[1];
        }

        // HopperAction memory rewardsSubmissions;
        // rewardsSubmissions.target = rewardsCoordinator;
        IRewardsCoordinator.RewardsSubmission[] memory rewardsSubmissions = new IRewardsCoordinator.RewardsSubmission[](2);
        for (uint256 i = 0; i < 2; ++i) {
            rewardsSubmissions[i] = IRewardsCoordinator.RewardsSubmission({
                strategiesAndMultipliers: strategiesAndMultipliers[i],
                token: EIGEN,
                amount: amountsToUse[i],
                startTimestamp: startTimestamp,
                duration: duration
            });
            totalAmount += amountsToUse[i];
        }

        // 0) mint new tokens
        actions[0] = HopperAction({
            target: address(bEIGEN),
            callData: abi.encodeWithSignature("mint(address,uint256)", hopper, totalAmount)
        });

        // 1) approve the bEIGEN token for transfer so it can be wrapped
        actions[1] = HopperAction({
            target: address(bEIGEN),
            callData: abi.encodeWithSelector(IERC20.approve.selector, address(EIGEN), totalAmount)
        });

        // 2) wrap the bEIGEN token to receive EIGEN
        actions[2] = HopperAction({
            target: address(EIGEN),
            callData: abi.encodeWithSignature("wrap(uint256)", totalAmount)
        });

        // 3) Set the proper aggregate allowance on the coordinator for the hopper
        actions[3] = HopperAction({
            target: address(EIGEN),
            callData: abi.encodeWithSelector(IERC20.approve.selector, rewardsCoordinator, totalAmount)
        });

        // 4) Call the reward coordinator's ForAll API, serializing the submission array as calldata.
        actions[4] = HopperAction({
            target: address(rewardsCoordinator),
            callData: abi.encodeWithSelector(IRewardsCoordinator.createRewardsForAllSubmission.selector, rewardsSubmissions)
        });

        // return array of hopper actions
        return actions; 

    }
}
