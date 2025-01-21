// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title KKUBUnwrapper Types Library
/// @notice Library containing types, constants, and errors for the KKUBUnwrapper
/// @dev Consolidates all type definitions used in the KKUBUnwrapper system
library KKUBUnwrapperTypes {
    /// @notice Withdrawal cooldown period
    uint256 public constant WITHDRAWAL_DELAY = 6 hours;

    /// @notice Maximum withdrawal amount per period
    uint256 public constant MAX_WITHDRAWAL_AMOUNT = 1000 ether;

    /// @notice Required KYC level for KKUB contract
    uint256 public constant REQUIRED_KYC_LEVEL = 1;

    // Custom Errors

    /// @notice Thrown when withdrawal attempted too soon after previous withdrawal
    error WithdrawalTooFrequent();

    /// @notice Thrown when contract has insufficient balance for operation
    error InsufficientBalance();

    /// @notice Thrown when withdrawal operation fails
    error WithdrawFailed();

    /// @notice Thrown when interacting with blacklisted address
    error BlacklistedAddress();

    /// @notice Thrown when amount specified is zero
    error ZeroAmount();

    /// @notice Thrown when KYC level is insufficient
    error InsufficientKYCLevel();

    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddressNotAllowed();

    /// @notice Thrown when invalid owner address is provided
    error InvalidNewOwner();
}
