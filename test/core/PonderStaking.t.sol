// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/core/staking/PonderStaking.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/periphery/router/PonderRouter.sol";

contract ReentrantToken is PonderKAP20 {
    PonderStaking public immutable stakingContract;
    bool private _isAttacking;

    constructor(address _stakingContract) PonderKAP20("Reentrant", "REKT") {
        stakingContract = PonderStaking(_stakingContract);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setAttacking(bool attacking) external {
        _isAttacking = attacking;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (_isAttacking && to != address(stakingContract)) {
            // Try to reenter
            _isAttacking = false; // Prevent recursive attack
            stakingContract.leave(amount / 2);
            return false;
        }
        return super.transfer(to, amount);
    }
}

contract PonderStakingTest is Test {
    PonderStaking public staking;
    PonderToken public ponder;
    PonderFactory public factory;
    PonderRouter public router;

    address public owner;
    address public user1;
    address public user2;
    address public treasury;
    address public teamReserve;
    address public marketing;
    address constant WETH = address(0x1234);

    uint256 public constant INITIAL_SUPPLY = 1_000_000e18;

    event Staked(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);
    event Withdrawn(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);
    event RebasePerformed(uint256 totalSupply, uint256 totalPonderBalance);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        teamReserve = address(0x4);

        // Deploy contracts
        factory = new PonderFactory(owner, address(1), address(1));
        router = new PonderRouter(address(factory), WETH, address(1));

        // Deploy token with owner as launcher to get initial liquidity
        ponder = new PonderToken(teamReserve, owner, address(1));  // owner is launcher
        staking = new PonderStaking(address(ponder), address(router), address(factory));

        // Set staking address and initialize team staking
        ponder.setStaking(address(staking));
        ponder.initializeStaking();

        // Transfer from initial liquidity allocation for testing
        vm.startPrank(owner);
        ponder.transfer(user1, 10_000e18);
        ponder.transfer(user2, 10_000e18);
        ponder.transfer(address(this), 100_000e18);
        vm.stopPrank();
    }

    function test_LeaveWithRewards() public {
        uint256 stakeAmount = 1000e18;

        // First stake
        vm.startPrank(user1);
        ponder.approve(address(staking), stakeAmount);
        uint256 initialShares = staking.enter(stakeAmount, user1);
        vm.stopPrank();

        // Track initial total supply excluding team allocation
        uint256 initialTotalSupply = staking.totalSupply();
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // Simulate fee distribution
        vm.startPrank(owner);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // Calculate expected amount including rewards
        uint256 finalStakingBalance = ponder.balanceOf(address(staking));
        uint256 expectedAmount = (initialShares * finalStakingBalance) / initialTotalSupply;

        // Leave all shares
        vm.startPrank(user1);
        uint256 ponderReceived = staking.leave(initialShares);
        vm.stopPrank();

        assertEq(ponderReceived, expectedAmount, "Should receive proportional share including rewards");
    }

    function test_MultipleEnters() public {
        // First user stakes
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // Add rewards using test contract's balance
        ponder.transfer(address(staking), 100e18);

        // Second user stakes
        uint256 user2StakeAmount = 1000e18;
        vm.startPrank(user2);
        ponder.approve(address(staking), user2StakeAmount);
        uint256 shares = staking.enter(user2StakeAmount, user2);
        vm.stopPrank();

        assertLt(shares, user2StakeAmount, "Should receive fewer shares due to rewards");
    }

    function test_GetPonderAmount() public {
        uint256 stakeAmount = 1000e18;

        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), stakeAmount);
        staking.enter(stakeAmount, user1);
        vm.stopPrank();

        uint256 initialAmount = staking.getPonderAmount(1000e18);

        // Add rewards
        vm.startPrank(owner);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        uint256 newAmount = staking.getPonderAmount(1000e18);
        assertGt(newAmount, initialAmount, "Amount should increase with rewards");
    }

    function test_MultipleUsers() public {
        // User1 stakes
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        uint256 user1Shares = staking.enter(1000e18, user1);
        vm.stopPrank();

        // Add rewards
        vm.startPrank(owner);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // User2 stakes same amount
        vm.startPrank(user2);
        ponder.approve(address(staking), 1000e18);
        uint256 user2Shares = staking.enter(1000e18, user2);
        vm.stopPrank();

        // User2 should get fewer shares due to increased share price
        assertLt(user2Shares, user1Shares, "User2 should get fewer shares");
    }

    function testFuzz_EnterAndLeave(uint256 amount) public {
        // Bound amount between minimum stake and reasonable max
        amount = bound(amount, staking.minimumFirstStake(), 10000e18);

        vm.startPrank(owner);
        ponder.transfer(address(this), amount);
        vm.stopPrank();

        ponder.approve(address(staking), amount);
        uint256 shares = staking.enter(amount, address(this));
        uint256 ponderReceived = staking.leave(shares);

        assertApproxEqRel(ponderReceived, amount, 1e14, "Should receive approximately staked amount");
    }

    function test_InitialState() public {
        assertEq(address(staking.PONDER()), address(ponder));
        assertEq(address(staking.ROUTER()), address(router));
        assertEq(address(staking.FACTORY()), address(factory));
        assertEq(staking.stakingOwner(), owner);

        // Verify team allocation is staked
        uint256 teamAllocation = PonderTokenTypes.TEAM_ALLOCATION;
        assertEq(staking.balanceOf(teamReserve), teamAllocation, "Team allocation not properly staked");
    }

    function test_Enter() public {
        uint256 stakeAmount = 1000e18;
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        vm.startPrank(user1);
        ponder.approve(address(staking), stakeAmount);

        vm.expectEmit(true, true, true, true);
        emit Staked(user1, stakeAmount, stakeAmount); // 1:1 for first user stake

        uint256 shares = staking.enter(stakeAmount, user1);
        vm.stopPrank();

        assertEq(shares, stakeAmount, "Should receive 1:1 shares for first stake");
        assertEq(staking.balanceOf(user1), stakeAmount, "Should have correct xPONDER balance");
        assertEq(ponder.balanceOf(address(staking)), initialStakingBalance + stakeAmount, "Staking contract should have increased balance");
    }

    function test_Leave() public {
        // First stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);

        // Leave half
        uint256 sharesToLeave = 500e18;

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(user1, 500e18, sharesToLeave);

        uint256 ponderReceived = staking.leave(sharesToLeave);
        vm.stopPrank();

        assertEq(ponderReceived, 500e18, "Should receive proportional PONDER");
        assertEq(staking.balanceOf(user1), 500e18, "Should have remaining xPONDER");
    }

    function test_RevertOnZeroAmount() public {
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        staking.enter(0, user1);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        staking.leave(0);

        vm.stopPrank();
    }

    function test_OwnershipTransfer() public {
        address newOwner = address(0x9);

        // Non-owner can't transfer
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotOwner()"));
        staking.transferOwnership(newOwner);
        vm.stopPrank();

        // Owner initiates transfer
        staking.transferOwnership(newOwner);
        assertEq(staking.pendingOwner(), newOwner);

        // Non-pending owner can't accept
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotPendingOwner()"));
        staking.acceptOwnership();
        vm.stopPrank();

        // Pending owner accepts
        vm.startPrank(newOwner);
        staking.acceptOwnership();
        vm.stopPrank();

        assertEq(staking.stakingOwner(), newOwner);
        assertEq(staking.pendingOwner(), address(0));
    }

    function test_PreventFirstStakeManipulation() public {
        uint256 initialTotalSupply = staking.totalSupply();
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // Attempt to manipulate by sending tokens directly
        vm.startPrank(user2);
        ponder.transfer(address(staking), 1e15);
        vm.stopPrank();

        // User1 performs normal stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // Verify shares are correct considering team allocation
        uint256 totalPonder = ponder.balanceOf(address(staking));
        uint256 finalTotalSupply = staking.totalSupply();

        // Expected share value should be proportional to total PONDER including team allocation
        uint256 expectedShares = (1000e18 * initialTotalSupply) / initialStakingBalance;
        uint256 actualShares = finalTotalSupply - initialTotalSupply;

        assertApproxEqRel(actualShares, expectedShares, 0.01e18, "Share calculation was manipulated");
    }

    function test_FirstStakeMinimum() public {
        uint256 minimumStake = staking.minimumFirstStake();
        uint256 smallAmount = minimumStake - 1;
        uint256 currentTotalSupply = staking.totalSupply(); // Should be TEAM_ALLOCATION

        vm.startPrank(user1);
        ponder.approve(address(staking), smallAmount);

        // Since team allocation is already staked, this shouldn't revert with InsufficientFirstStake
        // Instead should work normally as it's not the first stake
        staking.enter(smallAmount, user1);

        // Verify the stake worked but with appropriate share ratio
        assertEq(staking.totalSupply(), currentTotalSupply + smallAmount);
        vm.stopPrank();
    }

    function test_ShareRatioPreservation() public {
        uint256 initialTotalSupply = staking.totalSupply(); // Team allocation
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // First user stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        uint256 shares1 = staking.enter(1000e18, user1);
        vm.stopPrank();

        // Second stake with half amount
        vm.startPrank(user2);
        ponder.approve(address(staking), 500e18);
        uint256 shares2 = staking.enter(500e18, user2);
        vm.stopPrank();

        // Calculate expected shares considering team allocation
        uint256 expectedShares2 = (500e18 * (initialTotalSupply + shares1)) / (initialStakingBalance + 1000e18);
        assertEq(shares2, expectedShares2, "Share ratio not preserved");

        // Verify totals
        uint256 expectedTotalShares = initialTotalSupply + shares1 + shares2;
        assertEq(staking.totalSupply(), expectedTotalShares, "Incorrect total shares");
    }

    function test_ShareValueIncreasesWithFees() public {
        uint256 initialTotalSupply = staking.totalSupply();
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // First stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        uint256 shares = staking.enter(1000e18, user1);
        vm.stopPrank();

        // Record initial share value
        uint256 initialShareValue = (shares * initialStakingBalance) / initialTotalSupply;

        // Simulate fee distribution
        vm.startPrank(owner);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // Calculate new expected share value
        uint256 newStakingBalance = ponder.balanceOf(address(staking));
        uint256 newShareValue = (shares * newStakingBalance) / staking.totalSupply();

        assertGt(newShareValue, initialShareValue, "Share value should increase with fees");
        // Value should increase proportionally to fees added
        uint256 expectedIncrease = (shares * 100e18) / staking.totalSupply();
        assertApproxEqRel(newShareValue - initialShareValue, expectedIncrease, 0.01e18);
    }

    function test_ShareValueMaintainedThroughoutOperations() public {
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // Add fees
        vm.startPrank(owner);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // Second user stakes
        vm.startPrank(user2);
        ponder.approve(address(staking), 500e18);
        uint256 user2Shares = staking.enter(500e18, user2);
        vm.stopPrank();

        // More fees
        vm.startPrank(owner);
        ponder.transfer(address(staking), 50e18);
        vm.stopPrank();

        // Verify share value calculation
        uint256 totalPonder = ponder.balanceOf(address(staking));
        uint256 totalShares = staking.totalSupply();
        uint256 expectedShareValue = (totalPonder * 1e18) / totalShares;

        assertEq(
            staking.getPonderAmount(1e18),
            expectedShareValue,
            "Share value should be maintained"
        );
    }

    function test_MultipleShareholders() public {
        uint256 initialTotalSupply = staking.totalSupply(); // Team allocation
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // User1 stakes first
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        uint256 user1Shares = staking.enter(1000e18, user1);
        vm.stopPrank();

        // Simulate fee distribution (100e18 tokens = 10% rewards on user1's stake)
        vm.startPrank(owner);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // User2 stakes after fees
        vm.startPrank(user2);
        ponder.approve(address(staking), 1000e18);
        uint256 user2Shares = staking.enter(1000e18, user2);
        vm.stopPrank();

        // Calculate proportion of total shares for each user
        uint256 totalShares = staking.totalSupply();
        uint256 currentStakingBalance = ponder.balanceOf(address(staking));

        // Calculate actual PONDER value each user would receive
        uint256 user1Value = (user1Shares * currentStakingBalance) / totalShares;
        uint256 user2Value = (user2Shares * currentStakingBalance) / totalShares;

        // User2 should get their 1000e18 worth because they joined after rewards
        assertApproxEqRel(user2Value, 1000e18, 0.01e18, "User2 should get ~1000e18 PONDER value");

        // User1 should get approximately 1000e18 + their share of the 100e18 rewards
        uint256 expectedUser1Value = (1000e18 * (initialStakingBalance + 100e18)) / initialStakingBalance;
        assertApproxEqRel(user1Value, expectedUser1Value, 0.01e18, "User1 should get stake plus proportional rewards");
    }

    function test_PreventSandwichAttack() public {
        uint256 stakeAmount = 1000e18;

        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), stakeAmount);
        staking.enter(stakeAmount, user1);
        vm.stopPrank();

        // Simulate fee accumulation
        vm.prank(owner);
        ponder.transfer(address(staking), 100e18);

        // Calculate exact amount that will be transferred
        uint256 expectedAmount = 500e18 * (ponder.balanceOf(address(staking))) / staking.totalSupply();

        // Mock the failed transfer with proper revert data
        bytes memory revertData = abi.encodeWithSelector(
            bytes4(keccak256("SafeERC20FailedOperation(address)")),
            address(ponder)
        );

        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.transfer.selector, user1, expectedAmount),
            abi.encode(false)
        );

        // Should revert with proper error
        vm.startPrank(user1);
        vm.expectRevert(revertData);
        staking.leave(500e18);
        vm.stopPrank();
    }

    function test_PreventDustShares() public {
        // First make a proper stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);

        // Try to withdraw tiny amount
        vm.expectRevert(abi.encodeWithSignature("MinimumSharesRequired()"));
        staking.leave(1); // Dust amount
        vm.stopPrank();
    }

    function test_TeamLockPeriod() public {
        // Try to withdraw team allocation before lock period
        vm.startPrank(teamReserve);
        vm.expectRevert(abi.encodeWithSignature("TeamStakingLocked()"));
        staking.leave(PonderTokenTypes.TEAM_ALLOCATION);
        vm.stopPrank();

        // Move past lock period
        vm.warp(block.timestamp + PonderTokenTypes.TEAM_CLIFF);

        // Should now be able to withdraw
        vm.startPrank(teamReserve);
        uint256 withdrawn = staking.leave(PonderTokenTypes.TEAM_ALLOCATION);
        assertEq(withdrawn, PonderTokenTypes.TEAM_ALLOCATION, "Team should receive full allocation after cliff");
        vm.stopPrank();
    }
    // Additional helper test for team cliff duration
    function test_TeamCliffDuration() public {
        // Get initial deployment time from the token contract
        uint256 startTime = ponder.deploymentTime();

        // Get the actual error we're seeing in the trace
        bytes4 teamStakingLockedSelector = bytes4(keccak256("TeamStakingLocked()"));

        // Verify initial state
        assertEq(staking.balanceOf(teamReserve), PonderTokenTypes.TEAM_ALLOCATION);

        // Try right at the start - should be locked
        vm.startPrank(teamReserve);
        vm.expectRevert(abi.encodePacked(teamStakingLockedSelector));
        staking.leave(PonderTokenTypes.TEAM_ALLOCATION);
        vm.stopPrank();

        // Try in the middle of the lock period - should be locked
        vm.warp(startTime + PonderStakingTypes.TEAM_LOCK_DURATION / 2);
        vm.startPrank(teamReserve);
        vm.expectRevert(abi.encodePacked(teamStakingLockedSelector));
        staking.leave(PonderTokenTypes.TEAM_ALLOCATION);
        vm.stopPrank();

        // Try one second before cliff ends - should be locked
        vm.warp(startTime + PonderStakingTypes.TEAM_LOCK_DURATION - 1);
        vm.startPrank(teamReserve);
        vm.expectRevert(abi.encodePacked(teamStakingLockedSelector));
        staking.leave(PonderTokenTypes.TEAM_ALLOCATION);
        vm.stopPrank();

        // Move past cliff time - should succeed
        vm.warp(startTime + PonderStakingTypes.TEAM_LOCK_DURATION + 1);
        vm.startPrank(teamReserve);
        uint256 withdrawn = staking.leave(PonderTokenTypes.TEAM_ALLOCATION);
        vm.stopPrank();

        assertEq(withdrawn, PonderTokenTypes.TEAM_ALLOCATION, "Should receive full allocation after cliff");
        assertEq(staking.balanceOf(teamReserve), 0, "Should have no remaining shares");
    }

    function test_PreventExcessiveShares() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // Try to withdraw more than owned
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSharesAmount()"));
        staking.leave(2000e18);
        vm.stopPrank();
    }

    function test_PreventReentrancyOnLeave() public {
// Deploy malicious token
ReentrantToken reentrantToken = new ReentrantToken(address(staking));

// Mint tokens to attacker
vm.startPrank(user1);
reentrantToken.mint(user1, 1000e18);

// Set up the malicious token's staking
PonderStaking maliciousStaking = new PonderStaking(
address(reentrantToken),
address(router),
address(factory)
);

        reentrantToken.approve(address(maliciousStaking), 1000e18);
        maliciousStaking.enter(1000e18, user1);

        // Attempt reentrancy attack
        reentrantToken.setAttacking(true);
        vm.expectRevert();  // Should revert due to reentrancy guard
        maliciousStaking.leave(500e18);
        vm.stopPrank();
    }

    // Test updates to share price from fee accumulation
    function test_SharePriceIncrease() public {
        uint256 initialTotalSupply = staking.totalSupply();
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // First stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        uint256 user1Shares = staking.enter(1000e18, user1);
        vm.stopPrank();

        // Record share price before fees
        uint256 initialSharePrice = (initialStakingBalance * 1e18) / initialTotalSupply;

        // Add fees over time
        for (uint i = 0; i < 5; i++) {
            vm.startPrank(owner);
            ponder.transfer(address(staking), 10e18);
            vm.stopPrank();

            // Check share price increases
            uint256 currentBalance = ponder.balanceOf(address(staking));
            uint256 currentSharePrice = (currentBalance * 1e18) / staking.totalSupply();
            assertGt(currentSharePrice, initialSharePrice, "Share price should increase with fees");
            initialSharePrice = currentSharePrice;
        }
    }

    // Test partial withdrawals maintain correct share ratio
    function test_PartialWithdrawals() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);

        // Add some rewards
        vm.startPrank(owner);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // Withdraw half
        vm.startPrank(user1);
        uint256 initialShares = staking.balanceOf(user1);
        uint256 withdrawAmount = initialShares / 2;
        uint256 receivedTokens = staking.leave(withdrawAmount);

        // Verify remaining shares and value
        uint256 remainingShares = staking.balanceOf(user1);
        assertEq(remainingShares, initialShares - withdrawAmount, "Incorrect remaining shares");

        // Second withdrawal should get proportionally same amount
        uint256 secondWithdraw = staking.leave(remainingShares);
        assertApproxEqRel(secondWithdraw, receivedTokens, 0.01e18, "Second withdrawal should be proportional");
        vm.stopPrank();
    }

    function test_ClaimFees() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // Send 10_000 PONDER as fees (instead of 100)
        vm.startPrank(owner);
        ponder.transfer(address(staking), 10_000e18);
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();
        vm.stopPrank();

        // Check pending fees
        uint256 pendingFees = staking.getPendingFees(user1);
        assertGt(pendingFees, 0, "Should have pending fees");

        // Claim fees
        vm.startPrank(user1);
        uint256 claimed = staking.claimFees();
        vm.stopPrank();

        assertEq(claimed, pendingFees, "Should claim all pending fees");
        assertEq(staking.getPendingFees(user1), 0, "Should have no pending fees after claim");
    }

    function test_TeamClaimFeesWhileLocked() public {
        // Verify team stake is locked
        vm.startPrank(teamReserve);
        vm.expectRevert(abi.encodeWithSignature("TeamStakingLocked()"));
        staking.leave(1); // Try to unstake minimal amount
        vm.stopPrank();

        // Simulate fee distribution
        vm.startPrank(owner);
        ponder.transfer(address(staking), 1000e18);
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();
        vm.stopPrank();

        // Team should be able to claim fees while stake is locked
        vm.startPrank(teamReserve);
        uint256 pendingFees = staking.getPendingFees(teamReserve);
        uint256 claimed = staking.claimFees();
        vm.stopPrank();

        assertGt(claimed, 0, "Team should be able to claim fees");
        assertEq(claimed, pendingFees, "Should claim all pending fees");
    }

    function test_FeeDistributionProportional() public {
        // User1 stakes 1000
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // User2 stakes 2000
        vm.startPrank(user2);
        ponder.approve(address(staking), 2000e18);
        staking.enter(2000e18, user2);
        vm.stopPrank();

        // Distribute fees
        vm.startPrank(owner);
        ponder.transfer(address(staking), 300e18);
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();
        vm.stopPrank();

        // Get pending fees
        uint256 user1Fees = staking.getPendingFees(user1);
        uint256 user2Fees = staking.getPendingFees(user2);

        // User2 should get twice the fees of User1
        assertApproxEqRel(user2Fees, user1Fees * 2, 0.01e18, "Fee distribution not proportional to stakes");
    }

    function test_RevertOnZeroFees() public {
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);

        vm.expectRevert(abi.encodeWithSignature("NoFeesToClaim()"));
        staking.claimFees();
        vm.stopPrank();
    }

    function test_FeeAccumulationOverTime() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // Distribute larger fees (10,000 PONDER instead of 100)
        vm.startPrank(owner);
        ponder.transfer(address(staking), 10_000e18);
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();
        vm.stopPrank();

        // Get and verify pending fees
        vm.startPrank(user1);
        uint256 pendingFees = staking.getPendingFees(user1);
        uint256 claimed = staking.claimFees();
        vm.stopPrank();

        assertEq(pendingFees, claimed, "Claimed amount should match pending fees");
        assertGt(claimed, PonderStakingTypes.MINIMUM_FEE_CLAIM, "Should exceed minimum claim amount");
    }

    function test_FeeAccumulationMultipleUsers() public {
        // User1 stakes
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // User2 stakes
        vm.startPrank(user2);
        ponder.approve(address(staking), 2000e18);
        staking.enter(2000e18, user2);
        vm.stopPrank();

        // Distribute larger fees (30,000 PONDER instead of 300)
        vm.startPrank(owner);
        ponder.transfer(address(staking), 30_000e18);
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();
        vm.stopPrank();

        // Users claim
        vm.startPrank(user1);
        uint256 claimed1 = staking.claimFees();
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 claimed2 = staking.claimFees();
        vm.stopPrank();

        // User2 should get twice User1's fees
        assertApproxEqRel(claimed2, claimed1 * 2, 0.01e18, "User2 should receive twice User1's fees");
    }

    function test_InitialRebaseDoesNotCountTeamStakeAsFees() public {
        // Get initial state with team allocation
        uint256 initialBalance = ponder.balanceOf(address(staking));
        uint256 initialTotalUnclaimedFees = staking.totalUnclaimedFees();
        uint256 initialAccFeesPerShare = staking.getAccumulatedFeesPerShare();

        // Perform first rebase
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();

        // Verify no fees were created from team stake
        assertEq(staking.totalUnclaimedFees(), initialTotalUnclaimedFees,
            "Total unclaimed fees should not change from team stake");
        assertEq(staking.getAccumulatedFeesPerShare(), initialAccFeesPerShare,
            "Accumulated fees per share should not change from team stake");

        // Verify team has no claimable fees
        uint256 teamFees = staking.getPendingFees(teamReserve);
        assertEq(teamFees, 0, "Team should have no fees from initial stake");
    }

    function test_InitialStakeDoesNotGenerateFees() public {
        // Record initial state
        uint256 initialAccFeesPerShare = staking.getAccumulatedFeesPerShare();

        // Stake tokens
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // Rebase should not create fees from stake
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();

        assertEq(staking.getAccumulatedFeesPerShare(), initialAccFeesPerShare,
            "Accumulated fees should not change from user stake");
        assertEq(staking.getPendingFees(user1), 0,
            "User should have no fees from their own stake");
    }

    function test_OnlyNewBalanceCountsAsFees() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // First rebase
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();

        uint256 initialAccFeesPerShare = staking.getAccumulatedFeesPerShare();
        uint256 initialBalance = ponder.balanceOf(address(staking));

        // Add actual fees (10,000 PONDER)
        vm.startPrank(owner);
        ponder.transfer(address(staking), 10_000e18);
        vm.stopPrank();

        // Second rebase
        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();

        uint256 newBalance = ponder.balanceOf(address(staking));
        uint256 totalShares = staking.totalSupply();
        uint256 newFees = newBalance - initialBalance;
        uint256 expectedFeesPerShare = (newFees * PonderStakingTypes.FEE_PRECISION) / totalShares;

        uint256 actualIncrease = staking.getAccumulatedFeesPerShare() - initialAccFeesPerShare;
        assertApproxEqAbs(actualIncrease, expectedFeesPerShare, 10000, "Should only distribute new balance as fees");
    }

    function test_FeeDistributionAfterMultipleStakes() public {
        // Initial stakes
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        ponder.approve(address(staking), 2000e18);
        staking.enter(2000e18, user2);
        vm.stopPrank();

        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();

        uint256 initialAccFeesPerShare = staking.getAccumulatedFeesPerShare();

        // Transfer larger fee amount (30,000 PONDER instead of 300)
        vm.startPrank(owner);
        ponder.transfer(address(staking), 30_000e18);
        vm.stopPrank();

        vm.warp(block.timestamp + PonderStakingTypes.REBASE_DELAY);
        staking.rebase();

        uint256 user1Fees = staking.getPendingFees(user1);
        uint256 user2Fees = staking.getPendingFees(user2);

        assertApproxEqRel(user2Fees, user1Fees * 2, 0.01e18, "Fee distribution should be proportional to stakes");
    }
}
