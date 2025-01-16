// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWETH.sol";

interface IKKUB is IWETH {
    function blacklist(address addr) external view returns (bool);
}

contract KKUBUnwrapper {
    /// @notice The KKUB token contract
    address public immutable KKUB;
    /// @notice The contract owner
    address public owner;
    /// @notice The pending new owner
    address public pendingOwner;

    error NotOwner();
    error TransferFailed();
    error NotPendingOwner();
    error BlacklistedAddress();
    error ZeroAddress();

    event UnwrappedKKUB(address indexed recipient, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event EmergencyWithdraw(uint256 amount);
    event EmergencyWithdrawTokens(address indexed token, uint256 amount);

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(address _KKUB) {
        if (_KKUB == address(0)) revert ZeroAddress();
        KKUB = _KKUB;
        owner = msg.sender;
    }

    function unwrapKKUB(uint256 amount, address recipient) external returns (bool) {
        // Check blacklist for recipient
        if (IKKUB(KKUB).blacklist(recipient)) {
            revert BlacklistedAddress();
        }

        // Transfer KKUB from router to this contract
        bool success = IERC20(KKUB).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        // Withdraw KKUB to native tokens (KKUB will check KYC internally)
        IWETH(KKUB).withdraw(amount);

        // Forward the native tokens to recipient
        (success, ) = recipient.call{value: amount}("");
        if (!success) revert TransferFailed();

        emit UnwrappedKKUB(recipient, amount);
        return true;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        emit OwnershipTransferred(owner, msg.sender);
        owner = msg.sender;
        pendingOwner = address(0);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool success, ) = owner.call{value: amount}("");
        if (!success) revert TransferFailed();
        emit EmergencyWithdraw(amount);
    }

    function emergencyWithdrawTokens(address token) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        bool success = IERC20(token).transfer(owner, balance);
        if (!success) revert TransferFailed();
        emit EmergencyWithdrawTokens(token, balance);
    }

    receive() external payable {}
}
