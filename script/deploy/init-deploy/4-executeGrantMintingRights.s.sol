// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {SetRewardsPermission} from "./3-setRewardsPermission.s.sol";
import {QueueGrantMintingRights} from "./2-queueGrantMintingRights.s.sol";

import "eigenlayer-contracts/script/releases/Env.sol";
import {ZEnvHelpers} from "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";
import {Encode} from "eigenlayer-contracts/lib/zeus-templates/src/utils/Encode.sol";

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ITokenHopper, TokenHopper} from "src/TokenHopper.sol";
import {IHopperActionGenerator} from "src/interfaces/IHopperActionGenerator.sol";
import {TimeUtils} from "test/utils/TimeUtils.t.sol";

contract ExecuteUpgradeAndSetTimestampSubmitter is SetRewardsPermission {
    using Env for *;
    using Encode for *;
    using ZEnvHelpers for *;

    event ButtonPressed(address indexed caller, uint256 newCooldownHorizon);

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
        // 1. Deploy Impls
        _runAsEOA();

        // 2. Queue Grant Minting Rights
        QueueGrantMintingRights._runAsMultisig();
        // reset hasPranked so we can use it again
        _unsafeResetHasPranked();

        // 3. Set Rewards Permission
        SetRewardsPermission._runAsMultisig();
        // reset hasPranked so we can use it again
        _unsafeResetHasPranked();

        // move forward in time so we can execute the action
        vm.warp(block.timestamp + Env.timelockController().getMinDelay());
        _runAsMultisig();

        // Validate that the token hopper has minting permissions.
        assertTrue(
            IBackingEigen2(address(Env.proxy.beigen())).isMinter(ZEnvHelpers.state().envAddress("tokenHopper")),
            "new token hopper should have minting rights"
        );

        // Validate that the old token hopper does not have minting permissions.
        assertFalse(
            IBackingEigen2(address(Env.proxy.beigen())).isMinter(OLD_TOKEN_HOPPER),
            "old token hopper should not have minting rights"
        );

        // Validate that the old token hopper cannot press the button
        vm.expectRevert("TokenHopper.pressButton: call reverted");
        ITokenHopper(OLD_TOKEN_HOPPER).pressButton();

        // Validate the first submission
        _testFirstPress();

        // TODO: Test multiple cycles. See `ProgrammaticIncentives.t.sol` for examples.
        _testMultiplePresses();
    }

    // Addresses so we don't get stack too deep
    RewardsCoordinator rewardsCoordinator;
    IEigen eigen;
    IBackingEigen beigen;

    // Thu Oct 09 2025 00:00:00 GMT+0000 = 1759968000
    // Thu Oct 16 2025 00:00:00 GMT+0000 = 1729036800
    uint256 oct9th2025 = 1759968000;
    uint256 oct16th2025 = 1760572800;
    uint256 totalSupplyBefore;

    function _testFirstPress() internal {
        // Store addresses (so we don't get stack too deep)
        tokenHopper = TokenHopper(ZEnvHelpers.state().envAddress("tokenHopper"));
        rewardsCoordinator = Env.proxy.rewardsCoordinator();
        eigen = Env.proxy.eigen();
        beigen = Env.proxy.beigen();
        totalSupplyBefore = eigen.totalSupply();

        // Verify timestamps using TimeUtils
        TimeUtils.assertEq(oct9th2025, "Thu Oct 09 2025 00:00:00 GMT+0000");
        TimeUtils.assertEq(oct16th2025, "Thu Oct 16 2025 00:00:00 GMT+0000");

        // 0. Validate that we cannot press the button before the first submission start timestamp.
        vm.expectRevert("TokenHopper._canPress: block.timestamp < startTime");
        tokenHopper.canPress();
        vm.warp(FIRST_SUBMISSION_START_TIMESTAMP);
        assertTrue(tokenHopper.canPress(), "should be able to press button after first submission start timestamp");

        // 1.  get the before state of token balances.
        uint256 rewardsCoordinatorEigenBalanceBefore = eigen.balanceOf(address(rewardsCoordinator));
        uint256 eigenTotalSupplyBefore = eigen.totalSupply();
        uint256 beigenTotalSupplyBefore = beigen.totalSupply();

        // 2. Get the rewards submission configuration.
        // ITokenHopper.HopperConfiguration memory configuration = tokenHopper.getHopperConfiguration();
        uint256 currentNonce = rewardsCoordinator.submissionNonce(address(tokenHopper));
        IRewardsCoordinatorTypes.RewardsSubmission[] memory rewardsSubmissions;
        {
            IHopperActionGenerator.HopperAction[] memory actions =
                actionGenerator.generateHopperActions(address(tokenHopper), address(eigen));
            bytes memory rewardsSubmissionsRaw = this.sliceOffLeadingFourBytes(actions[4].callData);
            rewardsSubmissions = abi.decode(rewardsSubmissionsRaw, (IRewardsCoordinatorTypes.RewardsSubmission[]));
        }

        // Check that the rewards submission start and end time is correct.
        assertEq(
            rewardsSubmissions[0].startTimestamp, oct9th2025, "eigen rewards submission start timestamp is not correct"
        );
        assertEq(rewardsSubmissions[0].duration, 1 weeks, "eigen rewards submission duration is not correct");
        assertEq(
            rewardsSubmissions[1].startTimestamp, oct9th2025, "eth rewards submission start timestamp is not correct"
        );
        assertEq(rewardsSubmissions[1].duration, 1 weeks, "eth rewards submission duration is not correct");

        // 3. Store the expected total amount of rewards to be distributed.
        uint256 totalAmount;
        for (uint256 i = 0; i < rewardsSubmissions.length; ++i) {
            totalAmount += rewardsSubmissions[i].amount;
        }

        // 4. Expect all events that should be emitted.
        // event for minting
        vm.expectEmit(true, true, true, true, address(beigen));
        emit Transfer(address(0), address(tokenHopper), totalAmount);
        // event for approving to wrap
        vm.expectEmit(true, true, true, true, address(beigen));
        emit Approval(address(tokenHopper), address(eigen), totalAmount);
        // events from wrapping
        // spending approval
        vm.expectEmit(true, true, true, true, address(beigen));
        emit Approval(address(tokenHopper), address(eigen), 0);
        // transferring in beigen
        vm.expectEmit(true, true, true, true, address(beigen));
        emit Transfer(address(tokenHopper), address(eigen), totalAmount);
        // minting new eigen to hopper as last step of wrapping
        vm.expectEmit(true, true, true, true, address(eigen));
        emit Transfer(address(0), address(tokenHopper), totalAmount);
        // event for approving RewardsCoordinator to transfer
        vm.expectEmit(true, true, true, true, address(eigen));
        emit Approval(address(tokenHopper), address(rewardsCoordinator), totalAmount);
        // events for RewardsCoordinator performing the transfers
        uint256 remainingAllowance = totalAmount;
        for (uint256 i = 0; i < 2; ++i) {
            IRewardsCoordinatorTypes.RewardsSubmission memory rewardsSubmission = rewardsSubmissions[i];

            bytes32 rewardsSubmissionHash = keccak256(abi.encode(tokenHopper, currentNonce, rewardsSubmission));
            vm.expectEmit(true, true, true, true, address(rewardsCoordinator));
            emit RewardsSubmissionForAllEarnersCreated({
                submitter: address(tokenHopper),
                submissionNonce: currentNonce,
                rewardsSubmissionHash: rewardsSubmissionHash,
                rewardsSubmission: rewardsSubmission
            });
            // spending approval
            vm.expectEmit(true, true, true, true, address(eigen));
            remainingAllowance -= rewardsSubmission.amount;
            emit Approval(address(tokenHopper), address(rewardsCoordinator), remainingAllowance);
            // transferring into RewardsCoordinator
            vm.expectEmit(true, true, true, true, address(eigen));
            emit Transfer(address(tokenHopper), address(rewardsCoordinator), rewardsSubmission.amount);
            currentNonce++;
        }
        // event for pressing button
        vm.expectEmit(true, true, true, true, address(tokenHopper));
        emit ButtonPressed(address(this), oct16th2025);

        // 5. Press the button.
        tokenHopper.pressButton();

        // 6. Verify the after state of token balances.
        uint256 rewardsCoordinatorEigenBalanceAfter = eigen.balanceOf(address(rewardsCoordinator));
        uint256 eigenTotalSupplyAfter = eigen.totalSupply();
        uint256 beigenTotalSupplyAfter = beigen.totalSupply();

        assertEq(rewardsCoordinatorEigenBalanceAfter, rewardsCoordinatorEigenBalanceBefore + totalAmount);
        assertEq(eigenTotalSupplyAfter, eigenTotalSupplyBefore + totalAmount);
        assertEq(beigenTotalSupplyAfter, beigenTotalSupplyBefore + totalAmount);

        // 7. Verify we cannot press again.
        assertFalse(tokenHopper.canPress(), "should not be able to immediately press button again");
        vm.expectRevert("TokenHopper.pressButton: button currently unpressable.");
        tokenHopper.pressButton();

        // Verify that we cannot press again, even right before october 16th.
        vm.warp(oct16th2025 - 1);
        vm.expectRevert("TokenHopper.pressButton: button currently unpressable.");
        tokenHopper.pressButton();
    }

    function _testMultiplePresses() internal {
        vm.warp(oct16th2025);

        uint256 start = block.timestamp;
        for (uint256 i = 0; i < 51 weeks; i += 1 weeks) {
            uint256 currentTimestamp = start + i;

            // Assert that button presses fall on Thursdays.
            TimeUtils.assertWeekdayEq(currentTimestamp, "Thu");

            // Assert that we cannot press the button right before.
            vm.warp(currentTimestamp - 1 seconds);
            vm.expectRevert("TokenHopper.pressButton: button currently unpressable.");
            tokenHopper.pressButton();

            // Assert that we can press the button at the expected time.
            vm.warp(currentTimestamp);
            tokenHopper.pressButton();
        }

        uint256 expectedGrowth = EXPECTED_YEARLY_EIGEN_STAKER_DISTRIBUTION + EXPECTED_YEARLY_ETH_STAKER_DISTRIBUTION;
        uint256 totalSupplyAfter = Env.proxy.eigen().totalSupply();
        assertApproxEqRel(
            totalSupplyAfter,
            totalSupplyBefore * (1 ether + expectedGrowth) / 1 ether,
            0.0001 ether, // 0.01%
            "totalSupplyAfter is not correct (using expectedGrowth)"
        );
    }

    /// @notice returns the `bytestring` with its first four bytes removed. used to slice off function sig
    function sliceOffLeadingFourBytes(bytes calldata bytestring) public pure returns (bytes memory) {
        return bytestring[4:];
    }

    /// Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event RewardsSubmissionForAllEarnersCreated(
        address indexed submitter,
        uint256 indexed submissionNonce,
        bytes32 indexed rewardsSubmissionHash,
        IRewardsCoordinatorTypes.RewardsSubmission rewardsSubmission
    );
}

interface IBackingEigen2 {
    function isMinter(address who) external view returns (bool);
}
