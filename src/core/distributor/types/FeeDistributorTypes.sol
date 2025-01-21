// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title FeeDistributorTypes
/// @notice Type definitions and constants for the fee distribution system
library FeeDistributorTypes {
    // Constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MINIMUM_AMOUNT = 1000;
    uint256 public constant DISTRIBUTION_COOLDOWN = 1 hours;
    uint256 public constant MAX_PAIRS_PER_DISTRIBUTION = 10;

    // Custom Errors
    error InvalidRatio();
    error RatioSumIncorrect();
    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();
    error InvalidAmount();
    error SwapFailed();
    error TransferFailed();
    error InsufficientOutputAmount();
    error PairNotFound();
    error InvalidPairCount();
    error InvalidPair();
    error DistributionTooFrequent();
    error InsufficientAccumulation();
    error InvalidPairAddress();
    error InvalidRecipient();
    error InvalidRecoveryAmount();
    error InvalidReserves();
}
