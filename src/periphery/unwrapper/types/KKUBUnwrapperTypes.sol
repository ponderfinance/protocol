// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    KKUB UNWRAPPER TYPES
//////////////////////////////////////////////////////////////*/

/// @title KKUBUnwrapperTypes
/// @author Original author: [Insert author name]
/// @notice Type definitions and constants for KKUB unwrapping system
/// @dev Central library for all constants, errors, and type definitions
///      Used across the KKUB unwrapping protocol
///      All constants and errors are immutable and cannot be modified
library KKUBUnwrapperTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Time required between successive withdrawals
    /// @dev Used to implement rate limiting on withdrawals
    /// @dev Set to 6 hours to prevent rapid successive withdrawals
    uint256 public constant WITHDRAWAL_DELAY = 6 hours;

    /// @notice Maximum amount that can be withdrawn in a single period
    /// @dev Caps individual withdrawal size for risk management
    /// @dev Value is denominated in wei (1e18)
    uint256 public constant MAX_WITHDRAWAL_AMOUNT = 1000 ether;

    /// @notice Minimum KYC verification level required for operations
    /// @dev Enforced by KKUB token contract
    /// @dev Level 1 represents basic KYC verification
    uint256 public constant REQUIRED_KYC_LEVEL = 1;

    /*//////////////////////////////////////////////////////////////
                        ERROR DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error for withdrawal timing violations
    /// @dev Thrown when attempting withdrawal before WITHDRAWAL_DELAY has elapsed
    /// @dev Check getNextWithdrawalTime() before attempting withdrawal
    error WithdrawalTooFrequent();

    /// @notice Error for insufficient contract balance
    /// @dev Thrown when contract lacks ETH to fulfill unwrap request
    /// @dev Check getLockedBalance() before operations
    error InsufficientBalance();

    /// @notice Error for failed withdrawal operations
    /// @dev Thrown when ETH transfer fails during unwrapping
    /// @dev May indicate recipient contract rejection
    error WithdrawFailed();

    /// @notice Error for blacklisted address interactions
    /// @dev Thrown when interacting with KKUB-blacklisted addresses
    /// @dev Check address status before interaction
    error BlacklistedAddress();

    /// @notice Error for zero-value operations
    /// @dev Thrown when amount parameter is 0
    /// @dev All operations must involve positive amounts
    error ZeroAmount();

    /// @notice Error for KYC verification failures
    /// @dev Thrown when address lacks required KYC level
    /// @dev Verify KYC status before attempting operations
    error InsufficientKYCLevel();

    /// @notice Error for zero address inputs
    /// @dev Thrown when zero address is provided for critical parameters
    /// @dev Validate addresses before submission
    error ZeroAddressNotAllowed();

    /// @notice Error for invalid owner address updates
    /// @dev Thrown during ownership transfer to invalid address
    /// @dev Ensure new owner meets all requirements
    error InvalidNewOwner();
}
