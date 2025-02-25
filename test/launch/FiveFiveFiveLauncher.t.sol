// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/launch/FiveFiveFiveLauncher.sol";
import "../../src/launch/IFiveFiveFiveLauncher.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/oracle/PonderPriceOracle.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "../../src/launch/LaunchToken.sol";
import "../../src/launch/types/LaunchTokenTypes.sol";
import "../../src/launch/types/FiveFiveFiveLauncherTypes.sol";
import "../mocks/ERC20Mock.sol";
import "../mocks/WETH9.sol";
import "../mocks/MockKKUBUnwrapper.sol";

contract ReentrantAttacker {
    FiveFiveFiveLauncher public immutable launcher;
    bool public hasReentered;

    constructor(address payable _launcher) {
        launcher = FiveFiveFiveLauncher(_launcher);
    }

    function attack(uint256 launchId) external payable {
        launcher.contributeKUB{value: msg.value}(launchId);
    }

    function approveTokens(address token, uint256 amount) external {
        IERC20(token).approve(address(launcher), amount);
    }

    receive() external payable {
        hasReentered = false;
        try launcher.claimRefund(0) {
            // If this succeeds, we've reentered
            hasReentered = true;
        } catch {
            // Expected to fail - contract is secure
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
    address mockStaking;


    address creator = makeAddr("creator");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address feeCollector = makeAddr("feeCollector");
    address treasury = makeAddr("treasury");
    address teamReserve = makeAddr("teamReserve");
    address marketing = makeAddr("marketing");
    address attacker = makeAddr("attacker"); // Add this line


    uint256 constant TARGET_RAISE = 5555 ether;
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant INITIAL_LIQUIDITY = 10_000 ether;
    uint256 constant PONDER_PRICE = 0.1 ether;    // 1 PONDER = 0.1 KUB
    uint256 constant KUB_TO_MEME_KUB_LP = 6000; // 60% of KUB goes to KUB pool
    uint256 constant MAX_PONDER_PERCENT = 2000; // 20%
    uint256 constant MIN_KUB_CONTRIBUTION = 0.01 ether;
    uint256 constant MIN_PONDER_CONTRIBUTION = 0.1 ether;
    uint256 constant MIN_POOL_LIQUIDITY = 50 ether;
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
    event LaunchCancelled(
        uint256 indexed launchId,
        address indexed creator,
        uint256 kubCollected,
        uint256 ponderCollected
    );


    function setUp() public {
        vm.warp(1000);

        // Deploy core contracts
        weth = new WETH9();
        ponder = new PonderToken(teamReserve, address(this), mockStaking);  // mockStaking for testing

        factory = new PonderFactory(address(this), address(this), address(ponder));

        ponderWethPair = factory.createPair(address(ponder), address(weth));

        MockKKUBUnwrapper unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(address(factory), address(weth), address(unwrapper));

        // Setup initial PONDER liquidity using owner's allocation
        // We have 40% for liquidity from initial allocation
        uint256 liquidityAllocation = PonderTokenTypes.INITIAL_LIQUIDITY;
        ponder.transfer(address(this), INITIAL_LIQUIDITY * 10);
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
            ponderWethPair
        );

        _initializeOracleHistory();

        // Deploy launcher ONCE with all dependencies initialized
        launcher = new FiveFiveFiveLauncher(
            address(factory),
            payable(address(router)),
            feeCollector,
            address(ponder),
            address(oracle)
        );

        // Now update the launcher in PonderToken
        ponder.setLauncher(address(launcher));

        // Fund test accounts
        vm.deal(alice, 10000 ether);
        vm.deal(bob, 10000 ether);
        vm.deal(attacker, 10000 ether);

        // Transfer tokens from owner's allocation instead of minting
        ponder.transfer(alice, 100000 ether);
        ponder.transfer(bob, 100000 ether);
        ponder.transfer(attacker, 100000 ether);

        vm.prank(alice);
        ponder.approve(address(launcher), type(uint256).max);
        vm.prank(bob);
        ponder.approve(address(launcher), type(uint256).max);

        // Remove minter setting since we don't use minting anymore
        // ponder.setMinter(address(launcher));  // Remove this line
    }

    function testCreateLaunch() public {
        vm.startPrank(creator);

        FiveFiveFiveLauncherTypes.LaunchParams memory params = FiveFiveFiveLauncherTypes.LaunchParams({
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
        uint256 totalSupply =  LaunchTokenTypes.TOTAL_SUPPLY;

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
        uint256 totalSupply = LaunchTokenTypes.TOTAL_SUPPLY;
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

        assertGt(PonderKAP20(memeKubPair).totalSupply(), 0, "No KUB pool liquidity");
        assertGt(PonderKAP20(memePonderPair).totalSupply(), 0, "No PONDER pool liquidity");
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
        FiveFiveFiveLauncherTypes.LaunchParams memory params = FiveFiveFiveLauncherTypes.LaunchParams({
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
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
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
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
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
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
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
        address wethAddr = router.kkub();
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
        assertGt(PonderKAP20(memeKubPair).totalSupply(), 0, "No KUB pool liquidity");
        assertGt(PonderKAP20(memePonderPair).totalSupply(), 0, "No PONDER pool liquidity");
    }

    function testPartialPreExistingPairs() public {
        uint256 launchId = _createTestLaunch();
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);

        // Only create MEME/KUB pair manually
        address wethAddr = router.kkub();
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
        assertGt(PonderKAP20(memeKubPair).totalSupply(), 0, "No KUB pool liquidity");
        assertGt(PonderKAP20(memePonderPair).totalSupply(), 0, "No PONDER pool liquidity");
        assertTrue(memePonderPair != address(0), "PONDER pair should be created");
    }

    function testLaunchWithZeroPonderContribution() public {
        uint256 launchId = _createTestLaunch();
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);

        // Create both pairs manually
        factory.createPair(tokenAddress, router.kkub());
        factory.createPair(tokenAddress, address(ponder));

        // Complete launch with only KUB
        vm.startPrank(alice);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);
        vm.stopPrank();

        // Verify launch completed with only KUB pool
        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);

        assertFalse(hasSecondaryPool, "Should not have secondary pool with no PONDER contribution");
        assertGt(PonderKAP20(memeKubPair).totalSupply(), 0, "No KUB pool liquidity");

        // Check if memePonderPair exists but has no liquidity
        if (memePonderPair != address(0)) {
            assertEq(PonderKAP20(memePonderPair).totalSupply(), 0, "Should not have PONDER pool liquidity");
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
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
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
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
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
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
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
            uint256 ponderLiquidity = PonderKAP20(address(ponder)).balanceOf(memePonderPair);
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
        assertGt(PonderKAP20(memeKubPair).totalSupply(), 0, "KUB pool should have liquidity");
    }

    function testNoReentrancyInRefund() public {
        uint256 launchId = _createTestLaunch();

        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(launcher)));
        vm.deal(address(attacker), 1 ether);

        // Make initial contribution
        vm.startPrank(address(attacker));
        attacker.attack{value: 1 ether}(launchId);

        // Setup approvals
        (address token,,,,,, ) = launcher.getLaunchInfo(launchId);
        attacker.approveTokens(token, type(uint256).max);
        vm.stopPrank();

        // Cancel launch to enable refunds
        vm.prank(creator);
        launcher.cancelLaunch(launchId);

        // Attempt refund which will trigger receive()
        vm.prank(address(attacker));
        launcher.claimRefund(launchId);

        // Verify no reentry occurred
        assertFalse(attacker.hasReentered(), "Reentrancy should not be possible");
    }

    function testFinalizationFlag() public {
        uint256 launchId = _createTestLaunch();

        // First contribute almost enough to trigger finalization
        uint256 initialContribution = TARGET_RAISE - 1 ether;
        vm.prank(alice);
        launcher.contributeKUB{value: initialContribution}(launchId);

        // Bob tries to contribute while first tx processing
        vm.startPrank(bob);
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
        launcher.contributeKUB{value: 2 ether}(launchId);
        vm.stopPrank();

        // Alice completes the launch
        vm.prank(alice);
        launcher.contributeKUB{value: 1 ether}(launchId);

        // Verify final state
        (,,,,,bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should complete successfully");
    }

    function testContributionStateConsistency() public {
        uint256 launchId = _createTestLaunch();
        uint256 contribution = 1000 ether;

        // Record initial state
        (,,,, uint256 initialKubRaised,,) = launcher.getLaunchInfo(launchId);

        vm.startPrank(alice);
        launcher.contributeKUB{value: contribution}(launchId);

        // Verify state consistency
        (,,,, uint256 finalKubRaised,,) = launcher.getLaunchInfo(launchId);
        assertEq(finalKubRaised, initialKubRaised + contribution, "KUB raised should increase exactly by contribution");

        // Verify contributor info
        (uint256 kubContributed,,,) = launcher.getContributorInfo(launchId, alice);
        assertEq(kubContributed, contribution, "Contributor KUB amount should match");
        vm.stopPrank();
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
        vm.expectRevert(IFiveFiveFiveLauncher.ContributionTooSmall.selector);
        launcher.contributeKUB{value: MIN_KUB_CONTRIBUTION - 1}(launchId);
        vm.stopPrank();
    }

    function testBelowMinimumPonderContribution() public {
        uint256 launchId = _createTestLaunch();

        vm.startPrank(alice);
        vm.expectRevert(IFiveFiveFiveLauncher.ContributionTooSmall.selector);
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
    function testGetMinimumRequirements() public view {
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
        vm.expectRevert(IFiveFiveFiveLauncher.ContributionTooSmall.selector);
        launcher.contributeKUB{value: MIN_KUB_CONTRIBUTION - 1}(launchId);
        vm.stopPrank();
    }

    function testMinimumPonderContribution() public {
        uint256 launchId = _createTestLaunch();

        vm.startPrank(alice);
        // Test exactly minimum
        launcher.contributePONDER(launchId, MIN_PONDER_CONTRIBUTION);

        // Test below minimum
        vm.expectRevert(IFiveFiveFiveLauncher.ContributionTooSmall.selector);
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
        uint256 expectedTokens = _calculateExpectedTokens(oddContribution, LaunchTokenTypes.TOTAL_SUPPLY, TARGET_RAISE);
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
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
        launcher.contributePONDER(launchId, MIN_PONDER_CONTRIBUTION);
        vm.stopPrank();
    }

    function testDuplicateTokenName() public {
        FiveFiveFiveLauncherTypes.LaunchParams memory params1 = FiveFiveFiveLauncherTypes.LaunchParams({
            name: "Test Token",
            symbol: "TEST1",
            imageURI: "ipfs://test"
        });

        FiveFiveFiveLauncherTypes.LaunchParams memory params2 = FiveFiveFiveLauncherTypes.LaunchParams({
            name: "Test Token",  // Same name
            symbol: "TEST2",
            imageURI: "ipfs://test2"
        });

        vm.prank(creator);
        launcher.createLaunch(params1);

        vm.prank(creator);
        vm.expectRevert(IFiveFiveFiveLauncher.TokenNameExists.selector);
        launcher.createLaunch(params2);
    }

    function testInvalidCharactersInName() public {
        FiveFiveFiveLauncherTypes.LaunchParams memory params = FiveFiveFiveLauncherTypes.LaunchParams({
            name: "Test<>Token",  // Invalid characters
            symbol: "TEST",
            imageURI: "ipfs://test"
        });

        vm.prank(creator);
        vm.expectRevert(IFiveFiveFiveLauncher.InvalidTokenParams.selector);
        launcher.createLaunch(params);
    }

    function testValidTokenCreation() public {
        FiveFiveFiveLauncherTypes.LaunchParams memory params = FiveFiveFiveLauncherTypes.LaunchParams({
            name: "Valid-Token_Name",
            symbol: "VTN",
            imageURI: "ipfs://test"
        });

        vm.prank(creator);
        uint256 launchId = launcher.createLaunch(params);

        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        assertTrue(tokenAddress != address(0), "Token should be created");
    }

    function testMultipleSimultaneousLaunches() public {
        // Create multiple addresses to simulate concurrent launches
        address[] memory launchers = new address[](3);
        for(uint i = 0; i < 3; i++) {
            launchers[i] = makeAddr(string.concat("launcher", vm.toString(i)));
        }

        // Try to launch simultaneously
        for(uint i = 0; i < 3; i++) {
            vm.prank(launchers[i]);
            FiveFiveFiveLauncherTypes.LaunchParams memory params = FiveFiveFiveLauncherTypes.LaunchParams({
                name: string.concat("Token", vm.toString(i)),
                symbol: string.concat("TKN", vm.toString(i)),
                imageURI: "ipfs://test"
            });
            launcher.createLaunch(params);
        }

        // Verify launchIds are sequential and no launches were lost
        assertEq(launcher.launchCount(), 3, "Should have exactly 3 launches");
    }

    function testSuccessfulContribution() public {
        uint256 launchId = _createTestLaunch();

        // Make a normal contribution
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        launcher.contributeKUB{value: 0.5 ether}(launchId);

        // Verify state was updated correctly
        (uint256 kubCollected,,,) = launcher.getContributionInfo(launchId);
        assertEq(kubCollected, 0.5 ether, "KUB collected should be updated");

        // Verify token transfer
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        uint256 aliceBalance = LaunchToken(tokenAddress).balanceOf(alice);
        assertTrue(aliceBalance > 0, "Alice should have received tokens");
    }

    function testContributionRejection() public {
        uint256 launchId = _createTestLaunch();

        TokenRejecter rejecter = new TokenRejecter(payable(address(launcher)));
        vm.deal(address(rejecter), 1 ether);

        // First contribution should succeed
        vm.prank(address(rejecter));
        rejecter.attemptContribution{value: 0.5 ether}(launchId);

        // Record state after first contribution
        (uint256 initialKubCollected,,,) = launcher.getContributionInfo(launchId);

        // Set rejection mode
        rejecter.setShouldReject(true);

        // Contribution should fail at TokenRejecter level
        vm.prank(address(rejecter));
        vm.expectRevert("ETH transfer rejected at source");
        rejecter.attemptContribution{value: 0.5 ether}(launchId);

        // Verify state is unchanged
        (uint256 finalKubCollected,,,) = launcher.getContributionInfo(launchId);
        assertEq(finalKubCollected, initialKubCollected, "State should not change after rejected attempt");
    }

    function testPriceManipulationResistance() public {
        uint256 launchId = _createTestLaunch();

        // Setup proper oracle history first
        for (uint i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Deal PONDER to our test accounts
        deal(address(ponder), alice, 2000 ether);
        deal(address(ponder), bob, 100000 ether);

        // Approve spending
        vm.startPrank(alice);
        ponder.approve(address(launcher), 2000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        ponder.approve(address(router), 100000 ether);

        // Execute price manipulation
        address[] memory path = _getPath(address(ponder), address(weth));
        router.swapExactTokensForTokens(
            50000 ether, // Large swap to move price
            0,
            path,
            bob,
            block.timestamp
        );

        // Try to contribute - should fail due to price deviation
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessivePriceDeviation.selector);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();
    }

    function testPriceManipulationWithInsufficientHistory() public {
        uint256 launchId = _createTestLaunch();

        // Deal enough PONDER to alice for test
        deal(address(ponder), alice, 1000 ether);

        // Reset all oracle history
        vm.warp(block.timestamp + 24 hours); // Move way past any existing updates

        vm.startPrank(alice);
        ponder.approve(address(launcher), 1000 ether);

        // Should revert with StalePrice since no recent price data
        vm.expectRevert(IPonderPriceOracle.InvalidTimeElapsed.selector);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();
    }

    function testPriceStalenessProtection() public {
        uint256 launchId = _createTestLaunch();

        // Initialize history but then move time forward past staleness threshold
        _initializeOracleHistory();
        vm.warp(block.timestamp + 2 hours + 1); // Using explicit time since PRICE_STALENESS_THRESHOLD = 2 hours

        vm.startPrank(alice);
        vm.expectRevert(IPonderPriceOracle.InvalidTimeElapsed.selector);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();
    }


    function testMultiBlockManipulationResistance() public {
        uint256 launchId = _createTestLaunch();

        // Setup proper oracle history first
        for (uint i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Deal tokens to Bob for manipulation
        deal(address(ponder), bob, 100000 ether);

        vm.startPrank(bob);
        ponder.approve(address(router), 100000 ether);

        address[] memory path = _getPath(address(ponder), address(weth));

        // Execute multiple smaller swaps
        for (uint i = 0; i < 5; i++) {
            router.swapExactTokensForTokens(
                10000 ether,
                0,
                path,
                bob,
                block.timestamp
            );

            // Move time and update oracle
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Should fail due to accumulated deviation
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessivePriceDeviation.selector);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();
    }

    function _getPonderEquivalent(uint256 kubValue) internal pure returns (uint256) {
        return kubValue * 10; // 1 PONDER = 0.1 KUB
    }

    function _getKubValue(uint256 ponderAmount) internal pure returns (uint256) {
        return ponderAmount / 10; // 1 PONDER = 0.1 KUB
    }

    function _getPath(address tokenIn, address tokenOut) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return path;
    }

    function testConcurrentPoolCreation() public {
        uint256 launchId = _createTestLaunch();

        // Contribute enough to nearly complete the launch
        uint256 almostComplete = TARGET_RAISE - 1 ether;
        vm.prank(alice);
        launcher.contributeKUB{value: almostComplete}(launchId);

        // Try to complete launch from two different addresses simultaneously
        vm.prank(bob);
        launcher.contributeKUB{value: 0.6 ether}(launchId);

        vm.prank(alice);
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
        launcher.contributeKUB{value: 0.6 ether}(launchId);
    }

    function testPoolCreationWithMinimumValues() public {
        uint256 launchId = _createTestLaunch();

        // Calculate minimum contribution that creates valid pools
        // Need to account for both MIN_POOL_LIQUIDITY and the KUB_TO_MEME_KUB_LP ratio
        uint256 minValidContribution = (MIN_POOL_LIQUIDITY * BASIS_POINTS) / KUB_TO_MEME_KUB_LP;

        // Need to contribute enough to meet target raise
        vm.startPrank(alice);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);
        vm.stopPrank();

        // Verify launch completed and pools are created
        (address memeKubPair,,) = launcher.getPoolInfo(launchId);

        // Check pool liquidity
        (uint112 reserve0, uint112 reserve1,) = PonderPair(memeKubPair).getReserves();
        assertTrue(
            uint256(reserve0) >= MIN_POOL_LIQUIDITY || uint256(reserve1) >= MIN_POOL_LIQUIDITY,
            "Pool liquidity too low"
        );
    }

    function testPoolRatioManipulation() public {
        uint256 launchId = _createTestLaunch();

        // Try to manipulate pool ratios by using extreme values
        uint256 largeContribution = TARGET_RAISE / 2;
        vm.prank(alice);
        launcher.contributeKUB{value: largeContribution}(launchId);

        // Calculate PONDER amount that would create skewed ratios
        uint256 skewedPonderAmount = _getPonderEquivalent(largeContribution * 3);

        vm.startPrank(bob);
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessiveContribution.selector);
        launcher.contributePONDER(launchId, skewedPonderAmount);
        vm.stopPrank();
    }

    function testPriceSettingAttackResistance() public {
        uint256 launchId = _createTestLaunch();

        // First make a partial contribution
        vm.startPrank(alice);
        launcher.contributeKUB{value: TARGET_RAISE - 1 ether}(launchId);
        vm.stopPrank();

        // Setup attacker
        address attacker = makeAddr("attacker");
        vm.deal(attacker, 1000 ether);

        // Get token and pool info
        (address token,,,,,,) = launcher.getLaunchInfo(launchId);

        // Complete the launch
        vm.prank(alice);
        launcher.contributeKUB{value: 1 ether}(launchId);

        // Get pool info and initial price
        (address memeKubPair,,) = launcher.getPoolInfo(launchId);
        (uint112 initialReserve0, uint112 initialReserve1,) = PonderPair(memeKubPair).getReserves();
        uint256 initialPrice = uint256(initialReserve1) * 1e18 / uint256(initialReserve0);

        // Try to manipulate price
        vm.startPrank(attacker);
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = token;

        router.swapExactETHForTokens{value: 100 ether}(
            0,
            path,
            attacker,
            block.timestamp + 1
        );
        vm.stopPrank();

        // Check price impact
        (uint112 finalReserve0, uint112 finalReserve1,) = PonderPair(memeKubPair).getReserves();
        uint256 finalPrice = uint256(finalReserve1) * 1e18 / uint256(finalReserve0);

        // Verify price impact is limited
        uint256 priceImpact = (initialPrice > finalPrice)
            ? ((initialPrice - finalPrice) * 100) / initialPrice
            : ((finalPrice - initialPrice) * 100) / initialPrice;

        assertTrue(
            priceImpact <= 10,  // Price impact should be limited to 10%
            "Price impact too large"
        );
    }

    function testRefundWithMixedContributions() public {
        uint256 launchId = _createTestLaunch();

        // Make mixed contributions
        vm.startPrank(alice);
        launcher.contributeKUB{value: 1000 ether}(launchId);
        vm.stopPrank();

        vm.startPrank(bob);
        uint256 ponderAmount = 1000 ether; // Will be worth 100 ETH at 0.1 ETH/PONDER
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();

        // Cancel launch
        vm.prank(creator);
        launcher.cancelLaunch(launchId);

        // Record balances before refund
        uint256 aliceKubBefore = address(alice).balance;
        uint256 bobPonderBefore = ponder.balanceOf(bob);

        // Claim refunds
        vm.startPrank(alice);
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);
        launcher.claimRefund(launchId);
        vm.stopPrank();

        vm.startPrank(bob);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);
        launcher.claimRefund(launchId);
        vm.stopPrank();

        // Verify correct refund amounts
        assertEq(address(alice).balance - aliceKubBefore, 1000 ether, "KUB refund incorrect");
        assertEq(ponder.balanceOf(bob) - bobPonderBefore, ponderAmount, "PONDER refund incorrect");
    }

    function testRefundStateConsistency() public {
        uint256 launchId = _createTestLaunch();

        // Make contribution
        vm.startPrank(alice);
        launcher.contributeKUB{value: 1000 ether}(launchId);

        // Get initial state
        (uint256 kubContributedBefore,,,) = launcher.getContributorInfo(launchId, alice);
        vm.stopPrank();

        // Cancel launch
        vm.startPrank(creator);
        launcher.cancelLaunch(launchId);
        vm.stopPrank();

        // Refund
        vm.startPrank(alice);
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);
        launcher.claimRefund(launchId);

        // Check final state
        (uint256 kubContributedAfter,,,) = launcher.getContributorInfo(launchId, alice);

        assertGt(kubContributedBefore, 0, "Initial contribution not recorded");
        assertEq(kubContributedAfter, 0, "Contribution not cleared after refund");
        vm.stopPrank();
    }

    function testMultipleRefundAttempts() public {
        uint256 launchId = _createTestLaunch();

        // Make contribution
        vm.startPrank(alice);
        launcher.contributeKUB{value: 1000 ether}(launchId);
        vm.stopPrank();

        // Cancel launch
        vm.startPrank(creator);
        launcher.cancelLaunch(launchId);
        vm.stopPrank();

        // First refund
        vm.startPrank(alice);
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);
        launcher.claimRefund(launchId);

        // Try to refund again
        vm.expectRevert(IFiveFiveFiveLauncher.NoContributionToRefund.selector);
        launcher.claimRefund(launchId);
        vm.stopPrank();
    }

    function testRefundWithoutTokenApproval() public {
        uint256 launchId = _createTestLaunch();

        // Make contribution
        vm.startPrank(alice);
        launcher.contributeKUB{value: 1000 ether}(launchId);
        vm.stopPrank();

        // Cancel launch
        vm.startPrank(creator);
        launcher.cancelLaunch(launchId);
        vm.stopPrank();

        // Try refund without approval
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("TokenApprovalRequired()"));
        launcher.claimRefund(launchId);
        vm.stopPrank();
    }

    function testRefundAfterSuccessfulLaunch() public {
        uint256 launchId = _createTestLaunch();

        // Complete the launch successfully
        vm.startPrank(alice);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);

        // Setup for refund attempt
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);

        // Force past launch deadline
        vm.warp(block.timestamp + 7 days + 1);

        // Try to claim refund after successful launch
        vm.expectRevert(abi.encodeWithSignature("LaunchSucceeded()"));
        launcher.claimRefund(launchId);
        vm.stopPrank();
    }

    function testRefundDuringActiveLaunch() public {
        uint256 launchId = _createTestLaunch();

        // Make contribution
        vm.startPrank(alice);
        launcher.contributeKUB{value: 1000 ether}(launchId);

        // Try refund before deadline/cancel
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);
        vm.expectRevert(abi.encodeWithSignature("LaunchStillActive()"));
        launcher.claimRefund(launchId);
        vm.stopPrank();
    }

    function testRefundAtomicTransactions() public {
        uint256 launchId = _createTestLaunch();

        // Setup mixed contribution (both KUB and PONDER)
        vm.startPrank(alice);
        launcher.contributeKUB{value: 1000 ether}(launchId);
        launcher.contributePONDER(launchId, 10000 ether);
        vm.stopPrank();

        // Cancel launch
        vm.prank(creator);
        launcher.cancelLaunch(launchId);

        // Record initial balances
        uint256 initialKUB = address(alice).balance;
        uint256 initialPONDER = ponder.balanceOf(alice);

        // Setup token approvals
        vm.startPrank(alice);
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);

        // Process refund and verify atomicity
        launcher.claimRefund(launchId);

        // Verify both KUB and PONDER were refunded atomically
        assertEq(address(alice).balance - initialKUB, 1000 ether, "KUB refund incorrect");
        assertEq(ponder.balanceOf(alice) - initialPONDER, 10000 ether, "PONDER refund incorrect");
        vm.stopPrank();
    }

    function testRefundWithContractReceiver() public {
        uint256 launchId = _createTestLaunch();
        ReentrantAttacker attacker = new ReentrantAttacker(payable(address(launcher)));

        // Setup contribution
        vm.deal(address(attacker), 1 ether);
        vm.prank(address(attacker));
        attacker.attack{value: 1 ether}(launchId);

        // Cancel launch
        vm.prank(creator);
        launcher.cancelLaunch(launchId);

        // Setup token approvals
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        vm.prank(address(attacker));
        attacker.approveTokens(tokenAddress, type(uint256).max);

        // Verify refund succeeds without reentrancy
        vm.prank(address(attacker));
        launcher.claimRefund(launchId);

        // Verify no reentrancy occurred
        assertFalse(attacker.hasReentered(), "Refund should be reentrant-safe");
    }

    function testRefundStateValidation() public {
        uint256 launchId = _createTestLaunch();

        // Make initial contribution
        vm.startPrank(alice);
        launcher.contributeKUB{value: 1 ether}(launchId);
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken(tokenAddress).approve(address(launcher), type(uint256).max);

        // Try refund before cancellation/deadline - should revert with "Launch still active"
        vm.expectRevert(abi.encodeWithSignature("LaunchStillActive()"));
        launcher.claimRefund(launchId);

        // Complete the launch
        launcher.contributeKUB{value: TARGET_RAISE - 1 ether}(launchId);

        // Move past launch deadline
        vm.warp(block.timestamp + 7 days + 1);

        // Try refund after successful launch - should revert with "Launch succeeded"
        vm.expectRevert(abi.encodeWithSignature("LaunchSucceeded()"));
        launcher.claimRefund(launchId);
        vm.stopPrank();
    }

    function testDeadlineProtection() public {
        uint256 launchId = _createTestLaunch();

        // Contribute to complete launch
        vm.prank(alice);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);

        // Try adding late liquidity (3 minutes after launch completion)
        vm.warp(block.timestamp + 3 minutes);

        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        address pair = factory.getPair(tokenAddress, router.kkub());

        vm.startPrank(attacker);
        vm.expectRevert(); // Should fail due to deadline
        router.addLiquidityETH{value: 1 ether}(
            tokenAddress,
            1000 ether,
            0,
            0,
            attacker,
            block.timestamp
        );
        vm.stopPrank();
    }

    function testMinimumPoolLiquidity() public {
        uint256 launchId = _createTestLaunch();

        // Calculate minimum contribution needed for valid pool
        uint256 minPoolLiquidity = MIN_POOL_LIQUIDITY;
        uint256 minRequired = (minPoolLiquidity * BASIS_POINTS) / KUB_TO_MEME_KUB_LP;

        // Need to contribute enough to actually complete the launch
        vm.startPrank(alice);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);
        vm.stopPrank();

        // Now verify pool was created with sufficient liquidity
        (address memeKubPair,,) = launcher.getPoolInfo(launchId);
        assertTrue(memeKubPair != address(0), "Pool should be created");

        // Verify pool has minimum liquidity
        uint256 liquidity = PonderKAP20(memeKubPair).totalSupply();
        assertTrue(liquidity >= minPoolLiquidity, "Pool liquidity too low");

        // Verify reserves are properly set
        (uint112 reserve0, uint112 reserve1,) = PonderPair(memeKubPair).getReserves();
        assertTrue(uint256(reserve0) > 0 && uint256(reserve1) > 0, "Pool reserves not set");
    }

    function testLargeAndSmallDualPools() public {
        uint256 launchId = _createTestLaunch();

        // Contribute 80% in KUB
        uint256 kubAmount = (TARGET_RAISE * 80) / 100;  // 4444 ether
        vm.prank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);

        // Contribute 20% in PONDER
        uint256 ponderValue = (TARGET_RAISE * 20) / 100;  // 1111 ether in KUB value
        uint256 ponderAmount = ponderValue * 10;  // Convert to PONDER amount at 0.1 KUB per PONDER

        vm.prank(bob);
        launcher.contributePONDER(launchId, ponderAmount);

        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) = launcher.getPoolInfo(launchId);

        // Get KUB pool reserves - reserve1 is KUB
        (,uint112 kubReserve1,) = PonderPair(memeKubPair).getReserves();
        uint256 kubPoolValue = uint256(kubReserve1); // KUB value

        // Get PONDER pool reserves - reserve0 is PONDER
        (uint112 ponderReserve0,,) = PonderPair(memePonderPair).getReserves();
        // Convert PONDER amount to KUB value using oracle
        uint256 ponderPoolValue = _getPonderValue(uint256(ponderReserve0));

        assertTrue(kubPoolValue > ponderPoolValue, "KUB pool should be larger");
    }

    function testDualPoolSlippageProtection() public {
        uint256 launchId = _createTestLaunch();

        // Setup normal contributions
        uint256 kubAmount = (TARGET_RAISE * 80) / 100;
        vm.prank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);

        uint256 ponderValue = (TARGET_RAISE * 20) / 100;
        uint256 ponderAmount = ponderValue * 10;

        // Try to manipulate PONDER price right before contribution
        address[] memory path = _getPath(address(ponder), address(weth));

        vm.startPrank(bob);
        ponder.approve(address(router), ponderAmount * 2);

        // Execute large swap to move price
        router.swapExactTokensForTokens(
            ponderAmount,
            0,
            path,
            bob,
            block.timestamp
        );

        // Contribution should fail due to price impact
        vm.expectRevert(IFiveFiveFiveLauncher.ExcessivePriceDeviation.selector);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();
    }

    function testInitialPriceManipulationResistance() public {
        uint256 launchId = _createTestLaunch();
        (address tokenAddress,,,,,, ) = launcher.getLaunchInfo(launchId);
        LaunchToken token = LaunchToken(tokenAddress);

        // Enable transfers first
        vm.prank(address(launcher));
        token.enableTransfers();

        // Wait for trading restriction period to end
        vm.warp(block.timestamp + 15 minutes);

        // Create pairs
        address kubPair = factory.createPair(tokenAddress, address(weth));

        // Give attacker tokens and funds
        deal(tokenAddress, attacker, 2000 ether);
        deal(address(weth), attacker, 2000 ether);

        // Attempt price manipulation by adding manipulated liquidity
        vm.startPrank(attacker);
        // Approve tokens
        token.approve(address(router), 500 ether);
        IERC20(address(weth)).approve(address(router), 0.05 ether);

        // Add manipulated liquidity
        router.addLiquidityETH{value: 0.05 ether}(
            tokenAddress,
            500 ether,
            0, // No min amount
            0, // No min amount
            attacker,
            block.timestamp
        );
        vm.stopPrank();

        // Try to complete launch - should revert
        vm.startPrank(alice);
        vm.expectRevert(IFiveFiveFiveLauncher.PriceOutOfBounds.selector);
        launcher.contributeKUB{value: TARGET_RAISE}(launchId);
        vm.stopPrank();

        // Verify pairs still have no official liquidity
        (address memeKubPair,,) = launcher.getPoolInfo(launchId);
        assertEq(memeKubPair, address(0), "KUB pair should not be set");

        // Launch should not be marked as completed
        (,,,,,bool launched,) = launcher.getLaunchInfo(launchId);
        assertFalse(launched, "Launch should not complete when manipulated");
    }

    function testBelowMinimumPonderPoolSkipped() public {
        uint256 launchId = _createTestLaunch();

        // First contribute most in KUB but leave room for PONDER and final contribution
        uint256 kubAmount = TARGET_RAISE - 1.5 ether;  // Leave 1.5 ETH worth of space
        vm.prank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);

        // Small PONDER contribution
        uint256 tinyPonderValue = 0.5 ether; // Below MIN_POOL_LIQUIDITY
        uint256 ponderAmount = tinyPonderValue * 10;
        uint256 initialPonderSupply = ponder.totalSupply();

        vm.prank(bob);
        launcher.contributePONDER(launchId, ponderAmount);

        // Complete launch with remaining amount
        vm.prank(alice);
        launcher.contributeKUB{value: 1 ether}(launchId);

        // Verify pool creation results
        (address memeKubPair, address memePonderPair, bool hasSecondaryPool) =
                            launcher.getPoolInfo(launchId);

        assertFalse(hasSecondaryPool, "Should not create secondary pool");
        assertTrue(memeKubPair != address(0), "Should create KUB pool");
        assertTrue(memePonderPair == address(0), "Should not create PONDER pool");

        // Verify PONDER was burned
        uint256 finalPonderSupply = ponder.totalSupply();
        assertEq(
            initialPonderSupply - finalPonderSupply,
            ponderAmount,
            "All PONDER should be burned when skipping pool"
        );
    }

    function testCancelLaunchSecurityChecks() public {
        // Test 1: Cannot cancel non-existent launch
        vm.expectRevert(IFiveFiveFiveLauncher.LaunchNotCancellable.selector);
        launcher.cancelLaunch(999);

        // Create a test launch with unique name/symbol
        FiveFiveFiveLauncherTypes.LaunchParams memory params = FiveFiveFiveLauncherTypes.LaunchParams({
            name: "Security Test Token",
            symbol: "STT",
            imageURI: "ipfs://test"
        });

        vm.prank(creator);
        uint256 launchId = launcher.createLaunch(params);

        // Test 2: Only creator can cancel
        vm.prank(alice);
        vm.expectRevert(IFiveFiveFiveLauncher.Unauthorized.selector);
        launcher.cancelLaunch(launchId);

        // Test 3: Cannot cancel after deadline
        vm.warp(block.timestamp + 7 days + 1);
        vm.prank(creator);
        vm.expectRevert(IFiveFiveFiveLauncher.LaunchDeadlinePassed.selector);
        launcher.cancelLaunch(launchId);

        // Reset time and create new launch with different name
        vm.warp(1000);
        params.name = "Security Test Token 2";
        params.symbol = "STT2";

        vm.startPrank(creator);
        uint256 launchId2 = launcher.createLaunch(params);

        // Contribute almost enough to complete
        vm.stopPrank();

        vm.startPrank(alice);
        launcher.contributeKUB{value: TARGET_RAISE - 1 ether}(launchId2);
        vm.stopPrank();

        // Complete launch
        vm.prank(bob);
        launcher.contributeKUB{value: 1 ether}(launchId2);

        // Test 4: Cannot cancel completed launch
        vm.prank(creator);
        vm.expectRevert(IFiveFiveFiveLauncher.LaunchNotCancellable.selector);
        launcher.cancelLaunch(launchId2);
    }

    function testCancelLaunchNameSymbolReuse() public {
        // Create first launch
        FiveFiveFiveLauncherTypes.LaunchParams memory params = FiveFiveFiveLauncherTypes.LaunchParams({
            name: "Test Token",
            symbol: "TEST",
            imageURI: "ipfs://test"
        });

        vm.startPrank(creator);
        uint256 launchId = launcher.createLaunch(params);

        // Cancel first launch
        launcher.cancelLaunch(launchId);

        // Should be able to reuse name and symbol
        uint256 launchId2 = launcher.createLaunch(params);
        vm.stopPrank();

        // Verify second launch was created successfully
        (,string memory name, string memory symbol,,,,) = launcher.getLaunchInfo(launchId2);
        assertEq(name, "Test Token");
        assertEq(symbol, "TEST");
    }

    function testCancelLaunchEvent() public {
        uint256 launchId = _createTestLaunch();

        // Make some contributions
        vm.prank(alice);
        launcher.contributeKUB{value: 1000 ether}(launchId);

        vm.prank(bob);
        launcher.contributePONDER(launchId, 10000 ether);

        // Record contributions before cancel
        (uint256 kubCollected, uint256 ponderCollected,,) = launcher.getContributionInfo(launchId);

        // Watch for event emission
        vm.expectEmit(true, true, false, true);
        emit LaunchCancelled(launchId, creator, kubCollected, ponderCollected);

        // Cancel launch
        vm.prank(creator);
        launcher.cancelLaunch(launchId);
    }

    function testPonderContributions() public {
        uint256 launchId = _createTestLaunch();

        // Get the PONDER-KUB pair
        address ponderKubPair = factory.getPair(address(ponder), router.kkub());

        // Warp time forward before updating oracle
        vm.warp(block.timestamp + 1 hours);

        // Update oracle
        oracle.update(ponderKubPair);

        // Warp time forward again to allow contribution
        vm.warp(block.timestamp + 1 hours);

        // Try contribution
        vm.startPrank(alice);
        ponder.approve(address(launcher), 1000 ether);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();

        // Verify the contribution was successful
        (,uint256 ponderContributed,,) = launcher.getContributorInfo(launchId, alice);
        assertEq(ponderContributed, 1000 ether, "PONDER contribution failed");
    }

    function testExcessivePriceDeviationError() public {
        uint256 launchId = _createTestLaunch();

        // Setup proper oracle history first
        for (uint i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Deal PONDER to our test accounts
        deal(address(ponder), alice, 2000 ether);
        deal(address(ponder), bob, 100000 ether);

        // Approve spending
        vm.startPrank(alice);
        ponder.approve(address(launcher), 2000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        ponder.approve(address(router), 100000 ether);

        // Execute price manipulation
        address[] memory path = _getPath(address(ponder), address(weth));
        router.swapExactTokensForTokens(
            50000 ether, // Large swap to move price
            0,
            path,
            bob,
            block.timestamp
        );

        // Try to contribute - should fail with exact error signature 0xf7f78816
        bytes memory expectedError = abi.encodeWithSignature("ExcessivePriceDeviation()");
        vm.expectRevert(expectedError);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();
    }

    function testLiquidityDepthThresholds() public {
        // Store initial liquidity for later comparison
        (uint112 initialReserve0, uint112 initialReserve1,) = PonderPair(ponderWethPair).getReserves();
        console.log("Initial KOI Reserve:", initialReserve0);
        console.log("Initial KKUB Reserve:", initialReserve1);

        // Create a new launch
        uint256 launchId = _createTestLaunch();

        // Setup oracle history
        for (uint i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Test contribution sizes relative to pool depth
        uint256[] memory contributionPercentages = new uint256[](5);
        contributionPercentages[0] = 1;    // 1% of pool depth
        contributionPercentages[1] = 5;    // 5% of pool depth
        contributionPercentages[2] = 10;   // 10% of pool depth
        contributionPercentages[3] = 15;   // 15% of pool depth
        contributionPercentages[4] = 20;   // 20% of pool depth

        console.log("\nTesting different contribution sizes relative to pool depth:");

        for (uint i = 0; i < contributionPercentages.length; i++) {
            uint256 percentage = contributionPercentages[i];
            uint256 ponderAmount = (uint256(initialReserve0) * percentage) / 100;

            // Fund test account
            deal(address(ponder), alice, ponderAmount);

            vm.startPrank(alice);
            ponder.approve(address(launcher), ponderAmount);

            // Try contribution and log result
            try launcher.contributePONDER(launchId, ponderAmount) {
                console.log("%d%% of pool depth (Amount: %d KOI) - Success", percentage, ponderAmount / 1e18);
            } catch (bytes memory err) {
                bytes4 errorSig = bytes4(err);
                if (errorSig == bytes4(0xf7f78816)) { // ExcessivePriceDeviation
                    console.log("%d%% of pool depth (Amount: %d KOI) - Failed: ExcessivePriceDeviation", percentage, ponderAmount / 1e18);
                } else {
                    console.log("%d%% of pool depth (Amount: %d KOI) - Failed: Other error", percentage, ponderAmount / 1e18);
                }
            }
            vm.stopPrank();

            // Reset pool state for next test
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Now test with increased liquidity
        console.log("\nIncreasing pool liquidity by 10x and retesting:");

        // Add significant liquidity to the pool
        deal(address(ponder), address(this), initialReserve0 * 10);
        deal(address(weth), address(this), initialReserve1 * 10);

        ponder.approve(address(router), type(uint256).max);
        IERC20(address(weth)).approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(ponder),
            address(weth),
            initialReserve0 * 9,  // Add 9x more (plus existing = 10x)
            initialReserve1 * 9,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Update oracle with new liquidity
        for (uint i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Test same percentages with increased liquidity
        for (uint i = 0; i < contributionPercentages.length; i++) {
            uint256 percentage = contributionPercentages[i];
            uint256 ponderAmount = (uint256(initialReserve0) * 10 * percentage) / 100;

            deal(address(ponder), alice, ponderAmount);

            vm.startPrank(alice);
            ponder.approve(address(launcher), ponderAmount);

            try launcher.contributePONDER(launchId, ponderAmount) {
                console.log("%d%% of increased pool depth (Amount: %d KOI) - Success", percentage, ponderAmount / 1e18);
            } catch (bytes memory err) {
                bytes4 errorSig = bytes4(err);
                if (errorSig == bytes4(0xf7f78816)) {
                    console.log("%d%% of increased pool depth (Amount: %d KOI) - Failed: ExcessivePriceDeviation", percentage, ponderAmount / 1e18);
                } else {
                    console.log("%d%% of increased pool depth (Amount: %d KOI) - Failed: Other error", percentage, ponderAmount / 1e18);
                }
            }
            vm.stopPrank();

            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }
    }

    function testDebugPriceDeviationWithLiveConditions() public {
        uint256 launchId = _createTestLaunch();

        // Set exact reserves from production
        uint256 koiReserve = 227_582.354146170690 ether;
        uint256 kkubReserve = 1_103.044632190 ether;

        // Setup pool state
        deal(address(ponder), ponderWethPair, koiReserve);
        deal(address(weth), ponderWethPair, kkubReserve);
        PonderPair(ponderWethPair).sync();

        // Instead of trying to update oracle, let's check current state
        (uint112 reserve0, uint112 reserve1, uint32 lastUpdateTime) = PonderPair(ponderWethPair).getReserves();
        console.log("\nPool State:");
        console.log("KOI Reserve:", reserve0 / 1e18);
        console.log("KKUB Reserve:", reserve1 / 1e18);
        console.log("Last Update Time:", lastUpdateTime);

        // Get current prices without updating oracle
        uint256 spotPrice = oracle.getCurrentPrice(
            ponderWethPair,
            address(ponder),
            1e18
        );

        console.log("\nSpot Price in KKUB:", spotPrice / 1e18);

        // Try to make contribution
        uint256 contributionAmount = 1111 ether;

        vm.startPrank(alice);
        deal(address(ponder), alice, contributionAmount);
        ponder.approve(address(launcher), contributionAmount);

        // Get price impact for this contribution size
        uint256 contributionSpotPrice = oracle.getCurrentPrice(
            ponderWethPair,
            address(ponder),
            contributionAmount
        );
        console.log("\nPrice Impact Analysis:");
        console.log("Contribution Amount:", contributionAmount / 1e18, "KOI");
        console.log("Price for full contribution:", contributionSpotPrice / 1e18, "KKUB");

        try launcher.contributePONDER(launchId, contributionAmount) {
            console.log("\nContribution succeeded!");
        } catch (bytes memory returnData) {
            bytes4 errorSig = bytes4(returnData);
            console.log("\nContribution failed with error signature:", toHexString(errorSig));

            if (errorSig == bytes4(0xf7f78816)) { // ExcessivePriceDeviation
                console.log("Failed due to ExcessivePriceDeviation");
            }
        }
        vm.stopPrank();
    }

// Helper function to convert bytes4 to hex string
    function toHexString(bytes4 data) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(10);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 4; i++) {
            str[2+i*2] = alphabet[uint8(data[i] >> 4)];
            str[3+i*2] = alphabet[uint8(data[i] & 0x0f)];
        }
        return string(str);
    }

    function testPonderContributionWithOracleSetup() public {
        uint256 launchId = _createTestLaunch();

        // Setup initial liquidity with similar ratios to deployment
        uint256 kubAmount = 1000 ether;
        uint256 ponderAmount = 200_000 ether;

        // Deal tokens and KUB to this contract
        deal(address(ponder), address(this), ponderAmount);
        vm.deal(address(this), kubAmount * 2);

        ponder.approve(address(router), ponderAmount);

        // Add initial liquidity
        router.addLiquidityETH{value: kubAmount}(
            address(ponder),
            ponderAmount,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        // Check pair setup
        address ponderKubPair = factory.getPair(address(ponder), address(weth));
        console.log("\nPair Addresses:");
        console.log("PONDER-KUB pair:", ponderKubPair);

        // Get tokens in pair
        address token0 = PonderPair(ponderKubPair).token0();
        address token1 = PonderPair(ponderKubPair).token1();
        console.log("\nToken Addresses:");
        console.log("Pair token0:", token0);
        console.log("Pair token1:", token1);
        console.log("PONDER token:", address(ponder));
        console.log("WETH token:", address(weth));

        // Initialize oracle history
        console.log("\nPrice History:");
        for (uint i = 0; i < 15; i++) {
            vm.warp(block.timestamp + 5 minutes);
            PonderPair(ponderKubPair).sync();

            // Get cumulative prices before update
            uint256 price0CumulativeLast = PonderPair(ponderKubPair).price0CumulativeLast();
            uint256 price1CumulativeLast = PonderPair(ponderKubPair).price1CumulativeLast();
            console.log("\nBefore update %s:", i);
            console.log("price0Cumulative:", price0CumulativeLast);
            console.log("price1Cumulative:", price1CumulativeLast);

            oracle.update(ponderKubPair);

            // Get reserves after update
            (uint112 r0, uint112 r1,) = PonderPair(ponderKubPair).getReserves();
            console.log("After update %s - Reserves:", i);
            console.log("token0:", uint256(r0) / 1e18);
            console.log("token1:", uint256(r1) / 1e18);
        }

        // Wait additional time to ensure we have enough history
        vm.warp(block.timestamp + 1 hours);
        PonderPair(ponderKubPair).sync();
        oracle.update(ponderKubPair);

        // Log the spot price and TWAP
        uint256 spotPrice = oracle.getCurrentPrice(
            ponderKubPair,
            address(ponder),
            1 ether
        );
        console.log("\nFinal Prices:");
        console.log("Spot Price (KUB per PONDER):", spotPrice / 1e18);

        uint256 twapPrice = oracle.consult(
            ponderKubPair,
            address(ponder),
            1 ether,
            1 hours
        );
        console.log("TWAP Price (KUB per PONDER):", twapPrice / 1e18);

        // Try to contribute PONDER
        uint256 ponderContribution = 1000 ether;
        vm.startPrank(alice);
        deal(address(ponder), alice, ponderContribution);
        ponder.approve(address(launcher), ponderContribution);

        console.log("\nAttempting PONDER contribution of:", ponderContribution / 1e18);
        launcher.contributePONDER(launchId, ponderContribution);
        vm.stopPrank();

        // Verify contribution succeeded
        (,uint256 ponderContributed,,) = launcher.getContributorInfo(launchId, alice);
        assertEq(ponderContributed, ponderContribution, "PONDER contribution failed");
    }

    function testPriceValidationFailure() public {
        uint256 launchId = _createTestLaunch();

        // Initialize oracle history
        for (uint i = 0; i < 3; i++) {
            vm.warp(block.timestamp + 3 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Get last update time and advance significantly
        uint256 lastUpdateTime = oracle.lastUpdateTime(ponderWethPair);
        vm.warp(lastUpdateTime + 24 hours);

        vm.startPrank(alice);
        vm.expectRevert(IPonderPriceOracle.InvalidTimeElapsed.selector);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();
    }

    function testPriceCalculation() public {
        uint256 launchId = _createTestLaunch();

        uint256 kubAmount = 1000 ether;
        uint256 ponderAmount = 200_000 ether;

        deal(address(ponder), address(this), ponderAmount);
        vm.deal(address(this), kubAmount);
        ponder.approve(address(router), ponderAmount);

        router.addLiquidityETH{value: kubAmount}(
            address(ponder),
            ponderAmount,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        address ponderKubPair = factory.getPair(address(ponder), address(weth));

        // Get reserves
        (uint112 r0, uint112 r1,) = PonderPair(ponderKubPair).getReserves();
        console.log("Reserves before price check:");
        console.log("Reserve0 (PONDER):", uint256(r0) / 1e18);
        console.log("Reserve1 (KUB):", uint256(r1) / 1e18);

        // Test price calculation directly
        // Try for 1 PONDER
        uint256 amountIn = 1 ether;
        uint256 spotPrice = oracle.getCurrentPrice(
            ponderKubPair,
            address(ponder),
            amountIn
        );
        console.log("\nPrice check for 1 PONDER:");
        console.log("Spot Price:", spotPrice / 1e18);

        // Try with larger amount
        amountIn = 1000 ether;
        spotPrice = oracle.getCurrentPrice(
            ponderKubPair,
            address(ponder),
            amountIn
        );
        console.log("\nPrice check for 1000 PONDER:");
        console.log("Spot Price:", spotPrice / 1e18);
    }

    function testPriceCalculationPrecision() public {
        // Setup pool same as before
        uint256 kubAmount = 1000 ether;
        uint256 ponderAmount = 200_000 ether;

        deal(address(ponder), address(this), ponderAmount);
        vm.deal(address(this), kubAmount);
        ponder.approve(address(router), ponderAmount);

        router.addLiquidityETH{value: kubAmount}(
            address(ponder),
            ponderAmount,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        address ponderKubPair = factory.getPair(address(ponder), address(weth));

        // Test with increasing amounts
        uint256[] memory testAmounts = new uint256[](6);
        testAmounts[0] = 0.1 ether;    // 0.1 PONDER
        testAmounts[1] = 1 ether;      // 1 PONDER
        testAmounts[2] = 10 ether;     // 10 PONDER
        testAmounts[3] = 100 ether;    // 100 PONDER
        testAmounts[4] = 1000 ether;   // 1000 PONDER
        testAmounts[5] = 10000 ether;  // 10000 PONDER

        console.log("Price check for different amounts:");
        for (uint i = 0; i < testAmounts.length; i++) {
            uint256 spotPrice = oracle.getCurrentPrice(
                ponderKubPair,
                address(ponder),
                testAmounts[i]
            );
            console.log("Amount: %s PONDER -> Price: %s KUB", testAmounts[i] / 1e18, spotPrice / 1e18);
        }
    }

    function testSmallCompletionContributions() public {
        uint256 launchId = _createTestLaunch();

        // Fund alice with enough ETH for the large contribution
        vm.deal(alice, TARGET_RAISE); // Give alice 5555 ETH

        // First test KUB completion
        // Contribute everything except 0.005 ETH (below MIN_KUB_CONTRIBUTION of 0.01)
        uint256 kubAmount = TARGET_RAISE - 0.005 ether;
        vm.prank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);

        // Fund bob for the completion amount
        vm.deal(bob, 0.005 ether);

        // Now try to complete with amount below minimum
        vm.prank(bob);
        launcher.contributeKUB{value: 0.005 ether}(launchId);

        // Verify launch completed
        (,,,,,bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should complete with small KUB contribution");

        // Now test PONDER completion on a new launch with different name/symbol
        FiveFiveFiveLauncherTypes.LaunchParams memory params = FiveFiveFiveLauncherTypes.LaunchParams({
            name: "Test Token 2",  // Different name
            symbol: "TEST2",       // Different symbol
            imageURI: "ipfs://test"
        });

        vm.prank(creator);
        launchId = launcher.createLaunch(params);

        // Setup proper oracle history first
        for (uint i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Reset alice's ETH balance for the second launch
        vm.deal(alice, TARGET_RAISE);

        // First contribute most in KUB
        // Leave exactly 0.2 ETH worth of space (requires 2 PONDER at 0.1 ETH/PONDER rate)
        kubAmount = TARGET_RAISE - 0.2 ether;
        vm.prank(alice);
        launcher.contributeKUB{value: kubAmount}(launchId);

        // Try to complete with PONDER amount below minimum
        // MIN_PONDER_CONTRIBUTION is 0.1 ETH worth (1 PONDER)
        // We need 2 PONDER to complete but this is below minimum
        uint256 completionAmount = 2 ether; // 2 PONDER = 0.2 ETH value

        // Give bob enough PONDER for completion
        deal(address(ponder), bob, completionAmount);

        vm.startPrank(bob);
        ponder.approve(address(launcher), completionAmount);
        launcher.contributePONDER(launchId, completionAmount);
        vm.stopPrank();

        // Verify launch completed
        (,,,,,launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should complete with small PONDER contribution");

        // Verify exact contribution amounts
        (uint256 kubCollected, uint256 ponderCollected, uint256 ponderValueCollected, uint256 totalValue) =
                            launcher.getContributionInfo(launchId);

        assertEq(totalValue, TARGET_RAISE, "Total value should equal target");
        assertEq(kubCollected, kubAmount, "KUB collected should match contribution");
        assertEq(ponderCollected, completionAmount, "PONDER collected should match contribution");
        assertEq(ponderValueCollected, 0.2 ether, "PONDER value should match remaining amount");
    }

    function testPriceInterpolation() public {
        uint256 launchId = _createTestLaunch();

        // Initialize oracle history first with proper time gaps
        for (uint i = 0; i < 12; i++) {  // Build up sufficient history
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        // Record current update time and allow for TWAP period
        uint256 lastUpdate = oracle.lastUpdateTime(ponderWethPair);
        vm.warp(lastUpdate + 1 hours);  // Move forward enough for TWAP

        // Test contribution at interpolated time
        vm.startPrank(alice);
        ponder.approve(address(launcher), 1000 ether);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();
    }

    function testPriceInterpolationEdgeCases() public {
        uint256 launchId = _createTestLaunch();

        // Build up proper oracle history
        for (uint i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        uint256 lastUpdate = oracle.lastUpdateTime(ponderWethPair);

        // Test cases at different points after sufficient history

        // Test 1: Shortly after last update
        vm.warp(lastUpdate + 30 minutes);
        vm.startPrank(alice);
        ponder.approve(address(launcher), 1000 ether);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();

        // Test 2: Mid-way between updates
        vm.warp(lastUpdate + 45 minutes);
        vm.startPrank(alice);
        ponder.approve(address(launcher), 1000 ether);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();
    }

    function testPriceInterpolationWithPriceMovement() public {
        uint256 launchId = _createTestLaunch();

        // Build up proper oracle history
        for (uint i = 0; i < 12; i++) {
            vm.warp(block.timestamp + 6 minutes);
            PonderPair(ponderWethPair).sync();
            oracle.update(ponderWethPair);
        }

        uint256 lastUpdate = oracle.lastUpdateTime(ponderWethPair);

        // Create price movement
        deal(address(ponder), address(this), 10000 ether);
        vm.deal(address(this), 1000 ether);
        ponder.approve(address(router), 10000 ether);

        router.addLiquidityETH{value: 1000 ether}(
            address(ponder),
            10000 ether,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        // Allow enough time for TWAP after price movement
        vm.warp(lastUpdate + 1 hours);
        PonderPair(ponderWethPair).sync();
        oracle.update(ponderWethPair);

        // Wait enough time for valid contribution
        vm.warp(block.timestamp + 30 minutes);

        vm.startPrank(alice);
        ponder.approve(address(launcher), 1000 ether);
        launcher.contributePONDER(launchId, 1000 ether);
        vm.stopPrank();

        // Verify contribution was successful
        (,uint256 ponderContributed,,) = launcher.getContributorInfo(launchId, alice);
        assertEq(ponderContributed, 1000 ether, "Contribution failed with price movement");
    }


    receive() external payable {}
}


contract MaliciousRejecter {
    bool public shouldReject;

    function setShouldReject(bool _shouldReject) external {
        shouldReject = _shouldReject;
    }

    function attemptContribution(address payable launcher, uint256 launchId, uint256 amount) external {
        FiveFiveFiveLauncher(launcher).contributeKUB{value: amount}(launchId);
    }

    // Reject ETH transfers when shouldReject is true
    receive() external payable {
        require(!shouldReject, "ETH rejected");
    }

    // Prevent token transfers when rejecting
    function onERC20Received(address, uint256) external view returns (bool) {
        return !shouldReject;
    }
}

contract TokenRejecter {
    FiveFiveFiveLauncher public immutable launcher;
    bool public shouldReject;

    constructor(address payable _launcher) {
        launcher = FiveFiveFiveLauncher(_launcher);
    }

    function setShouldReject(bool _reject) external {
        shouldReject = _reject;
    }

    function attemptContribution(uint256 launchId) external payable {
        require(!shouldReject, "ETH transfer rejected at source");
        launcher.contributeKUB{value: msg.value}(launchId);
    }

    receive() external payable {
        require(!shouldReject, "ETH rejected");
    }
}

