// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/libraries/BitMath.sol";

contract BitMathTest is Test {
    function testMostSignificantBitSimple() public {
        assertEq(BitMath.mostSignificantBit(1), 0);
        assertEq(BitMath.mostSignificantBit(2), 1);
        assertEq(BitMath.mostSignificantBit(4), 2);
        assertEq(BitMath.mostSignificantBit(8), 3);
        assertEq(BitMath.mostSignificantBit(16), 4);
        assertEq(BitMath.mostSignificantBit(32), 5);
    }

    function testLeastSignificantBitSimple() public {
        assertEq(BitMath.leastSignificantBit(1), 0);
        assertEq(BitMath.leastSignificantBit(2), 1);
        assertEq(BitMath.leastSignificantBit(4), 2);
        assertEq(BitMath.leastSignificantBit(8), 3);
        assertEq(BitMath.leastSignificantBit(16), 4);
        assertEq(BitMath.leastSignificantBit(32), 5);
    }

    function testMostSignificantBitComplex() public {
        assertEq(BitMath.mostSignificantBit(0xff), 7);
        assertEq(BitMath.mostSignificantBit(0x100), 8);
        assertEq(BitMath.mostSignificantBit(0xffff), 15);
        assertEq(BitMath.mostSignificantBit(0x10000), 16);
    }

    function testLeastSignificantBitComplex() public {
        assertEq(BitMath.leastSignificantBit(0x100), 8);
        assertEq(BitMath.leastSignificantBit(0xFF00), 8);
        assertEq(BitMath.leastSignificantBit(0x10000), 16);
        assertEq(BitMath.leastSignificantBit(0xFF0000), 16);
    }

    function testRevertOnZeroMSB() public {
        vm.expectRevert(abi.encodeWithSelector(BitMath.ZeroValue.selector));
        BitMath.mostSignificantBit(0);
    }

    function testRevertOnZeroLSB() public {
        vm.expectRevert(abi.encodeWithSelector(BitMath.ZeroValue.selector));
        BitMath.leastSignificantBit(0);
    }

    function testFuzz_MostSignificantBit(uint256 value) public {
        if (value == 0) {
            vm.expectRevert(abi.encodeWithSelector(BitMath.ZeroValue.selector));
            BitMath.mostSignificantBit(value);
        } else {
            uint8 result = BitMath.mostSignificantBit(value);

            // Check lower bound
            assertTrue(value >= uint256(1) << result, "Value less than lower bound");

            // Check upper bound, handling the case where result is 255
            if (result < 255) {
                assertTrue(value < uint256(1) << (result + 1), "Value exceeds upper bound");
            } else {
                // For the case where result is 255, we just verify it's a valid use case
                assertTrue(value >= (uint256(1) << 255), "Invalid 255 case");
            }
        }
    }

    function testFuzz_LeastSignificantBit(uint256 value) public {
        if (value == 0) {
            vm.expectRevert(abi.encodeWithSelector(BitMath.ZeroValue.selector));
            BitMath.leastSignificantBit(value);
        } else {
            uint8 result = BitMath.leastSignificantBit(value);
            assertTrue(value & (uint256(1) << result) != 0);
            assertTrue(value & ((uint256(1) << result) - 1) == 0);
        }
    }

    function testEdgeCases() public {
        // Test maximum uint256
        uint256 maxUint = type(uint256).max;
        assertEq(BitMath.mostSignificantBit(maxUint), 255);

        // Test powers of 2
        assertEq(BitMath.mostSignificantBit(uint256(1) << 255), 255);
        assertEq(BitMath.mostSignificantBit(uint256(1) << 254), 254);
        assertEq(BitMath.mostSignificantBit(uint256(1) << 128), 128);

        // Test values just below powers of 2
        assertEq(BitMath.mostSignificantBit((uint256(1) << 255) - 1), 254);
        assertEq(BitMath.mostSignificantBit((uint256(1) << 128) - 1), 127);
        assertEq(BitMath.mostSignificantBit((uint256(1) << 64) - 1), 63);
    }
}
