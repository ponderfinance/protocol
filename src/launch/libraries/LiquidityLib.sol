// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { PonderPair } from "../../core/pair/PonderPair.sol";
import { PonderERC20 } from "../../core/token/PonderERC20.sol";
import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { LaunchToken } from "../LaunchToken.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { PonderPriceOracle } from "../../core/oracle/PonderPriceOracle.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { LaunchTokenTypes } from "../types/LaunchTokenTypes.sol";

/// @title LiquidityLib
/// @author taayyohh
/// @notice Library for liquidity management and view operations
/// @dev Optimized for storage operations and gas efficiency
library LiquidityLib {
    using SafeERC20 for PonderERC20;
    using FiveFiveFiveLauncherTypes for FiveFiveFiveLauncherTypes.LaunchInfo;

    event PonderPoolSkipped(uint256 indexed launchId, uint256 ponderAmount, uint256 ponderValueInKub);
    event PonderBurned(uint256 indexed launchId, uint256 amount);
    event DualPoolsCreated(uint256 indexed launchId, address memeKubPair, address memePonderPair, uint256 kubLiquidity, uint256 ponderLiquidity);
    event LaunchCompleted(uint256 indexed launchId, uint256 kubRaised, uint256 ponderRaised);

    /// @notice Finalizes a launch by creating pools and enabling trading
    /// @dev Uses packed storage values and optimized operations
    function finalizeLaunch(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        PonderPriceOracle priceOracle
    ) external {
        if (launch.base.launched) revert FiveFiveFiveLauncherTypes.AlreadyLaunched();

        // Check total distribution using uint128 comparison
        unchecked {
        // Safe arithmetic: tokensDistributed and tokensForLP are uint128
            if (uint128(launch.contributions.tokensDistributed) + launch.allocation.tokensForLP >
                uint128(LaunchTokenTypes.TOTAL_SUPPLY)) {
                revert FiveFiveFiveLauncherTypes.InsufficientLPTokens();
            }
        }

        // Mark as launched immediately to prevent reentrancy
        launch.base.launched = true;

        // Calculate pool amounts using packed values
        FiveFiveFiveLauncherTypes.PoolConfig memory pools = calculatePoolAmounts(launch);

        // Create and validate KUB pool
        _createKubPool(launch, pools, factory, router);

        // Handle PONDER pool if needed
        if (launch.contributions.ponderCollected > 0) {
            _handlePonderPool(launch, launchId, pools, factory, router, ponder, priceOracle);
        }

        // Enable trading and finalize
        _enableTrading(launch, launchId);
    }

    /// @notice Gets contributor information using packed values
    function getContributorInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address contributor
    ) external view returns (
        uint256 kubContributed,
        uint256 ponderContributed,
        uint256 ponderValue,
        uint256 tokensReceived
    ) {
        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
        // Unpack uint128 values to uint256 for return
        return (
            uint256(info.kubContributed),
            uint256(info.ponderContributed),
            uint256(info.ponderValue),
            uint256(info.tokensReceived)
        );
    }

    /// @notice Gets overall contribution information
    function getContributionInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view returns (
        uint256 kubCollected,
        uint256 ponderCollected,
        uint256 ponderValueCollected,
        uint256 totalValue
    ) {
        kubCollected = launch.contributions.kubCollected;
        ponderCollected = launch.contributions.ponderCollected;
        ponderValueCollected = launch.contributions.ponderValueCollected;

        unchecked {
        // Safe math: totalValue cannot overflow as contributions are limited
            totalValue = kubCollected + ponderValueCollected;
        }
    }

    /// @notice Gets pool information and checks pool state
    function getPoolInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view returns (
        address memeKubPair,
        address memePonderPair,
        bool hasSecondaryPool
    ) {
        return (
            launch.pools.memeKubPair,
            launch.pools.memePonderPair,
            launch.pools.memePonderPair != address(0)
        );
    }

    /// @notice Gets basic launch information with packed values
    function getLaunchInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view returns (
        address tokenAddress,
        string memory name,
        string memory symbol,
        string memory imageURI,
        uint256 kubRaised,
        bool launched,
        uint256 lpUnlockTime
    ) {
        return (
            launch.base.tokenAddress,
            launch.base.name,
            launch.base.symbol,
            launch.base.imageURI,
            launch.contributions.kubCollected,
            launch.base.launched,
            uint256(launch.base.lpUnlockTime)  // Unpack uint40 to uint256
        );
    }

    /// @notice Gets minimum requirements
    function getMinimumRequirements() external pure returns (
        uint256 minKub,
        uint256 minPonder,
        uint256 minPoolLiquidity
    ) {
        return (
            FiveFiveFiveLauncherTypes.MIN_KUB_CONTRIBUTION,
            FiveFiveFiveLauncherTypes.MIN_PONDER_CONTRIBUTION,
            FiveFiveFiveLauncherTypes.MIN_POOL_LIQUIDITY
        );
    }

    /// @notice Calculates remaining amounts that can be raised
    function getRemainingToRaise(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view returns (
        uint256 remainingTotal,
        uint256 remainingPonderValue
    ) {
        unchecked {
        // Safe math: contributions are limited by TARGET_RAISE
            uint256 total = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
            remainingTotal = total >= FiveFiveFiveLauncherTypes.TARGET_RAISE ?
                0 : FiveFiveFiveLauncherTypes.TARGET_RAISE - total;

            uint256 maxPonderValue = (FiveFiveFiveLauncherTypes.TARGET_RAISE *
                FiveFiveFiveLauncherTypes.MAX_PONDER_PERCENT) / FiveFiveFiveLauncherTypes.BASIS_POINTS;
            uint256 currentPonderValue = launch.contributions.ponderValueCollected;
            remainingPonderValue = currentPonderValue >= maxPonderValue ?
                0 : maxPonderValue - currentPonderValue;
        }

        return (
            remainingTotal,
            remainingPonderValue < remainingTotal ? remainingPonderValue : remainingTotal
        );
    }

    /// @dev Calculates amounts for pool creation using packed values
    function calculatePoolAmounts(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) internal view returns (FiveFiveFiveLauncherTypes.PoolConfig memory pools) {
        unchecked {
        // Safe math: all values are bounded by constants
            pools.kubAmount = (launch.contributions.kubCollected *
                uint16(FiveFiveFiveLauncherTypes.KUB_TO_MEME_KUB_LP)) / FiveFiveFiveLauncherTypes.BASIS_POINTS;
            pools.ponderAmount = (launch.contributions.ponderCollected *
                uint16(FiveFiveFiveLauncherTypes.PONDER_TO_MEME_PONDER)) / FiveFiveFiveLauncherTypes.BASIS_POINTS;
            pools.tokenAmount = uint128(launch.allocation.tokensForLP) / 2;
        }
        return pools;
    }

    /// @dev Creates KUB pool with optimized operations
    function _createKubPool(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.PoolConfig memory pools,
        IPonderFactory factory,
        IPonderRouter router
    ) private {
        address pair = _createOrGetPair(factory, launch.base.tokenAddress, router.weth());
        _validatePairState(pair);
        launch.pools.memeKubPair = pair;

        _validatePoolLiquidity(pools.kubAmount);

        if (!LaunchToken(launch.base.tokenAddress).approve(address(router), pools.tokenAmount)) {
            revert FiveFiveFiveLauncherTypes.ApprovalFailed();
        }

        router.addLiquidityETH{value: pools.kubAmount}(
            launch.base.tokenAddress,
            pools.tokenAmount,
            (pools.tokenAmount * 995) / 1000, // 0.5% slippage
            (pools.kubAmount * 995) / 1000,   // 0.5% slippage
            address(this),
            block.timestamp + 3 minutes
        );
    }

    /// @dev Handles PONDER pool creation with optimized value handling
    function _handlePonderPool(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        FiveFiveFiveLauncherTypes.PoolConfig memory pools,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        PonderPriceOracle priceOracle
    ) private {
        uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount, factory, router, ponder, priceOracle);

        if (ponderPoolValue >= FiveFiveFiveLauncherTypes.MIN_POOL_LIQUIDITY) {
            _createPonderPool(launch, pools, factory, router, ponder);

            emit DualPoolsCreated(
                launchId,
                launch.pools.memeKubPair,
                launch.pools.memePonderPair,
                pools.kubAmount,
                pools.ponderAmount
            );
        } else {
            emit PonderPoolSkipped(launchId, pools.ponderAmount, ponderPoolValue);
            emit PonderBurned(launchId, launch.contributions.ponderCollected);

            ponder.burn(launch.contributions.ponderCollected);
        }
    }

    /// @dev Creates PONDER pool with optimized operations
    function _createPonderPool(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.PoolConfig memory pools,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder
    ) private {
        uint256 ponderToBurn;
        unchecked {
        // Safe math: bounded by constant percentages
            ponderToBurn = (launch.contributions.ponderCollected *
                uint16(FiveFiveFiveLauncherTypes.PONDER_TO_BURN)) / FiveFiveFiveLauncherTypes.BASIS_POINTS;
        }

        address pair = _createOrGetPair(factory, launch.base.tokenAddress, address(ponder));
        _validatePairState(pair);
        launch.pools.memePonderPair = pair;

        if (!LaunchToken(launch.base.tokenAddress).approve(address(router), pools.tokenAmount)) {
            revert FiveFiveFiveLauncherTypes.ApprovalFailed();
        }
        if (!ponder.approve(address(router), pools.ponderAmount)) {
            revert FiveFiveFiveLauncherTypes.ApprovalFailed();
        }

        router.addLiquidity(
            launch.base.tokenAddress,
            address(ponder),
            pools.tokenAmount,
            pools.ponderAmount,
            (pools.tokenAmount * 995) / 1000, // 0.5% slippage
            (pools.ponderAmount * 995) / 1000, // 0.5% slippage
            address(this),
            block.timestamp + 3 minutes
        );

        ponder.burn(ponderToBurn);
    }

    /// @dev Creates or retrieves a pair from factory
    function _createOrGetPair(
        IPonderFactory factory,
        address tokenA,
        address tokenB
    ) private returns (address) {
        address pair = factory.getPair(tokenA, tokenB);
        return pair == address(0) ? factory.createPair(tokenA, tokenB) : pair;
    }

    /// @dev Validates pair state
    function _validatePairState(address pair) private view {
        (uint112 r0, uint112 r1,) = PonderPair(pair).getReserves();
        if (r0 != 0 || r1 != 0) revert FiveFiveFiveLauncherTypes.PriceOutOfBounds();
    }

    /// @dev Validates minimum liquidity requirements
    function _validatePoolLiquidity(uint256 amount) private pure {
        if (amount < FiveFiveFiveLauncherTypes.MIN_POOL_LIQUIDITY)
            revert FiveFiveFiveLauncherTypes.InsufficientPoolLiquidity();
    }

    /// @dev Enables trading with optimized timestamp handling
    function _enableTrading(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId
    ) private {
        unchecked {
        // Safe math: timestamp addition is bounded
            launch.base.lpUnlockTime = uint40(block.timestamp + FiveFiveFiveLauncherTypes.LP_LOCK_PERIOD);
        }

        LaunchToken token = LaunchToken(launch.base.tokenAddress);
        token.setPairs(launch.pools.memeKubPair, launch.pools.memePonderPair);
        token.enableTransfers();

        emit LaunchCompleted(
            launchId,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    /// @dev Gets KUB value of PONDER amount
    function _getPonderValue(
        uint256 amount,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        PonderPriceOracle priceOracle
    ) private view returns (uint256) {
        address ponderKubPair = factory.getPair(address(ponder), router.weth());
        return priceOracle.getCurrentPrice(
            ponderKubPair,
            address(ponder),
            amount
        );
    }

    /// @notice Withdraws LP tokens from a specific pair
    /// @param pair The pair address to withdraw from
    /// @param recipient Address to receive the LP tokens
    /// @return amount Amount of LP tokens withdrawn
    function withdrawPairLP(
        address pair,
        address recipient
    ) internal returns (uint256 amount) {
        if (pair == address(0)) return 0;

        amount = PonderERC20(pair).balanceOf(address(this));
        if (amount > 0) {
            PonderERC20(pair).safeTransfer(recipient, amount);
        }

        return amount;
    }
}
