// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/libraries/PonderLaunchGuard.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPair.sol";
import "../../src/core/PonderPriceOracle.sol";
import "../mocks/ERC20.sol";

contract PonderLaunchGuardTest is Test {
    using PonderLaunchGuard for *;

    PonderFactory factory;
    PonderPriceOracle oracle;
    ERC20 ponder;
    ERC20 weth;
    PonderPair pair;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_LIQUIDITY = 10000 ether;
    uint256 constant TARGET_RAISE = 5555 ether;

    function setUp() public {
        // Deploy tokens
        ponder = new ERC20("PONDER", "PONDER", 18);
        weth = new ERC20("WETH", "WETH", 18);

        // Deploy factory
        factory = new PonderFactory(address(this), address(this), address(1));

        // Create PONDER/WETH pair
        address pairAddress = factory.createPair(address(ponder), address(weth));
        pair = PonderPair(pairAddress);

        // Create oracle with WETH as base token
        oracle = new PonderPriceOracle(
            address(factory),
            address(weth),    // Use WETH as the base token
            address(0)        // No stablecoin needed for tests
        );

        // Set initial timestamp for consistent testing
        vm.warp(1000000);

        // Setup initial liquidity
        _setupInitialLiquidity();

        // Initialize oracle with proper history
        _initializeOracleHistory();
    }

    function testValidPonderContribution() public {
        uint256 amount = 10 ether;

        PonderLaunchGuard.ValidationResult memory result = PonderLaunchGuard.validatePonderContribution(
            address(pair),
            address(oracle),
            amount
        );

        assertGt(result.kubValue, 0, "KUB value should be non-zero");
        assertLt(result.priceImpact, PonderLaunchGuard.MAX_PRICE_IMPACT, "Price impact should be within limits");
        assertEq(result.maxPonderPercent, PonderLaunchGuard.MAX_PONDER_PERCENT, "Should return max percent");
    }

    function testInsufficientLiquidity() public {
        // Remove all liquidity
        _removeLiquidity();

        // Add small delay and sync
        vm.warp(block.timestamp + 5 minutes);
        pair.sync();
        oracle.update(address(pair));

        vm.expectRevert(PonderLaunchGuard.InsufficientLiquidity.selector);
        PonderLaunchGuard.validatePonderContribution(
            address(pair),
            address(oracle),
            100 ether
        );
    }

    function testExcessivePriceImpact() public {
        uint256 largeAmount = INITIAL_LIQUIDITY * 10;

        bytes4 selector = bytes4(keccak256("ExcessivePriceImpact()"));
        vm.expectRevert(selector);

        PonderLaunchGuard.validatePonderContribution(
            address(pair),
            address(oracle),
            largeAmount
        );
    }

    function calculateExpectedCap(uint256 liquidity) public pure returns (uint256) {
        if (liquidity >= PonderLaunchGuard.MAX_LIQUIDITY) {
            return PonderLaunchGuard.MAX_PONDER_PERCENT;
        }

        if (liquidity <= PonderLaunchGuard.MIN_LIQUIDITY) {
            return PonderLaunchGuard.MIN_PONDER_PERCENT;
        }

        uint256 range = PonderLaunchGuard.MAX_LIQUIDITY - PonderLaunchGuard.MIN_LIQUIDITY;
        uint256 excess = liquidity - PonderLaunchGuard.MIN_LIQUIDITY;
        uint256 percentRange = PonderLaunchGuard.MAX_PONDER_PERCENT - PonderLaunchGuard.MIN_PONDER_PERCENT;

        return PonderLaunchGuard.MIN_PONDER_PERCENT + (excess * percentRange) / range;
    }

    function _setupInitialLiquidity() internal {
        vm.startPrank(alice);
        ponder.mint(alice, INITIAL_LIQUIDITY);
        weth.mint(alice, INITIAL_LIQUIDITY);

        ponder.transfer(address(pair), INITIAL_LIQUIDITY);
        weth.transfer(address(pair), INITIAL_LIQUIDITY);

        pair.mint(alice);
        vm.stopPrank();
    }

    function _setupLiquidity(uint256 amount) internal {
        vm.startPrank(alice);
        ponder.mint(alice, amount);
        weth.mint(alice, amount);

        ponder.transfer(address(pair), amount);
        weth.transfer(address(pair), amount);

        pair.mint(alice);
        vm.stopPrank();
    }

    function _removeLiquidity() internal {
        vm.startPrank(alice);
        uint256 lpBalance = pair.balanceOf(alice);
        if (lpBalance > 0) {
            pair.transfer(address(pair), lpBalance);
            pair.burn(alice);
        }
        vm.stopPrank();
    }

    function _initializeOracleHistory() internal {
        // Initial oracle update
        pair.sync();
        oracle.update(address(pair));

        // Build required history for TWAP period
        for (uint i = 0; i < 6; i++) {
            // Wait exactly oracle's minimum delay
            vm.warp(block.timestamp + oracle.MIN_UPDATE_DELAY());
            pair.sync();
            oracle.update(address(pair));
        }

        // Ensure we have gap for next update
        vm.warp(block.timestamp + oracle.MIN_UPDATE_DELAY());
    }
}
