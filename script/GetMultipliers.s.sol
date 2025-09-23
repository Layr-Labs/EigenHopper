// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import "forge-std/Test.sol";
import "forge-std/Script.sol";
import "forge-std/console.sol";
import "src/TokenHopper.sol";
import "eigenlayer-contracts/src/contracts/interfaces/IStrategy.sol";
import {Env} from "eigenlayer-contracts/script/releases/Env.sol";

/// @title GetMultipliers for original ETH strategies at block 23426354 on mainnet
/// @dev To run this script, use the following command:
/// ```
/// zeus run --command "forge script script/GetMultipliers.s.sol" --env mainnet
/// ```
/// @dev The output will be written to mainnet.toml
contract GetMultipliers is Test, Script {
    Vm cheats = Vm(VM_ADDRESS);

    // List of strategy addresses
    uint256[] public strategyAddresses; /// @dev used to hold the strategy addresses in the `uint256` type, useful for sorting
    IStrategy[] public sortedStrategyAddresses; /// @dev used to hold the sorted strategy addresses in the `IStrategy` type
    uint256[] public multipliers;

    // Constant of 1 share value
    uint256 public ONE_SHARE = 1e18;

    // Block at which all multipliers will be calculated
    uint256 public forkBlock = 23426354;

    function setUp() public {
        // Parse Zeus Config for mainnet addresses
        _parseZeus();

        // Add beacon strategy
        strategyAddresses.push(uint256(uint160(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0)));

        // Sort the strategies
        strategyAddresses = cheats.sort(strategyAddresses);

        // Convert the strategy addresses to IStrategy types
        sortedStrategyAddresses = new IStrategy[](strategyAddresses.length);
        for (uint i; i < sortedStrategyAddresses.length; ++i) {
            sortedStrategyAddresses[i] = IStrategy(address(uint160(strategyAddresses[i])));
        }

        /**
         * After sorting we expect the following order of strategies:
         * 1. swETH: 0x0Fe4F44beE93503346A3Ac9EE5A26b130a5796d6
         * 2. ankrETH: 0x13760F50a9d7377e4F20CB8CF9e4c26586c658ff
         * 3. rETH: 0x1BeE69b7dFFfA4E2d53C2a2Df135C388AD25dCD2
         * 4. mETH: 0x298aFB19A105D59E74658C4C334Ff360BadE6dd2
         * 5. cbETH: 0x54945180dB7943c0ed0FEE7EdaB2Bd24620256bc
         * 6. osETH: 0x57ba429517c3473B6d34CA9aCd56c0e735b94c02
         * 7. wBETH: 0x7CA911E83dabf90C90dD3De5411a10F1A6112184
         * 8. sfrxETH: 0x8CA7A5d6f3acd3A7A8bC468a8CD0FB14B6BD28b6
         * 9. stETH: 0x93c4b944D05dfe6df7645A86cd2206016c51564D
         * 10. ETHx: 0x9d7eD45EE2E8FC5482fa2428f15C971e6369011d
         * 11. oETH: 0xa4C637e0F704745D182e4D38cAb7E7485321d059
         * 12. lsETH: 0xAe60d8180437b5C34bB956822ac2710972584473
         * 13. beacon: 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0
         */
        // Sanity check the order of strategies
        assertEq(address(sortedStrategyAddresses[0]), 0x0Fe4F44beE93503346A3Ac9EE5A26b130a5796d6);
        assertEq(address(sortedStrategyAddresses[1]), 0x13760F50a9d7377e4F20CB8CF9e4c26586c658ff);
        assertEq(address(sortedStrategyAddresses[2]), 0x1BeE69b7dFFfA4E2d53C2a2Df135C388AD25dCD2);
        assertEq(address(sortedStrategyAddresses[3]), 0x298aFB19A105D59E74658C4C334Ff360BadE6dd2);
        assertEq(address(sortedStrategyAddresses[4]), 0x54945180dB7943c0ed0FEE7EdaB2Bd24620256bc);
        assertEq(address(sortedStrategyAddresses[5]), 0x57ba429517c3473B6d34CA9aCd56c0e735b94c02);
        assertEq(address(sortedStrategyAddresses[6]), 0x7CA911E83dabf90C90dD3De5411a10F1A6112184);
        assertEq(address(sortedStrategyAddresses[7]), 0x8CA7A5d6f3acd3A7A8bC468a8CD0FB14B6BD28b6);
        assertEq(address(sortedStrategyAddresses[8]), 0x93c4b944D05dfe6df7645A86cd2206016c51564D);
        assertEq(address(sortedStrategyAddresses[9]), 0x9d7eD45EE2E8FC5482fa2428f15C971e6369011d);
        assertEq(address(sortedStrategyAddresses[10]), 0xa4C637e0F704745D182e4D38cAb7E7485321d059);
        assertEq(address(sortedStrategyAddresses[11]), 0xAe60d8180437b5C34bB956822ac2710972584473);
        assertEq(address(sortedStrategyAddresses[12]), 0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0);

        // Fork at the given block
        string memory rpcUrl = cheats.envString("RPC_MAINNET");
        cheats.createSelectFork(rpcUrl, forkBlock);

        multipliers = new uint256[](strategyAddresses.length);
    }

    function run() public {
        // 1. swETH
        multipliers[0] = get_swETH_multiplier(sortedStrategyAddresses[0]);

        // 2. ankrETH
        multipliers[1] = get_ankrETH_multiplier(sortedStrategyAddresses[1]);

        // 3. rETH
        multipliers[2] = get_rETH_multiplier(sortedStrategyAddresses[2]);

        // 4. mETH
        multipliers[3] = get_mETH_multiplier(sortedStrategyAddresses[3]);

        // 5. cbETH
        multipliers[4] = get_cbETH_multiplier(sortedStrategyAddresses[4]);

        // 6. osETH
        multipliers[5] = get_osETH_multiplier(sortedStrategyAddresses[5]);

        // 7. wBETH
        multipliers[6] = get_wBETH_multiplier(sortedStrategyAddresses[6]);

        // 8. sfrxETH
        multipliers[7] = get_sfrxETH_multiplier(sortedStrategyAddresses[7]);

        // 9. stETH
        multipliers[8] = get_stETH_multiplier(sortedStrategyAddresses[8]);

        // 10. ETHx
        multipliers[9] = get_ETHx_multiplier(sortedStrategyAddresses[9]);

        // 11. oETH
        multipliers[10] = get_oETH_multiplier(sortedStrategyAddresses[10]);

        // 12. lsETH
        multipliers[11] = get_lsETH_multiplier(sortedStrategyAddresses[11]);

        // 13. beacon
        // Beacon strategy is 1:1 with ETH
        multipliers[12] = ONE_SHARE;

        // Log all multipliers
        for (uint i; i < multipliers.length; ++i) {
            console.log("multiplier %s: %s", i, multipliers[i]);
        }

        // Sanity test the multipliers are all between 1e18 and 1.25e18
        for (uint i; i < multipliers.length; ++i) {
            assertGe(multipliers[i], 1e18);
            assertLe(multipliers[i], 1.25e18);
        }

        // Write the strategies and multipliers to mainnet.toml
        _writeStrategiesToToml();
    }

    /// 1. swETH
    /// @dev Retrieved from calling swETHToETHRate on the swETH token
    function get_swETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        ISWETH sweth = ISWETH(address(strategy.underlyingToken()));

        multiplier = sweth.swETHToETHRate();
    }

    /// 2. ankrETH
    /// @dev Retrieved from calling sharesToBonds on the ankrETH token
    function get_ankrETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        IAnkrETH ankrETH = IAnkrETH(address(strategy.underlyingToken()));
        
        multiplier = ankrETH.sharesToBonds(ONE_SHARE);
    }

    /// 3. rETH
    /// @dev Retrieved from calling `getExchangeRate` on the rETH token
    function get_rETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        IRETH rETH = IRETH(address(strategy.underlyingToken()));
        
        multiplier = rETH.getExchangeRate();
    }

    /// 4. mETH 
    /// @dev Retrieved from calling `mETHtoETH` on the mETH staking contract
    function get_mETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        IMETH mETH = IMETH(address(strategy.underlyingToken()));
        IMETH mETHStakingContract = IMETH(address(mETH.stakingContract()));
        
        multiplier = mETHStakingContract.mETHToETH(ONE_SHARE);
    }

    /// 5. cbETH
    /// @dev Retrieved from calling `exchangeRate` on the cbETH token
    function get_cbETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        ICBETH cbETH = ICBETH(address(strategy.underlyingToken()));
        
        multiplier = cbETH.exchangeRate();
    }

    /// 6. osETH
    /// @dev Retrieved from calling `getRate` on the osETH rate provider contract
    /// @dev Contract address: 0x8023518b2192FB5384DAdc596765B3dD1cdFe471: https://docs.stakewise.io/for-developers/networks/mainnet
    function get_osETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        IosETH osETH = IosETH(0x8023518b2192FB5384DAdc596765B3dD1cdFe471);
        
        multiplier = osETH.getRate();
    }

    /// 7. wBETH
    /// @dev Retrieved from calling `exchangeRate` on the wBETH token
    function get_wBETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        IwBETH wBETH = IwBETH(address(strategy.underlyingToken()));
        
        multiplier = wBETH.exchangeRate();
    }

    /// 8. sfrxETH
    /// @dev Retrieved from calling `pricePerShare` on the sfrxETH token
    function get_sfrxETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        ISfrxETH sfrxETH = ISfrxETH(address(strategy.underlyingToken()));
        
        multiplier = sfrxETH.pricePerShare();
    }

    /// 9. stETH
    /// @dev Retrieved from calling `sharesToUnderlying` on the stETH strategy
    /// @dev stETH is 1:1 with ETH and is a rebasing token
    function get_stETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        multiplier = strategy.sharesToUnderlying(ONE_SHARE);
    }

    /// 10. ETHx
    /// @dev Retrieved from calling `exchangeRate` on the ETHx oracle contract
    /// @dev Contract address: 0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737: https://staderlabs.gitbook.io/ethereum/smart-contracts
    /// @dev exchangeRate = totalETHBalance * ONE_SHARE / totalETHXSupply
    function get_ETHx_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        IETHx ETHx = IETHx(0xF64bAe65f6f2a5277571143A24FaaFDFC0C2a737);
        
        (, uint256 totalETHBalance, uint256 totalETHXSupply) = ETHx.exchangeRate();

        multiplier = totalETHBalance  * ONE_SHARE / totalETHXSupply;
    }

    /// 11. oETH
    /// @dev Retrieved from calling `sharesToUnderlying` on the oETH strategy
    /// @dev oETH is 1:1 with ETH and is a rebasing token
    function get_oETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {        
        multiplier = strategy.sharesToUnderlying(ONE_SHARE);
    }

    /// 12. lsETH
    /// @dev Retrieved from calling `underlyingBalanceFromShares` on the lsETH token
    function get_lsETH_multiplier(IStrategy strategy) internal returns (uint256 multiplier) {
        IlsETH lsETH = IlsETH(address(strategy.underlyingToken()));
        
        multiplier = lsETH.underlyingBalanceFromShares(ONE_SHARE);
    }

    function _writeStrategiesToToml() internal {         
        // Convert addresses to strings (using sortedStrategyAddresses which has IStrategy type)
        string[] memory strategyStrings = new string[](sortedStrategyAddresses.length);
        for (uint256 i = 0; i < sortedStrategyAddresses.length; i++) {
            strategyStrings[i] = vm.toString(address(sortedStrategyAddresses[i]));
        }
        
        // Create the JSON structure
        string memory strategiesKey = "strategies";
        string memory strategiesJson = vm.serializeString(strategiesKey, "strategies", strategyStrings);
        
        string memory multipliersKey = "multipliers";
        string memory multipliersJson = vm.serializeUint(multipliersKey, "multipliers", multipliers);
        
        // Create root object with both sections
        string memory root = "root";
        vm.serializeString(root, "strategies", strategiesJson);
        string memory finalJson = vm.serializeString(root, "multipliers", multipliersJson);
        
        // Write to mainnet.toml
        vm.writeToml(finalJson, "script/mainnet.toml");
        
        console.log("Successfully wrote strategies and multipliers to mainnet.toml");
    }

    function _parseZeus() internal {
        strategyAddresses = new uint256[](Env.strategyBaseTVLLimits_Count(Env.instance));
        for (uint i; i < strategyAddresses.length; ++i) {
            strategyAddresses[i] = uint256(uint160(address(Env.strategyBaseTVLLimits(Env.instance, i))));
        }
    }
}

interface ISWETH {
    function swETHToETHRate() external returns (uint256);
}

interface IAnkrETH {
    function sharesToBonds(uint256 shares) external returns (uint256);
}

interface IRETH {
    function getExchangeRate() external returns (uint256);
}

interface IMETH {
    function stakingContract() external returns (address);
    function mETHToETH(uint256) external returns (uint256);
}

interface ICBETH {
    function exchangeRate() external returns (uint256);
}

interface IosETH {
    function getRate() external returns (uint256);
}

interface IwBETH {
    function exchangeRate() external returns (uint256);
}

interface ISfrxETH {
    function pricePerShare() external returns (uint256);
}

interface IETHx {
    function exchangeRate() external returns (uint256 reportingBlockNumber, uint256 totalETHBalance, uint256 totalETHXSupply);
}

interface IlsETH {
    function underlyingBalanceFromShares(uint256 shares) external returns (uint256);
}