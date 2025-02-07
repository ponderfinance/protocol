// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER TOKEN STORAGE
//////////////////////////////////////////////////////////////*/

/// @title PonderTokenStorage
/// @author taayyohh
/// @notice Storage layout for Ponder protocol's token system
/// @dev Abstract contract defining state variables for token implementation
///      Storage slots are carefully ordered to optimize gas costs
///      Includes storage gap for future upgrades
abstract contract PonderTokenStorage {
    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    /// @notice Address authorized to mint farming rewards
    /// @dev Has time-limited minting privileges
    /// @dev Can only mint until MINTING_END timestamp
    address internal _minter;

    /// @notice Address with administrative privileges
    /// @dev Can update protocol parameters and roles
    /// @dev Transferable through two-step process
    address internal _owner;

    /// @notice Address proposed in ownership transfer
    /// @dev Part of two-step ownership transfer pattern
    /// @dev Must accept ownership to become effective owner
    address internal _pendingOwner;

    /*//////////////////////////////////////////////////////////////
                        ALLOCATION ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address for team and reserve allocations
    /// @dev Receives vested team tokens over time
    /// @dev Subject to vesting schedule defined by _teamVestingStart and _teamVestingEnd
    address internal _teamReserve;

    /// @notice Address for marketing operations
    /// @dev Receives allocation for marketing activities
    /// @dev Not subject to vesting restrictions
    address internal _marketing;

    /// @notice Special purpose launcher address
    /// @dev Has privileged access to specific operations
    /// @dev Used for initial token distribution
    address internal _launcher;

    /*//////////////////////////////////////////////////////////////
                        TOKEN ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Cumulative amount of PONDER tokens burned
    /// @dev Increases with each burn operation
    /// @dev Used for supply tracking and analytics
    uint256 internal _totalBurned;

    /// @notice Amount of team allocation tokens claimed
    /// @dev Tracks vested tokens claimed by team
    /// @dev Cannot exceed TEAM_ALLOCATION constant
    uint256 internal _teamTokensClaimed;

    /// @notice Remaining unvested team allocation
    /// @dev Decreases as team claims vested tokens
    /// @dev Initially set to total team allocation
    uint256 internal _reservedForTeam;

    /*//////////////////////////////////////////////////////////////
                        VESTING PARAMETERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Timestamp when team token vesting completes
    /// @dev All team tokens become available after this time
    /// @dev Calculated relative to deployment or vesting start
    uint256 internal _teamVestingEnd;

    /// @notice Timestamp when team token vesting begins
    /// @dev No team tokens can be claimed before this time
    /// @dev Can be set after deployment for flexible start
    uint256 internal _teamVestingStart;

    /*//////////////////////////////////////////////////////////////
                        UPGRADE GAP
    //////////////////////////////////////////////////////////////*/

    /// @notice Gap for future storage variables
    /// @dev Reserved storage slots for future versions
    /// @dev Prevents storage collision in upgrades
    uint256[50] private __gap;
}
