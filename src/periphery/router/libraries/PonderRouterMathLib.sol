// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { PonderRouterTypes } from "../types/PonderRouterTypes.sol";
import { IPonderFactory } from "../../../core/factory/IPonderFactory.sol";
import { PonderRouterSwapLib } from "./PonderRouterSwapLib.sol";

/// @title Ponder Router Math Library
/// @notice Library for mathematical calculations in the Ponder Router
/// @dev Contains core pricing and amount calculations
library PonderRouterMathLib {
    /// @notice Calculates amounts out for exact input swap
    /// @param amountIn Input amount
    /// @param reserveIn Input reserve
    /// @param reserveOut Output reserve
    /// @return Amount of output tokens
    function getAmountsOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        if (amountIn == 0) revert PonderRouterTypes.InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert PonderRouterTypes.InsufficientLiquidity();

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    /// @notice Calculates amounts for a sequence of swaps
    /// @param amountIn Initial input amount
    /// @param path Array of token addresses in swap path
    /// @param factory Factory for looking up pairs
    /// @return amounts Array of amounts for entire path
    function getAmountsOutMultiHop(
        uint256 amountIn,
        address[] memory path,
        IPonderFactory factory
    ) internal view returns (uint256[] memory amounts) {
        if (path.length < 2) revert PonderRouterTypes.InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = PonderRouterSwapLib.getReserves(
                path[i], path[i + 1], factory
            );
            amounts[i + 1] = getAmountsOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /// @notice Calculates amounts in for exact output swap
    /// @param amountOut Desired output amount
    /// @param reserveIn Input reserve
    /// @param reserveOut Output reserve
    /// @return Amount of input tokens needed
    function getAmountsIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256) {
        if (amountOut == 0) revert PonderRouterTypes.InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert PonderRouterTypes.InsufficientLiquidity();

        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        return (numerator / denominator) + 1;
    }

    /// @notice Calculates amounts for a sequence of exact output swaps
    /// @param amountOut Desired output amount
    /// @param path Array of token addresses in swap path
    /// @param factory Factory for looking up pairs
    /// @return amounts Array of amounts for entire path
    function getAmountsInMultiHop(
        uint256 amountOut,
        address[] memory path,
        IPonderFactory factory
    ) internal view returns (uint256[] memory amounts) {
        if (path.length < 2) revert PonderRouterTypes.InvalidPath();
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;

        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = PonderRouterSwapLib.getReserves(
                path[i - 1], path[i], factory
            );
            amounts[i - 1] = getAmountsIn(amounts[i], reserveIn, reserveOut);
        }
    }

    /// @notice Quotes the equivalent amount of tokens based on reserves
    /// @param amountA Amount of token A
    /// @param reserveA Reserve of token A
    /// @param reserveB Reserve of token B
    /// @return amountB Equivalent amount of token B
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        if (amountA == 0) revert PonderRouterTypes.InsufficientAmount();
        if (reserveA == 0 || reserveB == 0) revert PonderRouterTypes.InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }
}
