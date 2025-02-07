// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PonderRouterTypes } from "../types/PonderRouterTypes.sol";
import { IPonderFactory } from "../../../core/factory/IPonderFactory.sol";
import { PonderRouterSwapLib } from "./PonderRouterSwapLib.sol";

/*//////////////////////////////////////////////////////////////
                    ROUTER MATH OPERATIONS
//////////////////////////////////////////////////////////////*/

/// @title PonderRouterMathLib
/// @author taayyohh
/// @notice Library for DEX mathematical calculations and pricing
/// @dev Implements core AMM mathematics with precision handling
///      Uses constant product formula: x * y = k
///      Includes 0.3% swap fee in calculations
library PonderRouterMathLib {
    /*//////////////////////////////////////////////////////////////
                        EXACT INPUT CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates output amount for single-hop exact input swap
    /// @dev Uses constant product formula with 0.3% fee
    ///      Formula: dx * 0.997 * y / (x + dx * 0.997)
    /// @param amountIn Amount of input tokens
    /// @param reserveIn Current reserve of input token
    /// @param reserveOut Current reserve of output token
    /// @return Amount of output tokens to receive
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

    /// @notice Calculates output amounts for multi-hop exact input swap
    /// @dev Iteratively calculates amounts through the entire path
    ///      Handles arbitrary-length paths
    /// @param amountIn Initial input amount
    /// @param path Array of token addresses defining swap route
    /// @param factory Factory interface for pair lookups
    /// @return amounts Array of amounts at each hop in the path
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

    /*//////////////////////////////////////////////////////////////
                         EXACT OUTPUT CALCULATIONS
     //////////////////////////////////////////////////////////////*/

    /// @notice Calculates input amount needed for exact output swap
    /// @dev Reverse calculation of getAmountsOut with 0.3% fee
    ///      Formula: x * dy * 1000 / ((y - dy) * 997)
    /// @param amountOut Desired output amount
    /// @param reserveIn Current reserve of input token
    /// @param reserveOut Current reserve of output token
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

    /// @notice Calculates input amounts for multi-hop exact output swap
    /// @dev Iteratively calculates amounts backward through the path
    ///      Handles arbitrary-length paths
    /// @param amountOut Desired final output amount
    /// @param path Array of token addresses defining swap route
    /// @param factory Factory interface for pair lookups
    /// @return amounts Array of amounts at each hop in the path
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

    /*//////////////////////////////////////////////////////////////
                         LIQUIDITY CALCULATIONS
     //////////////////////////////////////////////////////////////*/

    /// @notice Calculates equivalent token amounts based on reserves
    /// @dev Uses basic ratio calculation: amountB = amountA * reserveB / reserveA
    ///      Used for liquidity provision calculations
    /// @param amountA Amount of token A
    /// @param reserveA Current reserve of token A
    /// @param reserveB Current reserve of token B
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
