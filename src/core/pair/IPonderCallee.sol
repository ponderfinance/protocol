// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER CALLBACK INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderCallee
/// @author taayyohh
/// @notice Callback interface for flash swap functionality
/// @dev Contracts must implement this to receive callbacks during flash swaps
/// @dev Similar to Uniswap's IUniswapV2Callee but with Ponder-specific features
interface IPonderCallee {
    /*//////////////////////////////////////////////////////////////
                            CALLBACK LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Called during flash swaps to notify the callee
    /// @dev Must handle receiving tokens and paying back the flash swap
    /// @dev Will revert the entire transaction if callback fails
    /// @param sender Original caller of the flash swap function
    /// @param amount0 Amount of token0 received in the flash swap
    /// @param amount1 Amount of token1 received in the flash swap
    /// @param data Arbitrary data to be passed through to the callback
    function ponderCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
}
