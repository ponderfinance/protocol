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
    /// @dev Hard cap of 1 billion PONDER tokens
    /// @dev Value includes 18 decimal places
    uint256 public constant MAXIMUM_SUPPLY = 1_000_000_000e18;

    /// @notice Duration of token minting period
    /// @dev Minting disabled after 4 years from deployment
    /// @dev Used to enforce controlled supply expansion
    uint256 public constant MINTING_END = 4 * 365 days;

    /// @notice Team token allocation amount
    /// @dev 25% of total supply (250M PONDER)
    /// @dev Subject to linear vesting schedule
    uint256 public constant TEAM_ALLOCATION = 250_000_000e18;

    /// @notice Team tokens vesting duration
    /// @dev Linear vesting over 1 year period
    /// @dev Used to calculate claimable amounts
    uint256 public constant VESTING_DURATION = 365 days;

    /*//////////////////////////////////////////////////////////////
                        ERROR DEFINITIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Unauthorized access attempt
    /// @dev Thrown when caller lacks required role
    error Forbidden();

    /// @notice Minting period has concluded
    /// @dev Thrown after MINTING_END timestamp
    error MintingDisabled();

    /// @notice Total supply cap reached
    /// @dev Thrown when mint would exceed MAXIMUM_SUPPLY
    error SupplyExceeded();

    /// @notice Invalid zero address provided
    /// @dev Thrown when address parameter is zero
    error ZeroAddress();

    /// @notice Vesting period not yet started
    /// @dev Thrown when claiming before vesting begins
    error VestingNotStarted();

    /// @notice No tokens available to claim
    /// @dev Thrown when vested amount is zero
    error NoTokensAvailable();

    /// @notice Vesting period still active
    /// @dev Thrown for operations requiring complete vesting
    error VestingNotEnded();

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

    /// @notice Records team token claim
    /// @dev Emitted when team claims vested tokens
    /// @param amount Number of tokens claimed
    event TeamTokensClaimed(uint256 amount);

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
