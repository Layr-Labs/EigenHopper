// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

// Action Generators are used by hopper owners 
// to power the logic of the hopper's button action.
// Generators should be reasonably stateless and
// immutable to be used safely.
import { 
  ITokenHopper
} from "./interfaces/ITokenHopper.sol";

/**
 * TokenHopper
 *
 * A minimal implementation of the ITokenHopper spec.
 */
contract ITokenHopper is ITokenHopper {
    // Loading State
    private boolean             loaded;        // set to true when hopper is loaded
    private HopperConfiguration configuration; // provided by contract owner

    // Button state
    private uint256 cooldownHorizon;           // timestamp of button re-activation

    /**
     * isLoaded()
     *
     * @return true if the hopper has been loaded by the owner, false otherwise.
     */
    function isLoaded() external returns (bool) {
        return loaded;
    }

    /**
     * isExpired()
     *
     * Determines if the hopper has expired, making any remaining token balance
     * retriavable by the owner.
     *
     * @return true if and only if isLoaded() && (doesExpire && block.timestamp >= expirationTimestamp)
     */
    function isExpired() external returns (bool) {
        return isLoaded &&                                           // something that isn't loaded can't expire 
               configuration.doesExpire &&                           // something that can't expire won't
               block.timestamp >= configuration.expirationTimestamp; // is this block past the expiration date?
    }

    /**
     * getHopperConfiguration()
     *
     * If the hopper has not yet been loaded, this call will revert.
     *
     * @return the hopper configuration initially supplied by the owner.
     */
    function getHopperConfiguration() external returns (HopperConfiguration) {
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
    function canPress() external returns (bool) {
        // hopper must be loaded, unexpired, and not in cooldown.
        return isLoaded &&
             (configuration.doesExpire ? block.timestamp < configuration.expirationTimestamp : true) &&
             block.timestamp >= cooldownHorizon;
    }

    /**
     * load()
     *
     * This method should only be called by the contracts owner,
     * and provides the configuration to "start" the hopper's operation.
     * Immediately after this method returns the "button" could be pressed.
     *
     * Subsequent calls to load() after the initial call will revert.
     *
     * This function will pull in initialAmount of the token, so the caller
     * must have properly set their allowances.
     *
     * @param configuration the Hopper Configuration defining the behavior 
     */
    function load(HopperConfiguration calldata config) external {
        require(!isLoaded, "Hopper is already loaded");
        
        // set the configuration
        configuration = config;
        isLoaded = true;

        // pull in the tokens. this will fail if the message sender
        // did not properly set approvals. we must also do this
        // last to make sure nothing silly happens
        assert(IERC20(token).transferFrom(msg.sender, address(this), amount));
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
        require(canPress(), "Hopper button currently unpressable.");

        // grab the actions
        HopperActions actions = configuration. 
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
     function retrieveFunds() external;
}
