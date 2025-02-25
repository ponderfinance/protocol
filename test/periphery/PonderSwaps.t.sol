// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../src/periphery/router/IPonderRouter.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/launch/LaunchToken.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";

contract MockKKUBUnwrapper {
    address public immutable KKUB;

    constructor(address _weth) {
        KKUB = _weth;
    }

    function unwrapKKUB(uint256 amount, address recipient) external returns (bool) {
        require(IERC20(KKUB).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        IKKUB(KKUB).withdraw(amount);
        (bool success,) = recipient.call{value: amount}("");
        require(success, "ETH transfer failed");
        return true;
    }

    receive() external payable {}
}

contract MockFactory {
    address public feeTo;
    address public launcher;
    address public ponder;

    mapping(address => mapping(address => address)) public pairs;

    constructor(address _feeTo, address _launcher, address _ponder) {
        feeTo = _feeTo;
        launcher = _launcher;
        ponder = _ponder;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return pairs[tokenA][tokenB];
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        PonderPair newPair = new PonderPair();
        newPair.initialize(tokenA, tokenB);
        pairs[tokenA][tokenB] = address(newPair);
        pairs[tokenB][tokenA] = address(newPair);
        return address(newPair);
    }
}

contract PonderRouterTest is Test {
    PonderPair standardPair;
    ERC20Mint token0;
    ERC20Mint token1;
    LaunchToken launchToken;
    PonderToken ponder;
    WETH9 weth;
    MockFactory factory;
    MockKKUBUnwrapper unwrapper;
    PonderRouter router;

    // Users for testing
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address creator = makeAddr("creator");
    address treasury = makeAddr("treasury");
    address ponderLauncher = makeAddr("ponderLauncher");

    // Common amounts
    uint256 constant INITIAL_LIQUIDITY_AMOUNT = 10000e18;
    uint256 constant SWAP_AMOUNT = 1000e18;

    function setUp() public {
        // Allocate sufficient ETH to Alice for liquidity and swaps
        vm.deal(alice, INITIAL_LIQUIDITY_AMOUNT * 10);

        // Deploy standard tokens
        token0 = new ERC20Mint("Token A", "TKNA");
        token1 = new ERC20Mint("Token B", "TKNB");
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Deploy KKUB and PONDER
        weth = new WETH9();
        ponder = new PonderToken(treasury, treasury, ponderLauncher);

        // Set up mock factory - uses test contract as launcher for launch tokens
        factory = new MockFactory(bob, address(this), address(ponder));

        // Setup unwrapper and router
        unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(
            address(factory),
            address(weth),
            address(unwrapper)
        );

        // Deploy LaunchToken - uses factory's launcher (address(this))
        launchToken = new LaunchToken(
            "Launch Token",
            "LAUNCH",
            address(this),
            address(factory),
            payable(address(1)),
            address(ponder)
        );

        launchToken.setupVesting(creator, INITIAL_LIQUIDITY_AMOUNT);
        launchToken.enableTransfers();

        // Create pairs
        address standardPairAddr = factory.createPair(address(token0), address(token1));
        address kubPairAddr = factory.createPair(address(launchToken), address(weth));
        address ponderPairAddr = factory.createPair(address(launchToken), address(ponder));

        standardPair = PonderPair(standardPairAddr);

        // Set launch token pairs
        launchToken.setPairs(kubPairAddr, ponderPairAddr);

        // Setup initial token balances
        token0.mint(alice, INITIAL_LIQUIDITY_AMOUNT * 4);
        token1.mint(alice, INITIAL_LIQUIDITY_AMOUNT * 4);
        deal(address(launchToken), alice, INITIAL_LIQUIDITY_AMOUNT * 4);
        deal(address(weth), alice, INITIAL_LIQUIDITY_AMOUNT * 4);
        deal(address(ponder), alice, INITIAL_LIQUIDITY_AMOUNT * 4);

        // Approvals
        vm.startPrank(alice);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        launchToken.approve(address(router), type(uint256).max);
        weth.approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);
        vm.stopPrank();
    }

    function testAllSwapTypesWithStandardTokens() public {
        // Add liquidity to the pair
        vm.startPrank(alice);
        router.addLiquidity(
            address(token0),
            address(token1),
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Perform a token swap
        uint256 token1BalanceBefore = token1.balanceOf(alice);
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            0,
            path,
            alice,
            block.timestamp + 1
        );
        uint256 token1BalanceAfter = token1.balanceOf(alice);
        assertGt(token1BalanceAfter, token1BalanceBefore, "Should receive token1");
        vm.stopPrank();
    }

    function testAllSwapTypesWithLaunchToken() public {
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(launchToken),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        uint256 launchTokenBalanceBefore = launchToken.balanceOf(alice);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(launchToken);

        router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            alice,
            block.timestamp + 1
        );
        uint256 launchTokenBalanceAfter = launchToken.balanceOf(alice);
        assertGt(launchTokenBalanceAfter, launchTokenBalanceBefore, "Should receive launch token");
        vm.stopPrank();
    }

    function testAllSwapTypesWithPONDER() public {
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(ponder),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        uint256 ponderBalanceBefore = ponder.balanceOf(alice);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(ponder);

        router.swapExactETHForTokens{value: 1 ether}(
            0,
            path,
            alice,
            block.timestamp + 1
        );
        uint256 ponderBalanceAfter = ponder.balanceOf(alice);
        assertGt(ponderBalanceAfter, ponderBalanceBefore, "Should receive PONDER");
        vm.stopPrank();
    }

    function testFeeOnTransferTokenSwaps() public {
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(launchToken),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        uint256 ethBalanceBefore = alice.balance;
        address[] memory path = new address[](2);
        path[0] = address(launchToken);
        path[1] = address(weth);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            SWAP_AMOUNT,
            0,
            path,
            alice,
            block.timestamp + 1
        );
        assertGt(alice.balance - ethBalanceBefore, 0, "Should receive ETH");
        vm.stopPrank();
    }

    function testBidirectionalLaunchTokenSwaps() public {
        vm.startPrank(alice);

        // Add liquidity
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(launchToken),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Buy launch tokens
        uint256 launchTokenBalanceBefore = launchToken.balanceOf(alice);
        address[] memory buyPath = new address[](2);
        buyPath[0] = address(weth);
        buyPath[1] = address(launchToken);

        router.swapExactETHForTokens{value: 1 ether}(
            0,
            buyPath,
            alice,
            block.timestamp + 1
        );

        uint256 received = launchToken.balanceOf(alice) - launchTokenBalanceBefore;

        // Sell 90% of received amount
        uint256 sellAmount = (received * 90) / 100;

        address[] memory sellPath = new address[](2);
        sellPath[0] = address(launchToken);
        sellPath[1] = address(weth);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            sellPath,
            alice,
            block.timestamp + 1
        );

        vm.stopPrank();
    }

    function testLaunchTokenFeeAmounts() public {
        vm.startPrank(alice);

        // Setup pair with initial liquidity
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(launchToken),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Get KUB pair address
        address kubPair = factory.getPair(address(launchToken), address(weth));

        // Record initial balances
        uint256 creatorBalanceBefore = launchToken.balanceOf(creator);
        uint256 bobBalanceBefore = launchToken.balanceOf(bob);  // feeTo address

        // Perform a sell of launch token
        uint256 sellAmount = 1000e18;
        address[] memory path = new address[](2);
        path[0] = address(launchToken);
        path[1] = address(weth);

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            sellAmount,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        // Call skim to collect protocol fees
        PonderPair(kubPair).skim(bob);

        // Check fee distributions
        uint256 creatorFee = launchToken.balanceOf(creator) - creatorBalanceBefore;
        uint256 protocolFee = launchToken.balanceOf(bob) - bobBalanceBefore;

        // For KUB pair: creator should get 0.01%, protocol should get 0.04%
        assertEq(creatorFee, sellAmount / 10000, "Incorrect creator fee");  // 0.01%
        assertEq(protocolFee, sellAmount * 4 / 10000, "Incorrect protocol fee"); // 0.04%

        vm.stopPrank();
    }

    function testPriceManipulationAttack() public {
        // Setup initial liquidity
        vm.startPrank(alice);
        router.addLiquidity(
            address(token0),
            address(token1),
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );
        vm.stopPrank();

        // Setup the attack
        vm.startPrank(bob);
        token0.mint(bob, INITIAL_LIQUIDITY_AMOUNT * 2);
        token0.approve(address(router), type(uint256).max);

        // Setup path for the swap
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        // Step 1: Get initial price
        uint256[] memory amountsOut = router.getAmountsOut(SWAP_AMOUNT, path);
        uint256 expectedOut = amountsOut[1];

        // Step 2: Manipulate price by doing a large swap
        router.swapExactTokensForTokens(
            INITIAL_LIQUIDITY_AMOUNT,  // Large swap to manipulate price
            0,
            path,
            bob,
            block.timestamp + 1
        );

        // Step 3: Try the original swap - should revert with InsufficientOutputAmount
        vm.expectRevert(abi.encodeWithSelector(IPonderRouter.InsufficientOutputAmount.selector));
        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            expectedOut,  // Using price from before manipulation
            path,
            bob,
            block.timestamp + 1
        );

        vm.stopPrank();
    }

    function testMultiHopPriceManipulation() public {
        // Setup initial liquidity for a multi-hop path (token0 -> token1 -> KKUB)
        vm.startPrank(alice);

        // Add liquidity to first pair (token0/token1)
        router.addLiquidity(
            address(token0),
            address(token1),
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Add liquidity to second pair (token1/KKUB)
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(token1),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );
        vm.stopPrank();

        // Setup multi-hop path
        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        // Setup manipulation path (just first pair)
        address[] memory manipulationPath = new address[](2);
        manipulationPath[0] = address(token0);
        manipulationPath[1] = address(token1);

        vm.startPrank(bob);
        token0.mint(bob, INITIAL_LIQUIDITY_AMOUNT * 2);
        token0.approve(address(router), type(uint256).max);

        // Get initial amounts
        uint256[] memory initialAmounts = router.getAmountsOut(SWAP_AMOUNT, path);

        // Try to manipulate intermediate pair
        router.swapExactTokensForTokens(
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            manipulationPath,
            bob,
            block.timestamp + 1
        );

        // Try multi-hop swap with original amounts - should revert with InsufficientOutputAmount
        vm.expectRevert(abi.encodeWithSelector(IPonderRouter.InsufficientOutputAmount.selector));
        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            initialAmounts[2],  // Expected output from initial calculation
            path,
            bob,
            block.timestamp + 1
        );

        vm.stopPrank();
    }

    function testKKUBUnwrappingInSwap() public {
        // Setup: Add liquidity to the KKUB pair
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(token0),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Record balances before swap
        uint256 aliceETHBalanceBefore = alice.balance;
        uint256 aliceToken0BalanceBefore = token0.balanceOf(alice);

        // Create path for swapping token0 to native KUB (which uses unwrapper)
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth); // This should trigger unwrapping

        // Perform swap that requires unwrapping
        router.swapExactTokensForETH(
            SWAP_AMOUNT,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        // Verify alice received native KUB
        assertGt(alice.balance - aliceETHBalanceBefore, 0, "Should receive native KUB");
        assertLt(token0.balanceOf(alice), aliceToken0BalanceBefore, "Should spend token0");

        vm.stopPrank();
    }

    // Tests exact output amount unwrapping
    function testExactOutputUnwrapping() public {
        // Setup: Add liquidity to the KKUB pair
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(token0),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Record balances before swap
        uint256 aliceETHBalanceBefore = alice.balance;

        // Get required input for exact output
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        uint256 exactETHAmount = 0.5 ether;
        uint256[] memory amounts = router.getAmountsIn(exactETHAmount, path);

        // Execute swap with exact output
        router.swapTokensForExactETH(
            exactETHAmount,
            amounts[0],
            path,
            alice,
            block.timestamp + 1
        );

        // Verify alice received exactly the requested amount of ETH
        assertEq(alice.balance - aliceETHBalanceBefore, exactETHAmount, "Should receive exact ETH amount");

        vm.stopPrank();
    }

// Tests unwrapping to a different recipient
    function testUnwrappingToDifferentRecipient() public {
        // Setup: Add liquidity to the KKUB pair
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(token0),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Record bob's balance before swap
        uint256 bobETHBalanceBefore = bob.balance;

        // Create path for swapping token0 to native KUB
        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        // Perform swap with bob as recipient
        router.swapExactTokensForETH(
            SWAP_AMOUNT,
            0,
            path,
            bob,
            block.timestamp + 1
        );

        // Verify bob received native KUB
        assertGt(bob.balance - bobETHBalanceBefore, 0, "Recipient should receive native KUB");

        vm.stopPrank();
    }

// Tests multi-hop route ending with unwrapping
    function testMultiHopUnwrapping() public {
        vm.startPrank(alice);

        // Setup two pairs for multi-hop: token0->token1->KKUB
        router.addLiquidity(
            address(token0),
            address(token1),
            INITIAL_LIQUIDITY_AMOUNT,
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(token1),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Record balances before swap
        uint256 aliceETHBalanceBefore = alice.balance;

        // Create multi-hop path ending with unwrapping
        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        // Perform swap
        router.swapExactTokensForETH(
            SWAP_AMOUNT,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        // Verify alice received native KUB
        assertGt(alice.balance - aliceETHBalanceBefore, 0, "Should receive native KUB after multi-hop");

        vm.stopPrank();
    }

// Tests slippage protection during unwrapping
    function testUnwrappingSlippageProtection() public {
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(token0),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        // Get expected amount out
        uint256[] memory amountsOut = router.getAmountsOut(SWAP_AMOUNT, path);

        // Set minimum output higher than possible
        uint256 unreachableMinimum = amountsOut[1] * 2;

        // Expect revert due to insufficient output amount
        vm.expectRevert(abi.encodeWithSelector(IPonderRouter.InsufficientOutputAmount.selector));
        router.swapExactTokensForETH(
            SWAP_AMOUNT,
            unreachableMinimum,
            path,
            alice,
            block.timestamp + 1
        );

        vm.stopPrank();
    }

// Tests deadline enforcement for unwrapping
    function testUnwrappingDeadline() public {
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(token0),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        // Set deadline in the past
        uint256 pastDeadline = block.timestamp - 1;

        // Expect revert due to expired deadline
        vm.expectRevert(abi.encodeWithSelector(IPonderRouter.ExpiredDeadline.selector));
        router.swapExactTokensForETH(
            SWAP_AMOUNT,
            0,
            path,
            alice,
            pastDeadline
        );

        vm.stopPrank();
    }

// Tests fee-on-transfer tokens with unwrapping
    function testFeeOnTransferUnwrapping() public {
        // Assuming launchToken has fee-on-transfer mechanics
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(launchToken),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        // Record balances before swap
        uint256 aliceETHBalanceBefore = alice.balance;

        // Create path for swapping fee-on-transfer token to native KUB
        address[] memory path = new address[](2);
        path[0] = address(launchToken);
        path[1] = address(weth);

        // Perform swap with supporting fee-on-transfer
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            SWAP_AMOUNT,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        // Verify alice received native KUB despite fee-on-transfer
        assertGt(alice.balance - aliceETHBalanceBefore, 0, "Should receive native KUB after fee-on-transfer");

        vm.stopPrank();
    }

// Tests behavior with very small amounts
    function testSmallAmountUnwrapping() public {
        vm.startPrank(alice);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(token0),
            INITIAL_LIQUIDITY_AMOUNT,
            0,
            0,
            alice,
            block.timestamp + 1
        );

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(weth);

        // Swap a very small amount
        uint256 tinyAmount = 1; // 1 wei of token0

        // Expect the appropriate error for amounts too small
        vm.expectRevert(abi.encodeWithSelector(IPonderRouter.InsufficientOutputAmount.selector));
        router.swapExactTokensForETH(
            tinyAmount,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        vm.stopPrank();
    }

// Tests direct unwrapping through MockKKUBUnwrapper
    function testDirectKKUBUnwrapping() public {
        vm.startPrank(alice);

        // Get KKUB tokens by depositing ETH
        weth.deposit{value: 1 ether}();

        // Approve the unwrapper to spend KKUB
        weth.approve(address(unwrapper), 1 ether);

        // Record balances before unwrap
        uint256 aliceETHBalanceBefore = alice.balance;
        uint256 aliceKKUBBalanceBefore = weth.balanceOf(alice);

        // Directly unwrap through the unwrapper
        unwrapper.unwrapKKUB(0.5 ether, alice);

        // Verify balances
        assertEq(weth.balanceOf(alice), aliceKKUBBalanceBefore - 0.5 ether, "Should spend KKUB");
        assertEq(alice.balance, aliceETHBalanceBefore + 0.5 ether, "Should receive exact ETH amount");

        vm.stopPrank();
    }
}
