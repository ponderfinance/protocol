// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title Ponder Router Types Library
/// @notice Library containing types, constants, and errors for the Ponder Router
/// @dev Consolidates all type definitions used in the PonderRouter system
library PonderRouterTypes {
    /// @notice Maximum number of token pairs in a swap path
    /// @dev Limits the complexity and gas cost of multi-hop swaps
    uint256 public constant MAX_PATH_LENGTH = 4;

    /// @notice Minimum required liquidity for valid price quotes
    /// @dev Prevents manipulation through low liquidity pools
    uint256 public constant MIN_VIABLE_LIQUIDITY = 1000; // 1000 wei

    /// @notice Parameters for swap operations
    /// @param amountIn Amount of input tokens for the swap
    /// @param minAmountsOut Minimum amounts of tokens to receive at each step
    /// @param path Array of token addresses defining the swap path
    /// @param to Address to receive the output tokens
    /// @param deadline Maximum timestamp for execution
    struct SwapParams {
        uint256 amountIn;
        uint256[] minAmountsOut;
        address[] path;
        address to;
        uint256 deadline;
    }

    // Custom Errors

    /// @notice Thrown when transaction deadline has passed
    error ExpiredDeadline();

    /// @notice Thrown when output amount is less than minimum required
    error InsufficientOutputAmount();

    /// @notice Thrown when tokenA amount is less than minimum required
    error InsufficientAAmount();

    /// @notice Thrown when tokenB amount is less than minimum required
    error InsufficientBAmount();

    /// @notice Thrown when pool liquidity is too low for operation
    error InsufficientLiquidity();

    /// @notice Thrown when swap path is invalid
    error InvalidPath();

    /// @notice Thrown when trying to swap identical tokens
    error IdenticalAddresses();

    /// @notice Thrown when input amount exceeds maximum allowed
    error ExcessiveInputAmount();

    /// @notice Thrown when ETH amount is insufficient
    error InsufficientETH();

    /// @notice Thrown when address provided is zero address
    error ZeroAddress();

    /// @notice Thrown when pair does not exist
    error PairNonexistent();

    /// @notice Thrown when amount specified is invalid
    error InvalidAmount();

    /// @notice Thrown when ETH amount is invalid
    error InvalidETHAmount();

    /// @notice Thrown when token transfer fails
    error TransferFailed();

    /// @notice Thrown when ETH refund fails
    error RefundFailed();

    /// @notice Thrown when output amount is zero
    error ZeroOutput();

    /// @notice Thrown when price impact exceeds threshold
    /// @param impact The calculated price impact in basis points
    error ExcessivePriceImpact(uint256 impact);

    /// @notice Thrown when contract is locked (reentrancy check)
    error Locked();

    /// @notice Thrown when WETH balance is insufficient
    error InsufficientWethBalance();

    /// @notice Thrown when WETH approval fails
    error WethApprovalFailed();

    /// @notice Thrown when amount is insufficient
    error InsufficientAmount();

    /// @notice Thrown when input amount is insufficient
    error InsufficientInputAmount();
}
