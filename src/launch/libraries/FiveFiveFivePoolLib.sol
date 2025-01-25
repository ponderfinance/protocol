// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { FiveFiveFiveConstants } from "./FiveFiveFiveConstants.sol";
import { PonderPair } from "../../core/pair/PonderPair.sol";
import { PonderERC20 } from "../../core/token/PonderERC20.sol";
import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { LaunchToken } from "../LaunchToken.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FiveFiveFivePoolLib
/// @author taayyohh
/// @notice Library for managing liquidity pool operations
/// @dev Handles pool creation, liquidity addition, and pool calculations
library FiveFiveFivePoolLib {
    using SafeERC20 for PonderERC20;
    using FiveFiveFiveConstants for uint256;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event PonderPoolSkipped(
        uint256 indexed launchId,
        uint256 ponderAmount,
        uint256 ponderValueInKub
    );

    /*//////////////////////////////////////////////////////////////
                        POOL CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates amounts for pool creation based on collected contributions
    /// @param launch The launch info
    /// @return pools Pool configuration with token amounts
    function calculatePoolAmounts(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) internal view returns (FiveFiveFiveLauncherTypes.PoolConfig memory pools) {
        // Calculate KUB amount for primary pool (60%)
        pools.kubAmount = (launch.contributions.kubCollected *
            FiveFiveFiveConstants.KUB_TO_MEME_KUB_LP) / FiveFiveFiveConstants.BASIS_POINTS;

        // Calculate PONDER amount for secondary pool (80% of collected PONDER)
        pools.ponderAmount = (launch.contributions.ponderCollected *
            FiveFiveFiveConstants.PONDER_TO_MEME_PONDER) / FiveFiveFiveConstants.BASIS_POINTS;

        // Split LP tokens equally between pairs
        pools.tokenAmount = launch.allocation.tokensForLP / 2;

        return pools;
    }

    /*//////////////////////////////////////////////////////////////
                        POOL CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates or retrieves KUB pair and validates its state
    /// @param factory The factory contract
    /// @param tokenAddress The token address
    /// @param router The router contract
    /// @return pair The validated pair address
    function getOrCreateKubPair(
        IPonderFactory factory,
        address tokenAddress,
        IPonderRouter router
    ) internal returns (address pair) {
        address weth = router.weth();
        pair = factory.getPair(tokenAddress, weth);

        if (pair == address(0)) {
            pair = factory.createPair(tokenAddress, weth);
        }

        // Validate pair state

        // Third value from getReserves is block.timestamp
        // which we don't need for reserve validation
        // slither-disable-next-line unused-return
        (uint112 r0, uint112 r1,) = PonderPair(pair).getReserves();

        if (r0 != 0 || r1 != 0) {
            revert FiveFiveFiveLauncherTypes.PriceOutOfBounds();
        }

        return pair;
    }

    /// @notice Creates or retrieves PONDER pair and validates its state
    /// @param factory The factory contract
    /// @param tokenAddress The token address
    /// @param ponder The PONDER token address
    /// @return pair The validated pair address
    function getOrCreatePonderPair(
        IPonderFactory factory,
        address tokenAddress,
        address ponder
    ) internal returns (address pair) {
        pair = factory.getPair(tokenAddress, ponder);

        if (pair == address(0)) {
            pair = factory.createPair(tokenAddress, ponder);
        }

        // Validate pair state
        // Third value from getReserves is block.timestamp
        // which we don't need for reserve validation
        // slither-disable-next-line unused-return
        (uint112 r0, uint112 r1,) = PonderPair(pair).getReserves();

        if (r0 != 0 || r1 != 0) {
            revert FiveFiveFiveLauncherTypes.PriceOutOfBounds();
        }

        return pair;
    }

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY ADDITION
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds KUB liquidity to a pool with slippage protection
    /// @param router The router contract
    /// @param tokenAddress The token address
    /// @param kubAmount Amount of KUB to add
    /// @param tokenAmount Amount of tokens to add
    /// @param recipient Address to receive LP tokens
    /// @return amountToken Amount of tokens added
    /// @return amountKUB Amount of KUB added
    /// @return liquidity Amount of LP tokens minted
    function addKubLiquidity(
        IPonderRouter router,
        address tokenAddress,
        uint256 kubAmount,
        uint256 tokenAmount,
        address recipient
    ) internal returns (
        uint256 amountToken,
        uint256 amountKUB,
        uint256 liquidity
    ) {
        // Set slippage tolerance to 0.5%
        uint256 minTokenAmount = tokenAmount * 995 / 1000;
        uint256 minKubAmount = kubAmount * 995 / 1000;

        // Add approvals first
        if (!LaunchToken(tokenAddress).approve(address(router), tokenAmount)) {
            revert FiveFiveFiveLauncherTypes.ApprovalFailed();
        }

        // Add liquidity with slippage protection
        return router.addLiquidityETH{value: kubAmount}(
            tokenAddress,
            tokenAmount,
            minTokenAmount,
            minKubAmount,
            recipient,
            block.timestamp + 3 minutes
        );
    }

    /// @notice Adds PONDER liquidity to a pool with slippage protection
    /// @param router The router contract
    /// @param tokenAddress The token address
    /// @param ponder The PONDER token address
    /// @param ponderAmount Amount of PONDER to add
    /// @param tokenAmount Amount of tokens to add
    /// @param recipient Address to receive LP tokens
    /// @return amountToken Amount of tokens added
    /// @return amountPonder Amount of PONDER added
    /// @return liquidity Amount of LP tokens minted
    function addPonderLiquidity(
        IPonderRouter router,
        address tokenAddress,
        address ponder,
        uint256 ponderAmount,
        uint256 tokenAmount,
        address recipient
    ) internal returns (
        uint256 amountToken,
        uint256 amountPonder,
        uint256 liquidity
    ) {
        // Set slippage tolerance to 0.5%
        uint256 minTokenAmount = tokenAmount * 995 / 1000;
        uint256 minPonderAmount = ponderAmount * 995 / 1000;

        // Add approvals first
        if (!LaunchToken(tokenAddress).approve(address(router), tokenAmount)) {
            revert FiveFiveFiveLauncherTypes.ApprovalFailed();
        }
        if (!PonderToken(ponder).approve(address(router), ponderAmount)) {
            revert FiveFiveFiveLauncherTypes.ApprovalFailed();
        }

        // Add liquidity with slippage protection
        return router.addLiquidity(
            tokenAddress,
            ponder,
            tokenAmount,
            ponderAmount,
            minTokenAmount,
            minPonderAmount,
            recipient,
            block.timestamp + 3 minutes
        );
    }

    /*//////////////////////////////////////////////////////////////
                        VALIDATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates pool creation and liquidity requirements
    /// @param pool The pool configuration
    /// @param pair The pair address
    function validatePoolCreation(
        FiveFiveFiveLauncherTypes.PoolConfig memory pool,
        address pair
    ) internal view {
        // Check minimum liquidity
        if (pool.kubAmount < FiveFiveFiveConstants.MIN_POOL_LIQUIDITY) {
            revert FiveFiveFiveLauncherTypes.InsufficientPoolLiquidity();
        }

        // Verify pair has no existing liquidity
        if (pair != address(0)) {
            // Third value from getReserves is block.timestamp
            // which we don't need for reserve validation
            // slither-disable-next-line unused-return
            (uint112 r0, uint112 r1,) = PonderPair(pair).getReserves();

            if (r0 != 0 || r1 != 0) {
                revert FiveFiveFiveLauncherTypes.PriceOutOfBounds();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        LP TOKEN MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraws LP tokens from a specific pair
    /// @param pair The pair address
    /// @param recipient The recipient address
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
