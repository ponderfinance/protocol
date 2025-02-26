// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title UQ112x112
/// @author taayyohh
/// @notice Library for handling fixed-point numbers with 112 bits
// for the integer part and 112 bits for the fractional part
/// @dev Used for price accumulation in the Ponder AMM
library UQ112x112 {
    /// @notice The value used as the denominator when converting to fixed-point format
    /// @dev Represents 2^112, used for scaling operations
    uint224 internal constant Q112 = 2**112;

    /// @notice Encodes a uint112 value as a UQ112x112 fixed-point number
    /// @dev Multiplies the input by 2^112 to create a fixed-point representation
    /// @param y The uint112 value to encode
    /// @return z The encoded UQ112x112 fixed-point number
    function encode(uint112 y) internal pure returns (uint224 z) {
        z = uint224(y) * Q112; // Never overflows
    }

    /// @notice Divides a UQ112x112 fixed-point number by a uint112
    /// @dev Division operation for fixed-point arithmetic
    /// @param x The UQ112x112 dividend
    /// @param y The uint112 divisor
    /// @return z The UQ112x112 quotient
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }
}
