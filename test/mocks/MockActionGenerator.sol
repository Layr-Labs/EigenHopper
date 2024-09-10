// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "src/interfaces/IHopperActionGenerator.sol";

contract MockActionGenerator is IHopperActionGenerator {

    HopperAction[] public actions;

    constructor() {
        bytes memory emptyBytes;
        actions.push(HopperAction({
            target: address(0),
            callData: emptyBytes
        }));
    }

    function setActions(HopperAction[] memory _actions) public {
        delete actions;
        for (uint256 i = 0; i < _actions.length; ++i) {
            actions.push(HopperAction({
                target: _actions[i].target,
                callData: _actions[i].callData
            }));
        }
    }

    function generateHopperActions(address /*hopper*/, address /*hopperToken*/)
        external
        view
        returns(HopperAction[] memory)
    {
        return actions;
    }
}
