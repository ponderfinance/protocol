// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/libraries/UQ112x112.sol";

contract UQ112x112Test is Test {
    using UQ112x112 for uint224;

    uint224 constant Q112 = 2**112;

    function testEncode() public {
        // Test encoding basic values
        assertEq(UQ112x112.encode(1), Q112, "Encoding 1 failed");
        assertEq(UQ112x112.encode(2), 2 * Q112, "Encoding 2 failed");
        assertEq(UQ112x112.encode(0), 0, "Encoding 0 failed");

        // Test max value
        uint112 maxValue = type(uint112).max;
        assertEq(UQ112x112.encode(maxValue), uint224(maxValue) * Q112, "Encoding max value failed");
    }

    function testUqdiv() public {
        // Test basic division cases
        assertEq(UQ112x112.encode(1).uqdiv(1), Q112, "1/1 failed");
        assertEq(UQ112x112.encode(2).uqdiv(2), Q112, "2/2 failed");
        assertEq(UQ112x112.encode(100).uqdiv(10), 10 * Q112, "100/10 failed");

        // Test division by 1
        uint112 randomValue = 123;
        assertEq(UQ112x112.encode(randomValue).uqdiv(1), uint224(randomValue) * Q112, "Division by 1 failed");

        // Test dividing 0
        assertEq(UQ112x112.encode(0).uqdiv(1), 0, "0/1 failed");
    }

    function testDivisionByLargeValues() public {
        // Test division with large denominators
        uint112 largeNum = type(uint112).max;
        uint224 encoded = UQ112x112.encode(largeNum);
        uint224 result = encoded.uqdiv(largeNum);
        assertEq(result, Q112, "Large number division failed");
    }

    function testPrecisionLoss() public {
        // Test division that requires rounding
        uint112 numerator = 10;
        uint112 denominator = 3;
        uint224 result = UQ112x112.encode(numerator).uqdiv(denominator);

        // Calculate expected result (10/3 ≈ 3.333... * Q112)
        uint224 expected = (uint224(numerator) * Q112) / denominator;
        assertEq(result, expected, "Precision loss test failed");

        // Verify the result is approximately 3.333...
        uint256 decimalPart = (result * 1000) / Q112;
        assertApproxEqAbs(decimalPart, 3333, 1, "Decimal precision test failed");
    }

    function testBoundaryValues() public {
        // Test with smallest possible values
        assertEq(UQ112x112.encode(1).uqdiv(type(uint112).max), 1, "Min value division failed");

        // Test with largest safe values
        uint112 maxSafe = type(uint112).max;
        uint224 encoded = UQ112x112.encode(maxSafe);
        uint224 result = encoded.uqdiv(1);
        assertEq(result, uint224(maxSafe) * Q112, "Max safe value test failed");
    }

    function testFuzz_EncodeDecode(uint112 value) public {
        uint224 encoded = UQ112x112.encode(value);
        uint224 decoded = encoded / Q112;
        assertEq(uint112(decoded), value, "Encode/decode roundtrip failed");
    }

    function testFuzz_Division(uint112 numerator, uint112 denominator) public {
        vm.assume(denominator > 0);

        uint224 encoded = UQ112x112.encode(numerator);
        uint224 result = encoded.uqdiv(denominator);

        // Result should match integer division scaled by Q112
        uint224 expected = (uint224(numerator) * Q112) / denominator;
        assertEq(result, expected, "Fuzzy division test failed");
    }

    function testFuzz_Multiplication(uint16 a, uint16 b) public {
        // Using uint16 instead of uint112 for more manageable test bounds
        uint224 encoded = UQ112x112.encode(uint112(a));
        uint224 result = encoded * uint112(b);
        uint224 expected = uint224(a) * uint224(b) * Q112;
        assertEq(result, expected, "Fuzzy multiplication test failed");
    }

    function testScalingOperations() public {
        // Test that Q112 scaling works correctly in series of operations
        uint112 initialValue = 1000;
        uint224 encoded = UQ112x112.encode(initialValue);

        // Perform a series of operations that should maintain Q112 scaling
        uint224 result = encoded;
        result = result.uqdiv(2);  // Scale down
        result = result * 2;       // Scale up

        // Result should equal original value
        assertEq(result, encoded, "Scaling operations failed to maintain Q112");
    }

    function testSmallValueOperations() public {
        // Test operations with small values to verify precision
        uint112 smallValue = 1;
        uint224 encoded = UQ112x112.encode(smallValue);

        // Test division
        uint224 result = encoded.uqdiv(10);  // 0.1 in Q112
        uint224 expected = Q112 / 10;
        assertEq(result, expected, "Small value division incorrect");

        // Test multiplication with small values
        result = encoded * 1;
        assertEq(result, encoded, "Small value multiplication incorrect");
    }

    function testRelativePrecision() public {
        // Test precision with different orders of magnitude
        uint112[3] memory values = [uint112(1), uint112(1000), uint112(1000000)];
        uint112[3] memory divisors = [uint112(3), uint112(7), uint112(11)];

        for(uint i = 0; i < values.length; i++) {
            uint224 result = UQ112x112.encode(values[i]).uqdiv(divisors[i]);
            uint224 expected = (uint224(values[i]) * Q112) / divisors[i];

            // Check relative error is small
            uint256 error = result > expected ? result - expected : expected - result;
            assertTrue(error <= 1, "Precision test failed");
        }
    }
}
