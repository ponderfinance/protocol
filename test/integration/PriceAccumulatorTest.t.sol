// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../mocks/ERC20Mint.sol";

contract PriceAccumulatorTest is Test {
    using console for *;

    PonderFactory factory;
    PonderPair pair;
    ERC20Mint token0;
    ERC20Mint token1;

    address alice = makeAddr("alice");

    function setUp() public {
        token0 = new ERC20Mint("Token A", "TKNA");
        token1 = new ERC20Mint("Token B", "TKNB");

        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        factory = new PonderFactory(address(this), address(1), address(2));
        address pairAddress = factory.createPair(address(token0), address(token1));
        pair = PonderPair(pairAddress);

        vm.warp(1);
    }

    function testAccumulationPrecision() public {
        vm.startPrank(alice);

        // Setup 5:1 ratio of reserves
        uint112 reserve0 = 1e18;
        uint112 reserve1 = 5e18;

        // Mint and add liquidity
        token0.mint(alice, reserve0);
        token1.mint(alice, reserve1);
        token0.transfer(address(pair), reserve0);
        token1.transfer(address(pair), reserve1);
        pair.mint(alice);

        vm.stopPrank();

        // Initial sync
        pair.sync();

        // Get first observation
        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 price0Start = pair.price0CumulativeLast();
        uint256 price1Start = pair.price1CumulativeLast();

        // Move forward small amount of time
        vm.warp(block.timestamp + 1);
        pair.sync();

        // Get second observation
        uint256 price0End = pair.price0CumulativeLast();
        uint256 price1End = pair.price1CumulativeLast();

        // Calculate price changes over the period
        uint256 price0Change = price0End - price0Start;
        uint256 price1Change = price1End - price1Start;

        // Log for debugging
        console.log("Reserve0:", r0);
        console.log("Reserve1:", r1);
        console.log("Price0 change:", price0Change);
        console.log("Price1 change:", price1Change);

        // In Uniswap V2/Ponder, price0 = reserve1/reserve0 and price1 = reserve0/reserve1
        // The price accumulator uses Q112 fixed point arithmetic, so we need to account for that
        uint256 timeElapsed = 1; // we moved forward 1 second
        uint256 priceAverage = price0Change / timeElapsed;
        uint256 priceRatio = (priceAverage * 1e18) / (1 << 112);  // Adjust for Q112 fixed point

        uint256 expectedRatio = (uint256(r1) * 1e18) / r0;

        console.log("Price ratio:", priceRatio);
        console.log("Expected ratio:", expectedRatio);

        assertApproxEqRel(
            priceRatio,
            expectedRatio,
            0.01e18 // 1% tolerance
        );
    }

    function testBasicAccumulation() public {
        // Setup simple equal liquidity
        uint256 amount = 1e18;

        vm.startPrank(alice);
        token0.mint(alice, amount);
        token1.mint(alice, amount);

        token0.transfer(address(pair), amount);
        token1.transfer(address(pair), amount);
        pair.mint(alice);
        vm.stopPrank();

        pair.sync();
        vm.warp(block.timestamp + 1);

        uint256 price0Start = pair.price0CumulativeLast();
        uint256 price1Start = pair.price1CumulativeLast();

        vm.warp(block.timestamp + 1);
        pair.sync();

        uint256 price0End = pair.price0CumulativeLast();
        uint256 price1End = pair.price1CumulativeLast();

        assertGt(price0End, price0Start, "Price0 should accumulate");
        assertGt(price1End, price1Start, "Price1 should accumulate");
    }

    function testPriceAccumulationWithoutTrades() public {
        uint256 amount = 1e18;

        vm.startPrank(alice);
        token0.mint(alice, amount);
        token1.mint(alice, amount);

        token0.transfer(address(pair), amount);
        token1.transfer(address(pair), amount);
        pair.mint(alice);
        vm.stopPrank();

        uint256 lastPrice0 = pair.price0CumulativeLast();
        uint256 lastPrice1 = pair.price1CumulativeLast();

        for (uint i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 1);
            pair.sync();

            uint256 currentPrice0 = pair.price0CumulativeLast();
            uint256 currentPrice1 = pair.price1CumulativeLast();

            uint256 price0Change = currentPrice0 - lastPrice0;
            uint256 price1Change = currentPrice1 - lastPrice1;

            assertGt(price0Change, 0, "Price0 should accumulate each period");
            assertGt(price1Change, 0, "Price1 should accumulate each period");
            assertApproxEqRel(price0Change, price1Change, 0.01e18);

            lastPrice0 = currentPrice0;
            lastPrice1 = currentPrice1;
        }
    }

    function testAccumulationOverflow() public {
        uint256 amount = 1e18;

        vm.startPrank(alice);
        token0.mint(alice, amount);
        token1.mint(alice, amount);

        token0.transfer(address(pair), amount);
        token1.transfer(address(pair), amount);
        pair.mint(alice);
        vm.stopPrank();

        pair.sync();

        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();

        vm.warp(block.timestamp + 1);
        pair.sync();

        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();

        assertEq(reserve0After, reserve0Before, "Reserves should not change");
        assertEq(reserve1After, reserve1Before, "Reserves should not change");
        assertEq(uint256(reserve0After), amount, "Reserve amount mismatch");
    }
}
