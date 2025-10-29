// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "src/TokenHopper.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IBackingEigen.sol";

/// @dev Tests what the total supply of bEIGEN should be after the old hopper's last two button presses
contract OldHopperMainnetSimTest is Test {
    Vm cheats = Vm(VM_ADDRESS);

    // Pointer to addresses on mainnet
    TokenHopper public constant hopper = TokenHopper(0x0ffC6AC10515EE0F83fEE71FCaf5Ea5805256563);
    IBackingEigen public constant bEIGEN = IBackingEigen(0x83E9115d334D248Ce39a6f36144aEaB5b3456e75);
    uint256 public bEIGENSupplyAtFork;

    // Block to fork from - September 19th, 2025 @ 14:06:59 
    // There should be two more button presses after this block
    // 1. Thursday, September 25th
    // 2. Thursday, October 2nd
    uint256 forkBlock = 23397616;
    uint256 firstButtonPressTimestamp;
    uint256 secondButtonPressTimestamp;

    // Amount of bEIGEN that is newly minted per-week
    uint256 weeklyInflation = 1_287_420_514_065_123_076_923_078;

    function setUp() public {
        string memory rpcUrl = cheats.envString("RPC_MAINNET");
        cheats.createSelectFork(rpcUrl, forkBlock);

        // Check that the bEIGEN total supply is what is expected
        bEIGENSupplyAtFork = bEIGEN.totalSupply();
        assertEq(bEIGENSupplyAtFork, 1_748_317_058_100_437_138_461_538_523);

        uint256 latestPress = hopper.latestPress();

        firstButtonPressTimestamp = latestPress + 1 weeks;
        secondButtonPressTimestamp = latestPress + 2 weeks;
    }

    function test_simulateMainnet() public {
        // Warp time to the first button press
        cheats.warp(firstButtonPressTimestamp);
        hopper.pressButton();
        
        // Check that the bEIGEN total supply is what is expected
        assertEq(bEIGEN.totalSupply(), bEIGENSupplyAtFork + weeklyInflation);

        // Warp time to the second button press
        cheats.warp(secondButtonPressTimestamp);
        hopper.pressButton();

        // Check that the bEIGEN total supply is what is expected
        assertEq(bEIGEN.totalSupply(), bEIGENSupplyAtFork + weeklyInflation * 2);

        // Assert the final bEIGEN total supply is what is expected from offchain calculations
        assertEq(bEIGEN.totalSupply(), 1_750_891_899_128_567_384_615_384_679);
    }
}