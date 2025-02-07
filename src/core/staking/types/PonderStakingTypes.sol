// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER STAKING TYPES
//////////////////////////////////////////////////////////////*/

/// @title PonderStakingTypes
/// @author taayyohh
/// @notice Type definitions and constants for Ponder protocol's staking system
/// @dev Library containing all custom errors and configuration constants
///      Used by the main staking implementation
library PonderStakingTypes {
    /*//////////////////////////////////////////////////////////////
                        STAKING CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum time between reward distributions
    /// @dev Prevents excessive rebasing to maintain system stability
    uint256 public constant REBASE_DELAY = 1 days;

    /// @notice Minimum PONDER required for first-time stakers
    /// @dev Prevents dust accounts and maintains economic security
    /// @dev Value is in PONDER tokens with 18 decimals (1000 PONDER)
    uint256 public constant MINIMUM_FIRST_STAKE = 1000e18;

    /// @notice Minimum allowed ratio of shares to tokens
    /// @dev Prevents share inflation attacks
    /// @dev Represents 0.0001 shares per token
    uint256 public constant MIN_SHARE_RATIO = 1e14;

    /// @notice Maximum allowed ratio of shares to tokens
    /// @dev Prevents share deflation attacks
    /// @dev Represents 100 shares per token
    uint256 public constant MAX_SHARE_RATIO = 100e18;

    /// @notice Minimum amount for withdrawal operations
    /// @dev Prevents dust withdrawals
    /// @dev Value is in PONDER tokens with 18 decimals (0.01 PONDER)
    uint256 public constant MINIMUM_WITHDRAW = 1e16;

    /*//////////////////////////////////////////////////////////////
                        ERROR DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an invalid amount is provided
    /// @dev Used for general amount validation
    error InvalidAmount();

    /// @notice Thrown when attempting to rebase before delay period
    /// @dev Ensures REBASE_DELAY is respected
    error RebaseTooFrequent();

    /// @notice Thrown when non-owner attempts privileged operation
    /// @dev Access control for owner-only functions
    error NotOwner();

    /// @notice Thrown when caller isn't the pending owner
    /// @dev Used in two-step ownership transfer
    error NotPendingOwner();

    /// @notice Thrown when zero address is provided
    /// @dev Prevents operations with invalid addresses
    error ZeroAddress();

    /// @notice Thrown when share ratio exceeds maximum
    /// @dev Protects against share price manipulation
    error ExcessiveShareRatio();

    /// @notice Thrown when balance check fails
    /// @dev Used for various balance validations
    error InvalidBalance();

    /// @notice Thrown when first stake is below minimum
    /// @dev Enforces MINIMUM_FIRST_STAKE constant
    error InsufficientFirstStake();

    /// @notice Thrown when share ratio is out of bounds
    /// @dev Ensures ratio is between MIN_SHARE_RATIO and MAX_SHARE_RATIO
    error InvalidShareRatio();

    /// @notice Thrown when share amount is below required minimum
    /// @dev Prevents dust share amounts
    error MinimumSharesRequired();

    /// @notice Thrown when invalid share amount is provided
    /// @dev Used for share amount validation
    error InvalidSharesAmount();

    /// @notice Thrown when token transfer fails
    /// @dev Handles failed ERC20 transfer operations
    error TransferFailed();
}
