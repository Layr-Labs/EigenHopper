// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {QueueGrantMintingRights} from "./2-queueGrantMintingRights.s.sol";
import {SetRewardsPermissionPt1} from "./3-setRewardsPermissionPt1.s.sol";
import {HopperEnv} from "script/HopperEnv.sol";
import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import {ZEnvHelpers} from "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";

contract SetRewardsPermissionPt2 is SetRewardsPermissionPt1 {
    using HopperEnv for *;
    using Env for *;
    using ZEnvHelpers for *;

    function _runAsMultisig() internal virtual override prank(Env.opsMultisig()) {
        Env.proxy.rewardsCoordinator().setRewardsForAllSubmitter(OLD_TOKEN_HOPPER, false);
    }

    function testScript() public virtual override {
        _runAsEOA();

        // Set the rewards permission for the new token hopper
        SetRewardsPermissionPt1._runAsMultisig();
        // reset hasPranked so we can use it again
        _unsafeResetHasPranked();

        // Set the rewards permission for the old token hopper
        _runAsMultisig();

        // Validate that the token hopper has the permission (from step 3)
        assertTrue(
            Env.proxy.rewardsCoordinator().isRewardsForAllSubmitter(address(HopperEnv.impl.tokenHopper())),
            "token hopper does not have requisite permission on rewardsCoordinator"
        );

        assertFalse(
            Env.proxy.rewardsCoordinator().isRewardsForAllSubmitter(OLD_TOKEN_HOPPER),
            "old token hopper still has permission on rewardsCoordinator"
        );
    }
}
