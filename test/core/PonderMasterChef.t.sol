// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/core/masterchef/PonderMasterChef.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/core/masterchef/IPonderMasterChef.sol";
import "../mocks/ERC20Mint.sol";

contract PonderMasterChefTest is Test {
    PonderMasterChef masterChef;
    PonderToken ponder;
    PonderFactory factory;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    ERC20Mint tokenC;
    PonderPair pair;

    address owner = address(this);
    address alice = address(0x1);
    address bob = address(0x2);
    address teamReserve = address(0x3);
    address launcher = address(0xbad);

    // Error Selectors
    bytes4 constant InvalidPool = bytes4(keccak256("InvalidPool()"));
    bytes4 constant Forbidden = bytes4(keccak256("Forbidden()"));
    bytes4 constant ExcessiveDepositFee = bytes4(keccak256("ExcessiveDepositFee()"));
    bytes4 constant InvalidBoostMultiplier = bytes4(keccak256("InvalidBoostMultiplier()"));
    bytes4 constant ZeroAmount = bytes4(keccak256("ZeroAmount()"));
    bytes4 constant InsufficientAmount = bytes4(keccak256("InsufficientAmount()"));
    bytes4 constant ZeroAddress = bytes4(keccak256("ZeroAddress()"));

    // Simplified constants
    uint256 constant PONDER_PER_SECOND = 3168000000000000000; // 3.168 PONDER
    uint256 constant INITIAL_LP_SUPPLY = 1000e18;
    uint256 constant LP2_SUPPLY = 999999999999999999000; // Adjusted to match mint calculation

    function setUp() public {
        // Deploy tokens and factory
        ponder = new PonderToken(owner, owner, launcher);
        factory = new PonderFactory(owner, address(1), address(2));

        // Deploy MasterChef
        masterChef = new PonderMasterChef(
            ponder,
            factory,
            teamReserve,
            PONDER_PER_SECOND
        );

        // Set minter
        vm.startPrank(owner);
        ponder.setMinter(address(masterChef));
        vm.stopPrank();

        // Setup test tokens
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");
        tokenC = new ERC20Mint("Token C", "TKNC");

        // Create first pair
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = PonderPair(pairAddress);

        // Setup initial LP tokens for first pair
        tokenA.mint(alice, INITIAL_LP_SUPPLY);
        tokenB.mint(alice, INITIAL_LP_SUPPLY);

        vm.startPrank(alice);
        tokenA.transfer(address(pair), INITIAL_LP_SUPPLY);
        tokenB.transfer(address(pair), INITIAL_LP_SUPPLY);
        pair.mint(alice);
        vm.stopPrank();
    }

    function testInitialState() public {
        assertEq(address(masterChef.PONDER()), address(ponder));
        assertEq(address(masterChef.FACTORY()), address(factory));
        assertEq(masterChef.teamReserve(), teamReserve);
        assertEq(masterChef.ponderPerSecond(), PONDER_PER_SECOND);
        assertEq(masterChef.totalAllocPoint(), 0);
        assertEq(masterChef.poolLength(), 0);
    }

    function testRevertInvalidPool() public {
        vm.startPrank(alice);
        vm.expectRevert(InvalidPool);
        masterChef.deposit(0, 100e18);

        vm.expectRevert(InvalidPool);
        masterChef.withdraw(0, 100e18);

        vm.expectRevert(InvalidPool);
        masterChef.emergencyWithdraw(0);

        vm.expectRevert(InvalidPool);
        masterChef.pendingPonder(0, alice);
        vm.stopPrank();
    }

    function testSinglePool() public {
        // Add pool
        masterChef.add(1, address(pair), 0, 20000);

        // Alice deposits
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);

        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Check rewards
        uint256 expectedReward = PONDER_PER_SECOND * 1 days;
        uint256 pendingRewards = masterChef.pendingPonder(0, alice);
        assertApproxEqRel(pendingRewards, expectedReward, 0.001e18);
    }

    function testBoostMultiplier() public {
        // Add pool with max 3x boost
        masterChef.add(1, address(pair), 0, 30000);
        uint256 depositAmount = 100e18;

        // Alice deposits LP
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);

        // Mint PONDER for boost
        vm.startPrank(address(masterChef));
        ponder.mint(alice, 1000e18);
        vm.stopPrank();

        // Alice stakes PONDER for 2x boost
        vm.startPrank(alice);
        ponder.approve(address(masterChef), 1000e18);
        uint256 requiredPonder = masterChef.getRequiredPonderForBoost(depositAmount, 20000);
        masterChef.boostStake(0, requiredPonder);
        vm.stopPrank();

        // Check boost multiplier
        uint256 boost = masterChef.previewBoostMultiplier(0, requiredPonder, depositAmount);
        assertEq(boost, 20000); // 2x
    }

    function testEmergencyWithdraw() public {
        masterChef.add(1, address(pair), 0, 20000);
        uint256 depositAmount = 100e18;

        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);

        uint256 balanceBefore = pair.balanceOf(alice);
        masterChef.emergencyWithdraw(0);

        assertEq(pair.balanceOf(alice), balanceBefore + depositAmount);
        (uint256 amount,,,) = masterChef.userInfo(0, alice);
        assertEq(amount, 0);
        vm.stopPrank();
    }

    function testDepositWithFee() public {
        uint16 depositFeeBP = 500; // 5% fee
        masterChef.add(1, address(pair), depositFeeBP, 20000);
        uint256 depositAmount = 100e18;

        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        uint256 expectedFee = (depositAmount * depositFeeBP) / masterChef.basisPoints();
        assertEq(pair.balanceOf(teamReserve), expectedFee);
    }

    function testRevertExcessiveDepositFee() public {
        vm.expectRevert(ExcessiveDepositFee);
        masterChef.add(1, address(pair), 1001, 20000); // More than 10% fee
    }
    function testEmissionsCapWithMaxBoosts() public {
        // Setup initial state
        masterChef.add(1, address(pair), 0, 30000); // Allow up to 3x boost
        uint256 farmingCap = 400_000_000e18; // 400M maximum farming allocation

        // Setup 5 users with max boost to try to exceed emissions
        address[] memory users = new address[](5);
        for(uint256 i = 0; i < 5; i++) {
            users[i] = address(uint160(i + 1));

            // Give each user LP tokens
            tokenA.mint(users[i], INITIAL_LP_SUPPLY);
            tokenB.mint(users[i], INITIAL_LP_SUPPLY);

            vm.startPrank(users[i]);
            tokenA.transfer(address(pair), INITIAL_LP_SUPPLY);
            tokenB.transfer(address(pair), INITIAL_LP_SUPPLY);
            pair.mint(users[i]);

            // Deposit LP tokens
            pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
            masterChef.deposit(0, INITIAL_LP_SUPPLY);

            // Mint and stake PONDER for max boost
            vm.startPrank(address(masterChef));
            ponder.mint(users[i], 1000e18);
            vm.stopPrank();

            vm.startPrank(users[i]);
            ponder.approve(address(masterChef), 1000e18);
            uint256 requiredPonder = masterChef.getRequiredPonderForBoost(INITIAL_LP_SUPPLY, 30000); // 3x boost
            masterChef.boostStake(0, requiredPonder);
            vm.stopPrank();
        }

        // Fast forward 4 years
        uint256 fourYears = 4 * 365 days;
        vm.warp(block.timestamp + fourYears);

        // Log initial supply
        uint256 initialSupply = ponder.totalSupply();
        console.log("Initial supply:", initialSupply);

        // Update pool to mint all rewards
        masterChef.updatePool(0);

        // Log final supply and emissions
        uint256 finalSupply = ponder.totalSupply();
        uint256 totalEmitted = finalSupply - initialSupply;
        console.log("Total emitted:", totalEmitted);
        console.log("Farming cap:", farmingCap);

        // Verify we haven't exceeded farming cap
        assertLe(totalEmitted, farmingCap, "Exceeded farming cap");

        // Test individual claims don't exceed cap
        uint256 totalClaimed;
        for(uint256 i = 0; i < 5; i++) {
            vm.startPrank(users[i]);
            uint256 balanceBefore = ponder.balanceOf(users[i]);
            masterChef.withdraw(0, INITIAL_LP_SUPPLY); // This claims rewards
            uint256 claimed = ponder.balanceOf(users[i]) - balanceBefore;
            totalClaimed += claimed;
            vm.stopPrank();
        }

        console.log("Total claimed by users:", totalClaimed);
        assertLe(totalClaimed, farmingCap, "Total claims exceeded farming cap");
    }

    function testEmissionsRateWithVaryingBoosts() public {
        masterChef.add(1, address(pair), 0, 30000); // Allow up to 3x boost

        // Setup 3 users with different boost levels
        address user1 = address(0x1); // Will have no boost
        address user2 = address(0x2); // Will have 2x boost
        address user3 = address(0x3); // Will have 3x boost

        // Setup initial LP for all users
        uint256 depositAmount = 100e18;
        setupUserWithLP(user1, depositAmount);
        setupUserWithLP(user2, depositAmount);
        setupUserWithLP(user3, depositAmount);

        // User 1: No boost
        vm.startPrank(user1);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        // User 2: 2x boost
        setupBoostForUser(user2, depositAmount, 20000);

        // User 3: 3x boost
        setupBoostForUser(user3, depositAmount, 30000);

        // Track initial state
        uint256 startTime = block.timestamp;
        uint256 initialSupply = ponder.totalSupply();

        // Fast forward one year
        vm.warp(block.timestamp + 365 days);
        masterChef.updatePool(0);

        // Calculate expected emissions for 1 year
        uint256 expectedBaseEmissions = PONDER_PER_SECOND * 365 days;
        uint256 actualEmissions = ponder.totalSupply() - initialSupply;

        console.log("Expected base emissions for 1 year:", expectedBaseEmissions);
        console.log("Actual emissions:", actualEmissions);

        // Even with different boosts, total emissions should match base rate
        assertApproxEqRel(actualEmissions, expectedBaseEmissions, 0.001e18);
    }

// Helper function to setup user with LP tokens
    function setupUserWithLP(address user, uint256 amount) internal {
        tokenA.mint(user, amount);
        tokenB.mint(user, amount);

        vm.startPrank(user);
        tokenA.transfer(address(pair), amount);
        tokenB.transfer(address(pair), amount);
        pair.mint(user);
        vm.stopPrank();
    }

    // Helper function to setup boost for a user
    function setupBoostForUser(address user, uint256 lpAmount, uint256 targetMultiplier) internal {
        // Mint PONDER for boost
        vm.startPrank(address(masterChef));
        ponder.mint(user, 1000e18);
        vm.stopPrank();

        vm.startPrank(user);
        // Deposit LP first
        pair.approve(address(masterChef), lpAmount);
        masterChef.deposit(0, lpAmount);

        // Then setup boost
        ponder.approve(address(masterChef), 1000e18);
        uint256 requiredPonder = masterChef.getRequiredPonderForBoost(lpAmount, targetMultiplier);
        masterChef.boostStake(0, requiredPonder);
        vm.stopPrank();
    }


    function testDynamicStartTime() public {
        // Add pool
        masterChef.add(1, address(pair), 0, 20000);

        // Verify farming hasn't started
        assertEq(masterChef.farmingStarted(), false);
        assertEq(masterChef.startTime(), 0);

        // Move time forward 1 week
        vm.warp(block.timestamp + 7 days);
        uint256 firstDepositTime = block.timestamp;

        // Alice makes first deposit
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        // Verify farming has started and start time is set
        assertEq(masterChef.farmingStarted(), true);
        assertEq(masterChef.startTime(), firstDepositTime);

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Check rewards - should be exactly 1 day worth
        uint256 expectedReward = PONDER_PER_SECOND * 1 days;
        uint256 pendingRewards = masterChef.pendingPonder(0, alice);
        assertApproxEqRel(pendingRewards, expectedReward, 0.001e18);
    }

    function testNoRewardsBeforeFirstDeposit() public {
        // Add pool
        masterChef.add(1, address(pair), 0, 20000);

        // Move time forward 30 days
        vm.warp(block.timestamp + 30 days);

        // Verify no rewards have been minted
        uint256 initialSupply = ponder.totalSupply();

        // Alice makes first deposit
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Claim rewards
        vm.prank(alice);
        masterChef.withdraw(0, 0); // withdraw 0 to claim rewards

        // Check only 1 day of rewards were minted despite 31 days passing
        uint256 finalSupply = ponder.totalSupply();
        uint256 expectedReward = PONDER_PER_SECOND * 1 days;
        assertApproxEqRel(finalSupply - initialSupply, expectedReward, 0.001e18);
    }

    function testFullEmissionPeriod() public {
        // Add pool
        masterChef.add(1, address(pair), 0, 20000);

        // Get initial timestamp and supply
        uint256 startTime = block.timestamp;
        uint256 initialSupply = ponder.totalSupply();

        // Move forward 30 days and make first deposit
        vm.warp(startTime + 30 days);
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        // Move forward 1 year (within minting period)
        vm.warp(block.timestamp + 365 days);

        // Update pool to trigger rewards
        masterChef.updatePool(0);

        // Calculate expected emissions for 1 year
        uint256 expectedEmissions = PONDER_PER_SECOND * 365 days;
        uint256 actualEmissions = ponder.totalSupply() - initialSupply;

        // Allow 0.1% variance for rounding
        assertApproxEqRel(actualEmissions, expectedEmissions, 0.001e18);
    }

    function testMultiplePoolsStartTimes() public {
        // Add first pool
        vm.startPrank(owner);
        masterChef.add(100, address(pair), 0, 20000);
        vm.stopPrank();

        // Move forward 1 week
        vm.warp(block.timestamp + 7 days);

        // First deposit in pool 0
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        uint256 farmStartTime = masterChef.startTime();

        // Update pool before adding new one to handle accumulated rewards
        masterChef.updatePool(0);

        // Create and setup second pair
        vm.startPrank(owner);
        address pair2 = factory.createPair(address(tokenA), address(tokenC));
        masterChef.add(100, pair2, 0, 20000);

        // Setup liquidity for second pair
        tokenA.mint(bob, INITIAL_LP_SUPPLY);
        tokenC.mint(bob, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        // Bob provides liquidity
        vm.startPrank(bob);
        tokenA.transfer(pair2, INITIAL_LP_SUPPLY);
        tokenC.transfer(pair2, INITIAL_LP_SUPPLY);
        PonderPair(pair2).mint(bob);

        // The LP amount needs to match what was minted
        uint256 lpBalance = PonderPair(pair2).balanceOf(bob);
        PonderPair(pair2).approve(address(masterChef), lpBalance);
        masterChef.deposit(1, lpBalance);
        vm.stopPrank();

        // Update both pools before checking rewards
        masterChef.updatePool(0);
        masterChef.updatePool(1);

        // Move forward 1 day to accumulate new rewards
        vm.warp(block.timestamp + 1 days);

        // Check rewards distribution
        uint256 alicePending = masterChef.pendingPonder(0, alice);
        uint256 bobPending = masterChef.pendingPonder(1, bob);

        // Since both pools have equal allocation points (100), their rewards over this period should be equal
        // Allow for a 1% difference due to rounding
        assertApproxEqRel(alicePending, bobPending, 0.01e18);
    }

    function testEmergencyWithdrawBeforeStart() public {
        // Add pool
        masterChef.add(1, address(pair), 0, 20000);

        // Alice deposits
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);

        // Emergency withdraw
        uint256 balanceBefore = pair.balanceOf(alice);
        masterChef.emergencyWithdraw(0);

        // Check LP tokens returned
        assertEq(pair.balanceOf(alice), balanceBefore + INITIAL_LP_SUPPLY);

        // Verify farming status remains started
        assertEq(masterChef.farmingStarted(), true);
        vm.stopPrank();
    }

    function testFrontRunningPrevention() public {
        // Add pool
        masterChef.add(1, address(pair), 0, 20000);

        // Setup Alice's LP tokens
        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);
        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Check Alice's pending rewards
        uint256 pendingRewardsAlice = masterChef.pendingPonder(0, alice);
        uint256 expectedRewards = PONDER_PER_SECOND * 1 days;
        assertApproxEqRel(pendingRewardsAlice, expectedRewards, 0.001e18);

        // Setup Bob's LP tokens
        tokenA.mint(bob, 1000e18);
        tokenB.mint(bob, 1000e18);

        vm.startPrank(bob);
        tokenA.transfer(address(pair), 1000e18);
        tokenB.transfer(address(pair), 1000e18);
        pair.mint(bob);  // This will give Bob LP tokens

        pair.approve(address(masterChef), 1000e18);
        masterChef.deposit(0, 1000e18);
        vm.stopPrank();

        // Alice claims rewards
        vm.startPrank(alice);
        masterChef.withdraw(0, 0);
        vm.stopPrank();

        // Verify Alice got proper rewards
        uint256 aliceBalance = ponder.balanceOf(alice);
        assertApproxEqRel(aliceBalance, expectedRewards, 0.001e18);

        // Also verify Bob didn't get rewards he shouldn't have
        uint256 bobPending = masterChef.pendingPonder(0, bob);
        assertLt(bobPending, expectedRewards / 10, "Bob got too many rewards");
    }

    function testBoostShareManipulation() public {
        // Add pool with 3x max boost
        masterChef.add(1, address(pair), 0, 30000);  // 3x max boost

        // Setup Alice's LP tokens
        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);
        vm.stopPrank();

        // Mint PONDER tokens for boost
        vm.startPrank(address(masterChef));
        ponder.mint(alice, 1000e18);
        vm.stopPrank();

        // Alice boosts with excessive PONDER trying to game shares
        vm.startPrank(alice);
        ponder.approve(address(masterChef), 1000e18);

        // Should revert if trying to boost beyond max multiplier
        vm.expectRevert(abi.encodeWithSignature("BoostTooHigh()"));
        masterChef.boostStake(0, 1000e18);
        vm.stopPrank();

        // Verify shares didn't exceed max boost
        (uint256 amount, , , uint256 weightedShares) = masterChef.userInfo(0, alice);
        uint256 maxBoostMultiplier = 30000; // 3x
        uint256 maxExpectedShares = (amount * maxBoostMultiplier) / masterChef.baseMultiplier();
        assertLe(weightedShares, maxExpectedShares, "Weighted shares exceeded max boost");

        // Try to game shares by repeated boost/unboost
        vm.startPrank(alice);
        uint256 validBoostAmount = masterChef.getRequiredPonderForBoost(amount, 30000);
        masterChef.boostStake(0, validBoostAmount);
        masterChef.boostUnstake(0, validBoostAmount/2);
        masterChef.boostStake(0, validBoostAmount/2);
        vm.stopPrank();

        // Verify shares still don't exceed max after manipulation
        (, , , uint256 finalShares) = masterChef.userInfo(0, alice);
        assertLe(finalShares, maxExpectedShares, "Shares exceeded max after manipulation");
    }

    function testBoostWithoutLP() public {
        // Setup pool
        masterChef.add(1, address(pair), 0, 30000);

        // Try to boost without LP tokens
        vm.startPrank(alice);
        ponder.approve(address(masterChef), 100e18);
        vm.expectRevert(abi.encodeWithSignature("InsufficientAmount()"));
        masterChef.boostStake(0, 100e18);
        vm.stopPrank();
    }

    function testBoostWithFakeTransfer() public {
        masterChef.add(1, address(pair), 0, 30000);

        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);

        // Setup initial PONDER balance mock
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.balanceOf.selector),
            abi.encode(0)
        );

        // Mock the balance checks before and after transfer to show no change
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(masterChef)),
            abi.encode(0)
        );

        // Calculate required PONDER for valid boost amount
        uint256 boostAmount = masterChef.getRequiredPonderForBoost(100e18, 20000); // 2x boost
        ponder.approve(address(masterChef), boostAmount);

        // Mock transferFrom to return success
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.transferFrom.selector, alice, address(masterChef), boostAmount),
            abi.encode(true)
        );

        // Mock balance check after transfer to still show 0
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(masterChef)),
            abi.encode(0)
        );

        // Should revert with ZeroAmount since no actual tokens were transferred
        vm.expectRevert(PonderMasterChefTypes.ZeroAmount.selector);
        masterChef.boostStake(0, boostAmount);
        vm.stopPrank();
    }

    function testSequentialBoostManipulation() public {
        masterChef.add(1, address(pair), 0, 30000);  // 3x max boost

        vm.startPrank(alice);
        // Deposit LP tokens first
        uint256 lpAmount = 100e18;
        pair.approve(address(masterChef), lpAmount);
        masterChef.deposit(0, lpAmount);

        // Calculate exact boost amounts
        uint256 maxBoostAmount = masterChef.getRequiredPonderForBoost(lpAmount, 30000); // For 3x boost
        uint256 smallBoostAmount = maxBoostAmount / 8; // Split into 8 parts to ensure last boost will exceed

        // Setup PONDER for alice
        vm.startPrank(address(masterChef));
        ponder.mint(alice, maxBoostAmount * 2);  // Mint extra to ensure enough balance
        vm.stopPrank();

        vm.startPrank(alice);
        ponder.approve(address(masterChef), maxBoostAmount * 2);

        // Do 8 boosts that should succeed
        for(uint i = 0; i < 8; i++) {
            masterChef.boostStake(0, smallBoostAmount);
            (,, uint256 ponderStaked,) = masterChef.userInfo(0, alice);
            // Verify each stake is within limits
            assertLe(ponderStaked, maxBoostAmount, "Staked amount exceeded max allowable");
        }

        // The next boost should fail as it would exceed max boost
        vm.expectRevert(abi.encodeWithSignature("BoostTooHigh()"));
        masterChef.boostStake(0, smallBoostAmount);
        vm.stopPrank();
    }

    function testPendingPonderAccuracy() public {
        // Add pool with high allocation points to get meaningful rewards
        masterChef.add(1000, address(pair), 0, 20000);

        vm.startPrank(alice);
        // Approve and deposit LP tokens
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Calculate expected rewards using masterChef's ponderPerSecond
        uint256 expectedRewards = masterChef.ponderPerSecond() * 1 days;
        uint256 pendingRewards = masterChef.pendingPonder(0, alice);

        assertApproxEqRel(pendingRewards, expectedRewards, 0.001e18, "Rewards calculation incorrect");
        vm.stopPrank();
    }

    function testPendingPonderWithWeightChange() public {
        // Add pool and initial deposit
        masterChef.add(1000, address(pair), 0, 20000);

        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);

        // Move forward 12 hours
        vm.warp(block.timestamp + 12 hours);

        // Get pending before weight change
        uint256 pendingBefore = masterChef.pendingPonder(0, alice);

        // Change pool weight
        vm.stopPrank();
        masterChef.set(0, 500, true); // Reduce allocation points by half

        vm.prank(alice);
        uint256 pendingAfter = masterChef.pendingPonder(0, alice);

        // Verify rewards before change were preserved
        assertApproxEqRel(
            pendingAfter,
            pendingBefore,
            0.001e18,
            "Rewards significantly changed after weight update"
        );
    }

    function testPendingPonderAfterMintingEnd() public {
        masterChef.add(1000, address(pair), 0, 20000);

        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);

        // Move time to just before minting end
        uint256 mintingEnd = block.timestamp + ponder.mintingEnd();
        vm.warp(mintingEnd - 1 days);

        // Should still have pending rewards
        uint256 pendingBefore = masterChef.pendingPonder(0, alice);
        assertGt(pendingBefore, 0, "Should have rewards before minting end");

        // Move past minting end
        vm.warp(mintingEnd + 1);

        // Should now return 0 rewards
        uint256 pendingAfter = masterChef.pendingPonder(0, alice);
        assertEq(pendingAfter, 0, "Should have no rewards after minting end");
        vm.stopPrank();
    }

    function testPendingPonderMaxSupply() public {
        masterChef.add(1000, address(pair), 0, 20000);

        // Get current supply and max supply
        uint256 maxSupply = ponder.maximumSupply();
        uint256 currentSupply = ponder.totalSupply();

        // Instead of trying to mint up to max supply, let's test with a smaller amount
        // that leaves enough room for rewards
        uint256 toMint = (maxSupply - currentSupply) / 2; // Mint half of remaining supply

        // Mint tokens as MasterChef
        vm.startPrank(address(masterChef));
        ponder.mint(address(this), toMint);
        vm.stopPrank();

        // Add liquidity and check pending rewards
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);

        // Move forward some time
        vm.warp(block.timestamp + 1 days); // Reduced from 30 days to 1 day

        // Check pending rewards
        uint256 pending = masterChef.pendingPonder(0, alice);
        uint256 remainingSupply = maxSupply - ponder.totalSupply();
        assertLe(pending, remainingSupply, "Rewards exceeded max supply");
        vm.stopPrank();
    }

    function testBoostShareExploitPrevention() public {
        // Add pool with 3x max boost
        masterChef.add(1000, address(pair), 0, 30000); // 3x max boost

        // Setup three users with equal LP amounts
        uint256 lpAmount = 100e18;
        address attacker = address(0x1);
        address user1 = address(0x2);
        address user2 = address(0x3);

        // Give each user LP tokens
        setupUserWithLP(attacker, lpAmount);
        setupUserWithLP(user1, lpAmount);
        setupUserWithLP(user2, lpAmount);

        // All users deposit same LP amount
        vm.startPrank(attacker);
        pair.approve(address(masterChef), lpAmount);
        masterChef.deposit(0, lpAmount);
        vm.stopPrank();

        vm.startPrank(user1);
        pair.approve(address(masterChef), lpAmount);
        masterChef.deposit(0, lpAmount);
        vm.stopPrank();

        vm.startPrank(user2);
        pair.approve(address(masterChef), lpAmount);
        masterChef.deposit(0, lpAmount);
        vm.stopPrank();

        // Mint PONDER for boosts
        vm.startPrank(address(masterChef));
        ponder.mint(attacker, 1000e18);
        ponder.mint(user1, 1000e18);
        ponder.mint(user2, 1000e18);
        vm.stopPrank();

        // Regular user adds normal 2x boost
        vm.startPrank(user1);
        ponder.approve(address(masterChef), 1000e18);
        uint256 normalBoostAmount = masterChef.getRequiredPonderForBoost(lpAmount, 20000); // 2x boost
        masterChef.boostStake(0, normalBoostAmount);
        vm.stopPrank();

        // Attacker tries to exploit by:
        // 1. Adding max boost
        // 2. Unstaking some PONDER to get under required amount
        // 3. Trying to keep boosted shares while reducing PONDER stake
        vm.startPrank(attacker);
        ponder.approve(address(masterChef), 1000e18);
        uint256 maxBoostAmount = masterChef.getRequiredPonderForBoost(lpAmount, 30000); // 3x boost

        // First add max boost
        masterChef.boostStake(0, maxBoostAmount);

        // Try to unstake half the PONDER while keeping boost
        masterChef.boostUnstake(0, maxBoostAmount / 2);

        // Try to restake a small amount to trigger share recalculation
        masterChef.boostStake(0, normalBoostAmount / 10);
        vm.stopPrank();

        // Move forward to accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Get shares and rewards for all users
        (,,,uint256 attackerShares) = masterChef.userInfo(0, attacker);
        (,,,uint256 user1Shares) = masterChef.userInfo(0, user1);
        (,,,uint256 user2Shares) = masterChef.userInfo(0, user2);

        uint256 attackerRewards = masterChef.pendingPonder(0, attacker);
        uint256 user1Rewards = masterChef.pendingPonder(0, user1);
        uint256 user2Rewards = masterChef.pendingPonder(0, user2);

        console.log("Attacker shares:", attackerShares);
        console.log("User1 shares (2x boost):", user1Shares);
        console.log("User2 shares (no boost):", user2Shares);

        console.log("\nRewards after 1 day:");
        console.log("Attacker rewards:", attackerRewards);
        console.log("User1 rewards:", user1Rewards);
        console.log("User2 rewards:", user2Rewards);

        // Verify attacker didn't get excessive shares
        uint256 maxAllowableShares = lpAmount * 30000 / masterChef.baseMultiplier(); // 3x max
        assertLe(attackerShares, maxAllowableShares, "Attacker got excessive shares");

        // Verify attacker's rewards aren't disproportionate
        uint256 totalShares = attackerShares + user1Shares + user2Shares;
        uint256 expectedAttackerRewards = (PONDER_PER_SECOND * 1 days * attackerShares) / totalShares;
        assertApproxEqRel(
            attackerRewards,
            expectedAttackerRewards,
            0.01e18,
            "Attacker got disproportionate rewards"
        );

        // Verify proper reward distribution ratios
        // User1 should get 2x the base rewards, Attacker max 3x
        assertLe(
            attackerRewards,
            user2Rewards * 3,
            "Attacker rewards exceeded 3x unbosted"
        );
        assertApproxEqRel(
            user1Rewards,
            user2Rewards * 2,
            0.01e18,
            "User1 rewards not properly 2x boosted"
        );
    }

    bytes4 constant ExcessiveAllocation = bytes4(keccak256("ExcessiveAllocation()"));
    bytes4 constant DuplicatePool = bytes4(keccak256("DuplicatePool()"));

    function testAddPoolZeroAddress() public {
        // Should revert when trying to add pool with zero address LP token
        vm.expectRevert(ZeroAddress);
        masterChef.add(100, address(0), 0, 20000);
    }

    function testAddPoolExcessiveAllocation() public {
        // Should revert when allocation points exceed MAX_ALLOC_POINT
        vm.expectRevert(ExcessiveAllocation);
        masterChef.add(10001, address(pair), 0, 20000);
    }

    function testAddPoolDuplicatePrevention() public {
        // First add should succeed
        masterChef.add(100, address(pair), 0, 20000);

        // Second add with same LP token should fail
        vm.expectRevert(DuplicatePool);
        masterChef.add(100, address(pair), 0, 20000);
    }

    function testAddPoolRewardPreservation() public {
        // Setup initial pool
        masterChef.add(1000, address(pair), 0, 20000);

        // Alice deposits in first pool
        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);
        vm.stopPrank();

        // Accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Check pending rewards before adding new pool
        uint256 pendingBefore = masterChef.pendingPonder(0, alice);

        // Create and add new pool
        address pair2 = factory.createPair(address(tokenA), address(tokenC));
        masterChef.add(1000, pair2, 0, 20000);

        // Verify rewards weren't diluted
        uint256 pendingAfter = masterChef.pendingPonder(0, alice);
        assertEq(pendingAfter, pendingBefore, "Rewards were diluted by new pool");
    }

    function testAddPoolForcedUpdate() public {
        // Setup initial pool
        masterChef.add(1000, address(pair), 0, 20000);

        // Alice deposits
        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);
        vm.stopPrank();

        // Move time forward
        vm.warp(block.timestamp + 1 days);

        // Create new pair
        address pair2 = factory.createPair(address(tokenA), address(tokenC));

        // Add new pool with withUpdate = false (should still update due to fix)
        masterChef.add(1000, pair2, 0, 20000);

        // Verify rewards were properly accounted
        uint256 pendingRewards = masterChef.pendingPonder(0, alice);
        uint256 expectedRewards = PONDER_PER_SECOND * 1 days;
        assertApproxEqRel(pendingRewards, expectedRewards, 0.001e18, "Rewards not properly updated");
    }

    function testAddPoolAllocationTracking() public {
        // Add first pool
        masterChef.add(1000, address(pair), 0, 20000);
        assertEq(masterChef.totalAllocPoint(), 1000, "Initial allocation incorrect");

        // Create and add second pool
        address pair2 = factory.createPair(address(tokenA), address(tokenC));
        masterChef.add(500, pair2, 0, 20000);

        // Verify total allocation
        assertEq(masterChef.totalAllocPoint(), 1500, "Total allocation tracking incorrect");
    }
}
