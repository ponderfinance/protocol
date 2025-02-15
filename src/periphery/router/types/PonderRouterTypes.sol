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
}
