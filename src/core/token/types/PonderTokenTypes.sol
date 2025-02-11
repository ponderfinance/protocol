// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                   PONDER TOKEN TYPES
//////////////////////////////////////////////////////////////*/

/// @title PonderTokenTypes
/// @author taayyohh
/// @notice Type definitions and constants for Ponder token system
/// @dev Library containing protocol configuration, errors and events
///      Used by PonderToken and related contracts
library PonderTokenTypes {
    /*//////////////////////////////////////////////////////////////
                        TOKEN CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum total token supply cap
    /// @dev Hard cap of 1 billion KOI tokens
    /// @dev Value includes 18 decimal places
    uint256 public constant MAXIMUM_SUPPLY = 1_000_000_000e18;

    /// @notice Initial liquidity allocation
    /// @dev 40% of total supply for protocol liquidity
    /// @dev Used across primary trading pairs
    uint256 public constant INITIAL_LIQUIDITY = 400_000_000e18;

    /// @notice Community rewards allocation
    /// @dev 40% of total supply for farming incentives
    /// @dev Distributed through MasterChef
    uint256 public constant COMMUNITY_REWARDS = 400_000_000e18;

    /// @notice Team token allocation
    /// @dev 20% of total supply, force-staked at launch
    /// @dev Subject to cliff vesting
    uint256 public constant TEAM_ALLOCATION = 200_000_000e18;

    /// @notice Team vesting cliff duration
    /// @dev Tokens remain staked for 2 years
    /// @dev No linear vesting, full unlock after cliff
    uint256 public constant TEAM_CLIFF = 930 days;

    /*//////////////////////////////////////////////////////////////
                        ERROR DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unauthorized access attempt
    /// @dev Thrown when caller lacks required role
    error Forbidden();

    /// @notice Total supply cap reached
    /// @dev Thrown when mint would exceed MAXIMUM_SUPPLY
    error SupplyExceeded();

    /// @notice Invalid zero address provided
    /// @dev Thrown when address parameter is zero
    error ZeroAddress();

    /// @notice Restricted launcher/owner operation
    /// @dev Thrown when unauthorized caller
    error OnlyLauncherOrOwner();

    /// @notice Burn amount below minimum
    /// @dev Thrown for dust burn attempts
    error BurnAmountTooSmall();

    /// @notice Burn amount above maximum
    /// @dev Thrown to prevent excessive burns
    error BurnAmountTooLarge();

    /// @notice Insufficient token balance
    /// @dev Thrown when balance < required amount
    error InsufficientBalance();

    /// @notice Thrown when trying to initialize an already initialized value
    /// @dev Used to prevent re-initialization of critical contract parameters
    /// @dev Particularly used for one-time settable addresses like staking
    error AlreadyInitialized();


    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Records minter role transfer
    /// @dev Emitted when owner updates minter address
    /// @param previousMinter Address of outgoing minter
    /// @param newMinter Address of incoming minter
    event MinterUpdated(address indexed previousMinter, address indexed newMinter);

    /// @notice Records initiation of ownership transfer
    /// @dev First step of two-step ownership transfer
    /// @param previousOwner Current owner initiating transfer
    /// @param newOwner Proposed new owner address
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @notice Records completion of ownership transfer
    /// @dev Final step of ownership transfer process
    /// @param previousOwner Address of previous owner
    /// @param newOwner Address of new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Records launcher address update
    /// @dev Emitted when owner updates launcher
    /// @param oldLauncher Previous launcher address
    /// @param newLauncher New launcher address
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);

    /// @notice Records token burn
    /// @dev Emitted when tokens are permanently removed
    /// @param burner Address that initiated burn
    /// @param amount Number of tokens burned
    event TokensBurned(address indexed burner, uint256 amount);
}
