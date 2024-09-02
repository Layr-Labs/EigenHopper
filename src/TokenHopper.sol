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

    // Loading State
    bool                private loaded;                    // set to true when hopper is loaded
    HopperConfiguration private configuration;             // provided by contract owner

    // Button state
    uint256             private cooldownHorizon;           // timestamp of button re-activation

    // It's not entirely possible to load the hopper on deployment, because without
    // a counterfactual deployment the deployer will not know what address to set
    // approvals for.
    constructor(address initialOwner) {
        _transferOwnership(initialOwner);
    }

    /**
     * isLoaded()
     *
     * @return true if the hopper has been loaded by the owner, false otherwise.
     */
    function isLoaded() external view returns (bool) {
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
     * load()
     *
     * This method should only be called by the contracts owner,
     * and provides the configuration to "start" the hopper's operation.
     * Immediately after this method returns the "button" could be pressed.
     *
     * Subsequent calls to load() after the initial call will revert.
     *
     * @param config the Hopper Configuration defining the behavior 
     */
    function load(HopperConfiguration calldata config) onlyOwner external {
        require(!loaded, "Hopper is already loaded");
       
        // set the cooldown to the current block timestamp
        // so the button can be pressed right after loading it
        cooldownHorizon = block.timestamp;

        // set the configuration
        configuration = config;
        loaded = true;
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
        require(_canPress(), "Hopper button currently unpressable.");

        // we need to immediately re-set the horizon so actions
        // can't re-enter and press the button again. if a button isn't
        // pressed 'right away,' then time is 'lost' and the button isn't
        // pressable "sooner."
        //
        // It's the responsibility of the action generators to modulo their
        // action generation to the same granularity as the cooldown period.
        // its a design decision to make the action generator "stateless"
        // and not compensate for missed button time.
        cooldownHorizon = block.timestamp + configuration.cooldownSeconds;

        // grab the actions
        IHopperActionGenerator.HopperAction[] memory actions = 
            IHopperActionGenerator(configuration.actionGenerator).generateHopperActions(
                address(this), configuration.token);

        // perform the actions, and make sure they were successful
        for(uint256 x = 0; x < actions.length; x++) {
            (bool success,) = (actions[x].target).call(actions[x].callData);
            assert(success);
        }
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
        require(_isExpired(), "Hopper is not currently expired.");

        // move the existing balance of the token in this contract
        // back to the caller, who must be the owner 
        IERC20(configuration.token).safeTransfer(owner(), IERC20(configuration.token).balanceOf(address(this)));
     }

     /////////////////////////////////////////////////
     // Internal Methods
     /////////////////////////////////////////////////
    
     function _canPress() internal view returns (bool) {
        // hopper must be loaded, unexpired, and not in cooldown.
        return loaded &&
             (configuration.doesExpire ? block.timestamp < configuration.expirationTimestamp : true) &&
             block.timestamp >= cooldownHorizon;
    }
    
    function _isExpired() internal view returns (bool) {
        return loaded &&                                             // something that isn't loaded can't expire 
               configuration.doesExpire &&                           // something that can't expire won't
               block.timestamp >= configuration.expirationTimestamp; // is this block past the expiration date?
    }
}
