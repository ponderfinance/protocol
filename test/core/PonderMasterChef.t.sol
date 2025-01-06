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
    uint256 constant INITIAL_PONDER_SUPPLY = 1000000e18; // Just for testing

    function setUp() public {
        // Simple token deployment
        ponder = new PonderToken(owner, owner, launcher);
        factory = new PonderFactory(owner, address(1), address(2));

        // Deploy MasterChef
        masterChef = new PonderMasterChef(
            ponder,
            factory,
            treasury,
            PONDER_PER_SECOND,
            block.timestamp
        );

        // Give MasterChef minting rights
        ponder.setMinter(address(masterChef));

        // Setup test tokens and pair
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");
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
    }

    function testInitialState() public {
        assertEq(address(masterChef.ponder()), address(ponder));
        assertEq(address(masterChef.factory()), address(factory));
        assertEq(masterChef.treasury(), treasury);
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
        masterChef.add(1, address(pair), 0, 20000, true);

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
        masterChef.add(1, address(pair), 0, 30000, true);
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
        masterChef.add(1, address(pair), 0, 20000, true);
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
        masterChef.add(1, address(pair), depositFeeBP, 20000, true);
        uint256 depositAmount = 100e18;

        vm.startPrank(alice);
        pair.approve(address(masterChef), depositAmount);
        masterChef.deposit(0, depositAmount);
        vm.stopPrank();

        uint256 expectedFee = (depositAmount * depositFeeBP) / masterChef.BASIS_POINTS();
        assertEq(pair.balanceOf(treasury), expectedFee);
    }

    function testRevertExcessiveDepositFee() public {
        vm.expectRevert(ExcessiveDepositFee);
        masterChef.add(1, address(pair), 1001, 20000, true); // More than 10% fee
    }
    function testEmissionsCapWithMaxBoosts() public {
        // Setup initial state
        masterChef.add(1, address(pair), 0, 30000, true); // Allow up to 3x boost
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
        masterChef.add(1, address(pair), 0, 30000, true); // Allow up to 3x boost

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
}
