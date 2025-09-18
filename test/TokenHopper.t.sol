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

        tokenHopper = new TokenHopper({config: hopperConfigurationStorage, initialOwner: initialOwner});

        cheats.warp(startTime);
    }

    function test_pressButton() public {
        // check integrity of storage
        ITokenHopper.HopperConfiguration memory loadedConfiguration = tokenHopper.getHopperConfiguration();
        require(
            keccak256(abi.encode(hopperConfigurationStorage)) == keccak256(abi.encode(loadedConfiguration)),
            "stored config does not match loaded config"
        );

        cheats.expectEmit(true, true, true, true, address(tokenHopper));
        uint256 newCooldownHorizon = (
            (block.timestamp - loadedConfiguration.startTime) / loadedConfiguration.cooldownSeconds + 1
        ) * loadedConfiguration.cooldownSeconds + loadedConfiguration.startTime;
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
        actions[0] = IHopperActionGenerator.HopperAction({target: address(6), callData: callData});
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
        assertEq(
            hopperBalanceBefore - hopperBalanceAfter,
            mockTokenBalanceAfter - mockTokenBalanceBefore,
            "hopper should transferred tokens to owner"
        );
    }

    function test_retrieveFunds_revertsPriorToExpiration() public {
        cheats.warp(expirationTimestamp - 1);
        cheats.prank(initialOwner);
        cheats.expectRevert("TokenHopper.retrieveFunds: Hopper is not currently expired.");
        tokenHopper.retrieveFunds();
    }

    // Constructor validation tests
    function test_constructor_revertsWithZeroCooldown() public {
        ITokenHopper.HopperConfiguration memory invalidConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: 0, // Invalid: zero cooldown
            actionGenerator: address(actionGenerator),
            doesExpire: doesExpire,
            expirationTimestamp: expirationTimestamp
        });

        cheats.expectRevert("TokenHopper: zero cooldown not allowed");
        new TokenHopper({config: invalidConfig, initialOwner: initialOwner});
    }

    function test_constructor_revertsWithZeroTokenAddress() public {
        ITokenHopper.HopperConfiguration memory invalidConfig = ITokenHopper.HopperConfiguration({
            token: address(0), // Invalid: zero address
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: doesExpire,
            expirationTimestamp: expirationTimestamp
        });

        cheats.expectRevert("TokenHopper: token cannot be zeroa ddress");
        new TokenHopper({config: invalidConfig, initialOwner: initialOwner});
    }

    function test_constructor_revertsWhenExpirationBeforeStart() public {
        ITokenHopper.HopperConfiguration memory invalidConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: startTime - 1 // Invalid: expires before starting
        });

        cheats.expectRevert("TokenHopper: cannot expire before starting");
        new TokenHopper({config: invalidConfig, initialOwner: initialOwner});
    }

    function test_constructor_revertsWhenExpirationEqualToStart() public {
        ITokenHopper.HopperConfiguration memory edgeConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: startTime // Edge case: expires exactly at start
        });

        // Should revert because expiration must be strictly greater than start
        cheats.expectRevert("TokenHopper: cannot expire before starting");
        new TokenHopper({config: edgeConfig, initialOwner: initialOwner});
    }

    function test_constructor_allowsMinimalExpirationAfterStart() public {
        ITokenHopper.HopperConfiguration memory minimalConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: startTime + 1 // Minimal valid expiration
        });

        // Should not revert
        TokenHopper minimalHopper = new TokenHopper({config: minimalConfig, initialOwner: initialOwner});

        // Verify it was created with correct config
        ITokenHopper.HopperConfiguration memory loadedConfig = minimalHopper.getHopperConfiguration();
        assertEq(loadedConfig.expirationTimestamp, startTime + 1);
    }

    function test_constructor_ignoresExpirationWhenDoesntExpire() public {
        ITokenHopper.HopperConfiguration memory nonExpiringConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: false,
            expirationTimestamp: 0 // Should be ignored when doesExpire is false
        });

        // Should not revert even with invalid expiration timestamp
        TokenHopper nonExpiringHopper = new TokenHopper({config: nonExpiringConfig, initialOwner: initialOwner});

        // Verify hopper never expires
        assertEq(nonExpiringHopper.isExpired(), false);

        // Fast forward time significantly
        cheats.warp(block.timestamp + 365 days);
        assertEq(nonExpiringHopper.isExpired(), false);
    }

    function test_constructor_withZeroActionGenerator() public {
        ITokenHopper.HopperConfiguration memory configWithZeroGenerator = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(0), // Zero address generator
            doesExpire: doesExpire,
            expirationTimestamp: expirationTimestamp
        });

        // Constructor should succeed - no validation on action generator
        TokenHopper hopperWithZeroGen = new TokenHopper({config: configWithZeroGenerator, initialOwner: initialOwner});

        // But pressing button should fail when trying to call zero address
        cheats.warp(startTime);
        cheats.expectRevert();
        hopperWithZeroGen.pressButton();
    }

    function test_constructor_emitsHopperLoadedEvent() public {
        ITokenHopper.HopperConfiguration memory config = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: doesExpire,
            expirationTimestamp: expirationTimestamp
        });

        cheats.expectEmit(true, true, true, true);
        emit HopperLoaded(config);

        new TokenHopper({config: config, initialOwner: initialOwner});
    }

    function test_constructor_setsCorrectOwner() public {
        address expectedOwner = address(0x1234);

        TokenHopper hopperWithCustomOwner =
            new TokenHopper({config: hopperConfigurationStorage, initialOwner: expectedOwner});

        assertEq(hopperWithCustomOwner.owner(), expectedOwner);
    }

    function test_constructor_withMaxValues() public {
        ITokenHopper.HopperConfiguration memory maxConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: type(uint256).max - 1,
            cooldownSeconds: type(uint256).max,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: type(uint256).max
        });

        // Should not revert with max values
        TokenHopper maxHopper = new TokenHopper({config: maxConfig, initialOwner: initialOwner});

        // Verify configuration is stored correctly
        ITokenHopper.HopperConfiguration memory loadedConfig = maxHopper.getHopperConfiguration();
        assertEq(loadedConfig.startTime, type(uint256).max - 1);
        assertEq(loadedConfig.cooldownSeconds, type(uint256).max);
        assertEq(loadedConfig.expirationTimestamp, type(uint256).max);
    }

    // Fuzz test for constructor validation
    function testFuzz_constructor_validatesTimestamps(
        uint256 _startTime,
        uint256 _cooldownSeconds,
        uint256 _expirationTimestamp,
        bool _doesExpire
    ) public {
        // Bound inputs to reasonable values
        _startTime = bound(_startTime, 0, type(uint128).max);
        _cooldownSeconds = bound(_cooldownSeconds, 1, 365 days); // At least 1 second, max 1 year

        ITokenHopper.HopperConfiguration memory fuzzConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: _startTime,
            cooldownSeconds: _cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: _doesExpire,
            expirationTimestamp: _expirationTimestamp
        });

        if (_doesExpire && _expirationTimestamp <= _startTime) {
            // Should revert if expiration is not after start
            cheats.expectRevert("TokenHopper: cannot expire before starting");
            new TokenHopper({config: fuzzConfig, initialOwner: initialOwner});
        } else {
            // Should succeed otherwise
            TokenHopper fuzzHopper = new TokenHopper({config: fuzzConfig, initialOwner: initialOwner});

            // Verify configuration is stored correctly
            ITokenHopper.HopperConfiguration memory loadedConfig = fuzzHopper.getHopperConfiguration();
            assertEq(loadedConfig.startTime, _startTime);
            assertEq(loadedConfig.cooldownSeconds, _cooldownSeconds);
            assertEq(loadedConfig.doesExpire, _doesExpire);
            assertEq(loadedConfig.expirationTimestamp, _expirationTimestamp);
        }
    }
}
