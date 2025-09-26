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

    // Timing edge case tests
    function test_pressButton_revertsBeforeStartTime() public {
        // Create a hopper with future start time
        uint256 futureStartTime = block.timestamp + 1 hours;
        ITokenHopper.HopperConfiguration memory futureConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: futureStartTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: doesExpire,
            expirationTimestamp: futureStartTime + 24 weeks
        });

        TokenHopper futureHopper = new TokenHopper({config: futureConfig, initialOwner: initialOwner});

        // Should not be able to press before start time
        // canPress() will revert if called before startTime
        cheats.expectRevert("TokenHopper._canPress: block.timestamp < startTime");
        futureHopper.canPress();

        // pressButton will also revert with the same error
        cheats.expectRevert("TokenHopper._canPress: block.timestamp < startTime");
        futureHopper.pressButton();
    }

    function test_pressButton_worksExactlyAtStartTime() public {
        // Create a hopper with specific start time
        uint256 specificStartTime = block.timestamp + 1;
        ITokenHopper.HopperConfiguration memory timedConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: specificStartTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: doesExpire,
            expirationTimestamp: specificStartTime + 24 weeks
        });

        TokenHopper timedHopper = new TokenHopper({config: timedConfig, initialOwner: initialOwner});

        // Warp to exactly start time
        cheats.warp(specificStartTime);

        // Should be able to press at exact start time
        assertEq(timedHopper.canPress(), true);
        timedHopper.pressButton();
        assertEq(timedHopper.latestPress(), specificStartTime);
    }

    function test_pressButton_cooldownPeriodBoundaries() public {
        // Test pressing at various points in cooldown cycle
        cheats.warp(startTime);

        // First press at start of first period
        tokenHopper.pressButton();
        assertEq(tokenHopper.canPress(), false);

        // Cannot press again in same period
        cheats.warp(startTime + cooldownSeconds - 1);
        assertEq(tokenHopper.canPress(), false);
        cheats.expectRevert("TokenHopper.pressButton: button currently unpressable.");
        tokenHopper.pressButton();

        // Can press exactly at start of next period
        cheats.warp(startTime + cooldownSeconds);
        assertEq(tokenHopper.canPress(), true);
        tokenHopper.pressButton();
        assertEq(tokenHopper.latestPress(), startTime + cooldownSeconds);

        // Skip a period - should still be able to press
        cheats.warp(startTime + 3 * cooldownSeconds);
        assertEq(tokenHopper.canPress(), true);
        tokenHopper.pressButton();
    }

    function test_pressButton_revertsAtExactExpiration() public {
        // Warp to exactly expiration time
        cheats.warp(expirationTimestamp);

        // Should be expired
        assertEq(tokenHopper.isExpired(), true);
        assertEq(tokenHopper.canPress(), false);

        cheats.expectRevert("TokenHopper.pressButton: button currently unpressable.");
        tokenHopper.pressButton();
    }

    function test_pressButton_worksOneSecondBeforeExpiration() public {
        // Warp to one second before expiration
        cheats.warp(expirationTimestamp - 1);

        // Should not be expired yet
        assertEq(tokenHopper.isExpired(), false);
        assertEq(tokenHopper.canPress(), true);

        // Should be able to press
        tokenHopper.pressButton();
        assertEq(tokenHopper.latestPress(), expirationTimestamp - 1);
    }

    function test_canPress_duringCooldownPeriodTransition() public {
        // Test canPress at exact period boundaries
        cheats.warp(startTime);

        // Press once
        tokenHopper.pressButton();

        // Test at various points
        uint256 nextPeriodStart = startTime + cooldownSeconds;

        // Just before next period
        cheats.warp(nextPeriodStart - 1);
        assertEq(tokenHopper.canPress(), false);

        // Exactly at next period
        cheats.warp(nextPeriodStart);
        assertEq(tokenHopper.canPress(), true);

        // Just after next period starts
        cheats.warp(nextPeriodStart + 1);
        assertEq(tokenHopper.canPress(), true);
    }

    function test_multiplePeriodsWithExpiration() public {
        // Test interaction between cooldown periods and expiration
        uint256 shortExpiration = startTime + cooldownSeconds * 2 + cooldownSeconds / 2; // Expires mid-third period

        ITokenHopper.HopperConfiguration memory shortConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: startTime,
            cooldownSeconds: cooldownSeconds,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: shortExpiration
        });

        TokenHopper shortHopper = new TokenHopper({config: shortConfig, initialOwner: initialOwner});

        // First period press
        cheats.warp(startTime);
        assertEq(shortHopper.canPress(), true);
        shortHopper.pressButton();

        // Second period press
        cheats.warp(startTime + cooldownSeconds);
        assertEq(shortHopper.canPress(), true);
        shortHopper.pressButton();

        // Third period - should expire mid-period
        cheats.warp(startTime + 2 * cooldownSeconds);
        assertEq(shortHopper.canPress(), true);
        assertEq(shortHopper.isExpired(), false);

        // Warp to expiration (mid-period)
        cheats.warp(shortExpiration);
        assertEq(shortHopper.canPress(), false);
        assertEq(shortHopper.isExpired(), true);
    }

    function test_pressButton_correctlyPreventsDoublePressAtPeriodStart() public {
        // This test verifies that pressing exactly at period start correctly
        // prevents immediate re-pressing in the same period

        // Create a hopper with specific timing for easy testing
        uint256 testStartTime = 1000;
        uint256 testCooldown = 100;

        ITokenHopper.HopperConfiguration memory testConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: testStartTime,
            cooldownSeconds: testCooldown,
            actionGenerator: address(actionGenerator),
            doesExpire: false,
            expirationTimestamp: 0
        });

        TokenHopper testHopper = new TokenHopper({config: testConfig, initialOwner: initialOwner});

        // Test multiple scenarios to ensure correctness

        // Scenario 1: Press at exact start of period 0
        cheats.warp(testStartTime);
        assertEq(testHopper.canPress(), true, "Should be able to press at period 0 start");
        testHopper.pressButton();
        assertEq(testHopper.latestPress(), testStartTime);
        assertEq(testHopper.canPress(), false, "Should NOT be able to press again in period 0");

        // Scenario 2: Press at exact start of period 1
        uint256 period1Start = testStartTime + testCooldown;
        cheats.warp(period1Start);
        assertEq(testHopper.canPress(), true, "Should be able to press at period 1 start");
        testHopper.pressButton();
        assertEq(testHopper.latestPress(), period1Start);
        assertEq(testHopper.canPress(), false, "Should NOT be able to press again in period 1");

        // Scenario 3: Press in middle of period 2, then check at period 3 start
        uint256 period2Middle = testStartTime + testCooldown * 2 + 50;
        cheats.warp(period2Middle);
        assertEq(testHopper.canPress(), true, "Should be able to press in middle of period 2");
        testHopper.pressButton();

        uint256 period3Start = testStartTime + testCooldown * 3;
        cheats.warp(period3Start);
        assertEq(testHopper.canPress(), true, "Should be able to press at period 3 start");
        testHopper.pressButton();
        assertEq(testHopper.canPress(), false, "Should NOT be able to press again in period 3");

        // Verify the cooldown logic is working correctly
        // The key insight: when latestPress == currentPeriodStart, we're still in the same period
        // so canPress should return false, which it does!
        emit log("TokenHopper correctly prevents double-pressing at period boundaries");
    }

    function test_currentPeriodStartCalculation() public {
        // Test the period start calculation to ensure it's correct despite the linter warning
        // The calculation intentionally divides before multiplying to find period boundaries

        // Set specific values for testing
        uint256 testStartTime = 1000;
        uint256 testCooldown = 100;

        ITokenHopper.HopperConfiguration memory testConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: testStartTime,
            cooldownSeconds: testCooldown,
            actionGenerator: address(actionGenerator),
            doesExpire: false,
            expirationTimestamp: 0
        });

        TokenHopper testHopper = new TokenHopper({config: testConfig, initialOwner: initialOwner});

        // Test various timestamps and verify period calculation
        // Period 0: timestamps 1000-1099
        cheats.warp(1050);
        assertEq(testHopper.canPress(), true);
        testHopper.pressButton();
        assertEq(testHopper.canPress(), false); // Can't press again in same period

        // Still in period 0
        cheats.warp(1099);
        assertEq(testHopper.canPress(), false);

        // Period 1: timestamps 1100-1199
        cheats.warp(1100);
        assertEq(testHopper.canPress(), true);
        testHopper.pressButton();

        // Period 2: timestamps 1200-1299
        cheats.warp(1250);
        assertEq(testHopper.canPress(), true);
        testHopper.pressButton();

        // Still in period 2 - can't press again
        cheats.warp(1299);
        assertEq(testHopper.canPress(), false);

        // Exactly at period 3 boundary - can press again
        cheats.warp(1300);
        assertEq(testHopper.canPress(), true);
    }

    function testFuzz_timingBoundaries(
        uint256 _startOffset,
        uint256 _cooldown,
        uint256 _expirationOffset,
        uint256 _pressTime
    ) public {
        // Bound inputs
        _startOffset = bound(_startOffset, 0, 365 days);
        _cooldown = bound(_cooldown, 1 hours, 30 days);
        _expirationOffset = bound(_expirationOffset, _cooldown, 365 days);
        _pressTime = bound(_pressTime, 0, 365 days * 2);

        uint256 fuzzStartTime = block.timestamp + _startOffset;
        uint256 fuzzExpiration = fuzzStartTime + _expirationOffset;

        ITokenHopper.HopperConfiguration memory fuzzConfig = ITokenHopper.HopperConfiguration({
            token: address(mockToken),
            startTime: fuzzStartTime,
            cooldownSeconds: _cooldown,
            actionGenerator: address(actionGenerator),
            doesExpire: true,
            expirationTimestamp: fuzzExpiration
        });

        TokenHopper fuzzHopper = new TokenHopper({config: fuzzConfig, initialOwner: initialOwner});

        // Warp to press time
        cheats.warp(_pressTime);

        if (block.timestamp < fuzzStartTime) {
            // Before start time - canPress will revert
            cheats.expectRevert("TokenHopper._canPress: block.timestamp < startTime");
            fuzzHopper.canPress();
        } else if (block.timestamp >= fuzzExpiration) {
            // After expiration - canPress returns false
            assertEq(fuzzHopper.canPress(), false);
        } else {
            // In valid time window - can press once per period
            assertEq(fuzzHopper.canPress(), true);
            fuzzHopper.pressButton();

            // After pressing, should not be able to press again in same period
            assertEq(fuzzHopper.canPress(), false);
        }
    }
}
