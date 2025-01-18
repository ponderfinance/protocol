// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../mocks/ERC20Mint.sol";

contract FlashSwapTest {
    bool public flashSwapExecuted;

    function ponderCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        flashSwapExecuted = true;

        // Get pair reserves to calculate exact repayment needed
        (uint112 reserve0, uint112 reserve1,) = PonderPair(msg.sender).getReserves();

        uint256 amount = amount0 > 0 ? amount0 : amount1;
        uint256 balance0 = IERC20(abi.decode(data, (address))).balanceOf(msg.sender);

        // Calculate amount needed to satisfy x * y ≥ k
        uint256 numerator = uint256(reserve0) * uint256(reserve1) * 1000;
        uint256 denominator = uint256(reserve0 - amount) * 997;
        uint256 amountToRepay = ((numerator / denominator) - uint256(reserve1)) + 1;

        // Repay the flash loan
        ERC20Mint(abi.decode(data, (address))).transfer(msg.sender, amountToRepay);
    }
}

contract PonderFlashSwapTest is Test {
    PonderFactory factory;
    PonderPair pair;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    FlashSwapTest flashSwapper;

    address alice = address(0x1);
    uint256 constant INITIAL_LIQUIDITY = 100_000e18;

    function setUp() public {
        // Deploy tokens
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");
        flashSwapper = new FlashSwapTest();

        // Deploy factory and create pair
        factory = new PonderFactory(address(this), address(1), address(2));
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = PonderPair(pairAddress);

        // Setup initial liquidity
        tokenA.mint(alice, INITIAL_LIQUIDITY);
        tokenB.mint(alice, INITIAL_LIQUIDITY);

        vm.startPrank(alice);
        tokenA.transfer(address(pair), INITIAL_LIQUIDITY);
        tokenB.transfer(address(pair), INITIAL_LIQUIDITY);
        pair.mint(alice);
        vm.stopPrank();

        // Fund flash swapper with enough tokens for repayment
        tokenA.mint(address(flashSwapper), INITIAL_LIQUIDITY);
        tokenB.mint(address(flashSwapper), INITIAL_LIQUIDITY);
    }

    function testFlashSwap() public {
        // Use small amount for flash loan (1% of liquidity)
        uint256 flashAmount = INITIAL_LIQUIDITY / 100;
        bytes memory data = abi.encode(address(tokenA));

        // Record initial state
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 k = uint256(reserve0) * uint256(reserve1);

        // Execute flash swap
        pair.swap(flashAmount, 0, address(flashSwapper), data);

        // Verify flash swap executed
        assertTrue(flashSwapper.flashSwapExecuted(), "Flash swap should have executed");

        // Verify k increased (or stayed same)
        (uint112 newReserve0, uint112 newReserve1,) = pair.getReserves();
        uint256 newK = uint256(newReserve0) * uint256(newReserve1);
        assertGe(newK, k, "K should not decrease");
    }

    function testFailFlashSwapWithoutRepay() public {
        uint256 flashAmount = INITIAL_LIQUIDITY / 100;
        bytes memory data = abi.encode(address(tokenA));  // Added this line

        vm.mockCall(
            address(flashSwapper),
            abi.encodeWithSelector(FlashSwapTest.ponderCall.selector),
            abi.encode()
        );

        // This should fail because no repayment
        pair.swap(flashAmount, 0, address(flashSwapper), data);
    }
}
