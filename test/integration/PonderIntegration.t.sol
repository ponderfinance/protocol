// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderMasterChef.sol";
import "../../src/core/PonderPair.sol";
import "../../src/core/PonderToken.sol";
import "../../src/periphery/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";

interface IRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

contract PonderIntegrationTest is Test {
    PonderFactory factory;
    PonderRouter router;
    PonderToken ponder;
    PonderMasterChef masterChef;
    WETH9 weth;
    ERC20Mint tokenA;
    ERC20Mint tokenB;

    address alice = address(0x1);
    address bob = address(0x2);
    address carol = address(0x3);
    address treasury = address(0x4);

    uint256 constant INITIAL_LIQUIDITY = 100_000e18;

    function setUp() public {
        // Deploy core contracts
        weth = new WETH9();
        ponder = new PonderToken(treasury, treasury, address(this)); // Add launcher address
        factory = new PonderFactory(address(this), address(1), address(2));
        MockKKUBUnwrapper unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(address(factory), address(weth), address(unwrapper));

        masterChef = new PonderMasterChef(
            ponder,
            factory,
            treasury,
            1e18 // 1 PONDER per second
        );

        // Setup tokens
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");

        // Setup initial balances
        tokenA.mint(alice, INITIAL_LIQUIDITY);
        tokenB.mint(alice, INITIAL_LIQUIDITY);
        vm.deal(alice, 100 ether);

        tokenA.mint(bob, INITIAL_LIQUIDITY);
        tokenB.mint(bob, INITIAL_LIQUIDITY);
        vm.deal(bob, 100 ether);
    }

    function testCompleteFlow() public {
        // 1. Add liquidity
        vm.startPrank(alice);
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

        address pairAddress = factory.getPair(address(tokenA), address(tokenB));
        PonderPair pair = PonderPair(pairAddress);

        // 2. Perform swaps
        vm.startPrank(bob);
        uint256 swapAmount = 1000e18;
        tokenA.approve(address(router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        router.swapExactTokensForTokens(
            swapAmount,
            0, // Accept any amount of TokenB
            path,
            bob,
            block.timestamp
        );
        vm.stopPrank();

        // 3. Test MasterChef staking
        vm.startPrank(alice);
        uint256 lpBalance = pair.balanceOf(alice);
        pair.approve(address(masterChef), lpBalance);

        // Add LP pool to MasterChef
        vm.startPrank(address(this));
        ponder.setMinter(address(masterChef));
        masterChef.add(100, address(pair), 0, 20000, true);
        vm.stopPrank();

        // Stake LP tokens
        vm.startPrank(alice);
        masterChef.deposit(0, lpBalance);

        // Move forward in time
        vm.warp(block.timestamp + 1 days);

        // Harvest rewards
        masterChef.deposit(0, 0);
        vm.stopPrank();

        // 4. Remove liquidity
        vm.startPrank(alice);
        masterChef.withdraw(0, lpBalance);
        pair.approve(address(router), lpBalance);

        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance,
            0,
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();

        // Verify final state
        assertGt(ponder.balanceOf(alice), 0, "Should have earned PONDER rewards");
        assertGt(tokenA.balanceOf(alice), 0, "Should have received back TokenA");
        assertGt(tokenB.balanceOf(alice), 0, "Should have received back TokenB");
    }

    function testMultipleUserSwaps() public {
        // Setup initial liquidity
        _setupInitialLiquidity();

        // Note initial reserves
        (uint112 initialReserve0, uint112 initialReserve1,) = PonderPair(factory.getPair(address(tokenA), address(tokenB))).getReserves();

        // Multiple users perform swaps tokenA -> tokenB
        address[] memory users = new address[](3);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        for (uint i = 0; i < users.length; i++) {
            address user = users[i];
            tokenA.mint(user, 1000e18);

            vm.startPrank(user);
            tokenA.approve(address(router), 1000e18);

            router.swapExactTokensForTokens(
                1000e18,
                0,
                path,
                user,
                block.timestamp
            );
            vm.stopPrank();
        }

        // Get final reserves
        (uint112 finalReserve0, uint112 finalReserve1,) = PonderPair(factory.getPair(address(tokenA), address(tokenB))).getReserves();

        assertGt(finalReserve0, initialReserve0, "TokenA reserve should have increased");
        assertLt(finalReserve1, initialReserve1, "TokenB reserve should have decreased");

        // Verify users received tokenB
        for (uint i = 0; i < users.length; i++) {
            assertGt(tokenB.balanceOf(users[i]), 0, "User should have received TokenB");
        }
    }

    function testReentrancyProtection() public {
        // Setup initial liquidity
        _setupInitialLiquidity();

        // Create a malicious contract that tries to reenter
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(router));

        // Fund the attacker
        tokenA.mint(address(attacker), INITIAL_LIQUIDITY);
        tokenB.mint(address(attacker), INITIAL_LIQUIDITY);

        // Attempt attack
        vm.expectRevert();
        attacker.initiateAttack();
    }

    function _setupInitialLiquidity() internal {
        vm.startPrank(alice);
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
}

contract ReentrancyAttacker {
    address public immutable router;
    bool public isAttacking;

    constructor(address _router) {
        router = _router;
    }

    function initiateAttack() external {
        isAttacking = true;
        _performReentrantSwap();
    }

    function _performReentrantSwap() internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = address(this);

        IRouter(router).swapExactTokensForTokens(
            1000e18,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    // Called by the router during swap
    function transferFrom(address, address, uint256) external returns (bool) {
        if (isAttacking) {
            // Try to reenter by performing another swap
            _performReentrantSwap();
        }
        return true;
    }

    // Required interface functions
    function balanceOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }
}
