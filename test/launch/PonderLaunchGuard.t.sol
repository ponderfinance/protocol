// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/libraries/PonderLaunchGuard.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/core/PonderPriceOracle.sol";
import "../mocks/ERC20Mock.sol";

contract PonderLaunchGuardSecurityTest is Test {
    using PonderLaunchGuard for *;

    PonderFactory factory;
    PonderPriceOracle oracle;
    ERC20Mock ponder;
    ERC20Mock weth;
    PonderPair pair;
    address attacker = makeAddr("attacker");

    uint256 constant INITIAL_LIQUIDITY = 10000 ether;

    function setUp() public {
        // Deploy tokens
        ponder = new ERC20Mock("PONDER", "PONDER", 18);
        weth = new ERC20Mock("WETH", "WETH", 18);

        // Deploy factory and create pair
        factory = new PonderFactory(address(this), address(this), address(1));
        address pairAddress = factory.createPair(address(ponder), address(weth));
        pair = PonderPair(pairAddress);

        // Create oracle with WETH as base
        oracle = new PonderPriceOracle(
            address(factory),
            address(weth),
            address(0)
        );

        // Setup initial state
        vm.warp(1000000);
        _setupInitialLiquidity();
        _initializeOracleHistory();
    }

    function testValidContribution() public {
        // Test with reasonable amount that should pass all checks
        PonderLaunchGuard.ValidationResult memory result =
                            PonderLaunchGuard.validatePonderContribution(
                address(pair),
                address(oracle),
                10 ether  // Small amount relative to liquidity
            );

        // Verify results
        assertGt(result.kubValue, 0, "KUB value should be non-zero");
        assertLt(result.priceImpact, PonderLaunchGuard.MAX_PRICE_IMPACT,
            "Price impact should be within limits");
        assertEq(result.maxPonderPercent, PonderLaunchGuard.MAX_PONDER_PERCENT,
            "Should return correct max percent");
    }

    function testExcessivePriceImpact() public {
        // Test with amount that would significantly impact price (50% of pool)
        uint256 largeAmount = INITIAL_LIQUIDITY / 2;

        vm.expectRevert(PonderLaunchGuard.ExcessivePriceImpact.selector);
        PonderLaunchGuard.validatePonderContribution(
            address(pair),
            address(oracle),
            largeAmount
        );
    }

    function testReserveImbalanceProtection() public {
        // Create extreme reserve imbalance (96:4 ratio)
        vm.startPrank(attacker);
        deal(address(ponder), attacker, INITIAL_LIQUIDITY * 24);
        ponder.transfer(address(pair), INITIAL_LIQUIDITY * 23);  // Makes reserves very imbalanced
        pair.sync();
        vm.stopPrank();

        vm.expectRevert(PonderLaunchGuard.ReserveImbalance.selector);
        PonderLaunchGuard.validatePonderContribution(
            address(pair),
            address(oracle),
            1000 ether
        );
    }

    function testZeroAmountRejection() public {
        vm.expectRevert(PonderLaunchGuard.ZeroAmount.selector);
        PonderLaunchGuard.validatePonderContribution(
            address(pair),
            address(oracle),
            0
        );
    }

    function testInsufficientLiquidity() public {
        vm.startPrank(address(this));
        uint256 lpBalance = pair.balanceOf(address(this));

        // Leave only about 10 wei of tokens
        uint256 targetLiquidity = 10;
        uint256 currentLiquidity = INITIAL_LIQUIDITY;
        uint256 amountToBurn = lpBalance * (currentLiquidity - targetLiquidity) / currentLiquidity;

        pair.transfer(address(pair), amountToBurn);
        pair.burn(address(this));

        // Force sync to ensure reserves are updated
        pair.sync();

        // Verify reserves are actually below minimum
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 totalLiquidity = uint256(reserve0) * uint256(reserve1);
        assertLt(totalLiquidity, PonderLaunchGuard.MIN_LIQUIDITY, "Setup failed: Liquidity still above minimum");
        vm.stopPrank();

        vm.expectRevert(PonderLaunchGuard.InsufficientLiquidity.selector);
        PonderLaunchGuard.validatePonderContribution(
            address(pair),
            address(oracle),
            1 ether
        );
    }

    // Add these test functions to PonderLaunchGuardSecurityTest

    function testValidKubContribution() public {
        // Test a normal, valid contribution
        uint256 amount = 10 ether;
        uint256 totalRaised = 100 ether;
        uint256 targetRaise = 1000 ether;
        uint256 contributorTotal = 0;

        PonderLaunchGuard.ContributionResult memory result =
                            PonderLaunchGuard.validateKubContribution(
                amount,
                totalRaised,
                targetRaise,
                contributorTotal
            );

        assertEq(result.acceptedAmount, amount, "Should accept full amount");
        assertEq(
            result.remainingAllowed,
            targetRaise - totalRaised - amount,
            "Should calculate remaining correctly"
        );
        assertFalse(result.targetReached, "Target should not be reached");
    }

    function testMinimumContributionLimit() public {
        uint256 tooSmall = PonderLaunchGuard.MIN_KUB_CONTRIBUTION - 1;

        vm.expectRevert(PonderLaunchGuard.ContributionTooSmall.selector);
        PonderLaunchGuard.validateKubContribution(
            tooSmall,
            0,
            1000 ether,
            0
        );
    }

    function testMaximumIndividualCap() public {
        uint256 tooLarge = PonderLaunchGuard.MAX_INDIVIDUAL_CAP + 1;

        vm.expectRevert(PonderLaunchGuard.ContributionTooLarge.selector);
        PonderLaunchGuard.validateKubContribution(
            tooLarge,
            0,
            1000 ether,
            0
        );
    }

    function testCumulativeIndividualCap() public {
        // Test when user has already contributed close to max
        uint256 existingContribution = PonderLaunchGuard.MAX_INDIVIDUAL_CAP - 1 ether;
        uint256 newContribution = 2 ether;

        PonderLaunchGuard.ContributionResult memory result =
                            PonderLaunchGuard.validateKubContribution(
                newContribution,
                100 ether,
                1000 ether,
                existingContribution
            );

        // Should only accept up to individual cap
        assertEq(
            result.acceptedAmount,
            1 ether,
            "Should limit to remaining individual cap"
        );
    }

    function testTargetRaiseLimitEnforcement() public {
        uint256 targetRaise = 1000 ether;
        uint256 totalRaised = 995 ether;
        uint256 contribution = 10 ether;

        PonderLaunchGuard.ContributionResult memory result =
                            PonderLaunchGuard.validateKubContribution(
                contribution,
                totalRaised,
                targetRaise,
                0
            );

        assertEq(
            result.acceptedAmount,
            5 ether,
            "Should limit to remaining target"
        );
        assertTrue(result.targetReached, "Target should be reached");
    }

    function testRejectIfTargetReached() public {
        uint256 targetRaise = 1000 ether;
        uint256 totalRaised = targetRaise;

        vm.expectRevert(PonderLaunchGuard.TargetReached.selector);
        PonderLaunchGuard.validateKubContribution(
            1 ether,
            totalRaised,
            targetRaise,
            0
        );
    }

    function testRejectInvalidTotalRaised() public {
        uint256 targetRaise = 1000 ether;
        uint256 totalRaised = 1001 ether; // More than target

        vm.expectRevert(PonderLaunchGuard.InvalidTotalRaised.selector);
        PonderLaunchGuard.validateKubContribution(
            1 ether,
            totalRaised,
            targetRaise,
            0
        );
    }

    function testMultipleContributionScenarios() public {
        uint256 targetRaise = 1000 ether;
        address[] memory contributors = new address[](3);
        uint256[] memory contributorTotals = new uint256[](3);
        contributors[0] = address(0x1);
        contributors[1] = address(0x2);
        contributors[2] = address(0x3);

        uint256 totalRaised = 0;

        // Simulate multiple contributions
        for (uint i = 0; i < 3; i++) {
            uint256 contribution = 400 ether; // Try to contribute more than individual cap

            PonderLaunchGuard.ContributionResult memory result =
                                PonderLaunchGuard.validateKubContribution(
                    contribution,
                    totalRaised,
                    targetRaise,
                    contributorTotals[i]
                );

            // Update tracking
            totalRaised += result.acceptedAmount;
            contributorTotals[i] += result.acceptedAmount;

            // Verify individual cap enforcement
            assertLe(
                contributorTotals[i],
                PonderLaunchGuard.MAX_INDIVIDUAL_CAP,
                "Individual cap exceeded"
            );
        }

        // Verify total raised doesn't exceed target
        assertLe(totalRaised, targetRaise, "Target raise exceeded");
    }

    function testEdgeCaseContributions() public {
        uint256 targetRaise = 1000 ether;

        // Test exact minimum contribution
        PonderLaunchGuard.ContributionResult memory result1 =
                            PonderLaunchGuard.validateKubContribution(
                PonderLaunchGuard.MIN_KUB_CONTRIBUTION,
                0,
                targetRaise,
                0
            );
        assertEq(
            result1.acceptedAmount,
            PonderLaunchGuard.MIN_KUB_CONTRIBUTION,
            "Should accept exact minimum"
        );

        // Test exact individual cap
        PonderLaunchGuard.ContributionResult memory result2 =
                            PonderLaunchGuard.validateKubContribution(
                PonderLaunchGuard.MAX_INDIVIDUAL_CAP,
                0,
                targetRaise,
                0
            );
        assertEq(
            result2.acceptedAmount,
            PonderLaunchGuard.MAX_INDIVIDUAL_CAP,
            "Should accept exact cap"
        );
    }

    function testSequentialContributions() public {
        uint256 targetRaise = 1000 ether;
        uint256 contributorTotal = 0;
        uint256 totalRaised = 0;
        uint256 contribution = 250 ether;

        // First 4 contributions should succeed (4 * 250 = 1000 ether, exactly target)
        for (uint i = 0; i < 4; i++) {
            PonderLaunchGuard.ContributionResult memory result =
                                PonderLaunchGuard.validateKubContribution(
                    contribution,
                    totalRaised,
                    targetRaise,
                    contributorTotal
                );

            totalRaised += result.acceptedAmount;
            contributorTotal += result.acceptedAmount;

            // Verify caps
            assertLe(contributorTotal, PonderLaunchGuard.MAX_INDIVIDUAL_CAP, "Individual cap exceeded");
            assertLe(totalRaised, targetRaise, "Target raise exceeded");

            // Last valid contribution should mark target as reached
            if (i == 3) {
                assertTrue(result.targetReached, "Target should be reached on final contribution");
                assertEq(totalRaised, targetRaise, "Total raised should equal target");
            }
        }

        // Fifth contribution should fail since target is reached
        vm.expectRevert(PonderLaunchGuard.TargetReached.selector);
        PonderLaunchGuard.validateKubContribution(
            contribution,
            totalRaised,
            targetRaise,
            contributorTotal
        );
    }

    function testExactTargetContribution() public {
        uint256 targetRaise = 1000 ether;
        uint256 totalRaised = 900 ether;  // 900 already raised
        uint256 contribution = 100 ether;  // Exactly what's needed to reach target

        PonderLaunchGuard.ContributionResult memory result =
                            PonderLaunchGuard.validateKubContribution(
                contribution,
                totalRaised,
                targetRaise,
                0
            );

        // Verify exact target behavior
        assertEq(result.acceptedAmount, contribution, "Should accept exact amount needed");
        assertTrue(result.targetReached, "Should mark target as reached");
        assertEq(result.remainingAllowed, 0, "Should have no remaining allowed");

        // Verify next contribution fails
        vm.expectRevert(PonderLaunchGuard.TargetReached.selector);
        PonderLaunchGuard.validateKubContribution(
            1 ether,
            targetRaise,  // now equals target
            targetRaise,
            0
        );
    }

    function _setupInitialLiquidity() internal {
        deal(address(ponder), address(this), INITIAL_LIQUIDITY);
        deal(address(weth), address(this), INITIAL_LIQUIDITY);

        ponder.transfer(address(pair), INITIAL_LIQUIDITY);
        weth.transfer(address(pair), INITIAL_LIQUIDITY);
        pair.mint(address(this));
    }

    function _initializeOracleHistory() internal {
        pair.sync();
        oracle.update(address(pair));
        vm.warp(block.timestamp + 5 minutes);
    }
}
