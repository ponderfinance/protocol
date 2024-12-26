// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/core/PonderPair.sol";
import "../../src/core/PonderToken.sol";
import "../../src/launch/LaunchToken.sol";
import "../../src/periphery/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";

contract MockKKUBUnwrapper {
    address public immutable WETH;

    constructor(address _weth) {
        WETH = _weth;
    }

    function unwrapKKUB(uint256 amount, address recipient) external returns (bool) {
        require(IERC20(WETH).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        IWETH(WETH).withdraw(amount);
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

        // Deploy WETH and PONDER
        weth = new WETH9();
        ponder = new PonderToken(treasury, treasury, treasury, ponderLauncher);

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

        // Check fee distributions
        uint256 creatorFee = launchToken.balanceOf(creator) - creatorBalanceBefore;
        uint256 protocolFee = launchToken.balanceOf(bob) - bobBalanceBefore;

        // For KUB pair: creator should get 0.1%, protocol should get 0.2%
        assertEq(creatorFee, sellAmount * 10 / 10000, "Incorrect creator fee");
        assertEq(protocolFee, sellAmount * 20 / 10000, "Incorrect protocol fee");

        vm.stopPrank();
    }
}
