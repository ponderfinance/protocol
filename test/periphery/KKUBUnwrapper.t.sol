// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../mocks/WETH9.sol";
import "../../src/periphery/KKUBUnwrapper.sol";

contract MockKKUB is WETH9 {
    mapping(address => bool) public blacklist;
    mapping(address => uint256) public kycsLevel;
    uint256 public constant REQUIRED_KYC_LEVEL = 1;

    function setBlacklist(address user, bool status) external {
        blacklist[user] = status;
    }

    function setKYCLevel(address user, uint256 level) external {
        kycsLevel[user] = level;
    }

    function withdraw(uint256 wad) public virtual override {
        require(kycsLevel[msg.sender] > REQUIRED_KYC_LEVEL, "Insufficient KYC level");
        require(!blacklist[msg.sender], "Address is blacklisted");
        balanceOf[msg.sender] -= wad;
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }
}

contract KKUBUnwrapperTest is Test {
    KKUBUnwrapper unwrapper;
    MockKKUB kkub;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant AMOUNT = 1 ether;

    event UnwrappedKKUB(address indexed recipient, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event EmergencyWithdraw(uint256 amount);
    event EmergencyWithdrawTokens(address indexed token, uint256 amount);

    function setUp() public {
        kkub = new MockKKUB();
        unwrapper = new KKUBUnwrapper(address(kkub));

        // Setup initial states
        kkub.setKYCLevel(address(unwrapper), 2);
        vm.deal(address(unwrapper), 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // Basic unwrap functionality
    function testBasicUnwrap() public {
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
        kkub.setKYCLevel(address(unwrapper), 0);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        vm.expectRevert("Insufficient KYC level");
        unwrapper.unwrapKKUB(AMOUNT, alice);
        vm.stopPrank();
    }

    function testUnwrapToBlacklistedRecipient() public {
        kkub.setBlacklist(alice, true);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

        vm.expectRevert(KKUBUnwrapper.BlacklistedAddress.selector);
        unwrapper.unwrapKKUB(AMOUNT, alice);
        vm.stopPrank();
    }

    function testUnwrapWithBlacklistedContract() public {
        kkub.setBlacklist(address(unwrapper), true);

        vm.startPrank(alice);
        kkub.deposit{value: AMOUNT}();
        kkub.approve(address(unwrapper), AMOUNT);

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

        vm.expectRevert(KKUBUnwrapper.NotOwner.selector);
        unwrapper.transferOwnership(alice);

        vm.expectRevert(KKUBUnwrapper.NotOwner.selector);
        unwrapper.emergencyWithdraw();

        vm.expectRevert(KKUBUnwrapper.NotOwner.selector);
        unwrapper.emergencyWithdrawTokens(address(kkub));

        vm.stopPrank();
    }

    function testRevertTransferOwnershipToZeroAddress() public {
        vm.expectRevert(KKUBUnwrapper.ZeroAddress.selector);
        unwrapper.transferOwnership(address(0));
    }

    function testRevertAcceptOwnershipNotPending() public {
        vm.startPrank(alice);
        vm.expectRevert(KKUBUnwrapper.NotPendingOwner.selector);
        unwrapper.acceptOwnership();
        vm.stopPrank();
    }

    function testOwnershipTransferComplete() public {
        address newOwner = makeAddr("newOwner");

        // Start ownership transfer
        unwrapper.transferOwnership(newOwner);
        assertEq(unwrapper.owner(), address(this), "Owner changed before acceptance");
        assertEq(unwrapper.pendingOwner(), newOwner, "Pending owner not set");

        // Accept ownership
        vm.prank(newOwner);
        unwrapper.acceptOwnership();
        assertEq(unwrapper.owner(), newOwner, "Ownership not transferred");
        assertEq(unwrapper.pendingOwner(), address(0), "Pending owner not cleared");
    }

    function testRevertTransferOwnershipFromNonOwner() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(alice);
        vm.expectRevert(KKUBUnwrapper.NotOwner.selector);
        unwrapper.transferOwnership(newOwner);
    }

    function testRevertAcceptOwnershipWhenNotPending() public {
        address newOwner = makeAddr("newOwner");

        // Start ownership transfer to one address
        unwrapper.transferOwnership(newOwner);

        // Try to accept from different address
        vm.prank(alice);
        vm.expectRevert(KKUBUnwrapper.NotPendingOwner.selector);
        unwrapper.acceptOwnership();
    }

    // Emergency functions tests
    function testEmergencyWithdraw() public {
        uint256 amount = 1 ether;
        vm.deal(address(unwrapper), amount);

        uint256 ownerBalanceBefore = address(this).balance;
        unwrapper.emergencyWithdraw();
        assertEq(
            address(this).balance - ownerBalanceBefore,
            amount,
            "Emergency withdrawal amount incorrect"
        );
    }

    function testEmergencyWithdrawTokens() public {
        uint256 amount = 1 ether;

        // Setup some tokens to withdraw
        vm.startPrank(alice);
        kkub.deposit{value: amount}();
        kkub.transfer(address(unwrapper), amount);
        vm.stopPrank();

        uint256 balanceBefore = kkub.balanceOf(address(this));
        unwrapper.emergencyWithdrawTokens(address(kkub));
        assertEq(
            kkub.balanceOf(address(this)) - balanceBefore,
            amount,
            "Emergency token withdrawal amount incorrect"
        );
    }

    // Edge cases
    function testUnwrapZeroAmount() public {
        vm.startPrank(alice);
        kkub.approve(address(unwrapper), 0);
        unwrapper.unwrapKKUB(0, alice);
        vm.stopPrank();
    }


    receive() external payable {}
}
