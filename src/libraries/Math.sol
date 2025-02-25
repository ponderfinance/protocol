// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Math Library
/// @notice A library for performing various math operations safely
library Math {
    /// @notice Calculates the square root of a number using the Babylonian method
    /// @dev Optimized version of the square root calculation
    /// @param y The number to calculate the square root of
    /// @return z The square root of the input
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }

        return z;
    }

    /// @notice Returns the minimum of two numbers
    /// @param x The first number
    /// @param y The second number
    /// @return The smaller of the two inputs
    function min(uint256 x, uint256 y) internal pure returns (uint256) {
        return x < y ? x : y;
    }

    /// @notice Returns the maximum of two numbers
    /// @param x The first number
    /// @param y The second number
    /// @return The larger of the two inputs
    function max(uint256 x, uint256 y) internal pure returns (uint256) {
        return x > y ? x : y;
    }

    /// @notice Returns the average of two numbers
    /// @dev The result is rounded towards zero
    /// @param x The first number
    /// @param y The second number
    /// @return The arithmetic average, rounded towards zero
    function average(uint256 x, uint256 y) internal pure returns (uint256) {
        // (x + y) / 2 can overflow
        return (x & y) + (x ^ y) / 2;
    }
}
