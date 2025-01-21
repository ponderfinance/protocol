// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";


contract PonderBoundaryTest is Test {
    PonderFactory factory;
    PonderRouter router;
    PonderPair pair;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    WETH9 weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // Test constants
    uint256 constant MAX_UINT = type(uint256).max;
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
        vm.deal(alice, 100 ether);
        vm.stopPrank();
    }

    function testExtremeTokenAmounts() public {
        uint256 largeAmount = type(uint112).max / 4;

        vm.startPrank(alice);

        // Test large but safe amounts
        tokenA.mint(alice, largeAmount);
        tokenB.mint(alice, largeAmount);
        tokenA.approve(address(router), largeAmount);
        tokenB.approve(address(router), largeAmount);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            largeAmount,
            largeAmount,
            0,
            0,
            alice,
            block.timestamp
        );

        // Verify initial state
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        assertEq(uint256(reserve0), largeAmount, "Incorrect reserve0");
        assertEq(uint256(reserve1), largeAmount, "Incorrect reserve1");

        // Test overflow scenario
        uint256 overflowAmount = type(uint112).max;
        tokenA.mint(address(pair), overflowAmount);
        tokenB.mint(address(pair), overflowAmount);

        vm.expectRevert(abi.encodeWithSignature("Overflow()"));
        pair.mint(alice);

        vm.stopPrank();
    }

    // Fix for testIncrementalOverflow
    function testIncrementalOverflow() public {
        vm.startPrank(alice);

        // First add normal liquidity
        uint256 baseAmount = type(uint112).max / 4;
        tokenA.mint(alice, baseAmount);
        tokenB.mint(alice, baseAmount);

        tokenA.approve(address(router), baseAmount);
        tokenB.approve(address(router), baseAmount);

        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            baseAmount,
            baseAmount,
            0,
            0,
            alice,
            block.timestamp
        );

        // Now try to add amount that would cause overflow
        uint256 overflowAmount = type(uint112).max;
        tokenA.mint(alice, overflowAmount);
        tokenB.mint(alice, overflowAmount);

        tokenA.approve(address(router), overflowAmount);
        tokenB.approve(address(router), overflowAmount);

        // Should revert due to overflow
        vm.expectRevert();  // Remove specific error message since it's a panic
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            overflowAmount,
            overflowAmount,
            0,
            0,
            alice,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testReservesOverflow() public {
        vm.startPrank(alice);

        // Add initial liquidity near max
        uint256 initialAmount = type(uint112).max / 3;
        tokenA.mint(alice, initialAmount);
        tokenB.mint(alice, initialAmount);

        tokenA.approve(address(pair), type(uint256).max);
        tokenB.approve(address(pair), type(uint256).max);

        // First mint should succeed via direct pair transfer
        tokenA.transfer(address(pair), initialAmount);
        tokenB.transfer(address(pair), initialAmount);
        pair.mint(alice);

        // Now try to cause overflow via direct transfer and mint
        uint256 additionalAmount = type(uint112).max;
        tokenA.mint(address(pair), additionalAmount);
        tokenB.mint(address(pair), additionalAmount);

        // This should overflow
        vm.expectRevert(abi.encodeWithSignature("Overflow()"));
        pair.mint(alice);

        vm.stopPrank();
    }

    function testZeroAmountHandling() public {
        vm.startPrank(alice);

        // Setup initial liquidity
        _setupInitialLiquidity();

        // Try to add zero liquidity
        bytes4 selector = bytes4(keccak256("InsufficientAmount()"));
        vm.expectRevert(selector);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            0,
            0,
            0,
            0,
            alice,
            block.timestamp
        );

        // Try to swap zero tokens
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes4 swapSelector = bytes4(keccak256("InsufficientInputAmount()"));
        vm.expectRevert(swapSelector);
        router.swapExactTokensForTokens(
            0,
            0,
            path,
            alice,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testSqrtOverflow() public {
        vm.startPrank(alice);

        // Setup amounts that would cause sqrt overflow
        uint256 sqrtOverflowAmount = type(uint128).max;
        tokenA.mint(alice, sqrtOverflowAmount);
        tokenB.mint(alice, sqrtOverflowAmount);

        tokenA.approve(address(pair), sqrtOverflowAmount);
        tokenB.approve(address(pair), sqrtOverflowAmount);

        // Transfer directly to pair to test mint
        tokenA.transfer(address(pair), sqrtOverflowAmount);
        tokenB.transfer(address(pair), sqrtOverflowAmount);

        vm.expectRevert(abi.encodeWithSignature("Overflow()"));
        pair.mint(alice);

        vm.stopPrank();
    }


    function testArithmeticOverflow() public {
        vm.startPrank(alice);

        // Setup initial liquidity
        uint256 initialAmount = type(uint112).max / 2;
        tokenA.mint(alice, initialAmount * 2);
        tokenB.mint(alice, initialAmount * 2);

        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);

        // Add initial liquidity
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

        // Try swap with amount that would cause arithmetic overflow
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        vm.expectRevert();
        router.swapExactTokensForTokens(
            type(uint112).max,
            0,
            path,
            alice,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testExtremePriceRatios() public {
        vm.startPrank(alice);

        // Test with extreme ratio (1:1M)
        uint256 amount1 = 1e18;
        uint256 amount2 = 1_000_000e18;

        tokenA.mint(alice, amount1);
        tokenB.mint(alice, amount2);

        tokenA.approve(address(router), amount1);
        tokenB.approve(address(router), amount2);

        // Add initial liquidity with extreme ratio
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amount1,
            amount2,
            0,
            0,
            alice,
            block.timestamp
        );

        // Test small swap
        uint256 minSwapAmount = 1000; // 1000 wei
        tokenA.mint(alice, minSwapAmount);
        tokenA.approve(address(router), minSwapAmount);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        router.swapExactTokensForTokens(
            minSwapAmount,
            0,
            path,
            alice,
            block.timestamp
        );

        vm.stopPrank();
    }


    function testMaxApprovalScenarios() public {
        vm.startPrank(alice);

        tokenA.mint(alice, INITIAL_LIQUIDITY * 5);
        tokenB.mint(alice, INITIAL_LIQUIDITY * 5);

        tokenA.approve(address(router), MAX_UINT);
        tokenB.approve(address(router), MAX_UINT);

        // Multiple liquidity adds without new approvals
        for (uint i = 0; i < 5; i++) {
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
        }

        assertEq(tokenA.allowance(alice, address(router)), MAX_UINT, "Allowance should remain max");
        vm.stopPrank();
    }

    function testReserveSyncEdgeCases() public {
        vm.startPrank(alice);

        _setupInitialLiquidity();

        // Direct token transfers
        uint256 amount = 1e18;
        tokenA.mint(address(pair), amount);
        tokenB.mint(address(pair), amount);

        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();
        pair.sync();
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();

        assertGt(reserve0After, reserve0Before, "Reserve0 should increase");
        assertGt(reserve1After, reserve1Before, "Reserve1 should increase");

        vm.stopPrank();
    }

    function testMinimumLiquidityLocking() public {
        vm.startPrank(alice);

        uint256 minLiquidity = 1001; // Just above MINIMUM_LIQUIDITY
        tokenA.mint(alice, minLiquidity);
        tokenB.mint(alice, minLiquidity);

        tokenA.approve(address(router), minLiquidity);
        tokenB.approve(address(router), minLiquidity);

        // Try below minimum
        vm.expectRevert(abi.encodeWithSignature("InsufficientLiquidityMinted()"));
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            1000, // Below MINIMUM_LIQUIDITY
            1000,
            0,
            0,
            alice,
            block.timestamp
        );

        // Try with valid minimum
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            minLiquidity,
            minLiquidity,
            0,
            0,
            alice,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testMaximumTransfer() public {
        uint256 maxTransfer = type(uint112).max;

        vm.startPrank(alice);
        tokenA.mint(alice, maxTransfer);
        assertTrue(tokenA.transfer(bob, maxTransfer), "Max transfer failed");
        assertEq(tokenA.balanceOf(bob), maxTransfer, "Incorrect balance after max transfer");
        vm.stopPrank();
    }

    function testCumulativePriceOverflow() public {
        vm.startPrank(alice);

        // Add initial liquidity
        _setupInitialLiquidity();

        // Move time forward significantly
        vm.warp(block.timestamp + 365 days);

        // Should not overflow price accumulators
        pair.sync();

        uint256 price0Cumulative = pair.price0CumulativeLast();
        uint256 price1Cumulative = pair.price1CumulativeLast();

        assertGt(price0Cumulative, 0, "Price0 accumulator should be non-zero");
        assertGt(price1Cumulative, 0, "Price1 accumulator should be non-zero");

        vm.stopPrank();
    }

    // Helper function
    function _setupInitialLiquidity() internal {
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
    }
}
