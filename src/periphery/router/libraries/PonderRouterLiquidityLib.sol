// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IPonderFactory } from "../../../core/factory/IPonderFactory.sol";
import { IPonderPair } from "../../../core/pair/IPonderPair.sol";
import { PonderRouterTypes } from "../types/PonderRouterTypes.sol";
import { PonderRouterMathLib } from "./PonderRouterMathLib.sol";
import { PonderRouterSwapLib } from "./PonderRouterSwapLib.sol";

/// @title Ponder Router Liquidity Library
/// @notice Library for handling liquidity operations in the Ponder Router
/// @dev Contains functions for adding and removing liquidity from pairs
library PonderRouterLiquidityLib {
    /// @notice Calculates optimal liquidity amounts for token pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param amountADesired Desired amount of tokenA
    /// @param amountBDesired Desired amount of tokenB
    /// @param amountAMin Minimum acceptable amount of tokenA
    /// @param amountBMin Minimum acceptable amount of tokenB
    /// @param factory PonderFactory reference for pair operations
    /// @return amountA Final amount of tokenA
    /// @return amountB Final amount of tokenB
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        IPonderFactory factory
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (factory.getPair(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB);
        }

        (uint256 reserveA, uint256 reserveB) = PonderRouterSwapLib.getReserves(tokenA, tokenB, factory);

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = PonderRouterMathLib.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert PonderRouterTypes.InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = PonderRouterMathLib.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) revert PonderRouterTypes.InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
}
