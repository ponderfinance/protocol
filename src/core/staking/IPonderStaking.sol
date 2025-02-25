// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER STAKING INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderStaking
/// @author taayyohh
/// @notice Interface for Ponder protocol's staking functionality
/// @dev Defines core staking operations, events, and view functions
///      Implemented by the main staking contract
interface IPonderStaking {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when PONDER tokens are staked for xPONDER
    /// @param user Address of the staking user
    /// @param ponderAmount Amount of PONDER tokens staked
    /// @param xPonderAmount Amount of xPONDER shares minted
    event Staked(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);

    /// @notice Emitted when PONDER tokens are withdrawn for xPONDER
    /// @param user Address of the withdrawing user
    /// @param ponderAmount Amount of PONDER tokens withdrawn
    /// @param xPonderAmount Amount of xPONDER shares burned
    event Withdrawn(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);

    /// @notice Emitted when rewards are distributed via rebase
    /// @param totalSupply Total supply of xPONDER after rebase
    /// @param totalPonderBalance Total PONDER tokens in staking contract
    event RebasePerformed(uint256 totalSupply, uint256 totalPonderBalance);

    /// @notice Emitted when protocol fees are claimed
    /// @param user Address claiming the fees
    /// @param amount Amount of PONDER fees claimed
    event FeesClaimed(address indexed user, uint256 amount);

    /// @notice Emitted when fees are distributed to staking contract
    /// @param amount Total amount of fees distributed
    /// @param accumulatedFeesPerShare New accumulated fees per share
    event FeesDistributed(uint256 amount, uint256 accumulatedFeesPerShare);

    /// @notice Emitted when two-step ownership transfer begins
    /// @param currentOwner Address of the current owner
    /// @param pendingOwner Address of the proposed new owner
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);


    /*//////////////////////////////////////////////////////////////
                        STAKING OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stakes PONDER tokens to receive xPONDER shares
    /// @param amount Amount of PONDER tokens to stake
    /// @param recipient Address of the xPONDER recipient
    /// @return shares Amount of xPONDER shares minted
    function enter(uint256 amount, address recipient) external returns (uint256 shares);

    /// @notice Withdraws PONDER tokens by burning xPONDER shares
    /// @param shares Amount of xPONDER shares to burn
    /// @return amount Amount of PONDER tokens returned
    function leave(uint256 shares) external returns (uint256 amount);

    /// @notice Claims accumulated protocol fees without unstaking
    /// @dev Only claims fees, does not affect staked position
    /// @return amount Amount of PONDER fees claimed
    function claimFees() external returns (uint256 amount);

    /// @notice Distributes accumulated rewards to all stakers
    function rebase() external;

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets pending protocol fees for an address
    /// @param user Address to check pending fees for
    /// @return Amount of PONDER fees available to claim
    function getPendingFees(address user) external view returns (uint256);

    /// @notice Gets accumulated fees per share
    /// @return Current accumulated fees per share value
    function getAccumulatedFeesPerShare() external view returns (uint256);

    /// @notice Calculates PONDER tokens for given xPONDER amount
    /// @param shares Amount of xPONDER shares to calculate for
    /// @return Amount of PONDER tokens that would be received
    function getPonderAmount(uint256 shares) external view returns (uint256);

    /// @notice Calculates xPONDER shares for given PONDER amount
    /// @param amount Amount of PONDER tokens to calculate for
    /// @return Amount of xPONDER shares that would be received
    function getSharesAmount(uint256 amount) external view returns (uint256);

    /// @notice Returns minimum PONDER required for first stake
    /// @return Minimum amount of PONDER for first-time stakers
    function minimumFirstStake() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates two-step ownership transfer
    /// @param newOwner Address to transfer ownership to
    function transferOwnership(address newOwner) external;

    /// @notice Completes two-step ownership transfer
    function acceptOwnership() external;

    /*//////////////////////////////////////////////////////////////
                    ERROR DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when an invalid amount is provided
    error InvalidAmount();

    /// @notice Thrown when attempting to rebase before delay period
    error RebaseTooFrequent();

    /// @notice Thrown when caller isn't the pending owner
    error NotPendingOwner();

    /// @notice Thrown when share ratio exceeds maximum
    error ExcessiveShareRatio();

    /// @notice Thrown when balance check fails
    error InvalidBalance();

    /// @notice Thrown when first stake is below minimum
    error InsufficientFirstStake();

    /// @notice Thrown when share ratio is out of bounds
    error InvalidShareRatio();

    /// @notice Thrown when share amount is below required minimum
    error MinimumSharesRequired();

    /// @notice Thrown when invalid share amount is provided
    error InvalidSharesAmount();

    /// @notice Thrown when token transfer fails
    error TransferFailed();

    /// @notice Error thrown when team attempts to unstake before lock expires
    error TeamStakingLocked();

    /// @notice Error thrown when ponder token already initialized
    error AlreadyInitialized();

    /// @notice Error when fee claim amount is below minimum
    error InsufficientFeeAmount();

    /// @notice Error when no fees are available to claim
    error NoFeesToClaim();

    /// @notice Error when fee transfer fails
    error FeeTransferFailed();

    /// @notice Error when fee accounting doesn't match
    error FeeAccountingError();

    /// @notice Error when fee claim exceeds available balance
    error ExcessiveFeeAmount();

    /// @notice Error when fees cannot be distributed
    error FeeDistributionFailed();

    /// @notice Error when fee calculation precision is lost
    error FeePrecisionLoss();
}
