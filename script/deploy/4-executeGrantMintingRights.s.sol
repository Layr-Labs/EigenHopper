// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {SetRewardsPermission} from "./3-setRewardsPermission.s.sol";
import {QueueGrantMintingRights} from "./2-queueGrantMintingRights.s.sol";
import {Deploy} from "./1-eoa.s.sol";

import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";
import {MultisigBuilder} from "eigenlayer-contracts/lib/zeus-templates/src/templates/MultisigBuilder.sol";
import "eigenlayer-contracts/lib/zeus-templates/src/utils/Encode.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract ExecuteUpgradeAndSetTimestampSubmitter is SetRewardsPermission {
    using Env for *;
    using Encode for *;
    using ZEnvHelpers for *;

    function _runAsMultisig()
        internal
        virtual
        override
        prank(Env.protocolCouncilMultisig())
    {
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

    // function testScript() public virtual override(QueueUnpause, Pause) {
    //     // 1-4 are completed in _completeSteps1_4()
    //     _completeSteps1_4();

    //     // Warp past delay
    //     TimelockController timelock = Env.timelockController();
    //     vm.warp(block.timestamp + timelock.getMinDelay()); // 1 tick after ETA
    //     assertEq(timelock.isOperationReady(QueueUpgradeAndTimestampSetter.getTimelockId()), true, "Transaction should be executable.");

    //     // 5. Execute
    //     execute();
    //     assertTrue(timelock.isOperationDone(QueueUpgradeAndTimestampSetter.getTimelockId()), "Transaction should be complete.");

    //     // Validate that the operations multisig is the timestamp submitter
    //     assertEq(Env.proxy.eigenPodManager().proofTimestampSetter(), Env.opsMultisig(), "Timestamp submitter is not the operations multisig");

    //     // Check that the unpause is not complete
    //     assertTrue(Env.proxy.eigenPodManager().paused(PAUSED_START_CHECKPOINT), "Not paused!");
    //     assertTrue(Env.proxy.eigenPodManager().paused(PAUSED_EIGENPODS_VERIFY_CREDENTIALS), "Not paused!");
    //     assertFalse(timelock.isOperationDone(QueueUnpause.getTimelockId()), "Transaction should NOT be complete.");

    //     // Validations
    //     _validateNewImplAddresses(true);
    //     _validateProxyAdmins();
    //     _validateProxyConstructors();
    //     _validateProxiesInitialized();
    // }

    // function _completeSteps1_4() internal {
    //      // 0. Get Queue Transactions
    //     TimelockController timelock = Env.timelockController();
    //     assertFalse(timelock.isOperationPending(QueueUpgradeAndTimestampSetter.getTimelockId()), "Transaction should not be queued.");
    //     assertFalse(timelock.isOperationReady(QueueUnpause.getTimelockId()), "Transaction should not be ready for execution.");

    //     // 1. Deploy Impls
    //     runAsEOA();

    //     // 2. Queue Upgrade and Set Timestamp Submitter
    //     QueueUpgradeAndTimestampSetter._runAsMultisig();
    //     _unsafeResetHasPranked(); // reset hasPranked so we can use it again

    //     assertTrue(timelock.isOperationPending(QueueUpgradeAndTimestampSetter.getTimelockId()), "Transaction should be queued.");
    //     assertFalse(timelock.isOperationReady(QueueUpgradeAndTimestampSetter.getTimelockId()), "Transaction should NOT be ready for execution.");
    //     assertFalse(timelock.isOperationDone(QueueUpgradeAndTimestampSetter.getTimelockId()), "Transaction should NOT be complete.");

    //     // 3. Queue Unpause
    //     QueueUnpause._runAsMultisig();
    //     _unsafeResetHasPranked(); // reset hasPranked so we can use it again

    //     assertTrue(timelock.isOperationPending(QueueUnpause.getTimelockId()), "Transaction should be queued.");
    //     assertFalse(timelock.isOperationReady(QueueUnpause.getTimelockId()), "Transaction should NOT be ready for execution.");
    //     assertFalse(timelock.isOperationDone(QueueUnpause.getTimelockId()), "Transaction should NOT be complete.");

    //     // 4. Run Pausing Logic
    //     Pause._runAsMultisig();
    //     _unsafeResetHasPranked(); // reset hasPranked so we can use it again

    //     assertTrue(Env.proxy.eigenPodManager().paused(PAUSED_START_CHECKPOINT), "Not paused!");
    //     assertTrue(Env.proxy.eigenPodManager().paused(PAUSED_EIGENPODS_VERIFY_CREDENTIALS), "Not paused!");
    // }
}
