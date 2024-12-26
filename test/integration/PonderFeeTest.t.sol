// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPair.sol";
import "../../src/periphery/PonderRouter.sol";
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
        vm.stopPrank();

        // Check that fee collector received protocol fees from swap
        uint256 feeAmount = tokenA.balanceOf(feeCollector) - initialTokenABalance;
        assertGt(feeAmount, 0, "No swap fees collected");
        assertEq(feeAmount, (SWAP_AMOUNT * 30) / 10000, "Incorrect fee amount"); // 0.3% fee

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

    function testFeeToggles() public {
        // Initial state - fees enabled
        assertTrue(factory.feeTo() == feeCollector);

        // Record initial fee collector balance
        uint256 initialTokenABalance = tokenA.balanceOf(feeCollector);

        // Do some swaps
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
        vm.stopPrank();

        // Check fees were collected
        uint256 feesCollected = tokenA.balanceOf(feeCollector) - initialTokenABalance;
        assertGt(feesCollected, 0, "Should have collected initial fees");
        assertEq(feesCollected, (SWAP_AMOUNT * 30) / 10000, "Incorrect fee amount"); // 0.3% fee

        // Disable fees
        vm.prank(address(this));
        factory.setFeeTo(address(0));

        // Record balance before next swap
        uint256 balanceBeforeSecondSwap = tokenA.balanceOf(feeCollector);

        // Do more swaps
        vm.startPrank(bob);
        tokenA.mint(bob, SWAP_AMOUNT);
        tokenA.approve(address(router), SWAP_AMOUNT);
        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            0,
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();

        // Verify no new fees were collected
        assertEq(
            tokenA.balanceOf(feeCollector),
            balanceBeforeSecondSwap,
            "Should not collect fees when disabled"
        );
    }

    function testKLastTracking() public {
        // Initial state
        (uint112 initialReserve0, uint112 initialReserve1,) = pair.getReserves();
        uint256 initialK = uint256(initialReserve0) * uint256(initialReserve1);

        // Perform swap
        vm.startPrank(bob);
        tokenA.mint(bob, 1e21);
        tokenA.approve(address(router), 1e21);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        router.swapExactTokensForTokens(1e21, 0, path, bob, block.timestamp);
        vm.stopPrank();

        // Check reserves after swap
        (uint112 newReserve0, uint112 newReserve1,) = pair.getReserves();
        uint256 newK = uint256(newReserve0) * uint256(newReserve1);

        assertGt(newK, initialK, "K should increase after swap");
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
        uint256 feeCollectorBalanceBefore = tokenA.balanceOf(feeCollector);

        // Execute swap
        router.swapExactTokensForTokens(
            swapAmount,
            0,  // Accept any output
            path,
            bob,
            block.timestamp
        );

        // Verify fees collected (0.3% fee)
        uint256 expectedFee = (swapAmount * 30) / 10000;
        uint256 actualFee = tokenA.balanceOf(feeCollector) - feeCollectorBalanceBefore;
        assertEq(actualFee, expectedFee, "Incorrect fee amount collected");
        vm.stopPrank();
    }

}
