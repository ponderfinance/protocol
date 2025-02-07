// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "../../../core/factory/IPonderFactory.sol";
import { PonderRouterTypes } from "../types/PonderRouterTypes.sol";
import { PonderRouterMathLib } from "./PonderRouterMathLib.sol";
import { PonderRouterSwapLib } from "./PonderRouterSwapLib.sol";

/*//////////////////////////////////////////////////////////////
                    ROUTER LIQUIDITY OPERATIONS
//////////////////////////////////////////////////////////////*/

/// @title PonderRouterLiquidityLib
/// @author taayyohh
/// @notice Library for managing liquidity operations in the Ponder Router
/// @dev Provides optimized functions for liquidity calculations and pool operations
///      Implements slippage protection and optimal amount calculations
///      Uses additional libraries for math and reserve operations
library PonderRouterLiquidityLib {
    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates and validates optimal liquidity amounts for a token pair
    /// @dev Handles both initial liquidity provision and subsequent additions
    ///      Creates pair if it doesn't exist
    ///      Optimizes amounts based on existing reserves
    ///      Implements slippage protection via minimum amounts
    /// @param tokenA First token address in pair
    /// @param tokenB Second token address in pair
    /// @param amountADesired Ideal amount of tokenA to add
    /// @param amountBDesired Ideal amount of tokenB to add
    /// @param amountAMin Minimum acceptable amount of tokenA
    /// @param amountBMin Minimum acceptable amount of tokenB
    /// @param factory Interface to PonderFactory for pair management
    /// @return amountA Actual amount of tokenA to provide
    /// @return amountB Actual amount of tokenB to provide
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        IPonderFactory factory
    ) internal returns (uint256 amountA, uint256 amountB) {
        // Create pair if it doesn't exist
        if (factory.getPair(tokenA, tokenB) == address(0)) {
            address pair = factory.createPair(tokenA, tokenB);
            if (pair == address(0)) revert PonderRouterTypes.PairCreationFailed();
        }

        // Get current reserves for both tokens
        (uint256 reserveA, uint256 reserveB) = PonderRouterSwapLib.getReserves(tokenA, tokenB, factory);

        // Handle initial liquidity case
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // Calculate optimal amounts based on current ratio
            uint256 amountBOptimal = PonderRouterMathLib.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                // Use full amount of tokenA and calculated amount of tokenB
                if (amountBOptimal < amountBMin) revert PonderRouterTypes.InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // Calculate and use optimal amount of tokenA instead
                uint256 amountAOptimal = PonderRouterMathLib.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) revert PonderRouterTypes.InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
}
