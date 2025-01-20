// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract PonderFeeTest is Test {
    PonderFactory factory;
    PonderRouter router;
    PonderPair pair;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    WETH9 weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address feeCollector = makeAddr("feeCollector");

    uint256 constant INITIAL_LIQUIDITY = 100_000e18;
    uint256 constant SWAP_AMOUNT = 1_000e18;
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    event Transfer(address indexed from, address indexed to, uint256 value);

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

        // Enable fees
        vm.prank(address(this));
        factory.setFeeTo(feeCollector);

        // Setup initial liquidity
        vm.startPrank(alice);
        tokenA.mint(alice, INITIAL_LIQUIDITY);
        tokenB.mint(alice, INITIAL_LIQUIDITY);
        tokenA.approve(address(router), INITIAL_LIQUIDITY);
        tokenB.approve(address(router), INITIAL_LIQUIDITY);
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
    }

    function testBasicFeeCollection() public {
        // Record initial K
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 initialK = uint256(reserve0) * uint256(reserve1);

        // Record initial fee collector balance
        uint256 initialTokenABalance = tokenA.balanceOf(feeCollector);

        // Do swaps to generate fees
        vm.startPrank(bob);
        tokenA.mint(bob, SWAP_AMOUNT);
        tokenA.approve(address(router), SWAP_AMOUNT);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            0,
            path,
            bob,
            block.timestamp
        );

        // Need to skim to collect protocol fees
        pair.skim(feeCollector);
        vm.stopPrank();

        // Check that fee collector received protocol fees from swap (0.05%)
        uint256 feeAmount = tokenA.balanceOf(feeCollector) - initialTokenABalance;
        assertGt(feeAmount, 0, "No swap fees collected");
        assertEq(feeAmount, (SWAP_AMOUNT * 5) / 10000, "Incorrect fee amount"); // 0.05% fee

        // Add more liquidity
        vm.startPrank(alice);
        tokenA.mint(alice, INITIAL_LIQUIDITY);
        tokenB.mint(alice, INITIAL_LIQUIDITY);
        tokenA.approve(address(router), INITIAL_LIQUIDITY);
        tokenB.approve(address(router), INITIAL_LIQUIDITY);

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

        // Verify K increased
        (reserve0, reserve1,) = pair.getReserves();
        uint256 finalK = uint256(reserve0) * uint256(reserve1);
        assertGt(finalK, initialK, "K should increase");
    }

    function testKLastTracking() public {
        // Initial state
        (uint112 initialReserve0, uint112 initialReserve1,) = pair.getReserves();
        uint256 initialK = uint256(initialReserve0) * uint256(initialReserve1);

        // Get correct token ordering from pair
        address token0 = pair.token0();
        address token1 = pair.token1();

        // Determine input token and amount
        uint256 swapAmount = 1e21;
        ERC20Mint inputToken;
        ERC20Mint outputToken;
        if (token0 == address(tokenA)) {
            inputToken = tokenA;
            outputToken = tokenB;
        } else {
            inputToken = tokenB;
            outputToken = tokenA;
        }

        // Perform swap
        vm.startPrank(bob);
        inputToken.mint(bob, swapAmount);
        inputToken.approve(address(pair), swapAmount);

        // Calculate amounts for swap
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountOut = (swapAmount * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + swapAmount * 997);

        // Do the swap directly through pair
        inputToken.transfer(address(pair), swapAmount);
        pair.swap(0, amountOut, bob, "");
        vm.stopPrank();

        // Check reserves after swap
        (uint112 newReserve0, uint112 newReserve1,) = pair.getReserves();
        uint256 newK = uint256(newReserve0) * uint256(newReserve1);

        assertGt(newK, initialK, "K should increase after swap");
    }

    function testFeeToggles() public {
        // Initial state - fees enabled
        assertTrue(factory.feeTo() == feeCollector);

        // First mint tokens to alice for initial liquidity
        vm.startPrank(alice);
        tokenA.mint(alice, INITIAL_LIQUIDITY);
        tokenB.mint(alice, INITIAL_LIQUIDITY);

        // Add initial liquidity
        tokenA.approve(address(pair), INITIAL_LIQUIDITY);
        tokenB.approve(address(pair), INITIAL_LIQUIDITY);
        tokenA.transfer(address(pair), INITIAL_LIQUIDITY);
        tokenB.transfer(address(pair), INITIAL_LIQUIDITY);
        pair.mint(alice);
        vm.stopPrank();

        // Record initial feeCollector LP token balance
        uint256 initialFeeCollectorLPBalance = pair.balanceOf(feeCollector);

        // Do trades to generate fees - fees will accumulate via k-value
        vm.startPrank(bob);
        tokenA.mint(bob, SWAP_AMOUNT);
        tokenA.approve(address(pair), SWAP_AMOUNT);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountOut = (SWAP_AMOUNT * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + SWAP_AMOUNT * 997);

        // Perform swap
        tokenA.transfer(address(pair), SWAP_AMOUNT);
        pair.swap(0, amountOut, bob, "");
        vm.stopPrank();

        // Add more liquidity - this should mint fee to feeCollector
        vm.startPrank(alice);
        uint256 liquidityAmount = INITIAL_LIQUIDITY / 10;
        tokenA.mint(alice, liquidityAmount);
        tokenB.mint(alice, liquidityAmount);
        tokenA.approve(address(pair), liquidityAmount);
        tokenB.approve(address(pair), liquidityAmount);
        tokenA.transfer(address(pair), liquidityAmount);
        tokenB.transfer(address(pair), liquidityAmount);
        pair.mint(alice);
        vm.stopPrank();

        // Check that feeCollector received LP tokens
        uint256 feeCollectorLPBalance = pair.balanceOf(feeCollector);
        assertGt(
            feeCollectorLPBalance - initialFeeCollectorLPBalance,
            0,
            "Should have collected LP token fees"
        );

        // Disable fees
        vm.prank(address(this));
        factory.setFeeTo(address(1));

        // Record LP balance before next round
        uint256 balanceBeforeSecondRound = pair.balanceOf(feeCollector);

        // Do another round of trades and liquidity
        vm.startPrank(bob);
        tokenA.mint(bob, SWAP_AMOUNT);
        tokenA.approve(address(pair), SWAP_AMOUNT);

        (reserve0, reserve1,) = pair.getReserves();
        amountOut = (SWAP_AMOUNT * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + SWAP_AMOUNT * 997);

        tokenA.transfer(address(pair), SWAP_AMOUNT);
        pair.swap(0, amountOut, bob, "");
        vm.stopPrank();

        // Add more liquidity
        vm.startPrank(alice);
        tokenA.mint(alice, liquidityAmount);
        tokenB.mint(alice, liquidityAmount);
        tokenA.approve(address(pair), liquidityAmount);
        tokenB.approve(address(pair), liquidityAmount);
        tokenA.transfer(address(pair), liquidityAmount);
        tokenB.transfer(address(pair), liquidityAmount);
        pair.mint(alice);
        vm.stopPrank();

        // Verify no new LP tokens were minted to feeCollector
        assertEq(
            pair.balanceOf(feeCollector),
            balanceBeforeSecondRound,
            "Should not collect LP fees when disabled"
        );
    }

    function testMultipleSwapFeeAccumulation() public {
        // Setup initial liquidity
        vm.startPrank(alice);
        tokenA.mint(alice, INITIAL_LIQUIDITY * 10);
        tokenB.mint(alice, INITIAL_LIQUIDITY * 10);
        tokenA.approve(address(router), INITIAL_LIQUIDITY * 10);
        tokenB.approve(address(router), INITIAL_LIQUIDITY * 10);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            INITIAL_LIQUIDITY * 5,
            INITIAL_LIQUIDITY * 5,
            0,
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();

        // Setup trader (bob)
        vm.startPrank(bob);
        uint256 swapAmount = INITIAL_LIQUIDITY / 100; // 1% of liquidity
        tokenA.mint(bob, swapAmount);
        tokenA.approve(address(router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Track feeCollector balance (not bob)
        // Track feeCollector balance
        uint256 feeCollectorBalanceBefore = tokenA.balanceOf(feeCollector);

        // Execute swap
        router.swapExactTokensForTokens(
            swapAmount,
            0,
            path,
            bob,
            block.timestamp
        );

        // Need to skim to collect protocol fees
        pair.skim(feeCollector);

        // Verify fees collected (0.05% protocol fee)
        uint256 expectedFee = (swapAmount * 5) / 10000;
        uint256 actualFee = tokenA.balanceOf(feeCollector) - feeCollectorBalanceBefore;
        assertEq(actualFee, expectedFee, "Incorrect fee amount collected");
        vm.stopPrank();
    }

}
