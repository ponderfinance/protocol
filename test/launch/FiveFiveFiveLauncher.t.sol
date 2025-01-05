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

    event LaunchCreated(uint256 indexed launchId, address indexed token, address creator, string imageURI);
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);
    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);
    event DualPoolsCreated(uint256 indexed launchId, address memeKubPair, address memePonderPair, uint256 kubLiquidity, uint256 ponderLiquidity);
    event LaunchCompleted(uint256 indexed launchId, uint256 kubRaised, uint256 ponderRaised);
    event PonderBurned(uint256 indexed launchId, uint256 amount);

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

    function testExcessivePonderContribution() public {
        uint256 launchId = _createTestLaunch();

        // Try to contribute 25% of target raise in PONDER
        // 25% of 5555 ETH = 1388.75 ETH worth of PONDER
        // At 0.1 ETH per PONDER, need 13,887.5 PONDER
        uint256 ponderAmount = (((TARGET_RAISE * 25) / 100) * 10); // Scale up by 10 for 0.1 price

        vm.startPrank(alice);
        vm.expectRevert(FiveFiveFiveLauncher.ExcessivePonderContribution.selector);
        launcher.contributePONDER(launchId, ponderAmount);
        vm.stopPrank();
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

    function testExcessiveContribution() public {
        uint256 launchId = _createTestLaunch();

        // First contribute 90% in KUB
        uint256 kubContribution = (TARGET_RAISE * 90) / 100;
        vm.prank(alice);
        launcher.contributeKUB{value: kubContribution}(launchId);

        // Try to contribute 15% in PONDER (should fail due to total raise limit)
        // Even though it's under 20% PONDER limit, it would exceed total raise
        uint256 ponderAmount = (((TARGET_RAISE * 15) / 100) * 10); // Scale up by 10 for 0.1 price

        vm.startPrank(bob);
        vm.expectRevert(FiveFiveFiveLauncher.ExcessiveContribution.selector);
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

    receive() external payable {}
}
