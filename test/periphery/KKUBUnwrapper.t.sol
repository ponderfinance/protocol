// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../mocks/WETH9.sol";
import "../../src/periphery/unwrapper/KKUBUnwrapper.sol";
import { IKKUBUnwrapper } from "../../src/periphery/unwrapper/IKKUBUnwrapper.sol";

// Mock KYC contract to match real implementation
contract MockKYC {
    mapping(address => uint256) public kycsLevel;

    function setKYCLevel(address user, uint256 level) external {
        kycsLevel[user] = level;
    }
}

contract MockKKUB is WETH9 {
    mapping(address => bool) public blacklist;
    uint256 public kycsLevel; // This is a state variable, not a function that takes an address
    MockKYC public kyc;  // Reference to KYC contract
    bool public silentWithdrawFailure;

    constructor() {
        kyc = new MockKYC();
        kycsLevel = 1; // Default KYC level requirement
    }

    function setBlacklist(address user, bool status) external {
        blacklist[user] = status;
    }

    // Set KYC level in the KYC contract
    function setKYCLevel(address user, uint256 level) external {
        kyc.setKYCLevel(user, level);
    }

    // Set required KYC level (state variable)
    function setRequiredKYCLevel(uint256 level) external {
        kycsLevel = level;
    }

    function setSilentWithdrawFailure(bool _fail) external {
        silentWithdrawFailure = _fail;
    }

    function withdraw(uint256 wad) public virtual override {
        require(kyc.kycsLevel(msg.sender) > kycsLevel, "Insufficient KYC level");
        require(!blacklist[msg.sender], "Address is blacklisted");
        balanceOf[msg.sender] -= wad;

        // Simulate silent failure by not transferring ETH but still marking as success
        if (!silentWithdrawFailure) {
            payable(msg.sender).transfer(wad);
        }
        emit Withdrawal(msg.sender, wad);
    }
}

// Add malicious receiver contract right before the main test contract
contract ExploitReceiver {
    KKUBUnwrapper public unwrapper;
    bool public attackSuccess;

    constructor(KKUBUnwrapper _unwrapper) {
        unwrapper = _unwrapper;
    }

    receive() external payable {
        if (address(unwrapper).balance > 0 && !attackSuccess) {
            // Try to exploit by calling unwrap again during ETH receive
            try unwrapper.unwrapKKUB(msg.value, address(this)) {
                attackSuccess = true;
            } catch {
                // Attack failed
            }
        }
    }
}

contract KKUBUnwrapperTest is Test {
    KKUBUnwrapper unwrapper;
    MockKKUB kkub;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant AMOUNT = 1 ether;
    uint256 public constant WITHDRAWAL_DELAY = 6 hours;

    event UnwrappedKKUB(address indexed recipient, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event EmergencyWithdraw(uint256 amount);
    event EmergencyWithdrawTokens(address indexed token, uint256 amount);
    event Paused(address account);
    event Unpaused(address account);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    function setUp() public {
        kkub = new MockKKUB();
        unwrapper = new KKUBUnwrapper(address(kkub));

        // Setup initial states - set KYC levels appropriately
        kkub.setKYCLevel(address(unwrapper), 2);
        kkub.setRequiredKYCLevel(1);

        vm.deal(address(unwrapper), 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function testExploit_PreventSilentWithdrawFailureTheft() public {
        uint256 existingBalance = 10 ether;
        vm.deal(address(unwrapper), existingBalance);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        kkub.setSilentWithdrawFailure(true);

        vm.expectRevert();
        unwrapper.unwrapKKUB(AMOUNT, alice);

        assertEq(address(unwrapper).balance, existingBalance, "ETH should not have been transferred");
        assertEq(alice.balance, 99 ether, "Attacker balance should remain unchanged");

        vm.stopPrank();
    }

    function testExploit_PreventExcessiveETHWithdrawal() public {
        uint256 smallAmount = 0.1 ether;
        uint256 largeAmount = 1 ether;

        // Setup initial balances
        vm.deal(address(unwrapper), 0); // Start with 0 balance
        vm.deal(alice, largeAmount);

        // Make sure unwrapper has sufficient KYC level
        kkub.setKYCLevel(address(unwrapper), 2);
        kkub.setRequiredKYCLevel(1);

        // Record initial balances
        uint256 initialUnwrapperBalance = address(unwrapper).balance;
        uint256 initialAliceBalance = alice.balance;

        vm.startPrank(alice);

        // Deposit KKUB
        kkub.deposit{value: smallAmount}();
        kkub.approve(address(unwrapper), smallAmount);

        // Execute unwrap
        unwrapper.unwrapKKUB(smallAmount, alice);

        // Final balances
        uint256 finalUnwrapperBalance = address(unwrapper).balance;
        uint256 finalAliceBalance = alice.balance;

        // Verify balances
        assertEq(
            finalUnwrapperBalance,
            initialUnwrapperBalance,
            "Contract should not retain any ETH"
        );

        assertApproxEqAbs(
            finalAliceBalance,
            initialAliceBalance - smallAmount + smallAmount, // deposit then withdrawal should roughly cancel out (minus gas)
            0.01 ether, // Allow for gas costs
            "Alice's balance should net to initial minus gas fees"
        );

        vm.stopPrank();
    }

    function testExploit_PreventReentrancyTheft() public {
        ExploitReceiver exploiter = new ExploitReceiver(unwrapper);
        vm.deal(address(exploiter), 1 ether);

        // Make sure unwrapper has sufficient KYC level
        kkub.setKYCLevel(address(unwrapper), 2);
        kkub.setRequiredKYCLevel(1);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        unwrapper.unwrapKKUB(AMOUNT, address(exploiter));

        assertEq(exploiter.attackSuccess(), false, "Reentrancy attack should fail");

        vm.stopPrank();
    }

    // Basic unwrap functionality
    function testBasicUnwrap() public {
        // Make sure unwrapper has sufficient KYC level
        kkub.setKYCLevel(address(unwrapper), 2);
        kkub.setRequiredKYCLevel(1);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        uint256 balanceBefore = alice.balance;

        vm.expectEmit(true, true, false, true);
        emit UnwrappedKKUB(alice, AMOUNT);

        unwrapper.unwrapKKUB(AMOUNT, alice);

        assertEq(alice.balance - balanceBefore, AMOUNT, "Incorrect ETH received");
        assertEq(kkub.balanceOf(alice), 0, "KKUB not fully unwrapped");
        vm.stopPrank();
    }

    // Test unwrapping to a different recipient
    function testUnwrapToOtherRecipient() public {
        // Make sure unwrapper has sufficient KYC level
        kkub.setKYCLevel(address(unwrapper), 2);
        kkub.setRequiredKYCLevel(1);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        uint256 bobBalanceBefore = bob.balance;

        vm.expectEmit(true, true, false, true);
        emit UnwrappedKKUB(bob, AMOUNT);

        unwrapper.unwrapKKUB(AMOUNT, bob);

        assertEq(bob.balance - bobBalanceBefore, AMOUNT, "Incorrect ETH received by recipient");
        assertEq(kkub.balanceOf(alice), 0, "KKUB not fully unwrapped from sender");
        vm.stopPrank();
    }

    // KYC and Blacklist tests
    function testUnwrapWithoutContractKYC() public {
        // Set contract KYC level to 0 in the KYC contract
        kkub.setKYCLevel(address(unwrapper), 0);

        // Ensure the required level is higher
        kkub.setRequiredKYCLevel(1);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        // Should revert with InsufficientKYCLevel error
        vm.expectRevert(IKKUBUnwrapper.InsufficientKYCLevel.selector);
        unwrapper.unwrapKKUB(AMOUNT, alice);
        vm.stopPrank();
    }

    function testUnwrapToBlacklistedRecipient() public {
        kkub.setBlacklist(alice, true);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        vm.expectRevert(IKKUBUnwrapper.BlacklistedAddress.selector);
        unwrapper.unwrapKKUB(AMOUNT, alice);
        vm.stopPrank();
    }

    function testUnwrapWithBlacklistedContract() public {
        kkub.setBlacklist(address(unwrapper), true);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        // The exact error will depend on your implementation
        // If the unwrapper checks its own blacklist status, it would be:
        vm.expectRevert("Address is blacklisted");
        unwrapper.unwrapKKUB(AMOUNT, alice);
        vm.stopPrank();
    }

    // Approval and balance tests
    function testUnwrapWithoutApproval() public {
        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        vm.expectRevert();
        unwrapper.unwrapKKUB(AMOUNT, alice);
        vm.stopPrank();
    }

    function testUnwrapWithInsufficientBalance() public {
        vm.startPrank(alice);
        kkub.approve(address(unwrapper), AMOUNT);
        vm.expectRevert();
        unwrapper.unwrapKKUB(AMOUNT, alice);
        vm.stopPrank();
    }

    // Ownership tests
    function testRevertNonOwnerFunctions() public {
        vm.startPrank(alice);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        unwrapper.transferOwnership(alice);

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        unwrapper.emergencyWithdraw();

        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        unwrapper.pause();

        vm.stopPrank();
    }

    function testRevertTransferOwnershipToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidNewOwner()"));
        unwrapper.transferOwnership(address(0));
    }

    function testRevertAcceptOwnershipNotPending() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        unwrapper.acceptOwnership();
        vm.stopPrank();
    }

    function testOwnershipTransferComplete() public {
        address newOwner = makeAddr("newOwner");

        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(address(this), newOwner);
        unwrapper.transferOwnership(newOwner);

        assertEq(unwrapper.owner(), address(this), "Owner should not change before acceptance");
        assertEq(unwrapper.pendingOwner(), newOwner, "Pending owner should be set");

        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(address(this), newOwner);
        unwrapper.acceptOwnership();

        assertEq(unwrapper.owner(), newOwner, "Owner should be updated after acceptance");
        assertEq(unwrapper.pendingOwner(), address(0), "Pending owner should be cleared");
    }

    function testRevertTransferOwnershipFromNonOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        unwrapper.transferOwnership(newOwner);
    }

    function testRevertAcceptOwnershipWhenNotPending() public {
        address newOwner = makeAddr("newOwner");

        // Start ownership transfer to one address
        unwrapper.transferOwnership(newOwner);

        // Try to accept from different address
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        unwrapper.acceptOwnership();
    }

    // Emergency functions tests
    function testEmergencyWithdraw() public {
        uint256 amount = 1000 ether; // MAX_WITHDRAWAL_AMOUNT
        vm.deal(address(unwrapper), amount * 2);

        // Warp time to allow withdrawal
        vm.warp(block.timestamp + 6 hours + 1);

        uint256 ownerBalanceBefore = address(this).balance;
        unwrapper.emergencyWithdraw();

        uint256 withdrawn = address(this).balance - ownerBalanceBefore;
        assertEq(withdrawn, amount, "Emergency withdrawal should respect max amount");
        assertTrue(unwrapper.paused(), "Contract should be paused after emergency withdraw");
    }

    // Edge cases
    function testUnwrapZeroAmount() public {
        vm.startPrank(alice);
        kkub.approve(address(unwrapper), 0);
        vm.expectRevert(IKKUBUnwrapper.ZeroAmount.selector);
        unwrapper.unwrapKKUB(0, alice);
        vm.stopPrank();
    }

    // Additional tests to add to KKUBUnwrapperTest contract

    function testEmergencyWithdraw_RateLimiting() public {
        vm.deal(address(unwrapper), 2000 ether);

        // First withdrawal should succeed with time warp
        vm.warp(block.timestamp + WITHDRAWAL_DELAY + 1);

        uint256 ownerBalanceBefore = address(this).balance;
        unwrapper.emergencyWithdraw();
        uint256 firstWithdrawal = address(this).balance - ownerBalanceBefore;
        assertEq(firstWithdrawal, 1000 ether, "Should be limited to MAX_WITHDRAWAL_AMOUNT");

        // Immediate second withdrawal should fail
        vm.expectRevert(IKKUBUnwrapper.WithdrawalTooFrequent.selector);
        unwrapper.emergencyWithdraw();

        // After delay, should work again
        vm.warp(block.timestamp + WITHDRAWAL_DELAY + 1);
        ownerBalanceBefore = address(this).balance;
        unwrapper.emergencyWithdraw();
        uint256 secondWithdrawal = address(this).balance - ownerBalanceBefore;
        assertEq(secondWithdrawal, 1000 ether, "Should allow max withdrawal after delay");
    }

    function testEmergencyWithdraw_AutoPause() public {
        // Check initial state
        assertEq(unwrapper.paused(), false, "Should start unpaused");

        // Warp time to allow withdrawal
        vm.warp(block.timestamp + 6 hours + 1);

        // Emergency withdraw should auto-pause
        unwrapper.emergencyWithdraw();
        assertEq(unwrapper.paused(), true, "Should be paused after emergency");

        // Try unwrap after emergency
        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        unwrapper.unwrapKKUB(AMOUNT, alice);
        vm.stopPrank();
    }

    function testResetWithdrawalLimit() public {
        vm.deal(address(unwrapper), 2000 ether);

        // Warp time to allow first withdrawal
        vm.warp(block.timestamp + 6 hours + 1);

        // Do max withdrawal
        unwrapper.emergencyWithdraw();

        // Try reset before delay (should not reset)
        unwrapper.resetWithdrawalLimit();
        vm.expectRevert(IKKUBUnwrapper.WithdrawalTooFrequent.selector);
        unwrapper.emergencyWithdraw();

        // Move past delay and reset
        vm.warp(block.timestamp + 6 hours + 1);
        unwrapper.resetWithdrawalLimit();

        // Should allow new max withdrawal
        uint256 ownerBalanceBefore = address(this).balance;
        unwrapper.emergencyWithdraw();
        uint256 withdrawn = address(this).balance - ownerBalanceBefore;
        assertEq(withdrawn, 1000 ether, "Should allow max withdrawal after reset");
    }

    function testPause_OnlyOwner() public {
        // Non-owner cannot pause
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        unwrapper.pause();

        // Owner can pause
        unwrapper.pause();
        assertTrue(unwrapper.paused(), "Contract should be paused");
    }

    function testUnpause_OnlyOwner() public {
        // First pause
        unwrapper.pause();

        // Non-owner cannot unpause
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        unwrapper.unpause();

        // Owner can unpause
        unwrapper.unpause();
        assertFalse(unwrapper.paused(), "Contract should be unpaused");
    }

    function testEmergencyWithdraw_LockedFunds() public {
        // Setup with more than MAX_WITHDRAWAL_AMOUNT (1000 ether)
        uint256 largeBalance = 2000 ether; // 2000 ETH > MAX_WITHDRAWAL_AMOUNT (1000 ETH)
        vm.deal(address(unwrapper), largeBalance);

        // Setup mock state
        kkub.setKYCLevel(address(unwrapper), 2);

        // Warp time to allow withdrawal
        vm.warp(block.timestamp + 6 hours + 1);

        // Record initial balances
        uint256 ownerBalanceBefore = address(this).balance;
        uint256 contractBalanceBefore = address(unwrapper).balance;

        // Perform emergency withdrawal
        unwrapper.emergencyWithdraw();

        // Check withdrawn amount
        uint256 withdrawn = address(this).balance - ownerBalanceBefore;
        assertEq(withdrawn, 1000 ether, "Should only withdraw max amount");

        // Verify remaining contract balance
        assertEq(
            address(unwrapper).balance,
            contractBalanceBefore - 1000 ether,
            "Contract should retain remaining balance"
        );
    }

    function testUnwrapKKUB_WhenPaused() public {
        // Setup
        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        // Pause contract
        vm.stopPrank();
        unwrapper.pause();

        // Try unwrap while paused
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        unwrapper.unwrapKKUB(AMOUNT, alice);
    }

    function testUnwrapWithExactReceivedAmount() public {
        // Setup
        uint256 existingBalance = 5 ether;
        vm.deal(address(unwrapper), existingBalance);

        // Make sure unwrapper has sufficient KYC level
        kkub.setKYCLevel(address(unwrapper), 2);
        kkub.setRequiredKYCLevel(1);

        // Setup mock KKUB behavior to return slightly less ETH
        kkub.setSilentWithdrawFailure(false); // Make sure normal withdraw works

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        uint256 initialAliceBalance = alice.balance;
        uint256 initialUnwrapperBalance = address(unwrapper).balance;

        // Execute unwrap operation
        unwrapper.unwrapKKUB(AMOUNT, alice);

        // Verify balances
        assertGe(alice.balance, initialAliceBalance, "Alice should receive ETH");
        assertEq(unwrapper.getLockedBalance(), 0, "Locked balance should be reset");
        assertApproxEqAbs(
            address(unwrapper).balance,
            initialUnwrapperBalance,
            0.001 ether,
            "Unwrapper should not retain significant ETH"
        );

        // Try a second unwrap to verify balance tracking works correctly
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);
        unwrapper.unwrapKKUB(AMOUNT, alice);

        // Verify locked balance is reset correctly
        assertEq(unwrapper.getLockedBalance(), 0, "Locked balance should be reset after second unwrap");
        vm.stopPrank();
    }

    function testConsecutiveUnwrapsAfterError() public {
        // Setup
        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT * 2}();
        kkub.approve(address(unwrapper), AMOUNT * 2);

        // First try an unwrap that will fail
        kkub.setSilentWithdrawFailure(true);
        vm.expectRevert(); // This should revert
        unwrapper.unwrapKKUB(AMOUNT, alice);

        // Verify locked balance is properly reset even after error
        assertEq(unwrapper.getLockedBalance(), 0, "Locked balance should be reset after error");

        // Now try a normal unwrap
        kkub.setSilentWithdrawFailure(false);
        unwrapper.unwrapKKUB(AMOUNT, alice);

        // Verify it succeeded and balance tracking is correct
        assertEq(unwrapper.getLockedBalance(), 0, "Locked balance should be reset after successful unwrap");
        vm.stopPrank();
    }

    receive() external payable {}
}
