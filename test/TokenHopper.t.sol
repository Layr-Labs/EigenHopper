// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetFixedSupply.sol";

import "src/TokenHopper.sol";

import "./mocks/MockActionGenerator.sol";

contract TokenHopperTests is Test {
    Vm cheats = Vm(VM_ADDRESS);

    address public initialOwner = address(this);

    TokenHopper public tokenHopper;
    MockActionGenerator public actionGenerator;

    IERC20 public mockToken;
    uint256 public constant initialSupply = 1e25;

    // Hopper config
    ITokenHopper.HopperConfiguration public hopperConfigurationStorage;
    uint256 public cooldownSeconds = 1 weeks;
    uint256 public expirationTimestamp = 24 weeks;
    bool public doesExpire = true;

    function setUp() public {
        mockToken = new ERC20PresetFixedSupply({
            name: "MOCK TOKEN",
            symbol: "MOCK",
            initialSupply: initialSupply,
            owner: initialOwner
        });

        actionGenerator = new MockActionGenerator();

        tokenHopper = new TokenHopper({
            initialOwner: initialOwner
        });

        hopperConfigurationStorage = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: doesExpire,
            expirationTimestamp: expirationTimestamp
        });
    }

    function test_loadAndPressButton() public {
        ITokenHopper.HopperConfiguration memory hopperConfiguration = hopperConfigurationStorage;
        tokenHopper.load(hopperConfiguration);

        // check integrity of storage
        ITokenHopper.HopperConfiguration memory loadedConfiguration = tokenHopper.getHopperConfiguration();
        require(keccak256(abi.encode(hopperConfiguration)) == keccak256(abi.encode(loadedConfiguration)),
            "stored config does not match loaded config");

        tokenHopper.pressButton();
    }

    function test_load_revertsWhenNotCalledByOwner() public {
        ITokenHopper.HopperConfiguration memory hopperConfiguration;

        address notOwner = address(11);
        cheats.prank(notOwner);
        cheats.expectRevert("Ownable: caller is not the owner");
        tokenHopper.load(hopperConfiguration);
    }

    function test_load_revertsWhenCalledTwice() public {
        ITokenHopper.HopperConfiguration memory hopperConfiguration = hopperConfigurationStorage;
        tokenHopper.load(hopperConfiguration);

        cheats.expectRevert("TokenHopper.load: Hopper is already loaded");
        tokenHopper.load(hopperConfiguration);
    }

    function test_pressButton_canBeCalledByAnyone() public {
        ITokenHopper.HopperConfiguration memory hopperConfiguration = hopperConfigurationStorage;
        tokenHopper.load(hopperConfiguration);

        address notOwner = address(11);
        cheats.prank(notOwner);
        tokenHopper.pressButton();
    }

    function test_pressButton_revertsWhenImmediatelyPressedTwice() public {
        ITokenHopper.HopperConfiguration memory hopperConfiguration = hopperConfigurationStorage;
        tokenHopper.load(hopperConfiguration);

        tokenHopper.pressButton();

        cheats.expectRevert("TokenHopper.pressButton: button currently unpressable.");
        tokenHopper.pressButton();
    }

    function test_pressButton_revertsWhenCallReverts() public {
        ITokenHopper.HopperConfiguration memory hopperConfiguration = hopperConfigurationStorage;
        tokenHopper.load(hopperConfiguration);

        // set up reverting call to precompile with mal-formed data
        IHopperActionGenerator.HopperAction[] memory actions = new IHopperActionGenerator.HopperAction[](1);
        bytes memory callData = abi.encode(address(5));
        actions[0] = IHopperActionGenerator.HopperAction({
            target: address(6),
            callData: callData
        });
        actionGenerator.setActions(actions);

        cheats.expectRevert("TokenHopper.pressButton: call reverted");
        tokenHopper.pressButton();
    }

    function test_retrieveFunds() public {
        ITokenHopper.HopperConfiguration memory hopperConfiguration = hopperConfigurationStorage;
        tokenHopper.load(hopperConfiguration);

        cheats.prank(initialOwner);
        mockToken.transfer(address(tokenHopper), initialSupply);

        uint256 hopperBalanceBefore = mockToken.balanceOf(address(tokenHopper));
        uint256 mockTokenBalanceBefore = mockToken.balanceOf(address(initialOwner));

        cheats.warp(expirationTimestamp);
        cheats.prank(initialOwner);
        tokenHopper.retrieveFunds();

        uint256 hopperBalanceAfter = mockToken.balanceOf(address(tokenHopper));
        uint256 mockTokenBalanceAfter = mockToken.balanceOf(address(initialOwner));

        assertEq(hopperBalanceAfter, 0, "hopper should have no tokens after retrieval");
        assertEq(hopperBalanceBefore - hopperBalanceAfter, mockTokenBalanceAfter - mockTokenBalanceBefore,
            "hopper should transferred tokens to owner");
    }

    function test_retrieveFunds_revertsPriorToExpiration() public {
        ITokenHopper.HopperConfiguration memory hopperConfiguration = hopperConfigurationStorage;
        tokenHopper.load(hopperConfiguration);

        cheats.warp(expirationTimestamp - 1);
        cheats.prank(initialOwner);
        cheats.expectRevert("TokenHopper.retrieveFunds: Hopper is not currently expired.");
        tokenHopper.retrieveFunds();
    }
}
