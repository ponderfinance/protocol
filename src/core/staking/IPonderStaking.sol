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
    /// @dev Tracks both input and output amounts for stake operations
    /// @param user Address of the staking user
    /// @param ponderAmount Amount of PONDER tokens staked
    /// @param xPonderAmount Amount of xPONDER shares minted
    event Staked(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);

    /// @notice Emitted when PONDER tokens are withdrawn for xPONDER
    /// @dev Tracks both input and output amounts for unstake operations
    /// @param user Address of the withdrawing user
    /// @param ponderAmount Amount of PONDER tokens withdrawn
    /// @param xPonderAmount Amount of xPONDER shares burned
    event Withdrawn(address indexed user, uint256 ponderAmount, uint256 xPonderAmount);

    /// @notice Emitted when rewards are distributed via rebase
    /// @dev Used to track system-wide staking metrics
    /// @param totalSupply Total supply of xPONDER after rebase
    /// @param totalPonderBalance Total PONDER tokens in staking contract
    event RebasePerformed(uint256 totalSupply, uint256 totalPonderBalance);

    /// @notice Emitted when two-step ownership transfer begins
    /// @dev First step of ownership transfer process
    /// @param currentOwner Address of the current owner
    /// @param pendingOwner Address of the proposed new owner
    event OwnershipTransferInitiated(address indexed currentOwner, address indexed pendingOwner);

    /// @notice Emitted when ownership transfer is completed
    /// @dev Final step of ownership transfer process
    /// @param previousOwner Address of the previous owner
    /// @param newOwner Address of the new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                        STAKING OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Stakes PONDER tokens to receive xPONDER shares
    /// @dev Transfers PONDER from user and mints xPONDER
    /// @param amount Amount of PONDER tokens to stake
    /// @param recipient Address of the xPONDER recipient
    /// @return shares Amount of xPONDER shares minted
    function enter(uint256 amount, address recipient) external returns (uint256 shares);

    /// @notice Withdraws PONDER tokens by burning xPONDER shares
    /// @dev Burns xPONDER and returns corresponding PONDER
    /// @param shares Amount of xPONDER shares to burn
    /// @return amount Amount of PONDER tokens returned
    function leave(uint256 shares) external returns (uint256 amount);

    /// @notice Distributes accumulated rewards to all stakers
    /// @dev Updates share price based on accumulated PONDER
    function rebase() external;

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates PONDER tokens for given xPONDER amount
    /// @dev Uses current share price for calculation
    /// @param shares Amount of xPONDER shares to calculate for
    /// @return Amount of PONDER tokens that would be received
    function getPonderAmount(uint256 shares) external view returns (uint256);

    /// @notice Calculates xPONDER shares for given PONDER amount
    /// @dev Uses current share price for calculation
    /// @param amount Amount of PONDER tokens to calculate for
    /// @return Amount of xPONDER shares that would be received
    function getSharesAmount(uint256 amount) external view returns (uint256);

    /// @notice Returns minimum PONDER required for first stake
    /// @dev Used to prevent dust accounts
    /// @return Minimum amount of PONDER for first-time stakers
    function minimumFirstStake() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates two-step ownership transfer
    /// @dev Only current owner can call
    /// @param newOwner Address to transfer ownership to
    function transferOwnership(address newOwner) external;

    /// @notice Completes two-step ownership transfer
    /// @dev Only pending owner can call
    function acceptOwnership() external;

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

    /// @notice Error thrown when team attempts to unstake before lock expires
    /// @dev Prevents early withdrawal of team allocation
    error TeamStakingLocked();

    /// @notice Error thrown when ponder token already initialized
    /// @dev Prevents changing address of ponder token
    error AlreadyInitialized();
}
