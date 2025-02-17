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

    /// @notice Duration of team staking lock
    /// @dev Team tokens cannot be unstaked before this period
    uint256 public constant TEAM_LOCK_DURATION = 730 days;

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
                            FEE CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Precision multiplier for fee calculations
    /// @dev Used to handle division with precision
    /// @dev Value is 1e12 to allow for very small fee amounts
    uint256 public constant FEE_PRECISION = 1e12;

    /// @notice Minimum claimable fee amount
    /// @dev Prevents dust fee claims
    /// @dev Value is in PONDER tokens with 18 decimals (0.01 PONDER)
    uint256 public constant MINIMUM_FEE_CLAIM = 1e16;

    /// @notice Maximum time between fee claims
    /// @dev Encourages regular claiming to reduce contract balance
    /// @dev Set to 30 days to ensure fees don't accumulate too long
    uint256 public constant MAX_FEE_CLAIM_DELAY = 30 days;
}
