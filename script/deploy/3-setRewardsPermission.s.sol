// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;


import {QueueGrantMintingRights} from "./2-queueGrantMintingRights.s.sol";
import {Deploy} from "./1-eoa.s.sol";

import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";


contract SetRewardsPermission is QueueGrantMintingRights {
    using Env for *;
    using ZEnvHelpers for *;

    function _runAsMultisig() prank(Env.opsMultisig()) internal virtual override {
        Env.proxy.rewardsCoordinator().setRewardsForAllSubmitter(ZEnvHelpers.state().envAddress("tokenHopper"), true);
    }

    // function testScript() public virtual override {
    //     // 1-4 are completed in _completeSteps1_4()
    //     _completeSteps1_4();

    //     // Warp past delay
    //     TimelockController timelock = Env.timelockController();
    //     vm.warp(block.timestamp + timelock.getMinDelay()); // 1 tick after ETA

    //     // 5. Execute Upgrade and Set Timestamp Submitter
    //     ExecuteUpgradeAndSetTimestampSubmitter._runAsMultisig();
    //     _unsafeResetHasPranked();

    //     // 6. Set the proof timestamp
    //     // This test uses the actual pectra fork timestamp, hence why `forkTimestamp.txt` already has a set timestamp
    //     execute();   

    //     // Validate that the proof timestamp is set
    //     assertEq(Env.proxy.eigenPodManager().pectraForkTimestamp(), proofTimestamp, "Proof timestamp is not set");
    // }

}