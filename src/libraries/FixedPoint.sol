// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Fixed Point Math Library
/// @author taayyohh
/// @notice A library for handling fixed-point arithmetic
library FixedPoint {
    // Custom errors
    error MultiplicationOverflow();
    error DivisionByZero();

    // 2^112
    // RESOLUTION represents the number of bits used for the fixed-point representation
    uint8 internal constant RESOLUTION = 112;

    // Q112 represents 2^112, used as the fixed-point multiplier
    uint256 internal constant Q112 = 2**112;

    // Q224 represents 2^224, used for handling multiplication results
    uint256 internal constant Q224 = 2**224;

    // Mask for the lower 112 bits
    uint256 internal constant LOWER_MASK = (1 << 112) - 1;

    struct UQ112x112 {
        uint224 _x;
    }

    struct UQ144x112 {
        uint256 _x;
    }

    /// @notice Encodes a uint112 as a UQ112x112
    /// @param y The number to encode
    /// @return A UQ112x112 representing y
    function encode(uint112 y) internal pure returns (UQ112x112 memory) {
        return UQ112x112(uint224(uint256(y) * Q112));
    }

    /// @notice Multiplies two UQ112x112 numbers, returning a UQ224x112
    /// @param self The first UQ112x112
    /// @param y The second UQ112x112
    /// @return The product as a UQ224x112
    function mul(UQ112x112 memory self, uint256 y) internal pure returns (UQ144x112 memory) {
        uint256 z = 0;
        if (y != 0 && (z = self._x * y) / y != self._x) {
            revert MultiplicationOverflow();
        }
        return UQ144x112(z);
    }

    /// @notice Divides a UQ112x112 by a uint112, returning a UQ112x112
    /// @param self The UQ112x112
    /// @param y The uint112 to divide by
    /// @return The quotient as a UQ112x112
    function div(UQ112x112 memory self, uint112 y) internal pure returns (UQ112x112 memory) {
        if (y == 0) revert DivisionByZero();
        return UQ112x112(uint224(uint256(self._x / y)));
    }

    /// @notice Decodes a UQ112x112 into a uint112 by truncating
    /// @param self The UQ112x112 to decode
    /// @return The decoded uint112
    function decode(UQ112x112 memory self) internal pure returns (uint112) {
        return uint112(self._x >> RESOLUTION);
    }

    /// @notice Creates a UQ112x112 from a numerator and denominator
    /// @param numerator The numerator of the fraction
    /// @param denominator The denominator of the fraction
    /// @return The UQ112x112 representation of the fraction
    function fraction(uint112 numerator, uint112 denominator) internal pure returns (UQ112x112 memory) {
        if (denominator == 0) revert DivisionByZero();
        return UQ112x112((uint224(uint256(numerator)) << RESOLUTION) / denominator);
    }
}
