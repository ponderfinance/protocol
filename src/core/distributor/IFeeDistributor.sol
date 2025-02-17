// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    FEE DISTRIBUTOR INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IFeeDistributor
/// @author taayyohh
/// @notice Interface for the protocol's fee distribution system
/// @dev Defines core events and functions for collecting and distributing protocol fees
interface IFeeDistributor {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when protocol fees are distributed to staking
    /// @param totalAmount Total amount of PONDER tokens distributed
    event FeesDistributed(uint256 totalAmount);

    /// @notice Emitted when tokens are recovered in emergency situations
    /// @dev Only callable by contract owner
    /// @param token Address of the recovered token
    /// @param to Destination address for recovered tokens
    /// @param amount Amount of tokens recovered
    event EmergencyTokenRecovered(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /// @notice Emitted when fees are collected from trading pairs
    /// @dev Triggered after successful fee collection
    /// @param token Address of the collected token
    /// @param amount Amount of tokens collected
    event FeesCollected(
        address indexed token,
        uint256 amount
    );

    /// @notice Emitted when collected fees are converted to PONDER tokens
    /// @dev Provides input and output amounts for transparency
    /// @param token Address of the input token
    /// @param tokenAmount Amount of input tokens converted
    /// @param ponderAmount Amount of PONDER tokens received
    event FeesConverted(
        address indexed token,
        uint256 tokenAmount,
        uint256 ponderAmount
    );


    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Triggers distribution of accumulated protocol fees
    /// @dev Splits PONDER tokens between staking rewards and team wallet
    function distribute() external;

    /// @notice Converts accumulated fees from other tokens to PONDER
    /// @dev Includes slippage protection and minimum output verification
    /// @param token Address of the token to convert to PONDER
    function convertFees(address token) external;


    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns minimum amount required for operations
    /// @dev Used to prevent dust transactions
    /// @return Minimum token amount threshold
    function minimumAmount() external pure returns (uint256);

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

    /// @notice Error thrown when pair reserves are in invalid state
    /// @dev Prevents operations when reserves don't match balances
    error InvalidReserveState();

    /// @notice Error thrown when fee collection fails
    /// @dev Indicates atomic fee collection operation failed
    error FeeCollectionFailed();

    /// @notice Error thrown when sync validation fails
    /// @dev Prevents operations with invalid reserve states
    error SyncValidationFailed();

    /// @notice Error thrown when fee state is invalid
    /// @dev Indicates inconsistency in fee accounting
    error InvalidFeeState();

    /// @notice Error thrown when collection state is invalid
    /// @dev Prevents fee collection with invalid state
    error InvalidCollectionState();

    /// @dev Not enough liquidity
    error InsufficientLiquidity();
}
