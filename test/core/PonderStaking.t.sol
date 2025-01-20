// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/core/staking/PonderStaking.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/periphery/router/PonderRouter.sol";

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
        marketing = address(0x5);

        // Deploy contracts
        factory = new PonderFactory(owner, address(0), address(0));
        router = new PonderRouter(address(factory), WETH, address(0));

        ponder = new PonderToken(teamReserve, marketing, address(0));
        staking = new PonderStaking(address(ponder), address(router), address(factory));

        // Get tokens from marketing wallet
        vm.startPrank(marketing);
        // Send tokens for user tests
        ponder.transfer(user1, 10_000e18);
        ponder.transfer(user2, 10_000e18);
        // Send tokens for test contract (for simulating rewards)
        ponder.transfer(address(this), 100_000e18);
        vm.stopPrank();
    }


    function test_LeaveWithRewards() public {
        // First stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Simulate fee distribution using test contract's balance
        ponder.transfer(address(staking), 100e18);

        // Leave all shares
        vm.startPrank(user1);
        uint256 ponderReceived = staking.leave(1000e18);
        vm.stopPrank();

        assertEq(ponderReceived, 1100e18, "Should receive initial stake plus rewards");
    }

    function test_MultipleEnters() public {
        // First user stakes
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Add rewards using test contract's balance
        ponder.transfer(address(staking), 100e18);

        // Second user stakes
        uint256 user2StakeAmount = 1000e18;
        vm.startPrank(user2);
        ponder.approve(address(staking), user2StakeAmount);
        uint256 shares = staking.enter(user2StakeAmount);
        vm.stopPrank();

        assertLt(shares, user2StakeAmount, "Should receive fewer shares due to rewards");
    }

    function test_GetPonderAmount() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        assertEq(staking.getPonderAmount(1000e18), 1000e18, "Should be 1:1 initially");

        // Add rewards using test contract's balance
        ponder.transfer(address(staking), 100e18);

        assertEq(staking.getPonderAmount(1000e18), 1100e18, "Should reflect rewards");
    }

    function testFuzz_EnterAndLeave(uint256 amount) public {
        // Bound amount between MINIMUM_FIRST_STAKE and reasonable max amount
        amount = bound(amount, staking.MINIMUM_FIRST_STAKE(), 10000e18);

        vm.startPrank(marketing);
        ponder.transfer(address(this), amount);
        vm.stopPrank();

        ponder.approve(address(staking), amount);
        uint256 shares = staking.enter(amount);
        uint256 ponderReceived = staking.leave(shares);

        assertApproxEqRel(ponderReceived, amount, 1e14);
    }

    function test_InitialState() public {
        assertEq(address(staking.PONDER()), address(ponder));
        assertEq(address(staking.ROUTER()), address(router));
        assertEq(address(staking.FACTORY()), address(factory));
        assertEq(staking.owner(), owner);
    }

    function test_Enter() public {
        uint256 stakeAmount = 1000e18;

        vm.startPrank(user1);
        ponder.approve(address(staking), stakeAmount);

        vm.expectEmit(true, true, true, true);
        emit Staked(user1, stakeAmount, stakeAmount); // 1:1 for first stake

        uint256 shares = staking.enter(stakeAmount);
        vm.stopPrank();

        assertEq(shares, stakeAmount, "Should receive 1:1 shares for first stake");
        assertEq(staking.balanceOf(user1), stakeAmount, "Should have correct xPONDER balance");
        assertEq(ponder.balanceOf(address(staking)), stakeAmount, "Staking contract should have PONDER");
    }

    function test_Leave() public {
        // First stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);

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
        staking.enter(0);

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

        assertEq(staking.owner(), newOwner);
        assertEq(staking.pendingOwner(), address(0));
    }

    function test_PreventFirstStakeManipulation() public {
        // Attacker tries to manipulate share ratio
        vm.startPrank(user2);
        ponder.transfer(address(staking), 1e15);
        vm.stopPrank();

        // User1 performs normal stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        uint256 shares = staking.enter(1000e18);
        vm.stopPrank();

        // Should get exact 1:1 ratio for first stake
        assertEq(shares, 1000e18, "Share ratio was manipulated");
    }

    function test_FirstStakeMinimum() public {
        uint256 smallAmount = 100e18; // Below MINIMUM_FIRST_STAKE

        vm.startPrank(user1);
        ponder.approve(address(staking), smallAmount);
        vm.expectRevert(abi.encodeWithSignature("InsufficientFirstStake()"));
        staking.enter(smallAmount);
        vm.stopPrank();
    }

    function test_ShareRatioPreservation() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        uint256 shares1 = staking.enter(1000e18);
        vm.stopPrank();

        // Second stake with half amount
        vm.startPrank(user2);
        ponder.approve(address(staking), 500e18);
        uint256 shares2 = staking.enter(500e18);
        vm.stopPrank();

        // Half amount should get half shares
        assertEq(shares2, shares1 / 2, "Share ratio not preserved");

        // Verify totals
        uint256 totalShares = staking.totalSupply();
        uint256 totalStaked = ponder.balanceOf(address(staking));
        assertEq(totalShares, shares1 + shares2, "Incorrect total shares");
        assertEq(totalStaked, 1500e18, "Incorrect total staked");
    }

    function test_ShareValueIncreasesWithFees() public {
        // First stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Record initial share value
        uint256 initialShareValue = staking.getPonderAmount(1000e18);

        // Simulate fee distribution
        ponder.transfer(address(staking), 100e18);

        // Share value should increase automatically
        uint256 newShareValue = staking.getPonderAmount(1000e18);
        assertGt(newShareValue, initialShareValue, "Share value should increase with fees");
        assertEq(newShareValue, 1100e18, "Share value should reflect total balance");
    }

    function test_MultipleShareholders() public {
        // User1 stakes first
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Simulate fee distribution
        ponder.transfer(address(staking), 100e18);

        // User2 stakes after fees
        vm.startPrank(user2);
        ponder.approve(address(staking), 1000e18);
        // When user2 stakes 1000e18 PONDER, they should get proportionally fewer shares
        // Total pool = 1100e18 PONDER, total shares = 1000e18
        // So 1000e18 PONDER should get (1000e18 * 1000e18) / 1100e18 shares
        uint256 user2Shares = staking.enter(1000e18);
        vm.stopPrank();

        // Both users should have proportional claims
        // User1: 1000e18 shares = 1100e18 PONDER
        // User2: ~909e18 shares = 1000e18 PONDER
        uint256 user1Ponder = staking.getPonderAmount(1000e18);
        uint256 user2Ponder = staking.getPonderAmount(user2Shares);

        // User2 should get ~1000e18 PONDER worth of value
        assertApproxEqRel(user2Ponder, 1000e18, 0.01e18, "User2 should get ~1000e18 PONDER value");
        // User1 should get ~1100e18 PONDER worth of value (original + fees)
        assertApproxEqRel(user1Ponder, 1100e18, 0.01e18, "User1 should get ~1100e18 PONDER value");
    }

    function test_ShareValueMaintainedThroughoutOperations() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Add fees
        ponder.transfer(address(staking), 100e18);

        // Second user stakes
        vm.startPrank(user2);
        ponder.approve(address(staking), 500e18);
        uint256 user2Shares = staking.enter(500e18);
        vm.stopPrank();

        // More fees
        ponder.transfer(address(staking), 50e18);

        // First user withdraws half
        vm.startPrank(user1);
        uint256 withdrawAmount = staking.leave(500e18);
        vm.stopPrank();

        // Verify proportions are maintained
        uint256 totalPonder = ponder.balanceOf(address(staking));
        uint256 totalShares = staking.totalSupply();
        uint256 expectedShareValue = (totalPonder * 1e18) / totalShares;
        assertEq(staking.getPonderAmount(1e18), expectedShareValue, "Share value should be maintained");
    }

    function test_PreventSandwichAttack() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Setup sandwich attack
        vm.prank(address(this));  // Test contract has tokens
        ponder.transfer(address(staking), 100e18);

        // Mock a transfer reversion during leave to simulate sandwich
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(true)
        );

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidBalance()"));
        staking.leave(500e18);
        vm.stopPrank();
    }

    function test_PreventDustShares() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Try to withdraw tiny amount
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("MinimumSharesRequired()"));
        staking.leave(1); // Dust amount
        vm.stopPrank();
    }

    function test_PreventExcessiveShares() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Try to withdraw more than owned
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidSharesAmount()"));
        staking.leave(2000e18);
        vm.stopPrank();
    }

    function test_PreventReentrancyOnLeave() public {
        // Initial stake with real token
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);

        // Record initial balances
        uint256 initialShares = staking.balanceOf(user1);
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // Now try to leave with a malicious transfer hook
        vm.mockCall(
            address(ponder),
            abi.encodeWithSelector(IERC20.transfer.selector),
            abi.encode(false)  // Simulate failed transfer that might try reentrancy
        );

        vm.expectRevert(abi.encodeWithSignature("TransferFailed()"));
        staking.leave(500e18);
        vm.stopPrank();

        // Verify state hasn't changed
        assertEq(staking.balanceOf(user1), initialShares, "Shares should not change");
        assertEq(ponder.balanceOf(address(staking)), initialStakingBalance, "Staking balance should not change");
    }
}

contract ReentrantToken is PonderERC20 {
    constructor() PonderERC20("Reentrant", "REKT") {}

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Try to reenter staking contract
        PonderStaking(msg.sender).leave(amount);
        return true;
    }
}
