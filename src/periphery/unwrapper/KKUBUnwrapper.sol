// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IWETH } from "./IWETH.sol";

interface IKKUB is IWETH {
    function blacklist(address addr) external view returns (bool);
    function kycsLevel(address addr) external view returns (uint256);
}

contract KKUBUnwrapper is ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice The KKUB token contract
    address public immutable KKUB;

    /// @notice Last successful withdrawal timestamp
    uint256 private lastWithdrawalTime;

    /// @notice Amount of ETH currently in active unwrapping operations
    uint256 private _lockedBalance;

    /// @notice Withdrawal cooldown period
    uint256 public constant WITHDRAWAL_DELAY = 6 hours;

    /// @notice Maximum withdrawal amount per period
    uint256 public constant MAX_WITHDRAWAL_AMOUNT = 1000 ether;

    /// @notice Required KYC level for KKUB contract
    uint256 public constant REQUIRED_KYC_LEVEL = 1;

    error WithdrawalTooFrequent();
    error InsufficientBalance();
    error WithdrawFailed();
    error BlacklistedAddress();
    error ZeroAmount();
    error InsufficientKYCLevel();
    error ZeroAddressNotAllowed();
    error InvalidNewOwner();

    event UnwrappedKKUB(address indexed recipient, uint256 amount);
    event EmergencyWithdraw(uint256 amount, uint256 timestamp);
    event WithdrawalLimitReset();

    constructor(address _kkub) Ownable(msg.sender) {
        if (_kkub == address(0)) revert ZeroAddressNotAllowed();
        KKUB = _kkub;
    }

    function transferOwnership(address newOwner) public virtual override {
        if (newOwner == address(0)) revert InvalidNewOwner();
        super.transferOwnership(newOwner);
    }

    function getLockedBalance() external view returns (uint256) {
        return _lockedBalance;
    }

    function unwrapKKUB(uint256 amount, address recipient)
    external
    nonReentrant
    whenNotPaused
    returns (bool)
    {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert ZeroAmount();

        // Check KYC level and blacklist before proceeding
        if (IKKUB(KKUB).kycsLevel(address(this)) <= REQUIRED_KYC_LEVEL) {
            revert InsufficientKYCLevel();
        }
        if (IKKUB(KKUB).blacklist(recipient)) {
            revert BlacklistedAddress();
        }

        // Lock the balance
        _lockedBalance += amount;

        // Store initial balance
        uint256 initialBalance = address(this).balance;

        // Transfer KKUB tokens to this contract
        IERC20(KKUB).safeTransferFrom(msg.sender, address(this), amount);

        // Attempt to withdraw ETH
        IWETH(KKUB).withdraw(amount);

        // Verify received amount
        uint256 ethReceived = address(this).balance - initialBalance;
        if (ethReceived < amount) {
            _lockedBalance -= amount;
            revert WithdrawFailed();
        }

        // Send ETH to recipient
        (bool sent,) = payable(recipient).call{value: amount}("");
        if (!sent) {
            _lockedBalance -= amount;
            revert WithdrawFailed();
        }

        // If successful, update state
        _lockedBalance -= amount;

        emit UnwrappedKKUB(recipient, amount);
        return true;
    }

    function emergencyWithdraw()
    external
    onlyOwner
    nonReentrant
    {
        if (block.timestamp < lastWithdrawalTime + WITHDRAWAL_DELAY) {
            revert WithdrawalTooFrequent();
        }

        uint256 withdrawableAmount = address(this).balance - _lockedBalance;
        if (withdrawableAmount == 0) revert InsufficientBalance();

        if (withdrawableAmount > MAX_WITHDRAWAL_AMOUNT) {
            withdrawableAmount = MAX_WITHDRAWAL_AMOUNT;
        }

        // Update state before transfer
        lastWithdrawalTime = block.timestamp;
        if (!paused()) {
            _pause();
        }

        // Transfer withdrawable amount
        payable(owner()).sendValue(withdrawableAmount);

        emit EmergencyWithdraw(withdrawableAmount, block.timestamp);
    }

    function resetWithdrawalLimit() external {
        if (block.timestamp >= lastWithdrawalTime + WITHDRAWAL_DELAY) {
            lastWithdrawalTime = 0;
            emit WithdrawalLimitReset();
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    receive() external payable {}
}
