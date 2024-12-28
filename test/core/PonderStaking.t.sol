// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/core/PonderStaking.sol";
import "../../src/core/PonderToken.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/periphery/PonderRouter.sol";

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
        treasury = address(0x3);
        teamReserve = address(0x4);
        marketing = address(0x5);

        // Deploy contracts
        factory = new PonderFactory(owner, address(0), address(0));

        router = new PonderRouter(
            address(factory),
            WETH,
            address(0) // No unwrapper needed for tests
        );

        ponder = new PonderToken(
            treasury,
            teamReserve,
            marketing,
            address(0)
        );

        staking = new PonderStaking(
            address(ponder),
            address(router),
            address(factory)
        );

        // Setup initial balances
        vm.startPrank(treasury);
        ponder.transfer(user1, 10_000e18);
        ponder.transfer(user2, 10_000e18);
        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(address(staking.ponder()), address(ponder));
        assertEq(address(staking.router()), address(router));
        assertEq(address(staking.factory()), address(factory));
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

    function test_MultipleEnters() public {
        // First user stakes
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Add rewards (simulating fee distribution)
        vm.startPrank(treasury);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // Second user stakes
        uint256 user2StakeAmount = 1000e18;
        vm.startPrank(user2);
        ponder.approve(address(staking), user2StakeAmount);
        uint256 shares = staking.enter(user2StakeAmount);
        vm.stopPrank();

        // Should receive fewer shares due to increased PONDER per share
        assertLt(shares, user2StakeAmount, "Should receive fewer shares due to rewards");
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

    function test_LeaveWithRewards() public {
        // First stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Simulate fee distribution
        vm.startPrank(treasury);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // Leave all shares
        vm.startPrank(user1);
        uint256 ponderReceived = staking.leave(1000e18);
        vm.stopPrank();

        assertEq(ponderReceived, 1100e18, "Should receive initial stake plus rewards");
    }

    function test_Rebase() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // Simulate fee distribution
        vm.startPrank(treasury);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // Advance time for rebase
        vm.warp(block.timestamp + 1 days);

        vm.expectEmit(true, true, true, true);
        emit RebasePerformed(1000e18, 1100e18);

        staking.rebase();

        // Check share value after rebase
        uint256 shareValue = staking.getPonderAmount(1000e18);
        assertEq(shareValue, 1100e18, "Share value should reflect rewards");
    }

    function test_RebaseFrequency() public {
        // Advance time past initial lastRebaseTime
        vm.warp(block.timestamp + 1 days);

        staking.rebase();

        vm.expectRevert(abi.encodeWithSignature("RebaseTooFrequent()"));
        staking.rebase();

        // Advance time but not enough
        vm.warp(block.timestamp + 12 hours);
        vm.expectRevert(abi.encodeWithSignature("RebaseTooFrequent()"));
        staking.rebase();

        // Advance enough time
        vm.warp(block.timestamp + 12 hours);
        staking.rebase(); // Should succeed
    }

    function test_GetPonderAmount() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // No rewards yet
        assertEq(staking.getPonderAmount(1000e18), 1000e18, "Should be 1:1 initially");

        // Add rewards
        vm.startPrank(treasury);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        assertEq(staking.getPonderAmount(1000e18), 1100e18, "Should reflect rewards");
    }

    function test_GetSharesAmount() public {
        // Initial stake
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18);
        vm.stopPrank();

        // No rewards yet
        assertEq(staking.getSharesAmount(1000e18), 1000e18, "Should be 1:1 initially");

        // Add rewards
        vm.startPrank(treasury);
        ponder.transfer(address(staking), 100e18);
        vm.stopPrank();

        // Should get fewer shares for same PONDER amount
        assertLt(staking.getSharesAmount(1000e18), 1000e18, "Should get fewer shares after rewards");
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

    function testFuzz_EnterAndLeave(uint256 amount) public {
        // Bound the amount to reasonable values and minimum necessary for share calculation
        amount = bound(amount, 1e18, 100_000e18);

        vm.startPrank(treasury);
        ponder.transfer(address(this), amount);
        vm.stopPrank();

        ponder.approve(address(staking), amount);
        uint256 shares = staking.enter(amount);
        uint256 ponderReceived = staking.leave(shares);

        // Should get back the same amount (minus rounding if any)
        assertApproxEqRel(ponderReceived, amount, 1e14); // 0.01% tolerance for rounding
    }
}
