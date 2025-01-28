// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PonderPairTypes
 * @notice Library containing types, constants, and custom errors for the PonderPair contract
 * @dev This library centralizes all type definitions and constants used in the PonderPair system
 */
library PonderPairTypes {
/**
     * @notice Minimum liquidity required to initialize a pair
     * @dev This value is burned during the first mint to prevent the pool being drained
     */
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    /**
     * @notice Denominator used for fee calculations (10000 = 100%)
     */
    uint256 internal constant FEE_DENOMINATOR = 10000;

    /**
     * @notice Fee allocated to liquidity providers (0.25%)
     */
    uint256 internal constant LP_FEE = 25;

    /**
     * @notice Creator fee for Ponder token pairs (0.04%)
     */
    uint256 internal constant PONDER_CREATOR_FEE = 4;

    /**
     * @notice Protocol fee for Ponder token pairs (0.01%)
     */
    uint256 internal constant PONDER_PROTOCOL_FEE = 1;

    /**
     * @notice Creator fee for KUB pairs (0.01%)
     */
    uint256 internal constant KUB_CREATOR_FEE = 1;

    /**
     * @notice Protocol fee for KUB pairs (0.04%)
     */
    uint256 internal constant KUB_PROTOCOL_FEE = 4;

    /**
     * @notice Standard protocol fee for regular pairs (0.05%)
     */
    uint256 internal constant STANDARD_PROTOCOL_FEE = 5;

    /**
     * @notice Function selector for the ERC20 transfer function
     */
    bytes4 internal constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    /**
     * @notice Struct containing data for swap operations
     * @param amount0Out Amount of token0 to output
     * @param amount1Out Amount of token1 to output
     * @param amount0In Amount of token0 input
     * @param amount1In Amount of token1 input
     * @param balance0 Current balance of token0
     * @param balance1 Current balance of token1
     * @param reserve0 Reserve of token0 before swap
     * @param reserve1 Reserve of token1 before swap
     */
    struct SwapData {
        uint256 amount0Out;
        uint256 amount1Out;
        uint256 amount0In;
        uint256 amount1In;
        uint256 balance0;
        uint256 balance1;
        uint112 reserve0;
        uint112 reserve1;
    }


    struct SwapCallbackData {
        uint256 amount0Out;
        uint256 amount1Out;
        uint256 amount0In;
        uint256 amount1In;
        address token0;
        address token1;
        address to;
        bytes callbackData;
    }

    /**
     * @notice Struct containing reserve data for the pair
     * @param reserve0 Reserve of token0
     * @param reserve1 Reserve of token1
     * @param blockTimestampLast Timestamp of last update
     */
    struct Reserves {
        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;
    }

    // Custom Errors
    /// @notice Thrown when a function is called while the contract is locked
    error Locked();
    /// @notice Thrown when a caller lacks the required permissions
    error Forbidden();
    /// @notice Thrown when a token transfer fails
    error TransferFailed();
    /// @notice Thrown when the output amount specified is insufficient
    error InsufficientOutputAmount();
    /// @notice Thrown when the recipient address is invalid
    error InvalidToAddress();
    /// @notice Thrown when there isn't enough liquidity for an operation
    error InsufficientLiquidity();
    /// @notice Thrown when not enough liquidity tokens are burned
    error InsufficientLiquidityBurned();
    /// @notice Thrown when initial liquidity provision is too low
    error InsufficientInitialLiquidity();
    /// @notice Thrown when liquidity minting results in zero tokens
    error InsufficientLiquidityMinted();
    /// @notice Thrown when output amounts are insufficient
    error InsufficientOutput();
    /// @notice Thrown when recipient address is invalid
    error InvalidRecipient();
    /// @notice Thrown when liquidity is insufficient for swap
    error InsufficientLiquiditySwap();
    /// @notice Thrown when input amount is insufficient
    error InsufficientInputAmount();
    /// @notice Thrown when K value check fails
    error KValueCheckFailed();
    /// @notice Thrown when constant product invariant is violated
    error InvariantViolation();
    /// @notice Thrown when a calculation would overflow
    error Overflow();
    /// @notice Throws Zero Address
    error ZeroAddress();
}
