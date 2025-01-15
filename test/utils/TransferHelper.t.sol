// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/libraries/TransferHelper.sol";
import "../mocks/ERC20Mint.sol";

// Mock contracts for testing different transfer scenarios
contract NonCompliantToken {
    // Transfer always returns false
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }

    function approve(address, uint256) external pure returns (bool) {
        return false;
    }
}

contract RevertingToken {
    // Transfer always reverts
    function transfer(address, uint256) external pure {
        revert("TRANSFER_FAILED");
    }

    function transferFrom(address, address, uint256) external pure {
        revert("TRANSFER_FROM_FAILED");
    }

    function approve(address, uint256) external pure {
        revert("APPROVE_FAILED");
    }
}

contract NoReturnToken {
    // Transfer returns nothing (common in some older tokens)
    function transfer(address, uint256) external pure {
    }

    function transferFrom(address, address, uint256) external pure {
    }

    function approve(address, uint256) external pure {
    }
}

contract TransferHelperTest is Test {
    ERC20Mint compliantToken;
    NonCompliantToken nonCompliantToken;
    RevertingToken revertingToken;
    NoReturnToken noReturnToken;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    uint256 constant TEST_AMOUNT = 100e18;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        // Deploy test tokens
        compliantToken = new ERC20Mint("Test Token", "TEST");
        nonCompliantToken = new NonCompliantToken();
        revertingToken = new RevertingToken();
        noReturnToken = new NoReturnToken();

        // Setup initial balances
        compliantToken.mint(address(this), TEST_AMOUNT);  // Mint to test contract instead
        vm.deal(alice, TEST_AMOUNT); // For ETH transfer tests
    }

    function testSafeTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), bob, TEST_AMOUNT);

        TransferHelper.safeTransfer(address(compliantToken), bob, TEST_AMOUNT);
        assertEq(compliantToken.balanceOf(bob), TEST_AMOUNT);
    }

    function testSafeTransferFrom() public {
        // Setup for transferFrom
        compliantToken.mint(alice, TEST_AMOUNT);

        vm.prank(alice);
        compliantToken.approve(address(this), TEST_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, TEST_AMOUNT);

        TransferHelper.safeTransferFrom(address(compliantToken), alice, bob, TEST_AMOUNT);
        assertEq(compliantToken.balanceOf(bob), TEST_AMOUNT);
    }

    function testSafeApprove() public {
        TransferHelper.safeApprove(address(compliantToken), bob, TEST_AMOUNT);
        assertEq(compliantToken.allowance(address(this), bob), TEST_AMOUNT);
    }

    function testSafeTransferETH() public {
        vm.prank(alice);
        uint256 balanceBefore = bob.balance;
        TransferHelper.safeTransferETH(bob, TEST_AMOUNT);
        assertEq(bob.balance - balanceBefore, TEST_AMOUNT);
    }

    function testFailNonCompliantTransfer() public {
        vm.expectRevert("TransferHelper::safeTransfer: transfer failed");
        TransferHelper.safeTransfer(address(nonCompliantToken), bob, TEST_AMOUNT);
    }

    function testFailNonCompliantTransferFrom() public {
        vm.expectRevert("TransferHelper::transferFrom: transferFrom failed");
        TransferHelper.safeTransferFrom(address(nonCompliantToken), alice, bob, TEST_AMOUNT);
    }

    function testFailNonCompliantApprove() public {
        vm.expectRevert("TransferHelper::safeApprove: approve failed");
        TransferHelper.safeApprove(address(nonCompliantToken), bob, TEST_AMOUNT);
    }

    function testFailRevertingTransfer() public {
        vm.expectRevert("TRANSFER_FAILED");
        TransferHelper.safeTransfer(address(revertingToken), bob, TEST_AMOUNT);
    }

    function testFailRevertingTransferFrom() public {
        vm.expectRevert("TRANSFER_FROM_FAILED");
        TransferHelper.safeTransferFrom(address(revertingToken), alice, bob, TEST_AMOUNT);
    }

    function testFailRevertingApprove() public {
        vm.expectRevert("APPROVE_FAILED");
        TransferHelper.safeApprove(address(revertingToken), bob, TEST_AMOUNT);
    }

    function testNoReturnTransfer() public {
        // Should not revert even though no return value
        TransferHelper.safeTransfer(address(noReturnToken), bob, TEST_AMOUNT);
    }

    function testNoReturnTransferFrom() public {
        // Should not revert even though no return value
        TransferHelper.safeTransferFrom(address(noReturnToken), alice, bob, TEST_AMOUNT);
    }

    function testNoReturnApprove() public {
        // Should not revert even though no return value
        TransferHelper.safeApprove(address(noReturnToken), bob, TEST_AMOUNT);
    }

    function testFailTransferToZeroAddress() public {
        vm.expectRevert();
        TransferHelper.safeTransfer(address(compliantToken), address(0), TEST_AMOUNT);
    }

    function testFailTransferFromZeroAddress() public {
        vm.expectRevert();
        TransferHelper.safeTransferFrom(address(compliantToken), address(0), bob, TEST_AMOUNT);
    }

    function testFailApproveZeroAddress() public {
        vm.expectRevert();
        TransferHelper.safeApprove(address(compliantToken), address(0), TEST_AMOUNT);
    }

    function testFailTransferToNonContract() public {
        address nonContract = makeAddr("nonContract");
        vm.expectRevert();
        TransferHelper.safeTransfer(nonContract, bob, TEST_AMOUNT);
    }

    function testFailETHTransferToRevertingContract() public {
        // Deploy contract that reverts on receive
        RevertingReceiver receiver = new RevertingReceiver();

        vm.prank(alice);
        vm.expectRevert("TransferHelper::safeTransferETH: ETH transfer failed");
        TransferHelper.safeTransferETH(address(receiver), TEST_AMOUNT);
    }}

// Helper contract that reverts on receive
contract RevertingReceiver {
    receive() external payable {
        revert("RECEIVE_FAILED");
    }
}
