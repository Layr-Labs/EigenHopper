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
    uint256 public startTime = 1 weeks;
    uint256 public cooldownSeconds = 1 weeks;
    uint256 public expirationTimestamp = 24 weeks;
    bool public doesExpire = true;

    event HopperLoaded(ITokenHopper.HopperConfiguration config);
    event ButtonPressed(address indexed caller, uint256 newCooldownHorizon);
    event FundsRetrieved(uint256 amount);

    function setUp() public {
        mockToken = new ERC20PresetFixedSupply({
            name: "MOCK TOKEN",
            symbol: "MOCK",
            initialSupply: initialSupply,
            owner: initialOwner
        });

        actionGenerator = new MockActionGenerator();

        hopperConfigurationStorage = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: doesExpire,
            expirationTimestamp: expirationTimestamp
        });

        tokenHopper = new TokenHopper({
            config: hopperConfigurationStorage,
            initialOwner: initialOwner
        });

        cheats.warp(startTime);
    }

    function test_pressButton() public {
        // check integrity of storage
        ITokenHopper.HopperConfiguration memory loadedConfiguration = tokenHopper.getHopperConfiguration();
        require(keccak256(abi.encode(hopperConfigurationStorage)) == keccak256(abi.encode(loadedConfiguration)),
            "stored config does not match loaded config");

        cheats.expectEmit(true, true, true, true, address(tokenHopper));
        uint256 newCooldownHorizon =
            ((block.timestamp - loadedConfiguration.startTime) / loadedConfiguration.cooldownSeconds + 1) * loadedConfiguration.cooldownSeconds;
        emit ButtonPressed(address(this), newCooldownHorizon);
        tokenHopper.pressButton();
    }

    function test_pressButton_canBeCalledByAnyone() public {
        address notOwner = address(11);
        cheats.prank(notOwner);
        tokenHopper.pressButton();
    }

    function test_pressButton_revertsWhenImmediatelyPressedTwice() public {
        tokenHopper.pressButton();

        cheats.expectRevert("TokenHopper.pressButton: button currently unpressable.");
        tokenHopper.pressButton();
    }

    function test_pressButton_revertsWhenCallReverts() public {
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
        cheats.prank(initialOwner);
        mockToken.transfer(address(tokenHopper), initialSupply);

        uint256 hopperBalanceBefore = mockToken.balanceOf(address(tokenHopper));
        uint256 mockTokenBalanceBefore = mockToken.balanceOf(address(initialOwner));

        cheats.warp(expirationTimestamp);
        cheats.prank(initialOwner);
        cheats.expectEmit(true, true, true, true, address(tokenHopper));
        emit FundsRetrieved(hopperBalanceBefore);
        tokenHopper.retrieveFunds();

        uint256 hopperBalanceAfter = mockToken.balanceOf(address(tokenHopper));
        uint256 mockTokenBalanceAfter = mockToken.balanceOf(address(initialOwner));

        assertEq(hopperBalanceAfter, 0, "hopper should have no tokens after retrieval");
        assertEq(hopperBalanceBefore - hopperBalanceAfter, mockTokenBalanceAfter - mockTokenBalanceBefore,
            "hopper should transferred tokens to owner");
    }

    function test_retrieveFunds_revertsPriorToExpiration() public {
        cheats.warp(expirationTimestamp - 1);
        cheats.prank(initialOwner);
        cheats.expectRevert("TokenHopper.retrieveFunds: Hopper is not currently expired.");
        tokenHopper.retrieveFunds();
    }
}
