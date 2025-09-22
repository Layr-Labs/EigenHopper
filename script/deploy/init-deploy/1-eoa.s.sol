// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.12;

import {EOADeployer} from "eigenlayer-contracts/lib/zeus-templates/src/templates/EOADeployer.sol";
import {Env} from "eigenlayer-contracts/script/releases/Env.sol";
import "eigenlayer-contracts/lib/zeus-templates/src/utils/ZEnvHelpers.sol";  
import "eigenlayer-contracts/src/contracts/interfaces/IRewardsCoordinator.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import {ITokenHopper} from "src/interfaces/ITokenHopper.sol";
import {TokenHopper} from "src/TokenHopper.sol";
import {RewardAllStakersActionGenerator} from "src/RewardAllStakersActionGenerator.sol";

contract Deploy is EOADeployer {
    using Env for *;
    using ZEnvHelpers for *;

    TokenHopper public tokenHopper;
    RewardAllStakersActionGenerator public actionGenerator;

    // Action Generator config -- hardcoding + reusing previous values
    uint32 public firstSubmissionStartTimestamp = 1723680000;
    uint256 public firstSubmissionTriggerCutoff = 1727913600;
    uint256[2] public amounts;
    IRewardsCoordinatorTypes.StrategyAndMultiplier[][2] public strategiesAndMultipliers;

    // weekly amounts
    uint256 public constant EIGEN_stakers_weekly_distribution = 321_855_128_516_280_769_230_770;
    uint256 public constant ETH_stakers_weekly_distribution = 965_565_385_548_842_307_692_308;

    uint256 public constant totalEigenSupply = 1673646668284660000000000000;
    uint256 public constant yearlyPercentageEigenStakers = 1;
    uint256 public constant yearlyPercentageEthStakers = 3;


    function _runAsEOA() internal override {
        constructArrays();
        deployContracts();
    }

    function testDeploy() public virtual {
        _runAsEOA();
    }

    function constructArrays() internal {
        // set up strategy arrays and amounts array
        amounts[0] = EIGEN_stakers_weekly_distribution;
        amounts[1] = ETH_stakers_weekly_distribution;
        require(amounts[0] < amounts[1], "ETH stakers expected to get larger share of distribution");
        uint256 roundingMarginOfError = 100 wei;
        require(amounts[0] * 52 < totalEigenSupply * yearlyPercentageEigenStakers / 100 + roundingMarginOfError,
            "EIGEN stakers getting too much");
        require(amounts[0] * 52 > totalEigenSupply * yearlyPercentageEigenStakers / 100 - roundingMarginOfError,
            "EIGEN stakers getting too little");
        require(amounts[1] * 52 < totalEigenSupply * yearlyPercentageEthStakers / 100 + roundingMarginOfError,
            "ETH stakers getting too much");
        require(amounts[1] * 52 > totalEigenSupply * yearlyPercentageEthStakers / 100 - roundingMarginOfError,
            "ETH stakers getting too little");


        strategiesAndMultipliers[0].push(IRewardsCoordinatorTypes.StrategyAndMultiplier({
            strategy: IStrategy(address(Env.proxy.eigenStrategy())),
            multiplier: 1e18
        }));

        // uint256 deployedStrategyCount = Env.strategyBaseTVLLimits_Count("StrategyBaseTVLLimits");
        uint256 deployedStrategyCount = Env.instance.strategyBaseTVLLimits_Count();
        uint256[] memory deployedStrategyArray = new uint256[](deployedStrategyCount + 1);

        // fetch all the strategies
        for (uint256 i = 0; i < deployedStrategyCount; ++i) {
            deployedStrategyArray[i] = uint256(uint160(address(Env.instance.strategyBaseTVLLimits(i))));
        }
        // add beacon strategy
        deployedStrategyArray[deployedStrategyCount] = uint256(uint160(address(0xbeaC0eeEeeeeEEeEeEEEEeeEEeEeeeEeeEEBEaC0)));

        // sort array
        deployedStrategyArray = vm.sort(deployedStrategyArray);

        // write sorted array and multipliers
        for (uint256 i = 0; i < deployedStrategyCount; ++i) {
            strategiesAndMultipliers[1].push(IRewardsCoordinatorTypes.StrategyAndMultiplier({
                strategy: IStrategy(address(uint160(deployedStrategyArray[i]))),
                // TODO: note that this is hard-coded -- should probably look values up somehow
                multiplier: 1e18
            }));
        }
    }

    function deployContracts() internal {
        require(strategiesAndMultipliers[0].length != 0, "arrays not constructed properly");
        require(strategiesAndMultipliers[1].length != 0, "arrays not constructed properly");

        vm.startBroadcast();

        // deploy ActionGenerator & Hopper
        actionGenerator = new RewardAllStakersActionGenerator({
            _rewardsCoordinator: address(Env.proxy.rewardsCoordinator()),
            _firstSubmissionStartTimestamp: firstSubmissionStartTimestamp,
            _firstSubmissionTriggerCutoff: firstSubmissionTriggerCutoff,
            _amounts: amounts,
            _strategiesAndMultipliers: strategiesAndMultipliers,
            _bEIGEN: Env.proxy.beigen(),
            _EIGEN: Env.proxy.eigen()
        });

        // fetch config from previous deployment, but replace the action generator and mark as non-expiring
        ITokenHopper.HopperConfiguration memory hopperConfiguration = ITokenHopper.HopperConfiguration({
            token: address(Env.proxy.eigen()),
            startTime: firstSubmissionStartTimestamp,
            cooldownSeconds: 1 weeks,
            actionGenerator: address(actionGenerator),
            doesExpire: false,
            expirationTimestamp: type(uint256).max
        });
        tokenHopper = new TokenHopper({
            config: hopperConfiguration,
            // ownership transferred to zero address because no rights are conferred to owner (since hopper is non-expiring)
            initialOwner: address(0)
        });

        zUpdate('actionGenerator', address(actionGenerator));
        zUpdate('tokenHopper', address(tokenHopper));

        vm.stopBroadcast();
    }
}
