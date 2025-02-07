// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                   ROUTER TYPE DEFINITIONS
//////////////////////////////////////////////////////////////*/

/// @title PonderRouterTypes
/// @author taayyohh
/// @notice Type definitions and error handling for Ponder Router
/// @dev Consolidates constants, structs, and custom errors
///      Used across router implementation and libraries
library PonderRouterTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum allowed length of swap path
    /// @dev Limits gas costs and complexity of multi-hop swaps
    /// @dev Set to 4 to allow up to 3-hop trades
    uint256 public constant MAX_PATH_LENGTH = 4;

    /// @notice Minimum liquidity threshold for valid operations
    /// @dev Prevents price manipulation in low liquidity pools
    /// @dev Set to 1000 wei as absolute minimum
    uint256 public constant MIN_VIABLE_LIQUIDITY = 1000;

    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Parameters for executing token swaps
    /// @dev Packed structure to minimize calldata cost
    /// @param amountIn Amount of input tokens to swap
    /// @param minAmountsOut Minimum acceptable output at each hop
    /// @param path Array of token addresses defining swap route
    /// @param to Recipient of output tokens
    /// @param deadline Maximum timestamp for execution
    struct SwapParams {
        uint256 amountIn;
        uint256[] minAmountsOut;
        address[] path;
        address to;
        uint256 deadline;
    }

    /*//////////////////////////////////////////////////////////////
                            TRANSACTION ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Timing and deadline errors
    error ExpiredDeadline();              /// @dev Transaction exceeded time limit
    error Locked();                       /// @dev Reentrancy guard triggered

    /*//////////////////////////////////////////////////////////////
                            AMOUNT ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Amount validation errors
    error InsufficientOutputAmount();     /// @dev Output below minimum
    error InsufficientAAmount();          /// @dev First token amount too low
    error InsufficientBAmount();          /// @dev Second token amount too low
    error InsufficientAmount();           /// @dev Generic amount too low
    error InsufficientInputAmount();      /// @dev Input amount too low
    error ExcessiveInputAmount();         /// @dev Input exceeds maximum
    error InvalidAmount();                /// @dev Amount validation failed
    error ZeroOutput();                   /// @dev Output calculated as zero

    /*//////////////////////////////////////////////////////////////
                            LIQUIDITY ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pool and liquidity errors
    error InsufficientLiquidity();        /// @dev Pool liquidity too low
    error ExcessivePriceImpact(           /// @dev Price impact too high
        uint256 impact                    /// @dev Impact in basis points
    );

    /*//////////////////////////////////////////////////////////////
                            PATH ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Path validation errors
    error InvalidPath();                  /// @dev Swap path is invalid
    error IdenticalAddresses();           /// @dev Attempting same-token swap
    error PairNonexistent();             /// @dev Trading pair not found
    error PairCreationFailed();          /// @dev Failed to create pair

    /*//////////////////////////////////////////////////////////////
                            ETH HANDLING ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH-specific errors
    error InsufficientETH();             /// @dev Not enough ETH sent
    error InvalidETHAmount();            /// @dev ETH amount invalid
    error RefundFailed();                /// @dev ETH refund failed
    error UnwrapFailed();                /// @dev KKUB unwrap failed

    /*//////////////////////////////////////////////////////////////
                            TOKEN ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Token operation errors
    error ZeroAddress();                 /// @dev Invalid zero address
    error TransferFailed();              /// @dev Token transfer failed
    error ApprovalFailed();              /// @dev Token approval failed
    error InsufficientKkubBalance();     /// @dev Not enough KKUB
    error KKUBApprovalFailure();          /// @dev KKUB approval failed
}
