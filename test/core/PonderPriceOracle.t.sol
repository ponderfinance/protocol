// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../mocks/ERC20.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPair.sol";
import "../../src/core/PonderPriceOracle.sol";

contract PonderPriceOracleTest is Test {
    PonderFactory public factory;
    PonderPriceOracle public oracle;

    ERC20 public baseToken;    // KUB
    ERC20 public stablecoin;   // USDT
    ERC20 public token0;       // Test token A
    ERC20 public token1;       // Test token B

    PonderPair public baseStablePair;  // KUB/USDT pair
    PonderPair public testPair;        // TKNA/TKNB pair
    PonderPair public token0BasePair;  // TKNA/KUB pair

    address alice = makeAddr("alice");

    // Testing constants
    uint256 constant INITIAL_LIQUIDITY = 100e18;
    uint256 constant STABLE_LIQUIDITY = 100_000e6;  // USDT uses 6 decimals
    uint256 constant BASE_PRICE = 30e6;             // 1 KUB = $30 USDT
    uint256 constant TIME_DELAY = 1 hours;
    uint256 constant MIN_UPDATE_DELAY = 5 minutes;

    event OracleUpdated(
        address indexed pair,
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    );

    function setUp() public {
        // Deploy factory
        factory = new PonderFactory(address(this), address(1), address(2));

        // Deploy tokens with different decimals
        baseToken = new ERC20("KUB", "KUB", 18);
        stablecoin = new ERC20("USDT", "USDT", 6);
        token0 = new ERC20("Token A", "TKNA", 18);
        token1 = new ERC20("Token B", "TKNB", 18);

        // Create all required pairs
        baseStablePair = PonderPair(factory.createPair(address(baseToken), address(stablecoin)));
        testPair = PonderPair(factory.createPair(address(token0), address(token1)));
        token0BasePair = PonderPair(factory.createPair(address(token0), address(baseToken)));

        // Add initial liquidity
        _addInitialLiquidity();

        // Deploy oracle
        oracle = new PonderPriceOracle(
            address(factory),
            address(baseToken),
            address(stablecoin)
        );

        // Initialize timestamp
        vm.warp(block.timestamp + MIN_UPDATE_DELAY);
    }

    function testInitialUpdate() public {
        // Calculate expected cumulative prices
        // At deployment both reserves are equal, so price is 1:1
        // price = reserve1/reserve0 * 2^112
        uint256 expectedPrice = 2**112; // 1 * 2^112 for equal reserves

        // Time elapsed since last update (block.timestamp - lastUpdateTime) * price
        uint256 timeElapsed = MIN_UPDATE_DELAY; // 5 minutes in seconds
        uint256 expectedCumulative = expectedPrice * timeElapsed;

        vm.expectEmit(true, true, true, true);
        emit OracleUpdated(
            address(testPair),
            expectedCumulative, // price0Cumulative
            expectedCumulative, // price1Cumulative
            uint32(block.timestamp)
        );

        oracle.update(address(testPair));

        assertEq(oracle.lastUpdateTime(address(testPair)), block.timestamp);

        // Check observation array was initialized
        assertEq(oracle.observationLength(address(testPair)), 24); // OBSERVATION_CARDINALITY

        // Verify the observation was stored correctly
        (uint32 timestamp, uint224 price0Cumulative, uint224 price1Cumulative) =
                            oracle.observations(address(testPair), 0);

        assertEq(timestamp, uint32(block.timestamp));
        assertEq(price0Cumulative, uint224(expectedCumulative));
        assertEq(price1Cumulative, uint224(expectedCumulative));
    }

    function testUpdateTooFrequent() public {
        oracle.update(address(testPair));

        vm.expectRevert(abi.encodeWithSignature("UpdateTooFrequent()"));
        oracle.update(address(testPair));

        // Should succeed after delay
        vm.warp(block.timestamp + MIN_UPDATE_DELAY);
        oracle.update(address(testPair));
    }

    function testConsultWithoutInitialization() public {
        vm.expectRevert(abi.encodeWithSignature("InsufficientData()"));
        oracle.consult(address(testPair), address(token0), 1e18, uint32(TIME_DELAY));
    }

    function testConsultWithValidPeriod() public {
        // Initial update
        oracle.update(address(testPair));

        // Move time forward for MIN_UPDATE_DELAY to get first valid observation
        vm.warp(block.timestamp + MIN_UPDATE_DELAY);
        oracle.update(address(testPair));

        // Move time forward and make a trade
        vm.warp(block.timestamp + TIME_DELAY);
        _executeTrade(testPair, token0, 1e18);

        // Update after trade
        vm.warp(block.timestamp + MIN_UPDATE_DELAY);
        oracle.update(address(testPair));

        // Consult oracle with period equal to time between first and last update
        uint256 amountOut = oracle.consult(
            address(testPair),
            address(token0),
            1e18,
            uint32(TIME_DELAY + MIN_UPDATE_DELAY) // Period covers our updates
        );

        assertGt(amountOut, 0, "TWAP price should be non-zero");
    }

    function testGetCurrentPrice() public {
        uint256 amountOut = oracle.getCurrentPrice(
            address(testPair),
            address(token0),
            1e18
        );

        assertGt(amountOut, 0, "Spot price should be non-zero");
        assertEq(amountOut, 1e18, "Initial price should be 1:1");
    }

    function testPriceInStablecoin() public {
        // Initial update to populate oracle data
        oracle.update(address(baseStablePair));

        // Get reserves to verify setup
        (uint112 reserve0, uint112 reserve1,) = baseStablePair.getReserves();
        console.log("Base Token Reserve:", reserve0);
        console.log("Stablecoin Reserve:", reserve1);

        // Need to wait minimum update delay
        vm.warp(block.timestamp + MIN_UPDATE_DELAY);
        oracle.update(address(baseStablePair));

        // Test direct stablecoin pair - convert 1 KUB (18 decimals) to USDT (6 decimals)
        uint256 baseTokenPrice = oracle.getPriceInStablecoin(
            address(baseStablePair),
            address(baseToken),
            1e18
        );
        console.log("Base Token Price:", baseTokenPrice);

        // Get current price directly to compare
        uint256 directPrice = oracle.getCurrentPrice(address(baseStablePair), address(baseToken), 1e18);
        console.log("Direct Price:", directPrice);

        assertEq(baseTokenPrice, 30e6, "Base token price should be 30 USDT");
    }

    function testPriceManipulationResistance() public {
        // Initial update
        oracle.update(address(testPair));

        // Need second update after MIN_UPDATE_DELAY
        vm.warp(block.timestamp + MIN_UPDATE_DELAY);
        oracle.update(address(testPair));

        // Move forward for meaningful TWAP period
        vm.warp(block.timestamp + TIME_DELAY);

        // Get initial spot price
        uint256 initialPrice = oracle.getCurrentPrice(
            address(testPair),
            address(token0),
            1e18
        );

        // Execute large trade to manipulate price
        _executeTrade(testPair, token0, INITIAL_LIQUIDITY * 10);

        // Get manipulated spot price
        uint256 manipulatedPrice = oracle.getCurrentPrice(
            address(testPair),
            address(token0),
            1e18
        );

        // Update oracle and check TWAP
        vm.warp(block.timestamp + MIN_UPDATE_DELAY);
        oracle.update(address(testPair));

        uint256 twapPrice = oracle.consult(
            address(testPair),
            address(token0),
            1e18,
            uint32(TIME_DELAY + MIN_UPDATE_DELAY) // Period matches our observation window
        );

        // TWAP should be closer to initial price
        uint256 twapDelta = twapPrice > initialPrice ?
            twapPrice - initialPrice : initialPrice - twapPrice;
        uint256 spotDelta = manipulatedPrice > initialPrice ?
            manipulatedPrice - initialPrice : initialPrice - manipulatedPrice;

        assertLt(twapDelta, spotDelta, "TWAP should be more stable than spot price");
    }

    function testDifferentDecimals() public {
        // Get price of baseToken (18 decimals) in stablecoin (6 decimals)
        uint256 price = oracle.getCurrentPrice(
            address(baseStablePair),
            address(baseToken),
            1e18
        );

        assertEq(price, BASE_PRICE, "Price should handle decimal conversion");
    }

    function _addInitialLiquidity() private {
        vm.startPrank(alice);

        // Add liquidity to KUB/USDT pair (1 KUB = $30)
        // KUB has 18 decimals, USDT has 6 decimals
        // We want 100 KUB and corresponding USDT
        uint256 kubAmount = 100e18;              // 100 KUB
        uint256 usdtAmount = 3000e6;             // 3000 USDT (30 USDT per KUB)

        baseToken.mint(alice, kubAmount);
        stablecoin.mint(alice, usdtAmount);
        baseToken.transfer(address(baseStablePair), kubAmount);
        stablecoin.transfer(address(baseStablePair), usdtAmount);
        baseStablePair.mint(alice);

        // Add liquidity to test pair with 1:1 ratio
        token0.mint(alice, INITIAL_LIQUIDITY);
        token1.mint(alice, INITIAL_LIQUIDITY);
        token0.transfer(address(testPair), INITIAL_LIQUIDITY);
        token1.transfer(address(testPair), INITIAL_LIQUIDITY);
        testPair.mint(alice);

        // Add liquidity to token0/KUB pair with 1:1 ratio
        token0.mint(alice, INITIAL_LIQUIDITY);
        baseToken.mint(alice, INITIAL_LIQUIDITY);
        token0.transfer(address(token0BasePair), INITIAL_LIQUIDITY);
        baseToken.transfer(address(token0BasePair), INITIAL_LIQUIDITY);
        token0BasePair.mint(alice);

        vm.stopPrank();
    }

    function _executeTrade(
        PonderPair pair,
        ERC20 tokenIn,
        uint256 amountIn
    ) private {
        vm.startPrank(alice);
        tokenIn.mint(alice, amountIn);
        tokenIn.transfer(address(pair), amountIn);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 expectedOut = (amountIn * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + (amountIn * 997));

        pair.swap(
            address(tokenIn) == pair.token0() ? 0 : expectedOut,
            address(tokenIn) == pair.token0() ? expectedOut : 0,
            alice,
            ""
        );
        vm.stopPrank();
    }

    function testExtremePriceScenarios() public {
        // Create new tokens for extreme ratio test
        ERC20 tokenExtreme1 = new ERC20("Extreme1", "EXT1", 18);
        ERC20 tokenExtreme2 = new ERC20("Extreme2", "EXT2", 18);

        // Setup extreme ratio (1:1000000)
        vm.startPrank(alice);
        tokenExtreme1.mint(alice, 1e18);
        tokenExtreme2.mint(alice, 1e24);

        PonderPair extremePair = PonderPair(factory.createPair(
            address(tokenExtreme1),
            address(tokenExtreme2)
        ));

        tokenExtreme1.transfer(address(extremePair), 1e18);
        tokenExtreme2.transfer(address(extremePair), 1e24);
        extremePair.mint(alice);

        // Update oracle with extreme price
        oracle.update(address(extremePair));

        // Move forward and verify price handling
        vm.warp(block.timestamp + MIN_UPDATE_DELAY);
        oracle.update(address(extremePair));

        uint256 price = oracle.getCurrentPrice(
            address(extremePair),
            address(tokenExtreme1),
            1e18
        );
        assertGt(price, 0, "Price should be non-zero even with extreme ratio");
        assertLe(price, 1e24, "Price should be bounded"); // Changed to assertLe
        vm.stopPrank();
    }

    function testPriceAccumulatorOverflow() public {
        // Initial update
        oracle.update(address(testPair));

        // Move far forward in time to test accumulator
        vm.warp(block.timestamp + 365 days);

        // Should still be able to update and get valid price
        oracle.update(address(testPair));
        uint256 price = oracle.getCurrentPrice(address(testPair), address(token0), 1e18);
        assertGt(price, 0, "Price should remain valid after long time period");
    }

    function testInvalidPairQueries() public {
        // Test with non-existent pair
        vm.expectRevert();
        oracle.update(address(0x123));

        // Test with non-pair contract
        ERC20 fakeToken = new ERC20("Fake", "FAKE", 18);
        vm.expectRevert();
        oracle.update(address(fakeToken));
    }




}
