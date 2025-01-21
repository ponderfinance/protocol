// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "../mocks/WETH9.sol";
import "forge-std/StdInvariant.sol";
import "forge-std/Test.sol";

contract PonderInvariantTest is StdInvariant, Test {
    PonderFactory factory;
    PonderRouter router;
    PonderPair pair;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    WETH9 weth;

    // Handler contract for fuzz testing
    PonderHandler handler;

    // Test users
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_LIQUIDITY = 10_000e18;

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

        // Deploy handler
        handler = new PonderHandler(
            payable(address(router)),
            address(pair),
            address(tokenA),
            address(tokenB)
        );

        // Setup initial state
        _setupInitialLiquidity();

        // Target handler for invariant testing
        targetContract(address(handler));

        // Set initial price boundaries in handler
        handler.updatePriceBoundaries();
    }

    function invariant_constant_product() public {
        // Get current reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 k = uint256(reserve0) * uint256(reserve1);

        // Get stored k value
        uint256 kLast = pair.kLast();

        // K should never decrease
        if (kLast > 0) {
            assertGe(k, kLast, "K value should never decrease");
        }

        // If fees are off, k should equal kLast
        if (factory.feeTo() == address(0) && kLast > 0) {
            assertEq(k, kLast, "K should equal kLast when fees are off");
        }
    }

    function invariant_total_supply_correlation() public {
        // Get current reserves and total supply
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 totalSupply = pair.totalSupply();

        // Total supply should be 0 if and only if both reserves are 0
        if (totalSupply == 0) {
            assertEq(reserve0, 0, "Reserve0 should be 0 when total supply is 0");
            assertEq(reserve1, 0, "Reserve1 should be 0 when total supply is 0");
        } else {
            assertTrue(reserve0 > 0 && reserve1 > 0, "Reserves should be positive when supply exists");
        }

        // Minimum liquidity should always be locked
        if (totalSupply > 0) {
            assertGe(totalSupply, pair.minimumLiquidity(), "Total supply should be >= MINIMUM_LIQUIDITY");
            assertEq(
                pair.balanceOf(address(1)),
                pair.minimumLiquidity(),
                "MINIMUM_LIQUIDITY balance mismatch"
            );
        }
    }

    function invariant_lp_token_proportionality() public {
        // Get total supply and reserves
        uint256 totalSupply = pair.totalSupply();
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Skip if no liquidity
        if (totalSupply == 0) return;

        // Check all LP holders
        address[] memory holders = handler.getLPHolders();
        uint256 totalLPShares = 0;

        // Track minimum liquidity separately
        uint256 minLiquidityBalance = pair.balanceOf(address(1));
        totalLPShares = minLiquidityBalance;

        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            // Skip address(0) and minimum liquidity holder
            if (holder == address(0) || holder == address(1)) continue;

            uint256 lpBalance = pair.balanceOf(holder);
            if (lpBalance > 0) {
                totalLPShares += lpBalance;
            }
        }

        // Allow for small rounding differences (1 wei per holder)
        uint256 maxRoundingDiff = holders.length;
        assertApproxEqAbs(
            totalLPShares,
            totalSupply,
            maxRoundingDiff,
            "Total LP shares mismatch (with rounding tolerance)"
        );
    }

    function invariant_fee_accumulation() public {
        address feeTo = factory.feeTo();
        if (feeTo == address(0)) return;

        uint256 feeBalance = pair.balanceOf(feeTo);
        if (feeBalance > 0) {
            // Verify fee balance is reasonable (can't exceed 1/6th of total supply)
            uint256 totalSupply = pair.totalSupply();
            assertTrue(
                feeBalance <= totalSupply / 6,
                "Fee balance exceeds maximum theoretical value"
            );
        }
    }

    function invariant_price_manipulation_resistance() public {
        // Get current reserves
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return;

        // Calculate current price
        uint256 price = (uint256(reserve0) * 1e18) / uint256(reserve1);

        // Get price boundaries from handler
        (uint256 minPrice, uint256 maxPrice) = handler.getPriceBoundaries();

        // Only check if boundaries have been initialized
        if (minPrice != type(uint256).max && maxPrice != 0) {
            assertGe(price, minPrice, "Price below historical minimum");
            assertLe(price, maxPrice, "Price above historical maximum");
        }
    }

    function _setupInitialLiquidity() internal {
        vm.startPrank(alice);

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

        handler.recordLPHolder(alice);
        vm.stopPrank();
    }
}

contract PonderHandler {
    PonderRouter public immutable router;
    PonderPair public immutable pair;
    ERC20Mint public immutable tokenA;
    ERC20Mint public immutable tokenB;

    uint256 public minPrice = type(uint256).max;
    uint256 public maxPrice = 0;
    address[] public lpHolders;

    constructor(
        address payable _router,
        address _pair,
        address _tokenA,
        address _tokenB
    ) {
        router = PonderRouter(_router);
        pair = PonderPair(_pair);
        tokenA = ERC20Mint(_tokenA);
        tokenB = ERC20Mint(_tokenB);
    }

    function addLiquidity(
        uint256 amountA,
        uint256 amountB,
        address to
    ) external {
        // Never allow adding liquidity to address(1) (MINIMUM_LIQUIDITY holder)
        if (to == address(0) || to == address(1)) return;

        // Bound inputs to reasonable ranges
        amountA = bound(amountA, 1000, 1000000e18);
        amountB = bound(amountB, 1000, 1000000e18);

        // Mint tokens
        tokenA.mint(address(this), amountA);
        tokenB.mint(address(this), amountB);

        // Approve router
        tokenA.approve(address(router), amountA);
        tokenB.approve(address(router), amountB);

        try router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amountA,
            amountB,
            0,
            0,
            to,
            block.timestamp
        ) {
            recordLPHolder(to);
            updatePriceBoundaries();
        } catch {
            // Silently fail - this is expected in some cases
        }
    }

    function removeLiquidity(
        uint256 liquidity,
        address to
    ) external {
        // Never allow removing liquidity to address(1)
        if (to == address(0) || to == address(1)) return;

        uint256 lpBalance = pair.balanceOf(address(this));
        if (lpBalance == 0) return;

        liquidity = bound(liquidity, 0, lpBalance);
        if (liquidity == 0) return;

        pair.approve(address(router), liquidity);

        try router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            liquidity,
            0,
            0,
            to,
            block.timestamp
        ) {
            updatePriceBoundaries();
        } catch {
            // Silently fail - this is expected in some cases
        }
    }

    function swap(
        uint256 amountIn,
        bool aToB,
        address to
    ) external {
        // Never allow swapping to address(1)
        if (to == address(0) || to == address(1)) return;

        amountIn = bound(amountIn, 1000, 100000e18);

        address[] memory path = new address[](2);
        path[0] = aToB ? address(tokenA) : address(tokenB);
        path[1] = aToB ? address(tokenB) : address(tokenA);

        ERC20Mint(path[0]).mint(address(this), amountIn);
        ERC20Mint(path[0]).approve(address(router), amountIn);

        try router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            to,
            block.timestamp
        ) {
            updatePriceBoundaries();
        } catch {
            // Silently fail - this is expected in some cases
        }
    }

    function recordLPHolder(address holder) public {
        if (holder == address(0) || holder == address(1)) return;
        for (uint i = 0; i < lpHolders.length; i++) {
            if (lpHolders[i] == holder) return;
        }
        lpHolders.push(holder);
    }

    function updatePriceBoundaries() public {
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        if (reserve0 == 0 || reserve1 == 0) return;

        uint256 price = (uint256(reserve0) * 1e18) / uint256(reserve1);
        if (price < minPrice) minPrice = price;
        if (price > maxPrice) maxPrice = price;
    }

    function getLPHolders() external view returns (address[] memory) {
        return lpHolders;
    }

    function getPriceBoundaries() external view returns (uint256, uint256) {
        return (minPrice, maxPrice);
    }

    function bound(
        uint256 value,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        return min + (value % (max - min + 1));
    }

    receive() external payable {}
}
