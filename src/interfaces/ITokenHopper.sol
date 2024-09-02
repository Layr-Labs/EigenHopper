// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

/**
 * ITokenHopper
 *
 * This interface acts as a virtual on-chain account that can be loaded
 * with a specific token and configuration once, and be permissionlessly
 * invoked to use the tokens in a periodic fashion.
 *
 * The sequence is the following:
 *
 * 1) A Hopper is deployed with an owner, and it is configured to be able
 *    to do one thing and one thing only, every X number of seconds.
 * 2) As long as the hopper is not in "cool down," anyone can invoke it
 *    to do the specified action.
 * 3) When the tokens are depleted or the expiration date hits the hopper
 *    ceases function.
 * 4) Only if in an expiration state, the owner of the contract can retrieve
 *    the funds.
 *
 * Note: This hopper is designed specifically and ignorantly for ERC-20 tokens,
 *       and will not support native gas tokens (ETH), or NFTs. Deviant ERC-20
 *       behavior may result in undefined hopper execution. Always fully
 *       understand the token behavior before putting it in a hopper.
 *
 * Usage:
 *    The most common way to use a hopper is to pre-program a single action
 *    to take that requires a specific amount of tokens. For this use case,
 *    an owner would use two HopperActions to define their behavior:
 *      1) {target: hopperTokenAddress, callData: (approve(targetCA, amount))}
 *      2) {target: targetCA, callData: (func(params))}
 *
 *    This way, the target contract only holds an allowance long enough to pull in
 *    a specific amount for each action. Calling the target contract then pulls the
 *    funds successfully from the hopper.
 */
interface ITokenHopper {
    /**
     * HopperConfiguration
     *
     * This structure is supplied by the hopper owner
     * to configure it's parameters.
     */
    struct HopperConfiguration {
        // Initial Funds
        address token;              // Each hopper will hold exactly one token type.

        // Behavior
        uint256 cooldownSeconds;    // The number of seconds minimally required between each action.
        address actionGenerator;    // The logic behind the button press for the hopper.

        // Expiration
        //
        // Optionally, a hopper can expire at a specific timestamp.
        // If set to true, the expirationTimestamp is used to disable
        // the hopper's programmed behavior and, if any funds are left,
        // enables the hopper owner to retrieve the funds.
        bool doesExpire;          // CAREFUL! Setting this to false will lock funds FOREVER! 
        uint256 expirationTimestamp; // only considered as valid (even set to 0) if doesExpire is true  
    } 

    /**
     * isLoaded()
     *
     * @return true if the hopper has been loaded by the owner, false otherwise.
     */
    function isLoaded() external view returns (bool);

    /**
     * isExpired()
     *
     * Determines if the hopper has expired, making any remaining token balance
     * retriavable by the owner.
     *
     * @return true if and only if isLoaded() && (doesExpire && block.timestamp >= expirationTimestamp)
     */
    function isExpired() external view returns (bool);

    /**
     * getHopperConfiguration()
     *
     * If the hopper has not yet been loaded, this call will revert.
     *
     * @return the hopper configuration initially supplied by the owner.
     */
    function getHopperConfiguration() external view returns (HopperConfiguration memory);

    /**
     * canPress()
     *
     * Determines if the hopper is in a state ready for action. Great way
     * within other contracts to make sure your transaction doesn't blow up.
     *
     * @return true if the hopper is loaded and not in cooldown, false otherwise.
     */
    function canPress() external view returns (bool);

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
    function load(HopperConfiguration calldata config) external;

    /**
     * pressButton()
     *
     * Any actor can call this function to initiate the set of actions in the hopper.
     *
     * This call will revert if any of the actions revert, if the hopper has
     * not yet been loaded, or if the hopper is in a cooldown period.
     */
    function pressButton() external;

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
