// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.12;

// Action Generators are used by hopper owners 
// to power the logic of the hopper's button action.
// Generators should be reasonably stateless and
// immutable to be used safely.
import { ITokenHopper } from "./interfaces/ITokenHopper.sol";
import { IHopperActionGenerator } from "./interfaces/IHopperActionGenerator.sol";

// We are going to use the standard OZ interfaces and implementations
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * TokenHopper
 *
 * A minimal implementation of the ITokenHopper spec.
 */
contract TokenHopper is ITokenHopper, Ownable {
    using SafeERC20 for IERC20;

    // provided on construction
    HopperConfiguration internal configuration;

    // Button state
    // timestamp of last button press
    uint256 public latestPress;

    constructor(HopperConfiguration memory config, address initialOwner) {
        _transferOwnership(initialOwner);
        // set the configuration and emit an event
        configuration = config;
        emit HopperLoaded(config);
    }

    /**
     * isExpired()
     *
     * Determines if the hopper has expired, making any remaining token balance
     * retriavable by the owner.
     *
     * @return true if and only if isLoaded() && (doesExpire && block.timestamp >= expirationTimestamp)
     */
    function isExpired() external view returns (bool) {
        return _isExpired();
    }

    /**
     * getHopperConfiguration()
     *
     * If the hopper has not yet been loaded, this call will revert.
     *
     * @return the hopper configuration initially supplied by the owner.
     */
    function getHopperConfiguration() external view returns (HopperConfiguration memory) {
        return configuration;
    }

    /**
     * canPress()
     *
     * Determines if the hopper is in a state ready for action. Great way
     * within other contracts to make sure your transaction doesn't blow up.
     *
     * @return true if the hopper is loaded and not in cooldown, false otherwise.
     */
    function canPress() external view returns (bool) {
       return _canPress(); 
    }

    /**
     * pressButton()
     *
     * Any actor can call this function to initiate the set of actions in the hopper.
     *
     * This call will revert if any of the actions revert, if the hopper has
     * not yet been loaded, or if the hopper is in a cooldown period.
     */
    function pressButton() external {
        // make sure we can press the button
        require(_canPress(), "TokenHopper.pressButton: button currently unpressable.");

        /**
         * We immediately set the latestPress time so that actions
         * can't re-enter and press the button again. If a button isn't
         * pressed during a window, then one opportunity for a button press is "lost"
         * -- there is no "button press backlog".
         * 
         * It's the responsibility of the action generators to modulo their
         * action generation to the same granularity as the cooldown period.
         * its a design decision to make the action generator "stateless"
         * and not compensate for missed button presses.
         */

        latestPress = block.timestamp;

        // grab the actions
        IHopperActionGenerator.HopperAction[] memory actions = 
            IHopperActionGenerator(configuration.actionGenerator).generateHopperActions(
                address(this), configuration.token);

        // perform the actions, and make sure they were successful
        for(uint256 x = 0; x < actions.length; x++) {
            (bool success,) = (actions[x].target).call(actions[x].callData);
            require(success, "TokenHopper.pressButton: call reverted");
        }

        uint256 newCooldownHorizon =
            ((block.timestamp - configuration.startTime) / configuration.cooldownSeconds + 1) * configuration.cooldownSeconds;
        emit ButtonPressed(msg.sender, newCooldownHorizon);
    }

    /**
     * retrieveFunds()
     *
     * This method can only be called by the owner and will return all remaining
     * token balance to them if and only if the hopper is expired.
     *
     * This method will always revert if the hopper is not configured to expire.
     * It will also revert if the expiration date has not yet passed.
     */
     function retrieveFunds() onlyOwner external {
        require(_isExpired(), "TokenHopper.retrieveFunds: Hopper is not currently expired.");

        // move the existing balance of the token in this contract
        // back to the caller, who must be the owner
        uint256 tokenBalance = IERC20(configuration.token).balanceOf(address(this));
        IERC20(configuration.token).safeTransfer(owner(), tokenBalance);
        emit FundsRetrieved(tokenBalance);
     }

     /////////////////////////////////////////////////
     // Internal Methods
     /////////////////////////////////////////////////
    
     function _canPress() internal view returns (bool) {
        // hopper must be unexpired and not yet pressed during the current period.
        uint256 currentPeriodStart =
            ((block.timestamp - configuration.startTime) / configuration.cooldownSeconds) * configuration.cooldownSeconds
            + configuration.startTime;
        return (configuration.doesExpire ? block.timestamp < configuration.expirationTimestamp : true) &&
            (latestPress < currentPeriodStart);
    }
    
    function _isExpired() internal view returns (bool) {
        return configuration.doesExpire &&                           // something that can't expire won't
               block.timestamp >= configuration.expirationTimestamp; // is this block past the expiration date?
    }
}
