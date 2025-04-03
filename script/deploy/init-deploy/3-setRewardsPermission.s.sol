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

    function testScript() public virtual override {
        _runAsEOA();
        _runAsMultisig();

        // Validate that the token hopper has the permission
        assertEq(Env.proxy.rewardsCoordinator().isRewardsForAllSubmitter(ZEnvHelpers.state().envAddress("tokenHopper")), true,
            "token hopper does not have requisite permission on rewardsCoordinator");
    }

}