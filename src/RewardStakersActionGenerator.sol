// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

import { IHopperActionGenerator } from "./interfaces/IHopperActionGenerator.sol";
import { IRewardsCoordinator } from "./interfaces/IRewardsCoordinator.sol";

// We are going to use the standard OZ interfaces and implementations
import "openzeppelin-contracts/contracts/interfaces/IERC20.sol";

/**
 * RewardStakersActionGenerator 
 *
 * A minimal implementation of the action generator interface that will
 * use the RewardsCoordinator::createRewardsForAllSubmission() interface.
 *
 * This implementation gives the deployer the ability to pre-select the
 * RewardSubmission array that is passed into that API, with a modulo
 * startTimestamp that coincides with the start epoch of the next upcoming rewards
 * epoch boundary.
 */
contract RewardStakersActionGenerator is IHopperActionGenerator {
    /**
     * RewardSubmissionShell
     *
     * This is technically a shell because it does not have
     * everything it needs to be considered a reward submission,
     * as it is missing the token and startTimestamp, which is supplied
     * at runtime.
     */
    struct RewardSubmissionShell {
        IRewardsCoordinator.StrategyAndMultiplier[] strategyAndMultipliers;
        uint256   amount;
        uint32    duration;
    }

    // We will use the shells to generate and populate the correct startTimestamp for each
    // one, depending on the current block height.
    RewardSubmissionShell[] public shells;
    IRewardsCoordinator public rewardCoordinator; 

    // this is calculated on deployment and is what allowance is needed to be set
    // for each set of actions to successfully complete.
    uint256 public requiredAllowance;

    // TODO: Getting embedded custom struct copy errors here, need to flatten.
    constructor(IRewardsCoordinator coordinator, RewardSubmissionShell[] memory configShells) {
        // for(uint256 x = 0; x < configShells.length; x++) {
            //shells.push(configShells[x]);

            // spool up the full required allowance that will need
            // to be set for each set of actions upfront.
            // requiredAllowance += configShells[x].amount;
        // }
        rewardCoordinator = coordinator;
    }

    /**
     * generateHopperActions()
     *
     *
     * This method transforms the stored shells into full RewardSubmission objects by hydrating
     * the token with the one supplied from the hopperToken, and determining the next upcoming
     * reward epoch start time from the reward coordinator.
     *
     * @param hopper      the address of the ITokenHopper you want to generate actions for.
     * @param hopperToken the contract address of the token that is loaded into the hopper.
     *
     * @return a list of hopper actions that are presumably to be executed by the hopper in the same transaction.
     */
    function generateHopperActions(address hopper, address hopperToken) external view returns(HopperAction[] memory) {
        // determine the correct start timestamp given the current block timestamp
        // and the configuration from the reward coordiantor.
        // NOTE: I do not understand why this isn't a uint256 and instead a uint32
        //uint32 startTimestamp = 0; // TODO: Determine Logic 

        // hydrate a Reward Submission array with proper hopperToken and timestamp values
        //IRewardsCoordinator.RewardsSubmission[] memory submissions = 
        //    new IRewardsCoordinator.RewardsSubmission[](shells.length);
       /*
        for(uint256 x = 0; x < shells.length; x++) {
            // painfully copy everything over, this is likely expensive.
            submissions[x].strategiesAndMultipliers = new
                IRewardsCoordinator.StrategyAndMultiplier[](submissions[x].strategiesAndMultipliers.length);
            for(uint256 y = 0; y < submissions[x].strategiesAndMultipliers.length; y++) {
                submissions[x].strategiesAndMultipliers[y].strategy = shells[x].strategyAndMultipliers[y].strategy;
                submissions[x].strategiesAndMultipliers[y].multiplier = shells[x].strategyAndMultipliers[y].multiplier;
            }

            // get the rest of it, which is thankfully less gassy
            //submissions[x].amount = shells[x].amount;
            //submissions[x].token  = IERC20(hopperToken);
            //submissions[x].duration = shells[x].duration;
            //submissions[x].startTimestamp = startTimestamp;
        } */
        
        // serialize the following into HopperActions:
        HopperAction[] memory actions = new HopperAction[](0); 
        
        // 1) Set the proper aggregate allowance on the coordinator for the hopper
        
        // 2) Call the reward coordinator's ForAll API, serializing the submission array as calldata.

        // return array of hopper actions
        return actions; 
    }

}
