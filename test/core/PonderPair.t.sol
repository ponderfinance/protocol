// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/pair/PonderPair.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/launch/LaunchToken.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";

contract MockRouter {
    address public immutable WETH;
    address public immutable factory;
    address public immutable unwrapper;

    constructor(address _factory, address _weth, address _unwrapper) {
        factory = _factory;
        WETH = _weth;
        unwrapper = _unwrapper;
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity) {
        // Simplified mock implementation
        IERC20(token).transferFrom(msg.sender, address(this), amountTokenDesired);
        return (amountTokenDesired, msg.value, 0);
    }

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        require(path[0] == WETH, "WETH must be first");

        // Mock output amounts
        uint[] memory output = new uint[](path.length);
        output[0] = msg.value;
        for(uint i = 1; i < path.length; i++) {
            output[i] = output[i-1] / 2;  // Mock 2:1 conversion rate
        }

        // Transfer last token in path to recipient
        uint256 outAmount = output[output.length - 1];
        IERC20(path[path.length - 1]).transfer(to, outAmount);

        return output;
    }

    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path.length >= 2, "Invalid path");
        require(path[path.length - 1] == WETH, "Invalid path end");

        // Simulate token transfer
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Mock output amounts
        uint[] memory output = new uint[](path.length);
        for (uint i = 0; i < path.length; i++) {
            output[i] = amountIn / (i + 1);
        }

        // Send ETH more safely
        uint256 ethToSend = amountIn / 2;
        require(address(this).balance >= ethToSend, "Insufficient ETH");
        (bool success,) = to.call{value: ethToSend}("");
        require(success, "ETH transfer failed");

        return output;
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts) {
        require(path.length >= 2, "Invalid path");

        // Simulate token transfer in
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

        // Simulate token transfer out
        uint amountOut = amountIn / 2;
        IERC20(path[path.length - 1]).transfer(to, amountOut);

        // Return mocked amounts
        uint[] memory output = new uint[](path.length);
        for (uint i = 0; i < path.length; i++) {
            output[i] = amountIn / (i + 1);
        }
        return output;
    }

    receive() external payable {}
}

contract MockKKUBUnwrapper {
    address public immutable WETH;

    constructor(address _weth) {
        WETH = _weth;
    }

    function unwrapKKUB(uint256 amount, address recipient) external returns (bool) {
        // Transfer WETH from sender to this contract
        require(IERC20(WETH).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        // Unwrap WETH for ETH
        IWETH(WETH).withdraw(amount);
        // Send ETH to recipient
        (bool success,) = recipient.call{value: amount}("");
        require(success, "ETH transfer failed");
        return true;
    }

    receive() external payable {}
}

contract MockFactory {
    address public feeTo;
    address public immutable launcher;
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

contract PonderPairTest is Test {
    PonderPair standardPair;
    PonderPair kubPair;
    PonderPair ponderPair;
    ERC20Mint token0;
    ERC20Mint token1;
    LaunchToken launchToken;
    PonderToken ponder;
    WETH9 weth;
    MockFactory factory;
    MockKKUBUnwrapper unwrapper; // Add unwrapper
    IPonderRouter router;  // Change from PonderRouter to IPonderRouter


    // Users for testing
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address creator = makeAddr("creator");
    address treasury = makeAddr("treasury");
    address ponderLauncher = makeAddr("ponderLaunchefr"); // New: separate launcher for PONDER
    address launcher = makeAddr("launcher");

    // Common amounts
    uint256 constant INITIAL_LIQUIDITY_AMOUNT = 10000e18;
    uint256 constant SWAP_AMOUNT = 1000e18;

    function setUp() public {
        launcher = makeAddr("launcher");

        // Deploy standard tokens
        token0 = new ERC20Mint("Token A", "TKNA");
        token1 = new ERC20Mint("Token B", "TKNB");
        if (address(token0) > address(token1)) {
            (token0, token1) = (token1, token0);
        }

        // Deploy WETH and PONDER
        weth = new WETH9();
        ponder = new PonderToken(treasury, treasury, ponderLauncher);

        // Set up mock factory
        factory = new MockFactory(bob, launcher, address(ponder));  // Use launcher instead of address(this)

        // Setup unwrapper and router using MockRouter instead of PonderRouter
        unwrapper = new MockKKUBUnwrapper(address(weth));
        MockRouter mockRouter = new MockRouter(
            address(factory),
            address(weth),
            address(unwrapper)
        );
        router = IPonderRouter(address(mockRouter));

        // Deploy LaunchToken
        launchToken = new LaunchToken(
            "Launch Token",
            "LAUNCH",
            launcher,
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Only do launcher init operations, NOT pair setup
        vm.startPrank(launcher);
        launchToken.setupVesting(creator, INITIAL_LIQUIDITY_AMOUNT);
        launchToken.enableTransfers();
        vm.stopPrank();

        // Create standard pair only
        address standardPairAddr = factory.createPair(address(token0), address(token1));
        standardPair = PonderPair(standardPairAddr);

        // Setup token approvals and balances
        token0.mint(alice, INITIAL_LIQUIDITY_AMOUNT * 2);
        token1.mint(alice, INITIAL_LIQUIDITY_AMOUNT * 2);
        deal(address(launchToken), alice, INITIAL_LIQUIDITY_AMOUNT * 2);
        deal(address(weth), alice, INITIAL_LIQUIDITY_AMOUNT * 2);
        deal(address(ponder), alice, INITIAL_LIQUIDITY_AMOUNT * 2);

        vm.startPrank(alice);
        token0.approve(address(standardPair), type(uint256).max);
        token1.approve(address(standardPair), type(uint256).max);
        vm.stopPrank();

        // Setup router with some initial balances
        vm.deal(address(router), 100 ether);
        deal(address(token0), address(router), INITIAL_LIQUIDITY_AMOUNT);
        deal(address(token1), address(router), INITIAL_LIQUIDITY_AMOUNT);
        deal(address(ponder), address(router), INITIAL_LIQUIDITY_AMOUNT);
        deal(address(launchToken), address(router), INITIAL_LIQUIDITY_AMOUNT);
    }

    function testStandardSwap() public {
        addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);

        vm.startPrank(alice);
        token0.transfer(address(standardPair), SWAP_AMOUNT);
        standardPair.swap(0, 900e18, alice, "");
        vm.stopPrank();

        console.log("Standard swap:");
        console.log("token0 address:", address(token0));
        console.log("token1 address:", address(token1));
        console.log("Pair token0:", standardPair.token0());
        console.log("Pair token1:", standardPair.token1());

        assertGt(token1.balanceOf(alice), 0, "Should have received token1");
        (uint112 reserve0, uint112 reserve1,) = standardPair.getReserves();
        assertGt(reserve0, INITIAL_LIQUIDITY_AMOUNT, "Reserve0 should have increased");
        assertLt(reserve1, INITIAL_LIQUIDITY_AMOUNT, "Reserve1 should have decreased");
    }

    function testBurnComplete() public {
        // Get initial state
        uint256 initialBalance0 = token0.balanceOf(alice);
        uint256 initialBalance1 = token1.balanceOf(alice);

        // Add liquidity with INITIAL_LIQUIDITY_AMOUNT
        uint256 initialLiquidity = addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);

        // Burn all liquidity
        vm.startPrank(alice);
        standardPair.transfer(address(standardPair), initialLiquidity);
        standardPair.burn(alice);
        vm.stopPrank();

        // Verify results
        assertEq(standardPair.balanceOf(alice), 0, "Should have no LP tokens");
        uint256 minLiquidity = standardPair.MINIMUM_LIQUIDITY();

        // Compare final balance with initial balance
        assertEq(
            token0.balanceOf(alice) - (initialBalance0 - INITIAL_LIQUIDITY_AMOUNT),
            INITIAL_LIQUIDITY_AMOUNT - minLiquidity,
            "Should have received all token0 minus MINIMUM_LIQUIDITY"
        );
        assertEq(
            token1.balanceOf(alice) - (initialBalance1 - INITIAL_LIQUIDITY_AMOUNT),
            INITIAL_LIQUIDITY_AMOUNT - minLiquidity,
            "Should have received all token1 minus MINIMUM_LIQUIDITY"
        );
    }

    function addInitialLiquidity(
        PonderPair pair,
        IERC20 tokenA,
        IERC20 tokenB,
        uint256 amount
    ) internal returns (uint256 liquidity) {
        vm.startPrank(alice);
        tokenA.transfer(address(pair), amount);
        tokenB.transfer(address(pair), amount);
        liquidity = pair.mint(alice);
        vm.stopPrank();

        return liquidity;
    }

    function testFailSwapInsufficientLiquidity() public {
        vm.startPrank(alice);
        token0.transfer(address(standardPair), SWAP_AMOUNT);
        standardPair.swap(0, SWAP_AMOUNT, alice, "");
        vm.stopPrank();
    }

    function testBurnPartial() public {
        uint256 initialLiquidity = addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);
        uint256 burnAmount = initialLiquidity / 2;

        vm.startPrank(alice);
        standardPair.transfer(address(standardPair), burnAmount);
        standardPair.burn(alice);
        vm.stopPrank();

        assertEq(standardPair.balanceOf(alice), burnAmount, "Should have half LP tokens remaining");
    }

    function testFailBurnInsufficientLiquidity() public {
        vm.startPrank(alice);
        standardPair.burn(alice);
        vm.stopPrank();
    }

    function testSync() public {
        addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);

        uint256 extraAmount = 1000e18;
        token0.mint(address(standardPair), extraAmount);
        token1.mint(address(standardPair), extraAmount);

        standardPair.sync();

        (uint112 reserve0, uint112 reserve1,) = standardPair.getReserves();
        assertEq(reserve0, INITIAL_LIQUIDITY_AMOUNT + extraAmount, "Reserve0 not synced");
        assertEq(reserve1, INITIAL_LIQUIDITY_AMOUNT + extraAmount, "Reserve1 not synced");
    }

    function testSkim() public {
        addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);

        uint256 extraAmount = 1000e18;
        token0.mint(address(standardPair), extraAmount);
        token1.mint(address(standardPair), extraAmount);

        uint256 aliceBalance0Before = token0.balanceOf(alice);
        uint256 aliceBalance1Before = token1.balanceOf(alice);

        standardPair.skim(alice);

        assertEq(
            token0.balanceOf(alice) - aliceBalance0Before,
            extraAmount,
            "Incorrect token0 skim amount"
        );
        assertEq(
            token1.balanceOf(alice) - aliceBalance1Before,
            extraAmount,
            "Incorrect token1 skim amount"
        );
    }

    function testStandardFeeCollection() public {
        addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);

        vm.startPrank(alice);
        token0.transfer(address(standardPair), SWAP_AMOUNT);
        standardPair.swap(0, 900e18, alice, "");
        vm.stopPrank();

        token0.mint(alice, INITIAL_LIQUIDITY_AMOUNT);
        token1.mint(alice, INITIAL_LIQUIDITY_AMOUNT);

        vm.startPrank(alice);
        token0.transfer(address(standardPair), INITIAL_LIQUIDITY_AMOUNT);
        token1.transfer(address(standardPair), INITIAL_LIQUIDITY_AMOUNT);
        standardPair.mint(alice);
        vm.stopPrank();

        assertGt(standardPair.balanceOf(bob), 0, "Should have collected fees");
    }

    function testKValueValidation() public {
        // Setup pair with initial liquidity
        uint256 initialLiquidity = addInitialLiquidity(
            standardPair,
            token0,
            token1,
            INITIAL_LIQUIDITY_AMOUNT
        );

        // Get initial K value
        (uint112 reserve0, uint112 reserve1,) = standardPair.getReserves();
        uint256 initialK = uint256(reserve0) * uint256(reserve1);

        // Perform actual swap
        vm.startPrank(alice);
        token0.transfer(address(standardPair), SWAP_AMOUNT);
        standardPair.swap(0, SWAP_AMOUNT / 2, alice, "");
        vm.stopPrank();

        // Check K value hasn't decreased
        (reserve0, reserve1,) = standardPair.getReserves();
        uint256 newK = uint256(reserve0) * uint256(reserve1);
        assertGe(newK, initialK, "K value should not decrease");
    }



    function testActualSwapWithFees() public {
        // First create and setup the pairs
        address launchKubPair = factory.createPair(address(launchToken), address(weth));
        vm.startPrank(launcher);
        launchToken.setPairs(launchKubPair, address(0));
        launchToken.enableTransfers();
        vm.stopPrank();

        addInitialLiquidity(
            PonderPair(launchKubPair),
            IERC20(address(launchToken)),
            IERC20(address(weth)),
            INITIAL_LIQUIDITY_AMOUNT
        );

        uint256 aliceWethBefore = weth.balanceOf(alice);
        uint256 protocolBalanceBefore = launchToken.balanceOf(bob);
        uint256 creatorBalanceBefore = launchToken.balanceOf(creator);

        vm.startPrank(alice);
        launchToken.transfer(launchKubPair, SWAP_AMOUNT);
        PonderPair(launchKubPair).swap(0, SWAP_AMOUNT/2, alice, "");
        PonderPair(launchKubPair).skim(bob);
        vm.stopPrank();

        assertGt(weth.balanceOf(alice), aliceWethBefore, "Should have received WETH");
        assertGt(
            launchToken.balanceOf(bob) - protocolBalanceBefore,
            0,
            "Protocol should have received fees"
        );
        assertGt(
            launchToken.balanceOf(creator) - creatorBalanceBefore,
            0,
            "Creator should have received fees"
        );
    }

    function testKubPairFees() public {
        // Create and setup pairs
        address launchKubPair = factory.createPair(address(launchToken), address(weth));

        vm.startPrank(launcher);
        launchToken.setPairs(launchKubPair, address(0));
        launchToken.enableTransfers();
        vm.stopPrank();

        // Add initial liquidity
        addInitialLiquidity(
            PonderPair(launchKubPair),
            IERC20(address(launchToken)),
            IERC20(address(weth)),
            INITIAL_LIQUIDITY_AMOUNT
        );

        uint256 creatorBalanceBefore = launchToken.balanceOf(creator);
        uint256 protocolBalanceBefore = launchToken.balanceOf(bob);

        // Execute swap and skim fees
        vm.startPrank(alice);
        launchToken.transfer(launchKubPair, SWAP_AMOUNT);
        PonderPair(launchKubPair).swap(0, SWAP_AMOUNT/2, alice, "");
        vm.stopPrank();

        // Need to call skim as protocol feeTo address
        vm.prank(bob);
        PonderPair(launchKubPair).skim(bob);

        // Calculate expected fees for KUB pair
        uint256 expectedProtocolFee = (SWAP_AMOUNT * 4) / 10000;  // 0.04%
        uint256 expectedCreatorFee = (SWAP_AMOUNT * 1) / 10000;   // 0.01%

        assertEq(
            launchToken.balanceOf(creator) - creatorBalanceBefore,
            expectedCreatorFee,
            "Incorrect creator fee for KUB pair"
        );
        assertEq(
            launchToken.balanceOf(bob) - protocolBalanceBefore,
            expectedProtocolFee,
            "Incorrect protocol fee for KUB pair"
        );
    }

    function testFuzz_KValueMaintained(uint256 swapAmount) public {
        // Bound swap amount to reasonable values
        swapAmount = bound(
            swapAmount,
            INITIAL_LIQUIDITY_AMOUNT / 100,  // 1% of liquidity
            INITIAL_LIQUIDITY_AMOUNT / 2     // 50% of liquidity
        );

        // Add initial liquidity to standard pair
        addInitialLiquidity(
            standardPair,
            token0,
            token1,
            INITIAL_LIQUIDITY_AMOUNT
        );

        // Store initial reserves
        (uint112 initialReserve0, uint112 initialReserve1,) = standardPair.getReserves();
        uint256 initialK = uint256(initialReserve0) * uint256(initialReserve1);

        // Ensure alice has enough tokens
        token0.mint(alice, swapAmount);

        // Perform swap with fuzzed amount
        vm.startPrank(alice);
        token0.transfer(address(standardPair), swapAmount);
        standardPair.swap(0, swapAmount/2, alice, "");
        vm.stopPrank();

        // Get final reserves
        (uint112 finalReserve0, uint112 finalReserve1,) = standardPair.getReserves();
        uint256 finalK = uint256(finalReserve0) * uint256(finalReserve1);

        // Verify K value hasn't decreased
        assertGe(finalK, initialK, "K should never decrease");

        // Additional validations
        assertGt(token1.balanceOf(alice), 0, "Should have received tokens");
        assertGt(finalReserve0, initialReserve0, "Reserve0 should have increased");
        assertLt(finalReserve1, initialReserve1, "Reserve1 should have decreased");
    }

    function testPonderToTokenSwaps() public {
        // Create pair
        address ponderToken0Pair = factory.createPair(address(ponder), address(token0));
        PonderPair pair = PonderPair(ponderToken0Pair);

        vm.startPrank(alice);

        // Add liquidity
        ponder.transfer(address(pair), INITIAL_LIQUIDITY_AMOUNT);
        token0.transfer(address(pair), INITIAL_LIQUIDITY_AMOUNT);
        pair.mint(alice);

        // Approve tokens
        ponder.approve(address(router), type(uint256).max);
        token0.approve(address(router), type(uint256).max);

        // Record state
        uint256 token0BalanceBefore = token0.balanceOf(alice);
        uint256 feeToBefore = ponder.balanceOf(bob);

        // Set up path for "I want to swap PONDER for token0"
        address[] memory path = new address[](2);
        path[0] = address(ponder);  // Input token
        path[1] = address(token0);  // Output token

        // Execute swap
        router.swapExactTokensForTokens(
            SWAP_AMOUNT,
            0,
            path,
            alice,
            block.timestamp + 1
        );

        // Verify results
        assertGt(
            token0.balanceOf(alice) - token0BalanceBefore,
            0,
            "Should receive token0"
        );

        vm.stopPrank();
    }

    function testPonderToETHSwap() public {
        // Create PONDER/WETH pair
        address ponderKubPair = factory.createPair(address(ponder), address(weth));

        vm.startPrank(alice);

        // Add initial liquidity
        ponder.transfer(ponderKubPair, INITIAL_LIQUIDITY_AMOUNT);

        // Fund alice with ETH first instead of funding contract
        vm.deal(alice, INITIAL_LIQUIDITY_AMOUNT);
        weth.deposit{value: INITIAL_LIQUIDITY_AMOUNT}();
        weth.transfer(ponderKubPair, INITIAL_LIQUIDITY_AMOUNT);
        PonderPair(ponderKubPair).mint(alice);

        // Record initial balances
        uint256 feeToBefore = ponder.balanceOf(bob);
        uint256 ethBalanceBefore = address(alice).balance;

        // Execute swap
        ponder.transfer(ponderKubPair, SWAP_AMOUNT);
        PonderPair(ponderKubPair).swap(0, SWAP_AMOUNT/2, alice, "");

        // Need to withdraw WETH to ETH
        uint256 wethBalance = weth.balanceOf(alice);
        vm.deal(address(weth), wethBalance); // Ensure WETH contract has enough ETH
        weth.withdraw(wethBalance);

        vm.stopPrank();

        // Call skim as protocol feeTo
        vm.prank(bob);
        PonderPair(ponderKubPair).skim(bob);

        assertGt(address(alice).balance - ethBalanceBefore, 0, "Should receive ETH");

        // Check 0.05% protocol fee
        uint256 expectedProtocolFee = (SWAP_AMOUNT * 5) / 10000;
        assertEq(
            ponder.balanceOf(bob) - feeToBefore,
            expectedProtocolFee,
            "Should take 0.05% protocol fee when selling PONDER to ETH"
        );
    }

    function testDetailedFeeCalculations() public {
        // Test with standard pair first
        address standardPair = factory.createPair(address(token0), address(token1));
        PonderPair standardPairContract = PonderPair(standardPair);

        // Deploy launch token
        LaunchToken launchToken = new LaunchToken(
            "Test Token",
            "TEST",
            launcher,  // Use the same launcher address
            address(factory),
            payable(address(router)),
            address(ponder)
        );

        // Create pairs and set them
        address launchKubPair = factory.createPair(address(launchToken), address(weth));
        address launchPonderPair = factory.createPair(address(launchToken), address(ponder));
        PonderPair kubPairContract = PonderPair(launchKubPair);
        PonderPair ponderPairContract = PonderPair(launchPonderPair);

        // Setup launch token
        vm.startPrank(launcher);  // Start impersonating launcher
        launchToken.setupVesting(creator, 1000e18);
        launchToken.setPairs(launchKubPair, launchPonderPair);
        launchToken.enableTransfers();
        vm.stopPrank();  // Stop impersonating launcher

        uint256 swapAmount = SWAP_AMOUNT;
        uint256 FEE_DENOMINATOR = 10000;

        // Test PONDER pair fees
        {
            // Give fresh allocation for PONDER pair testing
            deal(address(launchToken), alice, swapAmount * 4);
            ponder.setMinter(address(this));
            ponder.mint(alice, swapAmount * 4);

            vm.startPrank(alice);
            ponder.approve(address(launchPonderPair), type(uint256).max);

            // Add initial liquidity
            launchToken.transfer(launchPonderPair, swapAmount * 2);
            ponder.transfer(launchPonderPair, swapAmount * 2);
            PonderPair(launchPonderPair).mint(alice);

            // Record balances before swap
            uint256 creatorBalanceBefore = launchToken.balanceOf(creator);
            uint256 feeCollectorBalanceBefore = launchToken.balanceOf(bob);

            // Perform swap - selling launch token
            launchToken.transfer(launchPonderPair, swapAmount);
            uint256 expectedOutput = (swapAmount * 997) / 1000;
            PonderPair(launchPonderPair).swap(0, expectedOutput / 2, alice, "");

            // Call skim to collect protocol fees
            PonderPair(launchPonderPair).skim(bob);

            // Creator should get 0.04%, protocol should get 0.01%
            uint256 expectedCreatorFee = (swapAmount * 4) / FEE_DENOMINATOR;
            uint256 expectedProtocolFee = (swapAmount * 1) / FEE_DENOMINATOR;

            assertEq(
                launchToken.balanceOf(creator) - creatorBalanceBefore,
                expectedCreatorFee,
                "Incorrect creator fee for PONDER pair"
            );
            assertEq(
                launchToken.balanceOf(bob) - feeCollectorBalanceBefore,
                expectedProtocolFee,
                "Incorrect protocol fee for PONDER pair"
            );

            vm.stopPrank();
        }

        // Test KUB pair fees
        {
            // Give fresh allocation
            deal(address(launchToken), alice, swapAmount * 4);
            deal(address(weth), alice, swapAmount * 4);

            vm.startPrank(alice);

            // Add initial liquidity
            launchToken.transfer(launchKubPair, swapAmount * 2);
            weth.transfer(launchKubPair, swapAmount * 2);
            PonderPair(launchKubPair).mint(alice);

            // Record balances before swap
            uint256 creatorBalanceBefore = launchToken.balanceOf(creator);
            uint256 feeCollectorBalanceBefore = launchToken.balanceOf(bob);

            // Perform swap - selling launch token
            launchToken.transfer(launchKubPair, swapAmount);
            uint256 expectedOutput = (swapAmount * 997) / 1000;
            PonderPair(launchKubPair).swap(0, expectedOutput / 2, alice, "");

            // Call skim to collect protocol fees
            PonderPair(launchKubPair).skim(bob);

            // Creator should get 0.01%, protocol should get 0.04%
            uint256 expectedCreatorFee = (swapAmount * 1) / FEE_DENOMINATOR;
            uint256 expectedProtocolFee = (swapAmount * 4) / FEE_DENOMINATOR;

            assertEq(
                launchToken.balanceOf(creator) - creatorBalanceBefore,
                expectedCreatorFee,
                "Incorrect creator fee for KUB pair"
            );
            assertEq(
                launchToken.balanceOf(bob) - feeCollectorBalanceBefore,
                expectedProtocolFee,
                "Incorrect protocol fee for KUB pair"
            );

            vm.stopPrank();
        }
    }

    function testETHToLaunchTokenSwap() public {
        // Create launch token/WETH pair
        address launchKubPair = factory.createPair(address(launchToken), address(weth));

        // Fund alice
        vm.deal(alice, INITIAL_LIQUIDITY_AMOUNT * 2);

        // Add liquidity
        vm.startPrank(alice);

        // Add WETH side
        weth.deposit{value: INITIAL_LIQUIDITY_AMOUNT}();
        weth.transfer(address(launchKubPair), INITIAL_LIQUIDITY_AMOUNT);

        // Add launch token side
        launchToken.transfer(address(launchKubPair), INITIAL_LIQUIDITY_AMOUNT);
        PonderPair(launchKubPair).mint(alice);

        // Record initial balances
        uint256 launchTokenBalanceBefore = launchToken.balanceOf(alice);

        // Calculate expected output accounting for 0.3% fee
        uint256 swapAmount = 1 ether;
        uint256 expectedOutput = (swapAmount * 997) / 1000;

        // Perform swap
        weth.deposit{value: swapAmount}();
        weth.transfer(address(launchKubPair), swapAmount);
        PonderPair(launchKubPair).swap(expectedOutput / 2, 0, alice, "");

        // Verify swap succeeded
        assertGt(launchToken.balanceOf(alice) - launchTokenBalanceBefore, 0, "Should have received launch tokens");

        vm.stopPrank();
    }

    function testETHToLaunchTokenViaRouter() public {
        // Create launch token/WETH pair
        address launchKubPair = factory.createPair(address(launchToken), address(weth));

        // Enable trading first
        vm.startPrank(launcher);
        launchToken.setPairs(launchKubPair, address(0));
        launchToken.enableTransfers();
        vm.stopPrank();

        // Fund alice with both ETH and launch tokens
        vm.deal(alice, INITIAL_LIQUIDITY_AMOUNT * 2);
        deal(address(launchToken), alice, INITIAL_LIQUIDITY_AMOUNT * 2);

        vm.startPrank(alice);

        // Approve tokens
        launchToken.approve(address(router), type(uint256).max);

        // Add liquidity with ETH
        router.addLiquidityETH{value: INITIAL_LIQUIDITY_AMOUNT}(
            address(launchToken),
            INITIAL_LIQUIDITY_AMOUNT,
            0,  // Allow any slippage for test
            0,  // Allow any slippage for test
            alice,
            block.timestamp + 1
        );

        // Record balance before swap
        uint256 balanceBefore = launchToken.balanceOf(alice);

        // Try swap
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(launchToken);

        // Mock router needs ETH value exactly half of input for test
        uint256 swapAmount = 1 ether;
        router.swapExactETHForTokens{value: swapAmount}(
            0, // Accept any amount of tokens
            path,
            alice,
            block.timestamp + 1
        );

        // Verify received tokens
        assertGt(
            launchToken.balanceOf(alice),
            balanceBefore,
            "Should have received launch tokens"
        );

        vm.stopPrank();
    }

    function testMintInitialLiquidity() public {
        // Case 1: Insufficient initial liquidity - should revert
        vm.startPrank(alice);
        token0.transfer(address(standardPair), 500);  // Less than required 1000 units
        token1.transfer(address(standardPair), 500);
        vm.expectRevert("Insufficient initial liquidity");
        standardPair.mint(alice);
        vm.stopPrank();

        // Case 2: Sufficient initial liquidity - should succeed
        vm.startPrank(alice);
        token0.transfer(address(standardPair), 1000);  // Exactly 1000 units
        token1.transfer(address(standardPair), 1000);
        uint256 liquidity = standardPair.mint(alice);
        vm.stopPrank();

        // Validate that LP tokens were minted correctly
        assertGt(liquidity, 0, "Liquidity should be greater than zero");
        assertEq(standardPair.balanceOf(alice), liquidity, "Alice should receive LP tokens");
    }

    function testFlashLoanManipulationResistance() public {
        // Add initial liquidity to the pair
        addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);

        // Move time forward slightly and sync to initialize price accumulators
        vm.warp(block.timestamp + 10);
        standardPair.sync();

        // Record initial state after sync
        (uint112 reserve0Before, uint112 reserve1Before, uint32 timestampBefore) = standardPair.getReserves();
        uint256 initialK = uint256(reserve0Before) * uint256(reserve1Before);
        uint256 price0CumBefore = standardPair.price0CumulativeLast();
        uint256 price1CumBefore = standardPair.price1CumulativeLast();

        // Perform flash loan-like swap (1% of reserves)
        uint256 swapSize = INITIAL_LIQUIDITY_AMOUNT / 100;
        vm.startPrank(alice);
        token0.transfer(address(standardPair), swapSize);

        // Calculate expected output with 0.3% fee
        uint256 expectedOutput = (swapSize * 997 * uint256(reserve1Before)) /
            (uint256(reserve0Before) * 1000 + (swapSize * 997));
        standardPair.swap(0, expectedOutput, alice, "");
        vm.stopPrank();

        // Move time forward and sync
        vm.warp(block.timestamp + 10);
        standardPair.sync();

        // Get final state
        (uint112 reserve0After, uint112 reserve1After,) = standardPair.getReserves();
        uint256 finalK = uint256(reserve0After) * uint256(reserve1After);

        // Verify K value hasn't decreased
        assertGe(finalK, initialK, "K value should not decrease");

        // Calculate reserve-based price impact
        uint256 initialPrice = (uint256(reserve1Before) * 1e18) / reserve0Before;
        uint256 finalPrice = (uint256(reserve1After) * 1e18) / reserve0After;

        // Calculate absolute price change as percentage
        uint256 priceChange;
        if (finalPrice > initialPrice) {
            priceChange = ((finalPrice - initialPrice) * 100) / initialPrice;
        } else {
            priceChange = ((initialPrice - finalPrice) * 100) / initialPrice;
        }

        // Price impact from 1% flash loan should be less than 2%
        uint256 maxAllowedPriceImpact = 2;
        assertLe(priceChange, maxAllowedPriceImpact, "Flash loan price impact too high");
    }

    function testSustainedManipulationResistance() public {
        // Add initial liquidity to the pair
        addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);

        // Record initial cumulative prices
        (uint256 price0CumulativeStart, uint256 price1CumulativeStart, uint32 blockTimestampStart) = standardPair.getReserves();

        // Simulate time passing (sustained manipulation period)
        vm.warp(block.timestamp + 3600); // Fast forward 1 hour

        // Perform multiple swaps during sustained manipulation period
        vm.startPrank(alice);
        for (uint256 i = 0; i < 5; i++) {
            token0.transfer(address(standardPair), SWAP_AMOUNT / 5);
            standardPair.swap(0, SWAP_AMOUNT / 10, alice, "");
        }
        vm.stopPrank();

        // Capture the new cumulative prices
        (uint256 price0CumulativeEnd, uint256 price1CumulativeEnd, uint32 blockTimestampEnd) = standardPair.getReserves();

        // Assert TWAP is correctly updated without significant skew
        uint32 timeElapsed = blockTimestampEnd - blockTimestampStart;
        uint256 price0TWAP = (price0CumulativeEnd - price0CumulativeStart) / timeElapsed;
        assertGt(price0TWAP, 0, "TWAP for token0 should increase appropriately");
    }

    function testTWAPCalculationAccuracy() public {
        // Add initial liquidity to the pair
        addInitialLiquidity(standardPair, token0, token1, INITIAL_LIQUIDITY_AMOUNT);

        // Record initial cumulative prices
        (uint256 price0CumulativeStart, uint256 price1CumulativeStart, uint32 blockTimestampStart) = standardPair.getReserves();

        // Wait for a specific period (simulate normal time progression)
        vm.warp(block.timestamp + 600); // Fast forward 10 minutes

        // Perform a swap to trigger price update
        vm.startPrank(alice);
        token0.transfer(address(standardPair), SWAP_AMOUNT);
        standardPair.swap(0, SWAP_AMOUNT / 2, alice, "");
        vm.stopPrank();

        // Capture the final cumulative prices
        (uint256 price0CumulativeEnd, uint256 price1CumulativeEnd, uint32 blockTimestampEnd) = standardPair.getReserves();

        // Calculate TWAP for token0 -> token1
        uint32 timeElapsed = blockTimestampEnd - blockTimestampStart;
        uint256 price0TWAP = (price0CumulativeEnd - price0CumulativeStart) / timeElapsed;

        // Assert TWAP is correctly calculated and greater than zero
        assertGt(price0TWAP, 0, "TWAP for token0 should be correctly calculated");
    }
}
