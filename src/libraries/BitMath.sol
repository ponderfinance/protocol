// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title BitMath Library
/// @notice Library for computing most and least significant bits of a uint256
library BitMath {
    /// @notice Custom error for when input value is zero
    error ZeroValue();

    /// @notice Returns the index of the most significant bit of the number
    /// @dev Returns 0 if number is 0
    /// @param x The value for which to find the most significant bit
    /// @return r The index of the most significant bit
    function mostSignificantBit(uint256 x) internal pure returns (uint8 r) {
        if (x == 0) revert ZeroValue();

        // Check if bits 128 and higher are set
        if (x >= 0x1_00000000_00000000_00000000_00000000) {
            x >>= 128;
            r += 128;
        }
        // Check if bits 64-127 are set
        if (x >= 0x1_00000000_00000000) {
            x >>= 64;
            r += 64;
        }
        // Check if bits 32-63 are set
        if (x >= 0x1_00000000) {
            x >>= 32;
            r += 32;
        }
        if (x >= 0x10000) {
            x >>= 16;
            r += 16;
        }
        if (x >= 0x100) {
            x >>= 8;
            r += 8;
        }
        if (x >= 0x10) {
            x >>= 4;
            r += 4;
        }
        if (x >= 0x4) {
            x >>= 2;
            r += 2;
        }
        if (x >= 0x2) r += 1;
    }

    /// @notice Returns the index of the least significant bit of the number
    /// @dev Returns 0 if number is 0
    /// @param x The value for which to find the least significant bit
    /// @return r The index of the least significant bit
    function leastSignificantBit(uint256 x) internal pure returns (uint8 r) {
        if (x == 0) revert ZeroValue();

        r = 255;
        if (x & type(uint128).max > 0) {
            r -= 128;
        } else {
            x >>= 128;
        }
        if (x & type(uint64).max > 0) {
            r -= 64;
        } else {
            x >>= 64;
        }
        if (x & type(uint32).max > 0) {
            r -= 32;
        } else {
            x >>= 32;
        }
        if (x & type(uint16).max > 0) {
            r -= 16;
        } else {
            x >>= 16;
        }
        if (x & type(uint8).max > 0) {
            r -= 8;
        } else {
            x >>= 8;
        }
        if (x & 0xf > 0) {
            r -= 4;
        } else {
            x >>= 4;
        }
        if (x & 0x3 > 0) {
            r -= 2;
        } else {
            x >>= 2;
        }
        if (x & 0x1 > 0) r -= 1;
    }
}
