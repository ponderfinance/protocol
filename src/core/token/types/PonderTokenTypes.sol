// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title PonderTokenTypes
 * @notice Library containing all constants, custom errors, and events for the PonderToken system
 * @dev This library is used by PonderToken and related contracts
 */
library PonderTokenTypes {
    // ============ Constants ============

    /// @notice Total cap on token supply (1 billion PONDER)
    /// @dev Used to enforce maximum token supply limit
    uint256 public constant MAXIMUM_SUPPLY = 1_000_000_000e18;

    /// @notice Time after which minting is disabled forever (4 years in seconds)
    /// @dev Used to enforce end of minting period
    uint256 public constant MINTING_END = 4 * 365 days;

    /// @notice Total amount allocated for team vesting (25% of total supply)
    /// @dev Used to track and manage team token allocation
    uint256 public constant TEAM_ALLOCATION = 250_000_000e18;

    /// @notice Vesting duration for team allocation (1 year)
    /// @dev Used to calculate vesting schedule for team tokens
    uint256 public constant VESTING_DURATION = 365 days;

    // ============ Custom Errors ============

    /// @notice Thrown when a caller doesn't have required permissions
    error Forbidden();

    /// @notice Thrown when trying to mint after minting period has ended
    error MintingDisabled();

    /// @notice Thrown when an operation would exceed maximum supply
    error SupplyExceeded();

    /// @notice Thrown when a required address parameter is zero
    error ZeroAddress();

    /// @notice Thrown when trying to claim tokens before vesting starts
    error VestingNotStarted();

    /// @notice Thrown when no tokens are available for claiming
    error NoTokensAvailable();

    /// @notice Thrown when trying to perform operation before vesting ends
    error VestingNotEnded();

    /// @notice Thrown when non-launcher/owner tries to perform restricted operation
    error OnlyLauncherOrOwner();

    /// @notice Thrown when burn amount is below minimum threshold
    error BurnAmountTooSmall();

    /// @notice Thrown when burn amount exceeds maximum allowed
    error BurnAmountTooLarge();

    /// @notice Thrown when account has insufficient balance for operation
    error InsufficientBalance();

    // ============ Events ============

    /// @notice Emitted when the minter address is updated
    /// @param previousMinter Address of the previous minter
    /// @param newMinter Address of the new minter
    event MinterUpdated(address indexed previousMinter, address indexed newMinter);

    /// @notice Emitted when ownership transfer is initiated
    /// @param previousOwner Address of the current owner
    /// @param newOwner Address of the proposed new owner
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when ownership transfer is completed
    /// @param previousOwner Address of the previous owner
    /// @param newOwner Address of the new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when team tokens are claimed
    /// @param amount Amount of tokens claimed
    event TeamTokensClaimed(uint256 amount);

    /// @notice Emitted when launcher address is updated
    /// @param oldLauncher Address of the previous launcher
    /// @param newLauncher Address of the new launcher
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);

    /// @notice Emitted when tokens are burned
    /// @param burner Address that initiated the burn
    /// @param amount Amount of tokens burned
    event TokensBurned(address indexed burner, uint256 amount);
}
