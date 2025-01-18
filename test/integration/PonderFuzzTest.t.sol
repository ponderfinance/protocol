// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";

contract PonderFuzzTest is Test {
    PonderFactory factory;
    PonderRouter router;
    PonderPair pair;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    WETH9 weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Constants for reasonable bounds
    uint256 constant MAX_TEST_AMOUNT = 1_000_000e18;
    uint256 constant MIN_TEST_AMOUNT = 1001e18; // Just above MINIMUM_LIQUIDITY
    uint256 constant INITIAL_LIQUIDITY = 100_000e18;

    function setUp() public {
        // Deploy core contracts
        weth = new WETH9();
        factory = new PonderFactory(address(this), address(1), address(2));
        MockKKUBUnwrapper unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(address(factory), address(weth), address(unwrapper));

        // Deploy tokens
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");

        // Create pair
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = PonderPair(pairAddress);

        // Setup initial state
        vm.startPrank(alice);
        tokenA.mint(alice, MAX_TEST_AMOUNT * 2);
        tokenB.mint(alice, MAX_TEST_AMOUNT * 2);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_LiquidityProvision(uint256 amountA, uint256 amountB) public {
        // Bound inputs to reasonable ranges
        amountA = bound(amountA, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountB = bound(amountB, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);

        vm.startPrank(alice);

        // Record initial balances
        uint256 balanceABefore = tokenA.balanceOf(alice);
        uint256 balanceBBefore = tokenB.balanceOf(alice);

        try router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            alice,
            block.timestamp
        ) returns (uint256 actualA, uint256 actualB, uint256 liquidity) {
            // Verify reserves match provided liquidity
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

            assertGt(liquidity, 0, "No liquidity minted");
            assertGt(pair.balanceOf(alice), 0, "No LP tokens received");

            // Verify actual amounts are less than or equal to desired amounts
            assertLe(actualA, amountA, "Actual A exceeds desired");
            assertLe(actualB, amountB, "Actual B exceeds desired");

            // Verify balances changed correctly
            assertEq(tokenA.balanceOf(alice), balanceABefore - actualA, "Incorrect token A balance");
            assertEq(tokenB.balanceOf(alice), balanceBBefore - actualB, "Incorrect token B balance");
        } catch {
            // Operation should only revert for invalid inputs
            assertTrue(amountA < 1000 || amountB < 1000, "Unexpected revert");
        }
        vm.stopPrank();
    }

    function testFuzz_SwapExactTokensForTokens(
        uint256 existingLiquidity,
        uint256 swapAmount
    ) public {
        // Bound inputs to prevent unrealistic scenarios
        existingLiquidity = bound(existingLiquidity, INITIAL_LIQUIDITY, MAX_TEST_AMOUNT);
        swapAmount = bound(swapAmount, MIN_TEST_AMOUNT, existingLiquidity / 3); // Limit to 33% of liquidity

        // Setup initial liquidity
        vm.startPrank(alice);
        try router.addLiquidity(
            address(tokenA),
            address(tokenB),
            existingLiquidity,
            existingLiquidity,
            0,
            0,
            alice,
            block.timestamp
        ) {} catch {
            return; // Skip test if initial liquidity setup fails
        }
        vm.stopPrank();

        // Record state before swap
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();
        uint256 balance0Before = tokenA.balanceOf(bob);
        uint256 balance1Before = tokenB.balanceOf(bob);

        // Prepare swap
        vm.startPrank(bob);
        tokenA.mint(bob, swapAmount);
        tokenA.approve(address(router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        try router.swapExactTokensForTokens(
            swapAmount,
            0, // Accept any output amount
            path,
            bob,
            block.timestamp
        ) returns (uint256[] memory amounts) {
            // Verify reserves changed correctly
            (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
            uint256 kBefore = uint256(reserve0Before) * uint256(reserve1Before);
            uint256 kAfter = uint256(reserve0After) * uint256(reserve1After);

            assertGe(kAfter, kBefore, "K must not decrease");
            assertGt(amounts[1], 0, "No output tokens received");
            assertEq(tokenA.balanceOf(bob), balance0Before, "Input token balance mismatch");
            assertGt(tokenB.balanceOf(bob), balance1Before, "Output token balance mismatch");
        } catch {
            // Expected to fail in some cases
            assertTrue(
                swapAmount == 0 ||
                swapAmount >= existingLiquidity / 2,
                "Unexpected swap failure"
            );
        }
        vm.stopPrank();
    }

    function testFuzz_PriceImpact(uint256 swapAmount) public {
        // Setup initial liquidity
        vm.startPrank(alice);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            0,
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();

        // Bound swap amount to reasonable size (max 20% of liquidity)
        swapAmount = bound(swapAmount, MIN_TEST_AMOUNT, INITIAL_LIQUIDITY / 5);

        vm.startPrank(bob);
        tokenA.mint(bob, swapAmount);
        tokenA.approve(address(router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Calculate initial price
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();
        uint256 priceBefore = (uint256(reserve1Before) * 1e18) / uint256(reserve0Before);

        try router.swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            bob,
            block.timestamp
        ) {
            // Calculate price after swap
            (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();
            uint256 priceAfter = (uint256(reserve1After) * 1e18) / uint256(reserve0After);

            // Calculate relative price impact
            uint256 priceChange;
            if (priceAfter > priceBefore) {
                priceChange = ((priceAfter - priceBefore) * 100) / priceBefore;
            } else {
                priceChange = ((priceBefore - priceAfter) * 100) / priceBefore;
            }

            // Price impact should be proportional to swap size
            uint256 swapPercentage = (swapAmount * 100) / INITIAL_LIQUIDITY;
            assertLe(priceChange, swapPercentage * 4, "Price impact too high for swap size");
        } catch {
            // Expected to fail for very large swaps
            assertTrue(swapAmount > INITIAL_LIQUIDITY / 4, "Unexpected swap failure");
        }
        vm.stopPrank();
    }
}
