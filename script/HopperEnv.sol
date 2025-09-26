// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";

/// Hopper/
import "src/TokenHopper.sol";
import "src/RewardAllStakersActionGenerator.sol";

library HopperEnv {
    using ZEnvHelpers for *;

    /// Dummy types and variables to facilitate syntax, e.g: `Env.proxy.delegationManager()`
    enum DeployedProxy {
        A
    }
    enum DeployedBeacon {
        A
    }
    enum DeployedImpl {
        A
    }
    enum DeployedInstance {
        A
    }

    DeployedProxy internal constant proxy = DeployedProxy.A;
    DeployedBeacon internal constant beacon = DeployedBeacon.A;
    DeployedImpl internal constant impl = DeployedImpl.A;
    DeployedInstance internal constant instance = DeployedInstance.A;

    function tokenHopper(DeployedImpl) internal view returns (TokenHopper) {
        return TokenHopper(_deployedImpl(type(TokenHopper).name));
    }

    function actionGenerator(DeployedImpl) internal view returns (RewardAllStakersActionGenerator) {
        return RewardAllStakersActionGenerator(_deployedImpl(type(RewardAllStakersActionGenerator).name));
    }

    function _deployedImpl(string memory name) private view returns (address) {
        return ZEnvHelpers.state().deployedImpl(name);
    }
}
