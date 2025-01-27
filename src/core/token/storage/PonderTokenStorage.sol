// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PonderTokenStorage
 * @notice Abstract contract containing all storage variables for the PonderToken system
 * @dev Storage variables are ordered by type and grouped by functionality to optimize gas usage
 */
abstract contract PonderTokenStorage {
    // ============ Role Storage ============

    /// @notice Address with minting privileges for farming rewards
    /// @dev Can mint new tokens until MINTING_END
    address internal _minter;

    /// @notice Address that can set the minter
    /// @dev Has administrative privileges
    address internal _owner;

    /// @notice Future owner in 2-step transfer
    /// @dev Part of secure ownership transfer pattern
    address internal _pendingOwner;

    /// @notice Team/Reserve address
    /// @dev Receives vested team allocation
    address internal _teamReserve;

    /// @notice Marketing address
    /// @dev Receives marketing allocation
    address internal _marketing;

    /// @notice 555 Launcher address
    /// @dev Has special privileges for certain operations
    address internal _launcher;

    // ============ Token Accounting Storage ============

    /// @notice Track total burned PONDER
    /// @dev Increases when tokens are burned
    uint256 internal _totalBurned;

    /// @notice Amount of team tokens claimed
    /// @dev Tracks claimed portion of TEAM_ALLOCATION
    uint256 internal _teamTokensClaimed;

    /// @notice Track unvested team allocation
    /// @dev Decreases as team tokens are claimed
    uint256 internal _reservedForTeam;

    // ============ Timestamp Storage ============

    /// @notice Team vesting end timestamp
    /// @dev Calculated from deployment time
    uint256 internal _teamVestingEnd;

    /// @notice Vesting start timestamp for team allocation
    /// @dev Can be delayed from deployment time if needed
    uint256 internal _teamVestingStart;

    /// @dev Gap for future storage variables
    uint256[50] private __gap;
}
