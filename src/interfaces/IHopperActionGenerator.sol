// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.23;

/**
 * IHopperActionGenerator
 *
 * A permissionless interface component that encapsulates the runtime
 * logic for generating hopper actions. A hopper owner must configure a valid
 * IHopperActionGenerator when loading a hopper, and any internal logic to the
 * production of the actions are within this contract.
 * 
 */
interface IHopperActionGenerator {
    /**
     * HopperAction
     *
     * Represents an action that the hopper can do, *acting as itself* in an un-delegated way.
     * An action is specified by the target contract address, along with its call data.
     * The call data is the ABI encoded 4-byte function selector followed by the serialized
     * parameters of it's methods.
     *
     * The hopper's design does not support delegated calls, message values (ETH transfers)
     * nor the ability to understand, store, or otherwise use any return values.
     *
     * A hopper can be programmed *once* with a set of actions that are to be executed
     * for *each* initiation of the hopper's behavior.
     *
     * WARNING: If for any reason any of a hopper's actions revert during execution the
     *          hopper could be "attacked," "bricked," or otherwise rendered inoperable 
     *          until the expiration period, depending on the trust model with the target
     *          contracts.
     */ 
    struct HopperAction {
        address target;
        bytes   callData;
    }

    /**
     * generateHopperActions()
     *
     * Hoppers can call this function to generate a list of hopper actions, given its logic.
     * This method takes a hopper address instead of assuming the calling function is always the hopper itself,
     * which also enables proper "simulation" as well.
     *
     * This interface purposefully does not take the full hopper configuration because it should be
     * considered stateless or otherwise immutable logic for trustless operation.
     *
     * @param hopper      the address of the ITokenHopper you want to generate actions for.
     * @param hopperToken the contract address of the token that is loaded into the hopper.
     *
     * @return a list of hopper actions that are presumably to be executed by the hopper in the same transaction.
     */
    function generateHopperActions(address hopper, address hopperToken) external view returns(HopperAction[] memory); 
}
