// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/libraries/FixedPoint.sol";

contract FixedPointTest is Test {
    function testEncode() public {
        FixedPoint.UQ112x112 memory encoded = FixedPoint.encode(1);
        assertEq(encoded._x, 0x10000000000000000000000000000);
    }

    function testMul() public {
        FixedPoint.UQ112x112 memory encoded = FixedPoint.encode(2);
        FixedPoint.UQ144x112 memory result = FixedPoint.mul(encoded, 2);
        assertEq(result._x, 0x40000000000000000000000000000);
    }

    function testDiv() public {
        FixedPoint.UQ112x112 memory encoded = FixedPoint.encode(2);
        FixedPoint.UQ112x112 memory result = FixedPoint.div(encoded, 2);
        assertEq(result._x, 0x10000000000000000000000000000);
    }

    function testDecode() public {
        FixedPoint.UQ112x112 memory encoded = FixedPoint.encode(1);
        uint112 decoded = FixedPoint.decode(encoded);
        assertEq(decoded, 1);
    }

    function testFraction() public {
        FixedPoint.UQ112x112 memory result = FixedPoint.fraction(1, 2);
        assertEq(result._x, 0x8000000000000000000000000000);
    }

    function testFuzz_EncodeAndDecode(uint112 x) public {
        FixedPoint.UQ112x112 memory encoded = FixedPoint.encode(x);
        uint112 decoded = FixedPoint.decode(encoded);
        assertEq(decoded, x);
    }

    function testRevert_DivByZero() public {
        FixedPoint.UQ112x112 memory encoded = FixedPoint.encode(1);
        vm.expectRevert(abi.encodeWithSignature("DivisionByZero()"));
        FixedPoint.div(encoded, 0);
    }
}
