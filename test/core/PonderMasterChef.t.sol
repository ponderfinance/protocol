// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/core/PonderMasterChef.sol";
import "../../src/core/PonderToken.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPair.sol";
import "../../src/interfaces/IPonderMasterChef.sol";
import "../mocks/ERC20Mint.sol";

contract PonderMasterChefTest is Test {
    PonderMasterChef masterChef;
    PonderToken ponder;
    PonderFactory factory;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    PonderPair pair;

    address owner = address(this);
    address alice = address(0x1);
    address bob = address(0x2);
    address treasury = address(0x3);
    address launcher = address(0xbad);

    uint256 constant PONDER_PER_SECOND = 1e18;
    uint256 constant INITIAL_LP_SUPPLY = 1000e18;
    uint256 constant INITIAL_PONDER_SUPPLY = 100_000e18;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event BoostStake(address indexed user, uint256 indexed pid, uint256 amount);
    event BoostUnstake(address indexed user, uint256 indexed pid, uint256 amount);
    event PoolAdded(uint256 indexed pid, address indexed lpToken, uint256 allocPoint);
    event PoolUpdated(uint256 indexed pid, uint256 allocPoint);

    function setUp() public {
        // Deploy core contracts
        ponder = new PonderToken(owner, owner, launcher);
        factory = new PonderFactory(address(this), address(1), address(2));

        // Deploy MasterChef with start time = now
        masterChef = new PonderMasterChef(
            ponder,
            factory,
            treasury,
            PONDER_PER_SECOND,
            block.timestamp
        );

        // Set MasterChef as minter for PONDER token
        ponder.setMinter(address(masterChef));

        // Deploy test tokens and create pair
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");

        // Create pair through factory
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = PonderPair(pairAddress);

        // Setup initial liquidity
        tokenA.mint(alice, INITIAL_LP_SUPPLY);
        tokenB.mint(alice, INITIAL_LP_SUPPLY);

        vm.startPrank(alice);
        tokenA.transfer(address(pair), INITIAL_LP_SUPPLY);
        tokenB.transfer(address(pair), INITIAL_LP_SUPPLY);
        pair.mint(alice);
        vm.stopPrank();
    }

    function testInitialState() public view {
        assertEq(address(masterChef.ponder()), address(ponder));
        assertEq(address(masterChef.factory()), address(factory));
        assertEq(masterChef.treasury(), treasury);
        assertEq(masterChef.ponderPerSecond(), PONDER_PER_SECOND);
        assertEq(masterChef.totalAllocPoint(), 0);
        assertEq(masterChef.poolLength(), 0);
    }

    function testAddPool() public {
        uint256 allocPoint = 100;
        uint16 depositFeeBP = 500; // 5%
        uint16 boostMultiplier = 20000; // 2x

        vm.expectEmit(true, true, true, true);
        emit PoolAdded(0, address(pair), allocPoint);

        masterChef.add(
            allocPoint,
            address(pair),
            depositFeeBP,
            boostMultiplier,
            true
        );

        assertEq(masterChef.poolLength(), 1);
        assertEq(masterChef.totalAllocPoint(), allocPoint);

        (
            address lpToken,
            uint256 poolAllocPoint,
            uint256 lastRewardTime,
            uint256 accPonderPerShare,
            uint256 totalStaked,
            uint16 poolDepositFeeBP,
            uint16 poolBoostMultiplier
        ) = masterChef.poolInfo(0);

        assertEq(lpToken, address(pair));
        assertEq(poolAllocPoint, allocPoint);
        assertEq(lastRewardTime, block.timestamp);
        assertEq(accPonderPerShare, 0);
        assertEq(totalStaked, 0);
        assertEq(poolDepositFeeBP, depositFeeBP);
        assertEq(poolBoostMultiplier, boostMultiplier);
    }

    function testDeposit() public {
        // Add pool first
        masterChef.add(100, address(pair), 500, 20000, true);
        uint256 depositAmount = 100e18;

        // Calculate expected amount after fee
        uint256 depositFee = (depositAmount * 500) / 10000; // 5% fee
        uint256 expectedAmount = depositAmount - depositFee;

        // Approve and deposit LP tokens
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);

        vm.expectEmit(true, true, true, true);
        emit Deposit(alice, 0, expectedAmount);

        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        // Check balances and state
        (uint256 amount, uint256 rewardDebt, uint256 ponderStaked) = masterChef.userInfo(0, alice);
        assertEq(amount, expectedAmount);
        assertEq(rewardDebt, 0);
        assertEq(ponderStaked, 0);
    }

    function testRewards() public {
        // Add pool
        masterChef.add(100, address(pair), 0, 20000, true);
        uint256 depositAmount = 100e18;

        // Alice deposits
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Check pending rewards
        uint256 pending = masterChef.pendingPonder(0, alice);
        assertEq(pending, 1 days * PONDER_PER_SECOND);

        // Harvest rewards
        vm.prank(alice);
        masterChef.deposit(0, 0); // Deposit 0 to harvest

        assertEq(ponder.balanceOf(alice), pending);
    }

    function testBoost() public {
        // Add pool with 2x boost
        masterChef.add(100, address(pair), 0, 20000, true);
        uint256 depositAmount = 100e18;

        // Mint some PONDER to Alice first
        vm.prank(address(masterChef));
        ponder.mint(alice, 1000e18);

        // Alice deposits LP and stakes PONDER
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);

        // Stake PONDER for boost
        ponder.approve(address(masterChef), 1000e18);
        masterChef.boostStake(0, 1000e18);
        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Check boosted rewards (should be 2x)
        uint256 pending = masterChef.pendingPonder(0, alice);
        assertEq(pending, 2 * 1 days * PONDER_PER_SECOND);
    }

    function testWithdraw() public {
        // Add pool
        masterChef.add(100, address(pair), 0, 20000, true);
        uint256 depositAmount = 100e18;

        // Setup deposit
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);

        // Move forward for some rewards
        vm.warp(block.timestamp + 1 days);

        // Withdraw half
        uint256 withdrawAmount = 50e18;

        vm.expectEmit(true, true, true, true);
        emit Withdraw(alice, 0, withdrawAmount);

        masterChef.withdraw(0, withdrawAmount);
        vm.stopPrank();

        // Check balances
        (uint256 amount, , ) = masterChef.userInfo(0, alice);
        assertEq(amount, depositAmount - withdrawAmount);
        assertEq(pair.balanceOf(alice), INITIAL_LP_SUPPLY - depositAmount + withdrawAmount);
    }

    function testEmergencyWithdraw() public {
        // Add pool
        masterChef.add(100, address(pair), 0, 20000, true);
        uint256 depositAmount = 100e18;

        // Setup deposit
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);

        uint256 balanceBefore = pair.balanceOf(alice);

        // Emergency withdraw
        vm.expectEmit(true, true, true, true);
        emit EmergencyWithdraw(alice, 0, depositAmount);

        masterChef.emergencyWithdraw(0);
        vm.stopPrank();

        // Check all funds returned, rewards forfeited
        (uint256 amount, uint256 rewardDebt, uint256 ponderStaked) = masterChef.userInfo(0, alice);
        assertEq(amount, 0);
        assertEq(rewardDebt, 0);
        assertEq(ponderStaked, 0);
        assertEq(pair.balanceOf(alice), balanceBefore + depositAmount);
    }

    function testMultipleUsers() public {
        // Add pool
        masterChef.add(100, address(pair), 0, 20000, true);
        uint256 depositAmount = 100e18;

        // Give Bob some LP tokens
        vm.prank(alice);
        pair.transfer(bob, depositAmount);

        // Alice and Bob deposit
        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        vm.startPrank(bob);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        // Move forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Check rewards split equally
        uint256 alicePending = masterChef.pendingPonder(0, alice);
        uint256 bobPending = masterChef.pendingPonder(0, bob);
        assertEq(alicePending, bobPending);
        assertEq(alicePending, (1 days * PONDER_PER_SECOND) / 2);
    }
}
