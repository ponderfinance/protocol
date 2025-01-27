// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PonderStakingTypes
 * @notice Library containing types and constants for PonderStaking
 */
library PonderStakingTypes {
    // Constants
    uint256 public constant REBASE_DELAY = 1 days;
    uint256 public constant MINIMUM_FIRST_STAKE = 1000e18;
    uint256 public constant MIN_SHARE_RATIO = 1e14;     // 0.0001 shares per token minimum
    uint256 public constant MAX_SHARE_RATIO = 100e18;   // 100 shares per token maximum
    uint256 public constant MINIMUM_WITHDRAW = 1e16;    // 0.01 PONDER minimum withdrawal

    // Custom Errors
    error InvalidAmount();
    error RebaseTooFrequent();
    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();
    error ExcessiveShareRatio();
    error InvalidBalance();
    error InsufficientFirstStake();
    error InvalidShareRatio();
    error MinimumSharesRequired();
    error InvalidSharesAmount();
    error TransferFailed();
}
