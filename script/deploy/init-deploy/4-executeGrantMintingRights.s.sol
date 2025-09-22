// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {SetRewardsPermission} from "./3-setRewardsPermission.s.sol";
import {QueueGrantMintingRights} from "./2-queueGrantMintingRights.s.sol";

import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";
import "eigenlayer-contracts/lib/zeus-templates/src/utils/Encode.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract ExecuteUpgradeAndSetTimestampSubmitter is SetRewardsPermission {
    using Env for *;
    using Encode for *;
    using ZEnvHelpers for *;

    function _runAsMultisig() internal virtual override prank(Env.protocolCouncilMultisig()) {
        bytes memory calldata_to_executor = QueueGrantMintingRights._getCalldataToExecutor_queueChanges();

        TimelockController timelock = Env.timelockController();
        timelock.execute({
            target: Env.executorMultisig(),
            value: 0,
            payload: calldata_to_executor,
            predecessor: 0,
            salt: 0
        });
    }

    function testScript() public virtual override {
        _runAsEOA();

        QueueGrantMintingRights._runAsMultisig();
        // reset hasPranked so we can use it again
        _unsafeResetHasPranked();

        SetRewardsPermission._runAsMultisig();
        // reset hasPranked so we can use it again
        _unsafeResetHasPranked();

        // move forward in time so we can execute the action
        vm.warp(block.timestamp + Env.timelockController().getMinDelay());
        _runAsMultisig();

        // Validate that the token hopper has mintingRights
        (bool success, bytes memory returndata) = address(Env.proxy.beigen()).staticcall(
            abi.encodeWithSignature("isMinter(address)", ZEnvHelpers.state().envAddress("tokenHopper"))
        );
        require(success, "call failed");
        bool retVal = abi.decode(returndata, (bool));
        require(retVal, "token hopper does not have minting permission");
    }
}
