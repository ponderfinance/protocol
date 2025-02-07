// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    FEE DISTRIBUTOR TYPES
//////////////////////////////////////////////////////////////*/

/// @title FeeDistributorTypes
/// @author taayyohh
/// @notice Type definitions and constants for the fee distribution system
/// @dev Library containing all custom errors and constants used in fee distribution
library FeeDistributorTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The denominator used for ratio calculations (100%)
    /// @dev Used as the denominator for calculating fee splits (e.g., 8000/10000 = 80%)
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Minimum amount of tokens required for operations
    /// @dev Used to prevent dust transactions and ensure economic viability
    uint256 public constant MINIMUM_AMOUNT = 1000;

    /// @notice Minimum time required between distributions
    /// @dev Rate limiting mechanism to prevent excessive distributions
    uint256 public constant DISTRIBUTION_COOLDOWN = 1 hours;

    /// @notice Maximum number of pairs that can be processed in a single distribution
    /// @dev Prevents excessive gas consumption in single transactions
    uint256 public constant MAX_PAIRS_PER_DISTRIBUTION = 10;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Error thrown when an invalid ratio is provided for fee distribution
    /// @dev Thrown when ratio is out of bounds or invalid
    error InvalidRatio();

    /// @notice Error thrown when distribution ratios don't sum to BASIS_POINTS
    /// @dev Ensures fee distribution percentages total 100%
    error RatioSumIncorrect();

    /// @notice Error thrown when non-owner tries to access owner-only function
    /// @dev Access control error for administrative functions
    error NotOwner();

    /// @notice Error thrown when non-pending owner tries to accept ownership
    /// @dev Part of the two-step ownership transfer pattern
    error NotPendingOwner();

    /// @notice Error thrown when a zero address is provided where not allowed
    /// @dev Prevents setting critical addresses to zero
    error ZeroAddress();

    /// @notice Error thrown when amount is below MINIMUM_AMOUNT
    /// @dev Prevents dust transactions
    error InvalidAmount();

    /// @notice Error thrown when a token swap operation fails
    /// @dev Can occur due to slippage, insufficient liquidity, etc.
    error SwapFailed();

    /// @notice Error thrown when a token transfer fails
    /// @dev Can occur with non-compliant tokens or insufficient balance
    error TransferFailed();

    /// @notice Error thrown when swap output amount is below minimum
    /// @dev Protects against excessive slippage
    error InsufficientOutputAmount();

    /// @notice Error thrown when a requested pair doesn't exist
    /// @dev Occurs when trying to interact with non-existent trading pairs
    error PairNotFound();

    /// @notice Error thrown when pair count is 0 or exceeds maximum
    /// @dev Enforces batch size limits for gas efficiency
    error InvalidPairCount();

    /// @notice Error thrown when an invalid pair is provided
    /// @dev Includes zero address pairs or already processed pairs
    error InvalidPair();

    /// @notice Error thrown when distribution attempted too soon
    /// @dev Enforces DISTRIBUTION_COOLDOWN between distributions
    error DistributionTooFrequent();

    /// @notice Error thrown when accumulated fees are insufficient
    /// @dev Ensures economic viability of distribution
    error InsufficientAccumulation();

    /// @notice Error thrown when an invalid pair address is provided
    /// @dev Basic validation for pair addresses
    error InvalidPairAddress();

    /// @notice Error thrown when an invalid recipient is provided
    /// @dev Prevents sending tokens to invalid addresses
    error InvalidRecipient();

    /// @notice Error thrown when recovery amount is invalid
    /// @dev Used in emergency token recovery function
    error InvalidRecoveryAmount();

    /// @notice Error thrown when pair reserves are invalid
    /// @dev Prevents operations with pairs having zero reserves
    error InvalidReserves();

    /// @notice Error thrown when token approval fails
    /// @dev Can occur with non-compliant tokens
    error ApprovalFailed();

    /// @notice Error thrown when amount exceeds uint96
    /// @dev Prevents overflow in certain operations
    error AmountTooLarge();
}
