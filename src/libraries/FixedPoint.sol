// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Fixed Point Math Library
/// @notice A library for handling fixed-point arithmetic
library FixedPoint {
    // 2^112
    uint8 internal constant RESOLUTION = 112;
    uint256 internal constant Q112 = 0x10000000000000000000000000000;
    uint256 internal constant Q224 = 0x100000000000000000000000000000000000000000000000000000000;
    uint256 internal constant LOWER_MASK = 0xffffffffffffffffffffffffffff;

    struct uq112x112 {
        uint224 _x;
    }

    struct uq144x112 {
        uint256 _x;
    }

    /// @notice Encodes a uint112 as a UQ112x112
    /// @param y The number to encode
    /// @return A UQ112x112 representing y
    function encode(uint112 y) internal pure returns (uq112x112 memory) {
        return uq112x112(uint224(uint256(y) * Q112));
    }

    /// @notice Multiplies two UQ112x112 numbers, returning a UQ224x112
    /// @param self The first UQ112x112
    /// @param y The second UQ112x112
    /// @return The product as a UQ224x112
    function mul(uq112x112 memory self, uint256 y) internal pure returns (uq144x112 memory) {
        uint256 z = 0;
        require(y == 0 || (z = self._x * y) / y == self._x, "FixedPoint: MUL_OVERFLOW");
        return uq144x112(z);
    }

    /// @notice Divides a UQ112x112 by a uint112, returning a UQ112x112
    /// @param self The UQ112x112
    /// @param y The uint112 to divide by
    /// @return The quotient as a UQ112x112
    function div(uq112x112 memory self, uint112 y) internal pure returns (uq112x112 memory) {
        require(y != 0, "FixedPoint: DIV_BY_ZERO");
        return uq112x112(uint224(uint256(self._x / y)));
    }

    /// @notice Decodes a UQ112x112 into a uint112 by truncating
    /// @param self The UQ112x112 to decode
    /// @return The decoded uint112
    function decode(uq112x112 memory self) internal pure returns (uint112) {
        return uint112(self._x >> RESOLUTION);
    }

    /// @notice Creates a UQ112x112 from a numerator and denominator
    /// @param numerator The numerator of the fraction
    /// @param denominator The denominator of the fraction
    /// @return The UQ112x112 representation of the fraction
    function fraction(uint112 numerator, uint112 denominator) internal pure returns (uq112x112 memory) {
        require(denominator > 0, "FixedPoint: DIV_BY_ZERO");
        return uq112x112((uint224(uint256(numerator)) << RESOLUTION) / denominator);
    }
}
