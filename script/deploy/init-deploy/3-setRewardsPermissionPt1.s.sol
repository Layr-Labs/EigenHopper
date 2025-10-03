// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {QueueGrantMintingRights} from "./2-queueGrantMintingRights.s.sol";
import {HopperEnv} from "script/HopperEnv.sol";
import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import {ZEnvHelpers} from "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";

contract SetRewardsPermissionPt1 is QueueGrantMintingRights {
    using HopperEnv for *;
    using Env for *;
    using ZEnvHelpers for *;

    function _runAsMultisig() internal virtual override prank(Env.opsMultisig()) {
        Env.proxy.rewardsCoordinator().setRewardsForAllSubmitter(address(HopperEnv.impl.tokenHopper()), true);
    }

    function testScript() public virtual override {
        _runAsEOA();
        _runAsMultisig();

        // Validate that the token hopper has the permission
        assertTrue(
            Env.proxy.rewardsCoordinator().isRewardsForAllSubmitter(address(HopperEnv.impl.tokenHopper())),
            "token hopper does not have requisite permission on rewardsCoordinator"
        );
    }
}
