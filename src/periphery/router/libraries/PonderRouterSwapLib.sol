// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPonderFactory } from "../../../core/factory/IPonderFactory.sol";
import { IPonderPair } from "../../../core/pair/IPonderPair.sol";
import { PonderRouterMathLib } from "./PonderRouterMathLib.sol";
import { IPonderRouter } from "../IPonderRouter.sol";

/*//////////////////////////////////////////////////////////////
                    ROUTER SWAP OPERATIONS
//////////////////////////////////////////////////////////////*/

/// @title PonderRouterSwapLib
/// @author taayyohh
/// @notice Library for executing token swaps in the Ponder Router
/// @dev Implements core swap logic with support for:
///      - Regular ERC20 tokens
///      - Fee-on-transfer tokens
///      - Multi-hop swaps
library PonderRouterSwapLib {
    using PonderRouterMathLib for *;

    /*//////////////////////////////////////////////////////////////
                        CORE SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a token swap through a specified path
    /// @dev Handles both regular and fee-on-transfer token swaps
    ///      Supports multi-hop swaps through multiple pairs
    ///      Uses unchecked math for gas optimization where safe
    /// @param amounts Array of amounts for each hop in the path
    /// @param path Array of token addresses defining the swap route
    /// @param to Address to receive the final output tokens
    /// @param supportingFee Whether to handle fee-on-transfer tokens
    /// @param factory Interface for pair lookups
    function executeSwap(
        uint256[] memory amounts,
        address[] memory path,
        address to,
        bool supportingFee,
        IPonderFactory factory
    ) internal {
        for (uint256 i; i < path.length - 1;) {
            IPonderPair pair = IPonderPair(factory.getPair(path[i], path[i + 1]));

            // Calculate next recipient
            address recipient;
            unchecked {
                recipient = i < path.length - 2 ? factory.getPair(path[i + 1], path[i + 2]) : to;
                ++i;
            }

            _handleSwap(
                pair,
                SwapParams({
                    input: path[i - 1],
                    output: path[i],
                    amountOut: supportingFee ? 0 : amounts[i],
                    recipient: recipient,
                    supportingFee: supportingFee
                })
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                      INTERNAL STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Parameters for swap execution to avoid stack too deep
    /// @param input Address of input token
    /// @param output Address of output token
    /// @param amountOut Expected output amount (0 for fee-on-transfer)
    /// @param recipient Address to receive output tokens
    /// @param supportingFee Whether handling fee-on-transfer tokens
    struct SwapParams {
        address input;
        address output;
        uint256 amountOut;
        address recipient;
        bool supportingFee;
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Core swap execution logic
    /// @dev Handles both regular and fee-on-transfer token swaps
    /// @param pair Address of the pair contract
    /// @param params Struct containing swap parameters
    function _handleSwap(
        IPonderPair pair,
        SwapParams memory params
    ) private {
        (address token0,) = sortTokens(params.input, params.output);

        uint256 amount0Out;
        uint256 amount1Out;

        if (params.supportingFee) {
            (uint256 reserve0, uint256 reserve1,) = pair.getReserves();

            if (reserve0 == 0 && reserve1 == 0) revert IPonderRouter.InsufficientLiquidity();

            (uint256 reserveIn, uint256 reserveOut) = params.input == token0
                ? (reserve0, reserve1)
                : (reserve1, reserve0);

            uint256 amountInput = IERC20(params.input).balanceOf(address(pair)) - reserveIn;
            uint256 amountOutput = PonderRouterMathLib.getAmountsOut(amountInput, reserveIn, reserveOut);

            (amount0Out, amount1Out) = params.input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
        } else {
            (amount0Out, amount1Out) = params.input == token0
                ? (uint256(0), params.amountOut)
                : (params.amountOut, uint256(0));
        }

        pair.swap(amount0Out, amount1Out, params.recipient, new bytes(0));
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sorts two token addresses for consistent ordering
    /// @dev Ensures deterministic pair addressing
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return token0 Lower token address
    /// @return token1 Higher token address
    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert IPonderRouter.IdenticalAddresses();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert IPonderRouter.ZeroAddress();
    }

    /// @notice Retrieves current reserves for a token pair
    /// @dev Sorts tokens and handles reserve ordering
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param factory Interface for pair lookups
    /// @return reserveA Reserve of first token
    /// @return reserveB Reserve of second token
    function getReserves(
        address tokenA,
        address tokenB,
        IPonderFactory factory
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IPonderPair(factory.getPair(token0, token1)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }
}
