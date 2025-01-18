// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";

contract PonderEdgeCaseTest is Test {
    PonderFactory factory;
    PonderRouter router;
    PonderPair pair;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    WETH9 weth;

    address alice = address(0x1);
    uint256 constant INITIAL_LIQUIDITY = 100_000e18;
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    error ExpiredDeadline();

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

        // Initial setup for alice
        vm.startPrank(alice);
        vm.deal(alice, 100 ether);
        vm.stopPrank();
    }

    function testMinimumLiquidityLock() public {
        vm.startPrank(alice);

        // Mint sufficient tokens
        uint256 initialAmount = 10000e18;
        tokenA.mint(alice, initialAmount);
        tokenB.mint(alice, initialAmount);

        // Approve tokens
        tokenA.approve(address(router), initialAmount);
        tokenB.approve(address(router), initialAmount);

        // Add initial liquidity through router
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            initialAmount,
            initialAmount,
            0,
            0,
            alice,
            block.timestamp
        );

        // Get LP balance but subtract MINIMUM_LIQUIDITY
        uint256 lpBalance = pair.balanceOf(alice);
        assertTrue(lpBalance > 0, "Should have received LP tokens");

        // Only transfer the amount above MINIMUM_LIQUIDITY
        uint256 burnAmount = lpBalance - MINIMUM_LIQUIDITY;
        pair.transfer(address(pair), burnAmount);
        pair.burn(alice);

        // Verify minimum liquidity remains
        assertEq(pair.totalSupply(), MINIMUM_LIQUIDITY, "MINIMUM_LIQUIDITY should remain locked");
        assertEq(pair.balanceOf(address(1)), MINIMUM_LIQUIDITY, "MINIMUM_LIQUIDITY should be at address(1)");

        vm.stopPrank();
    }

    function testHighValueSwap() public {
        vm.startPrank(alice);

        // Add liquidity with reasonable amounts
        uint256 liquidityAmount = 1000e18;
        tokenA.mint(alice, liquidityAmount * 2); // Extra for swap
        tokenB.mint(alice, liquidityAmount);

        // Approve router
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // Add initial liquidity
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            liquidityAmount,
            liquidityAmount,
            0,
            0,
            alice,
            block.timestamp
        );

        // Setup swap parameters
        uint256 swapAmount = liquidityAmount / 10; // 10% of liquidity
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Perform swap
        uint256 balanceBefore = tokenB.balanceOf(alice);

        router.swapExactTokensForTokens(
            swapAmount,
            0,  // Accept any output amount
            path,
            alice,
            block.timestamp
        );

        uint256 balanceAfter = tokenB.balanceOf(alice);

        // Verify the swap was successful
        assertGt(balanceAfter, balanceBefore, "Should have received tokens from swap");

        vm.stopPrank();
    }

    function testDeadlinePassed() public {
        vm.startPrank(alice);

        // Setup initial liquidity
        uint256 amount = 1000e18;
        tokenA.mint(alice, amount * 2);
        tokenB.mint(alice, amount);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amount,
            amount,
            0,
            0,
            alice,
            block.timestamp
        );

        // Setup path for swap
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        // Try to swap with passed deadline
        vm.expectRevert(ExpiredDeadline.selector);
        router.swapExactTokensForTokens(
            amount,
            0,
            path,
            alice,
            block.timestamp - 1  // Deadline in the past
        );

        vm.stopPrank();
    }
}
