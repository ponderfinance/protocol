// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../../src/libraries/Math.sol";

contract MathTest is Test {
    function testSqrt() public {
        assertEq(Math.sqrt(0), 0);
        assertEq(Math.sqrt(1), 1);
        assertEq(Math.sqrt(2), 1);
        assertEq(Math.sqrt(3), 1);
        assertEq(Math.sqrt(4), 2);
        assertEq(Math.sqrt(144), 12);
        assertEq(Math.sqrt(999999), 999);
    }

    function testMin() public {
        assertEq(Math.min(5, 10), 5);
        assertEq(Math.min(10, 5), 5);
        assertEq(Math.min(5, 5), 5);
    }

    function testMax() public {
        assertEq(Math.max(5, 10), 10);
        assertEq(Math.max(10, 5), 10);
        assertEq(Math.max(5, 5), 5);
    }

    function testAverage() public {
        assertEq(Math.average(5, 10), 7);
        assertEq(Math.average(10, 5), 7);
        assertEq(Math.average(5, 5), 5);
    }

    function testFuzz_Sqrt(uint256 x) public {
        // Bound input to prevent overflow
        x = bound(x, 0, type(uint128).max);

        uint256 z = Math.sqrt(x);

        // z should be the largest number such that z*z <= x
        if (x > 0) {
            assertGe(z * z, 0);
            assertLe(z * z, x);
            assertGt((z + 1) * (z + 1), x);
        } else {
            assertEq(z, 0);
        }
    }
}
