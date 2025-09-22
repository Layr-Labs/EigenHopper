// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {QueueGrantMintingRights} from "./2-queueGrantMintingRights.s.sol";
import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import {ZEnvHelpers} from "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";

contract SetRewardsPermission is QueueGrantMintingRights {
    using Env for *;
    using ZEnvHelpers for *;

    address internal constant OLD_TOKEN_HOPPER = 0x0ffC6AC10515EE0F83fEE71FCaf5Ea5805256563;

    function _runAsMultisig() internal virtual override prank(Env.opsMultisig()) {
        Env.proxy.rewardsCoordinator().setRewardsForAllSubmitter(_tokenHopper(), true);
        Env.proxy.rewardsCoordinator().setRewardsForAllSubmitter(OLD_TOKEN_HOPPER, false);
    }

    function testScript() public virtual override {
        _runAsEOA();
        _runAsMultisig();

        // Validate that the token hopper has the permission
        assertTrue(
            Env.proxy.rewardsCoordinator().isRewardsForAllSubmitter(_tokenHopper()),
            "token hopper does not have requisite permission on rewardsCoordinator"
        );

        assertFalse(
            Env.proxy.rewardsCoordinator().isRewardsForAllSubmitter(OLD_TOKEN_HOPPER),
            "old token hopper still has permission on rewardsCoordinator"
        );
    }

    /// @dev Internal helper to improve readability.
    function _tokenHopper() internal view returns (address) {
        return ZEnvHelpers.state().envAddress("tokenHopper");
    }
}
