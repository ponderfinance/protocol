// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";

contract PonderGasTest is Test {
    PonderFactory factory;
    PonderRouter router;
    PonderPair pair;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    WETH9 weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_LIQUIDITY = 100_000e18;
    uint256 constant SWAP_AMOUNT = 1_000e18;

    // Gas limits adjusted based on actual measurements
    uint256 constant GAS_LIMIT_PAIR_CREATION = 4_500_000;
    uint256 constant GAS_LIMIT_INITIAL_LIQUIDITY = 280_000;
    uint256 constant GAS_LIMIT_ADDITIONAL_LIQUIDITY = 270_000;
    uint256 constant GAS_LIMIT_SWAP = 280_000;
    uint256 constant GAS_LIMIT_REMOVE_LIQUIDITY = 260_000;
    uint256 constant GAS_LIMIT_SYNC = 250_000;
    uint256 constant GAS_LIMIT_MULTI_HOP = 4_000_000;

    event GasUsed(string operation, uint256 gasUsed);

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

        // Setup users
        vm.startPrank(alice);
        tokenA.mint(alice, INITIAL_LIQUIDITY * 2);
        tokenB.mint(alice, INITIAL_LIQUIDITY * 2);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        tokenA.mint(bob, INITIAL_LIQUIDITY);
        tokenB.mint(bob, INITIAL_LIQUIDITY);
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function testGas_PairCreation() public {
        ERC20Mint newTokenA = new ERC20Mint("New Token A", "NTKA");
        ERC20Mint newTokenB = new ERC20Mint("New Token B", "NTKB");

        uint256 gasBefore = gasleft();
        factory.createPair(address(newTokenA), address(newTokenB));
        uint256 gasUsed = gasBefore - gasleft();

        emit GasUsed("Pair Creation", gasUsed);
        assertLt(gasUsed, GAS_LIMIT_PAIR_CREATION, "Pair creation gas too high");
    }

    function testGas_InitialLiquidityProvision() public {
        vm.startPrank(alice);

        uint256 gasBefore = gasleft();
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
        uint256 gasUsed = gasBefore - gasleft();

        emit GasUsed("Initial Liquidity", gasUsed);
        assertLt(gasUsed, GAS_LIMIT_INITIAL_LIQUIDITY, "Initial liquidity provision gas too high");
        vm.stopPrank();
    }

    function testGas_AdditionalLiquidityProvision() public {
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

        uint256 gasBefore = gasleft();
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            INITIAL_LIQUIDITY / 2,
            INITIAL_LIQUIDITY / 2,
            0,
            0,
            alice,
            block.timestamp
        );
        uint256 gasUsed = gasBefore - gasleft();

        emit GasUsed("Additional Liquidity", gasUsed);
        assertLt(gasUsed, GAS_LIMIT_ADDITIONAL_LIQUIDITY, "Additional liquidity provision gas too high");
        vm.stopPrank();
    }

    function testGas_SwapExactTokensForTokens() public {
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

        vm.startPrank(bob);
        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        uint256 gasBefore = gasleft();
        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            0,
            path,
            bob,
            block.timestamp
        );
        uint256 gasUsed = gasBefore - gasleft();

        emit GasUsed("Swap", gasUsed);
        assertLt(gasUsed, GAS_LIMIT_SWAP, "Swap gas too high");
        vm.stopPrank();
    }

    function testGas_RemoveLiquidity() public {
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

        uint256 lpBalance = pair.balanceOf(alice);
        pair.approve(address(router), lpBalance);

        uint256 gasBefore = gasleft();
        router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            lpBalance,
            0,
            0,
            alice,
            block.timestamp
        );
        uint256 gasUsed = gasBefore - gasleft();

        emit GasUsed("Remove Liquidity", gasUsed);
        assertLt(gasUsed, GAS_LIMIT_REMOVE_LIQUIDITY, "Remove liquidity gas too high");
        vm.stopPrank();
    }

    function testGas_Sync() public {
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

        uint256 gasBefore = gasleft();
        pair.sync();
        uint256 gasUsed = gasBefore - gasleft();

        emit GasUsed("Sync", gasUsed);
        assertLt(gasUsed, GAS_LIMIT_SYNC, "Sync gas too high");
    }

    function testGas_MultiHopSwap() public {
        // Create intermediate token and pairs
        ERC20Mint tokenC = new ERC20Mint("Token C", "TKNC");
        factory.createPair(address(tokenB), address(tokenC));
        address pairBC = factory.getPair(address(tokenB), address(tokenC));

        // Setup initial liquidity for both pairs
        vm.startPrank(alice);
        tokenC.mint(alice, INITIAL_LIQUIDITY);
        tokenC.approve(address(router), type(uint256).max);

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

        router.addLiquidity(
            address(tokenB),
            address(tokenC),
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            0,
            0,
            alice,
            block.timestamp
        );
        vm.stopPrank();

        vm.startPrank(bob);
        address[] memory path = new address[](3);
        path[0] = address(tokenA);
        path[1] = address(tokenB);
        path[2] = address(tokenC);

        uint256 gasBefore = gasleft();
        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            0,
            path,
            bob,
            block.timestamp
        );
        uint256 gasUsed = gasBefore - gasleft();

        emit GasUsed("Multi-hop Swap", gasUsed);
        assertLt(gasUsed, GAS_LIMIT_MULTI_HOP, "Multi-hop swap gas too high");
        vm.stopPrank();
    }
}
