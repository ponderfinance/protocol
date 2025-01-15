// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/libraries/PonderOracleLibrary.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPair.sol";
import "../mocks/ERC20Mint.sol";

contract PonderOracleLibraryTest is Test {
    using UQ112x112 for uint224;

    PonderFactory factory;
    PonderPair pair;
    ERC20Mint token0;
    ERC20Mint token1;

    address alice = makeAddr("alice");
    uint256 constant INITIAL_LIQUIDITY = 100_000e18;

    function setUp() public {
        // Deploy tokens with deterministic ordering
        token0 = new ERC20Mint("Token A", "TKNA");
        token1 = new ERC20Mint("Token B", "TKNB");

        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Deploy factory and create pair
        factory = new PonderFactory(address(this), address(1), address(2));
        address pairAddress = factory.createPair(address(token0), address(token1));
        pair = PonderPair(pairAddress);

        // Setup initial liquidity
        token0.mint(alice, INITIAL_LIQUIDITY);
        token1.mint(alice, INITIAL_LIQUIDITY);

        vm.startPrank(alice);
        token0.transfer(address(pair), INITIAL_LIQUIDITY);
        token1.transfer(address(pair), INITIAL_LIQUIDITY);
        pair.mint(alice);
        vm.stopPrank();

        // Initial sync and time setup
        vm.warp(block.timestamp + 1);
        pair.sync();
    }

    function testSimplePriceCalculation() public {
        // Get initial observation
        (uint256 price0CumulativeStart, uint256 price1CumulativeStart, uint32 timestampStart) =
                            PonderOracleLibrary.currentCumulativePrices(address(pair));

        // Move time forward
        vm.warp(block.timestamp + 1 hours);

        // Get second observation
        (uint256 price0CumulativeEnd, uint256 price1CumulativeEnd, uint32 timestampEnd) =
                            PonderOracleLibrary.currentCumulativePrices(address(pair));

        // Calculate time elapsed
        uint32 timeElapsed = timestampEnd - timestampStart;
        assertEq(timeElapsed, 3600, "Time elapsed should be 1 hour");

        // Check price accumulation is non-zero
        assertTrue(price0CumulativeEnd > price0CumulativeStart, "Price0 should accumulate");
        assertTrue(price1CumulativeEnd > price1CumulativeStart, "Price1 should accumulate");
    }

    function testPriceManipulationResistance() public {
        // Get initial price
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();

        // Calculate initial spot price
        uint256 initialSpotPrice = uint256(reserve1Before) * 1e18 / uint256(reserve0Before);

        // Record start of observation window
        vm.warp(block.timestamp + 1);
        (uint256 price0CumulativeStart,,) = PonderOracleLibrary.currentCumulativePrices(address(pair));

        // Let some time pass with stable price
        vm.warp(block.timestamp + 30 minutes);

        // Execute large swap to manipulate price
        vm.startPrank(alice);
        uint256 swapAmount = INITIAL_LIQUIDITY * 2;
        token0.mint(alice, swapAmount);
        token0.transfer(address(pair), swapAmount);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 expectedOut = (swapAmount * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + (swapAmount * 997));
        pair.swap(0, expectedOut, alice, "");
        vm.stopPrank();

        // Let a little more time pass
        vm.warp(block.timestamp + 30 minutes);

        // Get end of observation window
        (uint256 price0CumulativeEnd,,) = PonderOracleLibrary.currentCumulativePrices(address(pair));

        // Calculate TWAP over the full period
        uint256 amountIn = 1e18;
        uint256 twapAmountOut = PonderOracleLibrary.computeAmountOut(
            price0CumulativeStart,
            price0CumulativeEnd,
            3600, // 1 hour
            amountIn
        );

        // Calculate current spot price
        (reserve0, reserve1,) = pair.getReserves();
        uint256 spotAmountOut = (amountIn * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + (amountIn * 997));

        // Log values for debugging
        console.log("Initial spot price:", initialSpotPrice);
        console.log("Final spot price amount out:", spotAmountOut);
        console.log("TWAP amount out:", twapAmountOut);

        // TWAP should be closer to initial price than current spot price
        uint256 twapDiff = spotAmountOut > twapAmountOut ?
            spotAmountOut - twapAmountOut :
            twapAmountOut - spotAmountOut;
        uint256 spotDiff = spotAmountOut > initialSpotPrice ?
            spotAmountOut - initialSpotPrice :
            initialSpotPrice - spotAmountOut;

        assertTrue(twapDiff < spotDiff, "TWAP should be less affected by manipulation than spot price");
    }

    function testConsecutivePriceObservations() public {
        // Take initial observation
        (uint256 price0Start,,) = PonderOracleLibrary.currentCumulativePrices(address(pair));

        // Array of observation times
        uint256[] memory times = new uint256[](3);
        times[0] = 1 hours;
        times[1] = 6 hours;
        times[2] = 12 hours;

        uint256 lastPrice = price0Start;

        for(uint i = 0; i < times.length; i++) {
            // Move time forward
            vm.warp(block.timestamp + times[i]);

            // Get new observation
            (uint256 currentPrice,,) = PonderOracleLibrary.currentCumulativePrices(address(pair));

            // Price should always accumulate
            assertGt(currentPrice, lastPrice, "Price should accumulate over time");

            lastPrice = currentPrice;
        }
    }

    function testFailComputeAmountOutZeroElapsed() public {
        (uint256 price0CumulativeStart,,) = PonderOracleLibrary.currentCumulativePrices(address(pair));

        PonderOracleLibrary.computeAmountOut(
            price0CumulativeStart,
            price0CumulativeStart,
            0, // Zero time elapsed
            1e18
        );
    }
}
