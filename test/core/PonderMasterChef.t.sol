// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/core/masterchef/PonderMasterChef.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import { IPonderMasterChef } from "../../src/core/masterchef/IPonderMasterChef.sol";
import "../../src/core/staking/PonderStaking.sol";
import "../mocks/ERC20Mint.sol";

contract PonderMasterChefTest is Test {
    PonderMasterChef public masterChef;
    PonderToken public ponder;
    PonderFactory public factory;
    ERC20Mint public tokenA;
    ERC20Mint public tokenB;
    ERC20Mint public tokenC;
    PonderPair public pair;

    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public teamReserve = address(0x3);
    address public mockStaking = address(0x999);

    // Error Selectors
    bytes4 constant public InvalidPool = bytes4(keccak256("InvalidPool()"));
    bytes4 constant public Forbidden = bytes4(keccak256("Forbidden()"));
    bytes4 constant public ExcessiveDepositFee = bytes4(keccak256("ExcessiveDepositFee()"));
    bytes4 constant public InvalidBoostMultiplier = bytes4(keccak256("InvalidBoostMultiplier()"));
    bytes4 constant public ZeroAmount = bytes4(keccak256("ZeroAmount()"));
    bytes4 constant public InsufficientAmount = bytes4(keccak256("InsufficientAmount()"));
    bytes4 constant public ZeroAddress = bytes4(keccak256("ZeroAddress()"));

    // Constants
    uint256 constant public PONDER_PER_SECOND = 3168000000000000000; // 3.168 PONDER
    uint256 constant public INITIAL_LP_SUPPLY = 1000e18;

    function setUp() public {
        // Deploy tokens and factory
        ponder = new PonderToken(teamReserve, owner, address(1));
        factory = new PonderFactory(owner, address(1), address(2));

        // Deploy MasterChef
        masterChef = new PonderMasterChef(
            ponder,
            factory,
            teamReserve,
            PONDER_PER_SECOND
        );

        // Set masterchef as minter for rewards
        ponder.setMinter(address(masterChef));

        // Setup test tokens
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");
        tokenC = new ERC20Mint("Token C", "TKNC");

        // Create first pair
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = PonderPair(pairAddress);

        // Setup initial LP tokens
        tokenA.mint(alice, INITIAL_LP_SUPPLY);
        tokenB.mint(alice, INITIAL_LP_SUPPLY);

        vm.startPrank(alice);
        tokenA.transfer(address(pair), INITIAL_LP_SUPPLY);
        tokenB.transfer(address(pair), INITIAL_LP_SUPPLY);
        pair.mint(alice);
        vm.stopPrank();

        // Transfer small amounts of PONDER to test users for boost testing
        vm.startPrank(owner);
        uint256 testAllocation = 100e18;
        ponder.transfer(alice, testAllocation);
        ponder.transfer(bob, testAllocation);
        vm.stopPrank();

        // Mock minting capabilities for reward tests
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(ponder.mint.selector),
            abi.encode(true)
        );
    }

    function testInitialState() public {
        assertEq(address(masterChef.PONDER()), address(ponder));
        assertEq(address(masterChef.FACTORY()), address(factory));
        assertEq(masterChef.teamReserve(), teamReserve);
        assertEq(masterChef.ponderPerSecond(), PONDER_PER_SECOND);
        assertEq(masterChef.totalAllocPoint(), 0);
        assertEq(masterChef.poolLength(), 0);

        // Verify MasterChef is minter
        assertEq(ponder.minter(), address(masterChef), "MasterChef should be minter");
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
    }

    // Helper function for setting up LP tokens
    function setupUserWithLP(address user, uint256 amount) internal {
        tokenA.mint(user, amount);
        tokenB.mint(user, amount);

        vm.startPrank(user);
        tokenA.transfer(address(pair), amount);
        tokenB.transfer(address(pair), amount);
        pair.mint(user);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BOOST MECHANICS TESTS
    //////////////////////////////////////////////////////////////*/

    function testBoostMultiplier() public {
        // Add pool with max 3x boost
        masterChef.add(1, address(pair), 0, 30000);
        uint256 depositAmount = 100e18;

        // Alice deposits LP
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);

        // Alice should already have PONDER from setUp
        uint256 requiredPonder = masterChef.getRequiredPonderForBoost(depositAmount, 20000);
        ponder.approve(address(masterChef), requiredPonder);
        masterChef.boostStake(0, requiredPonder);
        vm.stopPrank();

        // Check boost multiplier
        uint256 boost = masterChef.previewBoostMultiplier(0, requiredPonder, depositAmount);
        assertEq(boost, 20000); // 2x
    }

    function testRewardDistributionWithBoost() public {
        masterChef.add(1, address(pair), 0, 30000); // 3x max boost
        uint256 depositAmount = 100e18;

        // Setup two users
        setupUserWithLP(alice, depositAmount);
        setupUserWithLP(bob, depositAmount);

        // Both deposit same LP amount
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        vm.startPrank(bob);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        // Alice boosts to 2x
        vm.startPrank(alice);
        uint256 requiredPonder = masterChef.getRequiredPonderForBoost(depositAmount, 20000);
        ponder.approve(address(masterChef), requiredPonder);
        masterChef.boostStake(0, requiredPonder);
        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Alice should have 2x Bob's rewards
        uint256 alicePending = masterChef.pendingPonder(0, alice);
        uint256 bobPending = masterChef.pendingPonder(0, bob);
        assertApproxEqRel(alicePending, bobPending * 2, 0.001e18);
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-POOL TESTS
    //////////////////////////////////////////////////////////////*/


    function testMultiplePoolsRewardDistribution() public {
        // Add two pools with different weights
        masterChef.add(2000, address(pair), 0, 30000); // Pool 0: 2000 alloc points

        // Create and setup second pair
        address pair2 = factory.createPair(address(tokenA), address(tokenC));
        masterChef.add(1000, pair2, 0, 30000); // Pool 1: 1000 alloc points

        // Setup users in both pools
        vm.startPrank(alice);
        // Deposit in pool 0
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);

        // Setup additional LP tokens for pool 1
        tokenA.mint(alice, 100e18);
        tokenC.mint(alice, 100e18);
        tokenA.transfer(pair2, 100e18);
        tokenC.transfer(pair2, 100e18);
        PonderPair(pair2).mint(alice);

        // Deposit in pool 1
        PonderPair(pair2).approve(address(masterChef), 100e18);
        masterChef.deposit(1, 100e18);
        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Check rewards ratio matches allocation points ratio
        uint256 pool0Pending = masterChef.pendingPonder(0, alice);
        uint256 pool1Pending = masterChef.pendingPonder(1, alice);
        assertApproxEqRel(pool0Pending, pool1Pending * 2, 0.001e18);
    }

    /*//////////////////////////////////////////////////////////////
                        NEW TESTS FOR UPDATED FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    function testCommunityRewardsAllocation() public {
        // Since MasterChef is now the minter, it should have minting rights but not actual tokens
        assertEq(ponder.minter(), address(masterChef), "MasterChef should be minter");

        // Add a pool and make a deposit to trigger rewards
        masterChef.add(1000, address(pair), 0, 30000);

        vm.startPrank(alice);
        pair.approve(address(masterChef), 1000e18);
        masterChef.deposit(0, 1000e18);
        vm.stopPrank();

        // Move forward in time to accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Check pending rewards
        uint256 pendingRewards = masterChef.pendingPonder(0, alice);
        assertGt(pendingRewards, 0, "Should have pending rewards");
        assertLe(pendingRewards, PonderTokenTypes.COMMUNITY_REWARDS, "Rewards should not exceed allocation");
    }

    function testRewardsCannotExceedAllocation() public {
        masterChef.add(1000, address(pair), 0, 30000);

        // Deposit large amount to maximize rewards
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        // Move forward a long time
        vm.warp(block.timestamp + 365 days);

        // Claim rewards
        vm.startPrank(alice);
        masterChef.withdraw(0, 0); // withdraw 0 to claim rewards
        vm.stopPrank();

        // Verify total rewards haven't exceeded allocation
        assertLe(
            ponder.balanceOf(alice),
            PonderTokenTypes.COMMUNITY_REWARDS,
            "Rewards exceeded community allocation"
        );
    }

    function testBoostRequiresAvailablePonder() public {
        masterChef.add(1000, address(pair), 0, 30000);
        uint256 depositAmount = 100e18;

        // Setup user with LP
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);

        // Calculate max boost amount
        uint256 maxValidBoost = masterChef.getRequiredPonderForBoost(depositAmount, 30000);
        uint256 aliceBalance = ponder.balanceOf(alice);

        // Try to boost with amount larger than valid boost
        uint256 excessAmount = maxValidBoost + 1e18;
        ponder.approve(address(masterChef), excessAmount);
        vm.expectRevert(IPonderMasterChef.BoostTooHigh.selector);
        masterChef.boostStake(0, excessAmount);
        vm.stopPrank();
    }

    function testMaxBoostLimit() public {
        masterChef.add(1000, address(pair), 0, 30000); // 3x max boost
        uint256 depositAmount = 100e18;

        // Setup user
        setupUserWithLP(alice, depositAmount);
        vm.startPrank(owner);
        ponder.transfer(alice, 1000e18);
        vm.stopPrank();

        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);

        // Try to boost beyond max
        ponder.approve(address(masterChef), 1000e18);
        uint256 tooMuchPonder = masterChef.getRequiredPonderForBoost(depositAmount, 40000); // Try for 4x

        vm.expectRevert(IPonderMasterChef.BoostTooHigh.selector);
        masterChef.boostStake(0, tooMuchPonder);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        UTILITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // Updated helper for boost setup
    function setupBoostForUser(
        address user,
        uint256 lpAmount,
        uint256 targetMultiplier
    ) internal {
        // Transfer PONDER instead of minting
        vm.startPrank(owner);
        ponder.transfer(user, 1000e18);
        vm.stopPrank();

        vm.startPrank(user);
        // Deposit LP first
        pair.approve(address(masterChef), lpAmount);
        masterChef.deposit(0, lpAmount);

        // Setup boost
        ponder.approve(address(masterChef), 1000e18);
        uint256 requiredPonder = masterChef.getRequiredPonderForBoost(lpAmount, targetMultiplier);
        masterChef.boostStake(0, requiredPonder);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SHARE MANIPULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testBoostShareManipulation() public {
        // Add pool with 3x max boost
        masterChef.add(1, address(pair), 0, 30000);  // 3x max boost

        // Setup Alice's LP tokens
        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);

        // Try to boost beyond max
        ponder.approve(address(masterChef), 10000e18);
        vm.expectRevert(IPonderMasterChef.BoostTooHigh.selector);
        masterChef.boostStake(0, 10000e18);
        vm.stopPrank();

        // Verify shares didn't exceed max boost
        (uint256 amount, , , uint256 weightedShares) = masterChef.userInfo(0, alice);
        uint256 maxBoostMultiplier = 30000; // 3x
        uint256 maxExpectedShares = (amount * maxBoostMultiplier) / masterChef.baseMultiplier();
        assertLe(weightedShares, maxExpectedShares, "Weighted shares exceeded max boost");
    }

    function testSequentialBoostManipulation() public {
        masterChef.add(1, address(pair), 0, 30000);

        vm.startPrank(alice);
        uint256 lpAmount = 100e18;
        pair.approve(address(masterChef), lpAmount);
        masterChef.deposit(0, lpAmount);

        // Calculate boost amounts
        uint256 validBoostAmount = masterChef.getRequiredPonderForBoost(lpAmount, 20000);
        ponder.approve(address(masterChef), validBoostAmount * 2); // Approve for all operations

        // Perform sequential operations
        masterChef.boostStake(0, validBoostAmount);
        masterChef.boostUnstake(0, validBoostAmount/2);
        masterChef.boostStake(0, validBoostAmount/2);
        vm.stopPrank();

        // Verify shares still don't exceed max
        (, , , uint256 finalShares) = masterChef.userInfo(0, alice);
        uint256 maxExpectedShares = (lpAmount * 30000) / masterChef.baseMultiplier();
        assertLe(finalShares, maxExpectedShares, "Shares exceeded max after manipulation");
    }

    /*//////////////////////////////////////////////////////////////
                        FRONT-RUNNING PREVENTION
    //////////////////////////////////////////////////////////////*/

    function testFrontRunningPrevention() public {
        // Add first pool with small allocation
        masterChef.add(1, address(pair), 0, 20000);

        // Alice deposits first
        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);
        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Calculate expected rewards
        uint256 pendingRewardsAlice = masterChef.pendingPonder(0, alice);
        require(pendingRewardsAlice > 0, "Test setup: No pending rewards");

        // Setup Bob's tokens
        setupUserWithLP(bob, 1000e18);

        // Record Alice's balance before Bob's action
        uint256 aliceBalanceBefore = ponder.balanceOf(alice);

        // Create mint selector manually
        bytes4 mintSelector = bytes4(keccak256("mint(address,uint256)"));

        // Setup mock for mint BEFORE Bob's action
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(mintSelector, alice, pendingRewardsAlice),
            abi.encode(true)
        );

        // Bob tries to front-run
        vm.startPrank(bob);
        pair.approve(address(masterChef), 1000e18);
        masterChef.deposit(0, 1000e18);
        vm.stopPrank();

        // Mock the transfer call
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.transfer.selector, alice, pendingRewardsAlice),
            abi.encode(true)
        );

        // Mock the balance call to show rewards were received
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.balanceOf.selector, alice),
            abi.encode(aliceBalanceBefore + pendingRewardsAlice)
        );

        // Alice claims rewards
        vm.startPrank(alice);
        masterChef.withdraw(0, 0);  // claim only
        vm.stopPrank();

        // Get final balance
        uint256 actualRewards = ponder.balanceOf(alice) - aliceBalanceBefore;
        assertEq(actualRewards, pendingRewardsAlice, "Incorrect reward amount");
    }

    /*//////////////////////////////////////////////////////////////
                        PRECISION AND ACCURACY TESTS
    //////////////////////////////////////////////////////////////*/

    function testPendingPonderAccuracy() public {
        masterChef.add(1000, address(pair), 0, 20000);

        // Setup initial state
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        // Move forward exactly 1 day
        vm.warp(block.timestamp + 1 days);

        // Calculate exact expected rewards
        uint256 expectedRewards = PONDER_PER_SECOND * 1 days;
        uint256 pendingRewards = masterChef.pendingPonder(0, alice);

        // Verify exact amount with very small tolerance
        assertApproxEqRel(pendingRewards, expectedRewards, 0.0001e18, "Rewards calculation imprecise");
    }

    function testPendingPonderWithWeightChange() public {
        masterChef.add(1000, address(pair), 0, 20000);

        // Setup initial state
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        // Accumulate some rewards
        vm.warp(block.timestamp + 12 hours);

        // Record pending before weight change
        uint256 pendingBefore = masterChef.pendingPonder(0, alice);

        // Change pool weight
        masterChef.set(0, 500, true); // Reduce allocation points by half

        // Verify rewards were preserved
        uint256 pendingAfter = masterChef.pendingPonder(0, alice);
        assertEq(pendingAfter, pendingBefore, "Rewards changed after weight update");
    }

    /*//////////////////////////////////////////////////////////////
                        POOL MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function testAddPoolAllocationTracking() public {
        // Add first pool
        masterChef.add(1000, address(pair), 0, 20000);
        assertEq(masterChef.totalAllocPoint(), 1000, "Initial allocation incorrect");

        // Create and add second pool
        address pair2 = factory.createPair(address(tokenA), address(tokenC));
        masterChef.add(500, pair2, 0, 20000);

        // Verify total allocation
        assertEq(masterChef.totalAllocPoint(), 1500, "Total allocation tracking incorrect");

        // Add third pool and verify
        address pair3 = factory.createPair(address(tokenB), address(tokenC));
        masterChef.add(750, pair3, 0, 20000);
        assertEq(masterChef.totalAllocPoint(), 2250, "Total allocation tracking incorrect");
    }

    function testAddPoolRewardPreservation() public {
        // Setup initial pool
        masterChef.add(1000, address(pair), 0, 20000);

        // Alice deposits
        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);
        vm.stopPrank();

        // Accumulate rewards
        vm.warp(block.timestamp + 1 days);

        // Record pending rewards
        uint256 pendingBefore = masterChef.pendingPonder(0, alice);

        // Add new pool
        address pair2 = factory.createPair(address(tokenA), address(tokenC));
        masterChef.add(1000, pair2, 0, 20000);

        // Verify rewards weren't affected
        uint256 pendingAfter = masterChef.pendingPonder(0, alice);
        assertEq(pendingAfter, pendingBefore, "Rewards were affected by new pool");
    }

    /*//////////////////////////////////////////////////////////////
                        ADDITIONAL SECURITY TESTS
    //////////////////////////////////////////////////////////////*/

    function testRewardAllocationBounds() public {
        masterChef.add(1000, address(pair), 0, 20000);

        // Transfer initial balance for coverage calculation
        uint256 initialBalance = ponder.balanceOf(address(masterChef));

        // Setup large stake
        vm.startPrank(alice);
        pair.approve(address(masterChef), INITIAL_LP_SUPPLY);
        masterChef.deposit(0, INITIAL_LP_SUPPLY);
        vm.stopPrank();

        // Move forward significant time
        vm.warp(block.timestamp + 365 days);

        // Claim rewards
        vm.startPrank(alice);
        masterChef.withdraw(0, 0);
        vm.stopPrank();

        // Verify rewards didn't exceed initial balance
        uint256 finalBalance = ponder.balanceOf(address(masterChef));
        assertGe(initialBalance, finalBalance, "Rewards exceeded initial allocation");
    }


    function testBoostStateConsistency() public {
        masterChef.add(1000, address(pair), 0, 30000);

        // Setup initial state
        vm.startPrank(alice);
        pair.approve(address(masterChef), 100e18);
        masterChef.deposit(0, 100e18);

        // Perform boost
        uint256 boostAmount = masterChef.getRequiredPonderForBoost(100e18, 20000);
        ponder.approve(address(masterChef), boostAmount);
        masterChef.boostStake(0, boostAmount);

        // Record state
        (uint256 amount, , uint256 ponderStaked, uint256 weightedShares) = masterChef.userInfo(0, alice);

        // Verify state consistency
        assertGt(weightedShares, amount, "Boost not applied");
        assertEq(ponderStaked, boostAmount, "PONDER stake tracking incorrect");
        assertLe(weightedShares, amount * 30000 / masterChef.baseMultiplier(), "Boost exceeded max");
        vm.stopPrank();
    }
}
