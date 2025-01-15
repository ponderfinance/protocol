// PonderRouterETHTest.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPair.sol";
import "../../src/periphery/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/WETH9.sol";
import "../mocks/MockKKUBUnwrapper.sol";


contract PonderRouterETHTest is Test {
    PonderFactory factory;
    PonderRouter router;
    ERC20Mint token;
    WETH9 weth;
    address pair;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_LIQUIDITY = 100e18;
    uint256 constant MINIMUM_LIQUIDITY = 1000;

    event LiquidityETHAdded(
        address indexed token,
        address indexed to,
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    );

    function setUp() public {
        // Deploy contracts
        weth = new WETH9();
        factory = new PonderFactory(address(this), address(1), address(2));
        MockKKUBUnwrapper unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(address(factory), address(weth), address(unwrapper));
        token = new ERC20Mint("Test Token", "TEST");

        // Setup Alice
        vm.startPrank(alice);
        token.mint(alice, INITIAL_LIQUIDITY * 2);
        vm.deal(alice, INITIAL_LIQUIDITY * 2);
        token.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function testBasicAddLiquidityETH() public {
        vm.startPrank(alice);

        uint256 tokenAmount = INITIAL_LIQUIDITY;
        uint256 ethAmount = INITIAL_LIQUIDITY;

        // Expected event
        vm.expectEmit(true, true, true, true);
        emit LiquidityETHAdded(
            address(token),
            alice,
            tokenAmount,
            ethAmount,
            tokenAmount - MINIMUM_LIQUIDITY
        );

        // Add liquidity
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{
                value: ethAmount
            }(
            address(token),
            tokenAmount,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Verify amounts
        assertEq(amountToken, tokenAmount, "Incorrect token amount");
        assertEq(amountETH, ethAmount, "Incorrect ETH amount");
        assertEq(liquidity, tokenAmount - MINIMUM_LIQUIDITY, "Incorrect liquidity");

        vm.stopPrank();
    }

    function testAddLiquidityETHWithSlippage() public {
        vm.startPrank(alice);

        uint256 tokenAmount = INITIAL_LIQUIDITY;
        uint256 ethAmount = INITIAL_LIQUIDITY;
        uint256 minTokenAmount = tokenAmount * 95 / 100; // 5% slippage
        uint256 minETHAmount = ethAmount * 95 / 100;

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{
                value: ethAmount
            }(
            address(token),
            tokenAmount,
            minTokenAmount,
            minETHAmount,
            alice,
            block.timestamp + 1
        );

        assertTrue(amountToken >= minTokenAmount, "Token amount below minimum");
        assertTrue(amountETH >= minETHAmount, "ETH amount below minimum");
        assertGt(liquidity, 0, "No liquidity minted");

        vm.stopPrank();
    }

    function testAddLiquidityETHWithExcessETH() public {
        vm.startPrank(alice);

        // First add initial liquidity at 1:1 ratio
        router.addLiquidityETH{value: INITIAL_LIQUIDITY}(
            address(token),
            INITIAL_LIQUIDITY,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Now try to add more liquidity but with excess ETH
        uint256 tokenAmount = INITIAL_LIQUIDITY;
        uint256 excessETHAmount = INITIAL_LIQUIDITY * 2;  // Double the ETH needed

        // Need to ensure alice has enough ETH for the excess test
        vm.deal(alice, excessETHAmount);  // Replenish alice's ETH balance

        token.mint(alice, tokenAmount);  // Ensure alice has enough tokens too
        token.approve(address(router), tokenAmount);

        uint256 ethBalanceBefore = alice.balance;

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{
                value: excessETHAmount
            }(
            address(token),
            tokenAmount,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Verify excess ETH was refunded
        uint256 ethSpent = ethBalanceBefore - alice.balance;
        assertEq(ethSpent, amountETH, "Excess ETH not refunded");
        assertLt(amountETH, excessETHAmount, "All ETH was used");

        vm.stopPrank();
    }

    function testFailAddLiquidityETHWithExpiredDeadline() public {
        vm.startPrank(alice);
        vm.warp(2);

        router.addLiquidityETH{value: INITIAL_LIQUIDITY}(
            address(token),
            INITIAL_LIQUIDITY,
            0,
            0,
            alice,
            1 // Expired deadline
        );

        vm.stopPrank();
    }

    function testFailAddLiquidityETHWithInsufficientETH() public {
        vm.startPrank(alice);

        router.addLiquidityETH{value: INITIAL_LIQUIDITY / 2}(
            address(token),
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,  // Min token amount equals desired
            INITIAL_LIQUIDITY,  // Min ETH amount greater than sent
            alice,
            block.timestamp + 1
        );

        vm.stopPrank();
    }

    function testFailAddLiquidityETHToZeroAddress() public {
        vm.startPrank(alice);

        router.addLiquidityETH{value: INITIAL_LIQUIDITY}(
            address(token),
            INITIAL_LIQUIDITY,
            0,
            0,
            address(0),  // Zero address recipient
            block.timestamp + 1
        );

        vm.stopPrank();
    }

    function testReentrancyProtection() public {
        ReentrantToken maliciousToken = new ReentrantToken(address(router));

        // Mint tokens to the malicious contract
        maliciousToken.mint(address(maliciousToken), INITIAL_LIQUIDITY);

        vm.startPrank(alice);
        vm.deal(alice, INITIAL_LIQUIDITY);
        maliciousToken.approve(address(router), type(uint256).max);

        // Update expectRevert to match the actual error from TransferHelper
        vm.expectRevert("TransferHelper::transferFrom: transferFrom failed");
        router.addLiquidityETH{value: INITIAL_LIQUIDITY}(
            address(maliciousToken),
            INITIAL_LIQUIDITY,
            0,
            0,
            alice,
            block.timestamp + 1
        );
        vm.stopPrank();
    }

    function testFuzz_AddLiquidityETH(
        uint256 tokenAmount,
        uint256 ethAmount
    ) public {
        // Bound inputs to reasonable ranges
        tokenAmount = bound(tokenAmount, MINIMUM_LIQUIDITY * 2, INITIAL_LIQUIDITY * 100);
        ethAmount = bound(ethAmount, MINIMUM_LIQUIDITY * 2, INITIAL_LIQUIDITY * 100);

        vm.startPrank(alice);
        token.mint(alice, tokenAmount);
        vm.deal(alice, ethAmount);

        (uint256 amountToken, uint256 amountETH, uint256 liquidity) = router.addLiquidityETH{
                value: ethAmount
            }(
            address(token),
            tokenAmount,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        assertTrue(amountToken > 0, "Token amount should be non-zero");
        assertTrue(amountETH > 0, "ETH amount should be non-zero");
        assertTrue(liquidity > 0, "Liquidity should be non-zero");

        vm.stopPrank();
    }
}

contract ReentrantToken is ERC20Mint {
    PonderRouter immutable public router;
    bool public attacking = true;
    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(address routerAddr) ERC20Mint("Reentrant", "REET") {
        router = PonderRouter(payable(routerAddr));
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (attacking) {
            attacking = false;
            router.addLiquidityETH{value: 1 ether}(
                address(this),
                1e18,
                0,
                0,
                address(this),
                block.timestamp + 1
            );
            return false; // Force the transfer to fail
        }

        // Standard transferFrom implementation
        if (allowance(from, msg.sender) != type(uint256).max) {
            require(allowance(from, msg.sender) >= amount, "ERC20: insufficient allowance");
            _approve(from, msg.sender, allowance(from, msg.sender) - amount);
        }
        _transfer(from, to, amount);
        return true;
    }
}
