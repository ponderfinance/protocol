// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/launch/FiveFiveFiveLauncher.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderToken.sol";
import "../../src/core/PonderPriceOracle.sol";
import "../../src/periphery/PonderRouter.sol";
import "../../src/launch/LaunchToken.sol";
import "../mocks/ERC20.sol";
import "../mocks/WETH9.sol";
import "../mocks/MockKKUBUnwrapper.sol";

contract ReentrantAttacker {
    FiveFiveFiveLauncher public launcher;
    uint256 public attackCount;

    constructor(address payable _launcher) {
        launcher = FiveFiveFiveLauncher(_launcher);
    }

    function attack(uint256 launchId) external payable {
        launcher.contributeKUB{value: msg.value}(launchId);
    }

    receive() external payable {
        if (attackCount < 3) {
            attackCount++;
            launcher.contributeKUB{value: 1000 ether}(0);
        }
    }
}

contract FiveFiveFiveLauncherTest is Test {
    FiveFiveFiveLauncher launcher;
    PonderFactory factory;
    PonderRouter router;
    PonderToken ponder;
    PonderPriceOracle oracle;
    WETH9 weth;
    address ponderWethPair;

    address creator = makeAddr("creator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address feeCollector = makeAddr("feeCollector");
    address treasury = makeAddr("treasury");
    address teamReserve = makeAddr("teamReserve");
    address marketing = makeAddr("marketing");

    uint256 constant TARGET_RAISE = 5555 ether;
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant INITIAL_LIQUIDITY = 10_000 ether;
    uint256 constant PONDER_PRICE = 0.1 ether;    // 1 PONDER = 0.1 KUB
    uint256 constant KUB_TO_MEME_KUB_LP = 6000; // 60% of KUB goes to KUB pool
    uint256 constant MAX_PONDER_PERCENT = 2000; // 20%
    uint256 constant MIN_KUB_CONTRIBUTION = 0.01 ether;
    uint256 constant MIN_PONDER_CONTRIBUTION = 0.1 ether;
    uint256 constant MIN_POOL_LIQUIDITY = 1 ether;
    uint256 constant PONDER_TO_MEME_PONDER = 8000;  // 80% of PONDER goes to PONDER pool
    uint256 constant PONDER_TO_BURN = 2000;         // 20% of PONDER gets burned if pool created


    event LaunchCreated(uint256 indexed launchId, address indexed token, address creator, string imageURI);
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);
    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);
    event DualPoolsCreated(uint256 indexed launchId, address memeKubPair, address memePonderPair, uint256 kubLiquidity, uint256 ponderLiquidity);
    event LaunchCompleted(uint256 indexed launchId, uint256 kubRaised, uint256 ponderRaised);
    event PonderBurned(uint256 indexed launchId, uint256 amount);
    event PonderPoolSkipped(uint256 indexed launchId, uint256 ponderAmount, uint256 ponderValueInKub);

    function setUp() public {
        vm.warp(1000);

        // Deploy core contracts
        weth = new WETH9();
        factory = new PonderFactory(address(this), address(this), address(1));
        ponder = new PonderToken(teamReserve, marketing, address(this));

        ponderWethPair = factory.createPair(address(ponder), address(weth));

        MockKKUBUnwrapper unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(address(factory), address(weth), address(unwrapper));

        // Setup initial PONDER liquidity
        ponder.setMinter(address(this));
        ponder.mint(address(this), INITIAL_LIQUIDITY * 10);
        ponder.approve(address(router), INITIAL_LIQUIDITY * 10);

        vm.deal(address(this), INITIAL_LIQUIDITY);
        router.addLiquidityETH{value: INITIAL_LIQUIDITY}(
            address(ponder),
            INITIAL_LIQUIDITY * 10,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        oracle = new PonderPriceOracle(
            address(factory),
            ponderWethPair,
            address(weth)
        );

        _initializeOracleHistory();

        launcher = new FiveFiveFiveLauncher(
            address(factory),
            payable(address(router)),
            feeCollector,
            address(ponder),
            address(oracle)
        );


        // Fund test accounts
        vm.deal(alice, 10000 ether);
        vm.deal(bob, 10000 ether);
        ponder.mint(alice, 100000 ether);
        ponder.mint(bob, 100000 ether);

        vm.prank(alice);
        ponder.approve(address(launcher), type(uint256).max);
        vm.prank(bob);
        ponder.approve(address(launcher), type(uint256).max);

        ponder.setMinter(address(launcher));
    }

    function testCreateLaunch() public {
        vm.startPrank(creator);

        FiveFiveFiveLauncher.LaunchParams memory params = FiveFiveFiveLauncher.LaunchParams({
            name: "Test Token",
            symbol: "TEST",
            imageURI: "ipfs://test"
        });

        uint256 launchId = launcher.createLaunch(params);
        vm.stopPrank();

        (
            address tokenAddress,
            string memory name,
            string memory symbol,
            string memory imageURI,
            uint256 kubRaised,
            bool launched,
            uint256 lpUnlockTime
        ) = launcher.getLaunchInfo(launchId);

        assertEq(name, "Test Token");
        assertEq(symbol, "TEST");
        assertEq(imageURI, "ipfs://test");
        assertEq(kubRaised, 0);
        assertFalse(launched);
        assertTrue(tokenAddress != address(0));
    }

    function _calculateExpectedTokens(
        uint256 contribution,
        uint256 totalSupply,
        uint256 targetRaise
    ) internal pure returns (uint256) {
        // First calculate contributor allocation (70%)
        uint256 contributorTokens = (totalSupply * 70) / 100;

        // Then calculate this contribution's share
        return (contribution * contributorTokens) / targetRaise;
    }

    function testKUBContribution() public {
        uint256 launchId = _createTestLaunch();
        uint256 contribution = 1000 ether;

        // Get actual total supply from token
        (address tokenAddress,,,,,,) = launcher.getLaunchInfo(launchId);
        uint256 totalSupply = LaunchToken(tokenAddress).TOTAL_SUPPLY();

        // Calculate expected tokens
        uint256 contributorTokens = (totalSupply * 70) / 100;
        uint256 expectedTokens = (contribution * contributorTokens) / TARGET_RAISE;

        console.log("Total Supply:", totalSupply);
        console.log("Contributor Tokens:", contributorTokens);
        console.log("Expected Tokens:", expectedTokens);

        vm.startPrank(alice);
        launcher.contributeKUB{value: contribution}(launchId);

        // Get actual tokens received
        (,,,uint256 tokensReceived) = launcher.getContributorInfo(launchId, alice);
        console.log("Actual Tokens Received:", tokensReceived);

        // Let's try to understand the ratio
        console.log("Actual/Expected Ratio:", (tokensReceived * 100) / expectedTokens);

        assertEq(tokensReceived, expectedTokens, "Token distribution incorrect");
        vm.stopPrank();
    }

    function testPonderContribution() public {
        uint256 launchId = _createTestLaunch();
        uint256 ponderAmount = 10000 ether;
        uint256 expectedKubValue = _getPonderValue(ponderAmount);

        (address tokenAddress,,,,,,) = launcher.getLaunchInfo(launchId);
        uint256 totalSupply = LaunchToken(tokenAddress).TOTAL_SUPPLY();
        uint256 contributorTokens = (totalSupply * 70) / 100;
        uint256 expectedTokens = (expectedKubValue * contributorTokens) / TARGET_RAISE;

        vm.startPrank(alice);

        // First expect TokensDistributed event
        vm.expectEmit(true, true, false, true);
        emit TokensDistributed(launchId, alice, expectedTokens);

        // Then expect PonderContributed event
        vm.expectEmit(true, true, false, true);
        emit PonderContributed(launchId, alice, ponderAmount, expectedKubValue);

        launcher.contributePONDER(launchId, ponderAmount);

        (,uint256 ponderContributed, uint256 ponderValue, uint256 tokensReceived) =
                            launcher.getContributorInfo(launchId, alice);

        assertEq(ponderContributed, ponderAmount);
        assertEq(ponderValue, expectedKubValue);
        assertEq(tokensReceived, expectedTokens);

        vm.stopPrank();
    }

    function testCompleteLaunchWithDualPools() public {
        uint256 launchId = _createTestLaunch();

        // Contribute 80% in KUB
        uint256 kubAmount = (TARGET_RAISE * 80) / 100;  // 4444 ether
        vm.startPrank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);
        vm.stopPrank();

        // Calculate PONDER amount for remaining 20%
        // Price is 0.1 KUB per PONDER, so multiply by 10 to get PONDER amount
        uint256 ponderValue = (TARGET_RAISE * 20) / 100;  // 1111 ether in KUB value
        uint256 ponderAmount = ponderValue * 10;  // Convert to PONDER amount at 0.1 KUB per PONDER

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();

        (,,,, uint256 kubRaised, bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should be completed");

        (
            address memeKubPair,
            address memePonderPair,
            bool hasSecondaryPool
        ) = launcher.getPoolInfo(launchId);

        assertTrue(memeKubPair != address(0), "KUB pool not created");
        assertTrue(memePonderPair != address(0), "PONDER pool not created");
        assertTrue(hasSecondaryPool, "Secondary pool flag not set");

        assertGt(PonderERC20(memeKubPair).totalSupply(), 0, "No KUB pool liquidity");
        assertGt(PonderERC20(memePonderPair).totalSupply(), 0, "No PONDER pool liquidity");
    }

    function testTokenAllocation() public {
        uint256 launchId = _createTestLaunch();
        uint256 onePercent = TARGET_RAISE / 100;

        vm.startPrank(alice);
        launcher.contributeKUB{value: onePercent}(launchId);
        vm.stopPrank();

        // Should receive 1% of 70% of total supply
        uint256 expectedTokens = (555_555_555 ether * 70) / 10000;
        (, , , uint256 tokensReceived) = launcher.getContributorInfo(launchId, alice);
        assertEq(tokensReceived, expectedTokens, "Incorrect token allocation");
    }

    function _createTestLaunch() internal returns (uint256) {
        FiveFiveFiveLauncher.LaunchParams memory params = FiveFiveFiveLauncher.LaunchParams({
            name: "Test Token",
            symbol: "TEST",
            imageURI: "ipfs://test"
        });

        vm.prank(creator);
        return launcher.createLaunch(params);
    }

    function _initializeOracleHistory() internal {
        PonderPair(ponderWethPair).sync();
        vm.warp(block.timestamp + 1 hours);
        oracle.update(ponderWethPair);

        for (uint i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 1 hours);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }
    }

    function _getPonderValue(uint256 amount) internal view returns (uint256) {
        return oracle.getCurrentPrice(ponderWethPair, address(ponder), amount);
    }

    function testMaxPonderContribution() public {
        uint256 launchId = _createTestLaunch();

        // Calculate exactly 20% of target raise in PONDER
        // 20% of 5555 ETH = 1111 ETH worth of PONDER
        // At 0.1 ETH per PONDER, need 11,110 PONDER
        uint256 ponderAmount = (((TARGET_RAISE * 20) / 100) * 10); // Scale up by 10 for 0.1 price

        vm.startPrank(alice);
        launcher.contributePONDER(launchId, ponderAmount);

        // Verify contribution was accepted
        (,uint256 ponderContributed, uint256 ponderValue,) = launcher.getContributorInfo(launchId, alice);
        assertEq(ponderValue, (TARGET_RAISE * 2000) / BASIS_POINTS, "PONDER value should be 20% of target");
        vm.stopPrank();
    }

    function testPonderContributionAfterKub() public {
        uint256 launchId = _createTestLaunch();

        // First contribute 85% in KUB
        uint256 kubContribution = (TARGET_RAISE * 85) / 100;
        vm.prank(alice);
        launcher.contributeKUB{value: kubContribution}(launchId);

        // Try to contribute an amount that would exceed 20% PONDER limit
        uint256 maxPonderValue = (TARGET_RAISE * 21) / 100; // 21% to ensure it exceeds limit
        uint256 ponderAmount = maxPonderValue * 10 * 1e18 / PONDER_PRICE; // Convert to PONDER amount with 18 decimals

        vm.startPrank(bob);
        vm.expectRevert(FiveFiveFiveLauncher.ExcessivePonderContribution.selector);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();
    }

    function testValidMixedContribution() public {
        uint256 launchId = _createTestLaunch();

        // First contribute 85% in KUB
        uint256 kubContribution = (TARGET_RAISE * 85) / 100;
        vm.prank(alice);
        launcher.contributeKUB{value: kubContribution}(launchId);

        // Now contribute 10% in PONDER (should succeed as it's under 20% limit)
        uint256 ponderAmount = (((TARGET_RAISE * 10) / 100) * 10); // Scale up by 10 for 0.1 price

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, ponderAmount);

        // Verify final contributions
        (uint256 kubCollected, uint256 ponderCollected, uint256 ponderValueCollected, uint256 totalValue) =
                            launcher.getContributionInfo(launchId);

        assertLe(ponderValueCollected, (TARGET_RAISE * 2000) / BASIS_POINTS, "PONDER value should not exceed 20%");
        assertTrue(totalValue <= TARGET_RAISE, "Total value should not exceed target");
        assertTrue(kubCollected >= totalValue - ponderValueCollected, "KUB contribution accounting error");
        vm.stopPrank();
    }

    function testExcessivePonderContribution() public {
        uint256 launchId = _createTestLaunch();

        // First contribute 90% in KUB
        uint256 kubContribution = (TARGET_RAISE * 90) / 100;
        vm.prank(alice);
        launcher.contributeKUB{value: kubContribution}(launchId);

        // Calculate remaining needed (10%) in KUB value
        uint256 remainingKub = TARGET_RAISE - kubContribution;

        // Try to contribute more than needed
        uint256 ponderAmount = (remainingKub * 10) + 100 ether; // Add excess amount

        vm.startPrank(bob);
        vm.expectRevert(FiveFiveFiveLauncher.ExcessiveContribution.selector);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();
    }

    function testGetRemainingToRaise() public {
        uint256 launchId = _createTestLaunch();

        // Initial check
        (uint256 remainingTotal, uint256 remainingPonderValue) = launcher.getRemainingToRaise(launchId);
        assertEq(remainingTotal, TARGET_RAISE, "Should show full raise amount initially");
        assertEq(remainingPonderValue, (TARGET_RAISE * MAX_PONDER_PERCENT) / BASIS_POINTS,
            "Should show max PONDER value initially");

        // Contribute some KUB
        uint256 kubContribution = TARGET_RAISE / 2;
        vm.prank(alice);
        launcher.contributeKUB{value: kubContribution}(launchId);

        // Check updated values
        (remainingTotal, remainingPonderValue) = launcher.getRemainingToRaise(launchId);
        assertEq(remainingTotal, TARGET_RAISE - kubContribution, "Should show remaining raise amount");
        assertTrue(remainingPonderValue <= remainingTotal, "Remaining PONDER should not exceed total");
    }


    // Add separate test for PONDER cap
    function testPonderExceedsMaxPercent() public {
        uint256 launchId = _createTestLaunch();

        // Try to contribute 25% in PONDER (over 20% limit)
        uint256 ponderAmount = (((TARGET_RAISE * 25) / 100) * 10); // Scale up by 10 for 0.1 price

        vm.startPrank(bob);
        ponder.approve(address(launcher), ponderAmount);
        vm.expectRevert(FiveFiveFiveLauncher.ExcessivePonderContribution.selector);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();
    }

    function testRefundAfterDeadline() public {
        uint256 launchId = _createTestLaunch();

        // Make a contribution
        uint256 contribution = 1000 ether;
        vm.startPrank(alice);
        launcher.contributeKUB{value: contribution}(launchId);

        // Fast forward past deadline
        vm.warp(block.timestamp + 7 days + 1);

        // Get launch token address and approve transfer
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);

        // Claim refund
        uint256 balanceBefore = alice.balance;
        launcher.claimRefund(launchId);
        uint256 balanceAfter = alice.balance;

        assertEq(balanceAfter - balanceBefore, contribution, "Refund amount incorrect");

        // Verify contribution was reset
        (uint256 kubContributed,,,) = launcher.getContributorInfo(launchId, alice);
        assertEq(kubContributed, 0, "Contribution not reset");
        vm.stopPrank();
    }

    function testRefundAfterCancel() public {
        uint256 launchId = _createTestLaunch();
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken token = LaunchToken(tokenAddress);

        // Make contributions
        vm.startPrank(alice);
        launcher.contributeKUB{value: 1000 ether}(launchId);
        // Approve tokens for refund
        token.approve(address(launcher), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, 10000 ether);
        // Approve tokens for refund
        token.approve(address(launcher), type(uint256).max);
        vm.stopPrank();

        // Cancel launch
        vm.prank(creator);
        launcher.cancelLaunch(launchId);

        // Test both KUB and PONDER refunds
        vm.startPrank(alice);
        launcher.claimRefund(launchId);
        vm.stopPrank();

        vm.startPrank(bob);
        launcher.claimRefund(launchId);
        vm.stopPrank();
    }

    function testPreExistingPairs() public {
        uint256 launchId = _createTestLaunch();
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);

        // Create pairs manually before launch is completed
        address wethAddr = router.WETH();
        factory.createPair(tokenAddress, wethAddr);  // Create MEME/KUB pair
        factory.createPair(tokenAddress, address(ponder));  // Create MEME/PONDER pair

        // Contribute enough to complete the launch
        uint256 kubAmount = (TARGET_RAISE * 80) / 100;  // 80% in KUB
        vm.startPrank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);
        vm.stopPrank();

        // Add remaining 20% in PONDER
        uint256 ponderValue = (TARGET_RAISE * 20) / 100;
        uint256 ponderAmount = ponderValue * 10;  // Convert to PONDER amount at 0.1 KUB per PONDER

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();

        // Check if launch completed successfully
        (,,,, uint256 kubRaised, bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should complete even with pre-existing pairs");

        // Verify pools were used correctly
        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);

        // Verify liquidity was added to existing pairs
        assertGt(PonderERC20(memeKubPair).totalSupply(), 0, "No KUB pool liquidity");
        assertGt(PonderERC20(memePonderPair).totalSupply(), 0, "No PONDER pool liquidity");
    }

    function testPartialPreExistingPairs() public {
        uint256 launchId = _createTestLaunch();
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);

        // Only create MEME/KUB pair manually
        address wethAddr = router.WETH();
        factory.createPair(tokenAddress, wethAddr);

        // Contribute enough to complete the launch
        uint256 kubAmount = (TARGET_RAISE * 80) / 100;
        vm.startPrank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);
        vm.stopPrank();

        // Add remaining 20% in PONDER
        uint256 ponderValue = (TARGET_RAISE * 20) / 100;
        uint256 ponderAmount = ponderValue * 10;

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();

        // Verify launch completed and both pools exist
        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);

        assertTrue(hasSecondaryPool, "Secondary pool should exist");
        assertGt(PonderERC20(memeKubPair).totalSupply(), 0, "No KUB pool liquidity");
        assertGt(PonderERC20(memePonderPair).totalSupply(), 0, "No PONDER pool liquidity");
        assertTrue(memePonderPair != address(0), "PONDER pair should be created");
    }

    function testLaunchWithZeroPonderContribution() public {
        uint256 launchId = _createTestLaunch();
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);

        // Create both pairs manually
        factory.createPair(tokenAddress, router.WETH());
        factory.createPair(tokenAddress, address(ponder));

        // Complete launch with only KUB
        vm.startPrank(alice);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);
        vm.stopPrank();

        // Verify launch completed with only KUB pool
        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);

        assertFalse(hasSecondaryPool, "Should not have secondary pool with no PONDER contribution");
        assertGt(PonderERC20(memeKubPair).totalSupply(), 0, "No KUB pool liquidity");

        // Check if memePonderPair exists but has no liquidity
        if (memePonderPair != address(0)) {
            assertEq(PonderERC20(memePonderPair).totalSupply(), 0, "Should not have PONDER pool liquidity");
        }
    }

    function testExcessiveKubContribution() public {
        uint256 launchId = _createTestLaunch();

        // First contribute 90% in KUB
        uint256 kubContribution = (TARGET_RAISE * 90) / 100;
        vm.prank(alice);
        launcher.contributeKUB{value: kubContribution}(launchId);

        // Try to contribute more than remaining
        uint256 remainingNeeded = TARGET_RAISE - kubContribution;
        uint256 excessiveContribution = remainingNeeded + 100 ether;

        vm.startPrank(bob);
        vm.expectRevert(FiveFiveFiveLauncher.ExcessiveContribution.selector);
        launcher.contributeKUB{value: excessiveContribution}(launchId);
        vm.stopPrank();
    }

    function testExactKubContribution() public {
        uint256 launchId = _createTestLaunch();

        // First contribute all but 1 ETH of target
        uint256 firstContribution = TARGET_RAISE - 1 ether;
        vm.prank(alice);
        launcher.contributeKUB{value: firstContribution}(launchId);

        // Contribute exactly what's needed - should not need refund
        vm.startPrank(bob);
        uint256 balanceBefore = bob.balance;
        launcher.contributeKUB{value: 1 ether}(launchId);
        uint256 balanceAfter = bob.balance;

        assertEq(
            balanceBefore - balanceAfter,
            1 ether,
            "Should deduct exactly 1 ETH"
        );

        // Verify launch completed
        (,,,,, bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should be completed");
    }

    function testMultipleExcessiveKubContributions() public {
        uint256 launchId = _createTestLaunch();
        uint256 excessive = 1000 ether;

        vm.startPrank(alice);
        uint256 balanceBefore = alice.balance;

        // Make multiple excessive contributions
        for(uint i = 0; i < 3; i++) {
            launcher.contributeKUB{value: excessive}(launchId);
        }

        uint256 balanceAfter = alice.balance;

        // Should not deduct more than TARGET_RAISE
        assertLe(
            balanceBefore - balanceAfter,
            TARGET_RAISE,
            "Total deductions should not exceed target raise"
        );

        vm.stopPrank();
    }

    function testKubContributionEventAccuracy() public {
        uint256 launchId = _createTestLaunch();

        // Try to contribute more than needed
        uint256 contribution = TARGET_RAISE + 100 ether;

        vm.startPrank(alice);

        // Should revert with excessive contribution error
        vm.expectRevert(FiveFiveFiveLauncher.ExcessiveContribution.selector);
        launcher.contributeKUB{value: contribution}(launchId);

        // Now try with exact amount
        vm.expectEmit(true, true, false, true);
        emit KUBContributed(launchId, alice, TARGET_RAISE);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);

        vm.stopPrank();
    }

    function testPonderContributionEventAccuracy() public {
        uint256 launchId = _createTestLaunch();

        // Fill 90% with KUB
        uint256 kubContribution = (TARGET_RAISE * 90) / 100;
        vm.prank(alice);
        launcher.contributeKUB{value: kubContribution}(launchId);

        // Calculate exact remaining amount needed in PONDER
        uint256 remainingKubValue = TARGET_RAISE - kubContribution;
        uint256 ponderAmount = remainingKubValue * 10; // Convert to PONDER amount (0.1 KUB per PONDER)

        vm.startPrank(bob);

        // Try excessive amount first - should revert
        vm.expectRevert(FiveFiveFiveLauncher.ExcessiveContribution.selector);
        launcher.contributePONDER(launchId, ponderAmount * 2);

        // Now try exact amount - should succeed
        vm.expectEmit(true, true, false, true);
        emit PonderContributed(launchId, bob, ponderAmount, remainingKubValue);
        launcher.contributePONDER(launchId, ponderAmount);

        // Verify actual contribution
        (,uint256 actualPonderContributed,,) = launcher.getContributorInfo(launchId, bob);
        assertEq(actualPonderContributed, ponderAmount, "Should accept exact PONDER amount");
        vm.stopPrank();
    }

    function testTinyPonderContribution() public {
        uint256 launchId = _createTestLaunch();

        // First contribute most in KUB
        uint256 kubAmount = TARGET_RAISE - 1 ether;
        vm.prank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);

        // Now try minimum valid PONDER contribution
        uint256 minValidPonder = MIN_PONDER_CONTRIBUTION;

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, minValidPonder);

        // Check if PONDER pool was created and has appropriate liquidity
        (,address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);

        // If pool was created, verify liquidity
        if (hasSecondaryPool) {
            uint256 ponderLiquidity = PonderERC20(address(ponder)).balanceOf(memePonderPair);
            assertGt(ponderLiquidity, 0, "PONDER pool should have liquidity if created");
        }
        vm.stopPrank();
    }

    function testZeroPonderPoolCreation() public {
        uint256 launchId = _createTestLaunch();

        // Complete launch with only KUB
        vm.prank(alice);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);

        // Check pool creation
        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);

        assertFalse(hasSecondaryPool, "Should not create PONDER pool with zero PONDER");
        assertEq(memePonderPair, address(0), "PONDER pair should be zero address");

        // Verify KUB pool is still created and valid
        assertTrue(memeKubPair != address(0), "KUB pool should exist");
        assertGt(PonderERC20(memeKubPair).totalSupply(), 0, "KUB pool should have liquidity");
    }

    function testReentrantContribution() public {
        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(launcher)));
        uint256 launchId = _createTestLaunch();

        vm.deal(address(attacker), TARGET_RAISE);
        vm.startPrank(address(attacker));

        // Try to attack with exact target amount to avoid LP token issues
        attacker.attack{value: TARGET_RAISE}(launchId);
        vm.stopPrank();

        // Verify no excess KUB was stolen
        assertLe(
            address(launcher).balance,
            TARGET_RAISE,
            "Contract should not hold excess KUB"
        );
    }

    function testLiquidityRatioSanityChecks() public {
        uint256 launchId = _createTestLaunch();

        // Contribute mix of KUB and PONDER
        uint256 kubAmount = (TARGET_RAISE * 85) / 100;
        vm.prank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);

        uint256 ponderValue = (TARGET_RAISE * 15) / 100;
        uint256 ponderAmount = ponderValue * 10;

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();

        // Check liquidity ratios in both pools
        (address memeKubPair, address memePonderPair,) = launcher.getPoolInfo(launchId);

        // Get reserves for KUB pool
        (uint112 kub0, uint112 kub1,) = PonderPair(memeKubPair).getReserves();

        // Get reserves for PONDER pool
        (uint112 ponder0, uint112 ponder1,) = PonderPair(memePonderPair).getReserves();

        // Verify ratios are sane and match expected percentages
        assertGt(kub0, 0, "KUB pool reserve0 should be non-zero");
        assertGt(kub1, 0, "KUB pool reserve1 should be non-zero");
        assertGt(ponder0, 0, "PONDER pool reserve0 should be non-zero");
        assertGt(ponder1, 0, "PONDER pool reserve1 should be non-zero");

        // Compare ratios instead of absolute values to avoid overflow
        uint256 kubRatio = uint256(kub0) * 1e18 / uint256(kub1);
        uint256 ponderRatio = uint256(ponder0) * 1e18 / uint256(ponder1);

        assertTrue(kubRatio > 0, "KUB pool ratio should be positive");
        assertTrue(ponderRatio > 0, "PONDER pool ratio should be positive");
    }

    function testMinimumLiquidityLockPrevention() public {
        uint256 launchId = _createTestLaunch();

        // Try to contribute just above minimum
        uint256 contribution = MIN_KUB_CONTRIBUTION + 0.001 ether;

        vm.startPrank(alice);
        launcher.contributeKUB{value: contribution}(launchId);

        // Fast forward past launch deadline
        vm.warp(block.timestamp + 7 days + 1);

        // Get launch token and approve first
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);

        // Try to claim refund
        launcher.claimRefund(launchId);

        // Verify contribution was refunded
        (uint256 kubContributed,,,) = launcher.getContributorInfo(launchId, alice);
        assertEq(kubContributed, 0, "Contribution should be refundable");
        vm.stopPrank();
    }

    // New tests for minimum contribution checks
    function testBelowMinimumKubContribution() public {
        uint256 launchId = _createTestLaunch();

        vm.startPrank(alice);
        vm.expectRevert(FiveFiveFiveLauncher.ContributionTooSmall.selector);
        launcher.contributeKUB{value: MIN_KUB_CONTRIBUTION - 1}(launchId);
        vm.stopPrank();
    }

    function testBelowMinimumPonderContribution() public {
        uint256 launchId = _createTestLaunch();

        vm.startPrank(alice);
        vm.expectRevert(FiveFiveFiveLauncher.ContributionTooSmall.selector);
        launcher.contributePONDER(launchId, MIN_PONDER_CONTRIBUTION - 1);
        vm.stopPrank();
    }

    function testPonderPoolCreationThreshold() public {
        uint256 launchId = _createTestLaunch();

        // Calculate remaining needed in KUB value and convert to PONDER
        uint256 kubNeeded = TARGET_RAISE - 4555 ether; // Exact remaining needed

        // Need enough PONDER to equal the kubNeeded when valued by oracle
        // Since oracle gives 0.1 KUB per PONDER, multiply by 10
        uint256 ponderNeeded = kubNeeded * 10;

        vm.prank(alice);
        launcher.contributeKUB{value: 4555 ether}(launchId);

        uint256 initialPonderSupply = ponder.totalSupply();

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, ponderNeeded);

        // Verify launch completed
        (,,,,,bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should complete");

        // Verify pools were created
        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);
        assertTrue(memeKubPair != address(0), "KUB pool should be created");
        assertTrue(memePonderPair != address(0), "PONDER pool should be created");
        assertTrue(hasSecondaryPool, "Should have secondary pool");

        // Verify standard burn amount
        uint256 finalPonderSupply = ponder.totalSupply();
        uint256 expectedBurn = (ponderNeeded * PONDER_TO_BURN) / BASIS_POINTS;
        assertEq(
            initialPonderSupply - finalPonderSupply,
            expectedBurn,
            "Should burn standard percentage"
        );
        vm.stopPrank();
    }

    function testPonderBurnWithoutPool() public {
        uint256 launchId = _createTestLaunch();

        // First contribute almost all in KUB
        uint256 kubAmount = TARGET_RAISE - 0.5 ether;  // Leave 0.5 ETH worth of space
        vm.prank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);

        // Calculate PONDER needed to complete raise but not enough for pool
        // 5 PONDER will be worth 0.5 ETH (less than MIN_POOL_LIQUIDITY)
        uint256 ponderAmount = 5 ether;  // Will be worth 0.5 KUB, under MIN_POOL_LIQUIDITY
        uint256 initialPonderSupply = ponder.totalSupply();

        vm.startPrank(bob);
        launcher.contributePONDER(launchId, ponderAmount);

        // Verify launch completed
        (,,,,,bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should complete");

        // Verify only KUB pool exists
        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);
        assertTrue(memeKubPair != address(0), "KUB pool should be created");
        assertFalse(hasSecondaryPool, "Should not have secondary pool");

        // Verify all PONDER was burned
        uint256 finalPonderSupply = ponder.totalSupply();
        assertEq(
            initialPonderSupply - finalPonderSupply,
            ponderAmount,
            "All PONDER should be burned"
        );

        // Double check the PONDER pool wasn't created
        assertTrue(memePonderPair == address(0), "PONDER pool should not be created");
        vm.stopPrank();
    }

    function testValidMinimumContributions() public {
        uint256 launchId = _createTestLaunch();

        // Test minimum valid KUB contribution
        vm.startPrank(alice);
        launcher.contributeKUB{value: MIN_KUB_CONTRIBUTION}(launchId);
        vm.stopPrank();

        // Test minimum valid PONDER contribution
        vm.startPrank(bob);
        launcher.contributePONDER(launchId, MIN_PONDER_CONTRIBUTION);
        vm.stopPrank();

        // Verify contributions were accepted
        (uint256 kubContributed,,,) = launcher.getContributorInfo(launchId, alice);
        assertEq(kubContributed, MIN_KUB_CONTRIBUTION, "KUB contribution not recorded");

        (,uint256 ponderContributed,,) = launcher.getContributorInfo(launchId, bob);
        assertEq(ponderContributed, MIN_PONDER_CONTRIBUTION, "PONDER contribution not recorded");
    }

    // Test view function for minimum requirements
    function testGetMinimumRequirements() public {
        (uint256 minKub, uint256 minPonder, uint256 minPoolLiquidity) =
                            launcher.getMinimumRequirements();

        assertEq(minKub, MIN_KUB_CONTRIBUTION, "Incorrect minimum KUB");
        assertEq(minPonder, MIN_PONDER_CONTRIBUTION, "Incorrect minimum PONDER");
        assertEq(minPoolLiquidity, MIN_POOL_LIQUIDITY, "Incorrect minimum pool liquidity");
    }

    function testMinimumKubContribution() public {
        uint256 launchId = _createTestLaunch();

        vm.startPrank(alice);
        // Test exactly minimum
        launcher.contributeKUB{value: MIN_KUB_CONTRIBUTION}(launchId);

        // Test below minimum
        vm.expectRevert(FiveFiveFiveLauncher.ContributionTooSmall.selector);
        launcher.contributeKUB{value: MIN_KUB_CONTRIBUTION - 1}(launchId);
        vm.stopPrank();
    }

    function testMinimumPonderContribution() public {
        uint256 launchId = _createTestLaunch();

        vm.startPrank(alice);
        // Test exactly minimum
        launcher.contributePONDER(launchId, MIN_PONDER_CONTRIBUTION);

        // Test below minimum
        vm.expectRevert(FiveFiveFiveLauncher.ContributionTooSmall.selector);
        launcher.contributePONDER(launchId, MIN_PONDER_CONTRIBUTION - 1);
        vm.stopPrank();
    }

    function testPoolLiquidityEdgeCases() public {
        uint256 launchId = _createTestLaunch();

        // Test exactly minimum pool liquidity
        uint256 minPoolContribution = (MIN_POOL_LIQUIDITY * BASIS_POINTS) / KUB_TO_MEME_KUB_LP;

        vm.startPrank(alice);
        launcher.contributeKUB{value: TARGET_RAISE - minPoolContribution}(launchId);
        launcher.contributeKUB{value: minPoolContribution}(launchId);

        // Verify launch succeeded
        (,,,,, bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should succeed with minimum pool liquidity");
        vm.stopPrank();
    }

    function testMixedContributionWithMinimums() public {
        uint256 launchId = _createTestLaunch();

        // Contribute minimum KUB
        vm.prank(alice);
        launcher.contributeKUB{value: MIN_KUB_CONTRIBUTION}(launchId);

        // Contribute minimum PONDER
        vm.prank(bob);
        launcher.contributePONDER(launchId, MIN_PONDER_CONTRIBUTION);

        // Verify both contributions recorded
        (uint256 kubContributed,,,) = launcher.getContributorInfo(launchId, alice);
        assertEq(kubContributed, MIN_KUB_CONTRIBUTION, "KUB contribution not recorded");

        (,uint256 ponderContributed,,) = launcher.getContributorInfo(launchId, bob);
        assertEq(ponderContributed, MIN_PONDER_CONTRIBUTION, "PONDER contribution not recorded");
    }

    function testContributionRoundingEdgeCases() public {
        uint256 launchId = _createTestLaunch();

        // Get token address first
        (address tokenAddress,,,,,,) = launcher.getLaunchInfo(launchId);

        // Test contribution that would cause token calculation rounding
        uint256 oddContribution = TARGET_RAISE / 3 + 1; // Non-round number

        vm.startPrank(alice);
        launcher.contributeKUB{value: oddContribution}(launchId);

        // Verify token calculation handled correctly
        (,,,uint256 tokensReceived) = launcher.getContributorInfo(launchId, alice);
        uint256 expectedTokens = _calculateExpectedTokens(oddContribution, LaunchToken(tokenAddress).TOTAL_SUPPLY(), TARGET_RAISE);
        assertEq(tokensReceived, expectedTokens, "Token calculation should handle odd numbers");
        vm.stopPrank();
    }

    function testPonderValueBoundaries() public {
        uint256 launchId = _createTestLaunch();

        // Test exactly at 20% PONDER value cap
        // Note: MAX_PONDER_PERCENT should be 2000 (20%) - we'll add it as a constant
        uint256 maxPonderValue = (TARGET_RAISE * 2000) / BASIS_POINTS;  // 20% of target raise
        uint256 ponderAmount = maxPonderValue * 10; // Convert to PONDER amount

        vm.startPrank(alice);
        launcher.contributePONDER(launchId, ponderAmount);

        // Verify contribution accepted
        (,, uint256 ponderValue,) = launcher.getContributorInfo(launchId, alice);
        assertEq(ponderValue, maxPonderValue, "Should accept exactly 20% in PONDER value");

        // Try to contribute any more PONDER
        vm.expectRevert(FiveFiveFiveLauncher.ExcessivePonderContribution.selector);
        launcher.contributePONDER(launchId, MIN_PONDER_CONTRIBUTION);
        vm.stopPrank();
    }

    function _getPonderEquivalent(uint256 kubValue) internal pure returns (uint256) {
        return kubValue * 10; // 1 PONDER = 0.1 KUB
    }

    function _getKubValue(uint256 ponderAmount) internal pure returns (uint256) {
        return ponderAmount / 10; // 1 PONDER = 0.1 KUB
    }

    receive() external payable {}
}
