// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {Deploy} from "./1-eoa.s.sol";

import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";
import {MultisigBuilder} from "eigenlayer-contracts/lib/zeus-templates/src/templates/MultisigBuilder.sol";
import "eigenlayer-contracts/lib/zeus-templates/src/utils/Encode.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract QueueGrantMintingRights is MultisigBuilder, Deploy {
    using Env for *;
    using Encode for *;
    using ZEnvHelpers for *;

    function _runAsMultisig()
        internal
        virtual
        override
        prank(Env.opsMultisig())
    {
        bytes memory calldata_to_executor = _getCalldataToExecutor_queueChanges();

        TimelockController timelock = Env.timelockController();
        timelock.schedule({
            target: Env.executorMultisig(),
            value: 0,
            data: calldata_to_executor,
            predecessor: 0,
            salt: 0,
            delay: timelock.getMinDelay()
        });
    }

    /// @dev Get the calldata to be sent from the timelock to the executor
    function _getCalldataToExecutor_queueChanges() internal virtual returns (bytes memory) {
        MultisigCall[] storage executorCalls = Encode
            .newMultisigCalls()
            .append({
                to: address(Env.proxy.beigen()),
                // data: abi.encodeWithSignature("setIsMinter(address,bool)", Env.tokenHopper(), true)
                data: abi.encodeWithSignature("setIsMinter(address,bool)", ZEnvHelpers.state().envAddress("tokenHopper"), true)
            });

        // Set the timestamp submitter to the ops multisig
        // executorCalls.append({
        //     to: address(Env.proxy.eigenPodManager()),
        //     data: abi.encodeCall(EigenPodManager.setProofTimestampSetter, (address(Env.opsMultisig())))
        // });
            
        return
            Encode.gnosisSafe.execTransaction({
                from: address(Env.timelockController()),
                to: address(Env.multiSendCallOnly()),
                op: Encode.Operation.DelegateCall,
                data: Encode.multiSend(executorCalls)
            });
    }

    function testScript() public virtual {
        runAsEOA();

        TimelockController timelock = Env.timelockController();
        bytes memory calldata_to_executor = _getCalldataToExecutor_queueChanges();
        bytes32 txHash = timelock.hashOperation({
            target: Env.executorMultisig(),
            value: 0,
            data: calldata_to_executor,
            predecessor: 0,
            salt: 0
        });

        // Check that the upgrade does not exist in the timelock
        assertFalse(
            timelock.isOperationPending(txHash),
            "Transaction should NOT be queued."
        );

        execute();

        // Check that the upgrade has been added to the timelock
        assertTrue(
            timelock.isOperationPending(txHash),
            "Transaction should be queued."
        );
    }

    function getTimelockId() public virtual returns (bytes32) {
        TimelockController timelock = Env.timelockController();
        bytes memory calldata_to_executor = _getCalldataToExecutor_queueChanges();
        return timelock.hashOperation({
            target: Env.executorMultisig(),
            value: 0,
            data: calldata_to_executor,
            predecessor: 0,
            salt: 0
        });
    }
}
