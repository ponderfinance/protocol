// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { PonderMasterChefTypes } from "../types/PonderMasterChefTypes.sol";

/**
 * @title PonderMasterChefStorage
 * @notice Storage layout for the Ponder MasterChef contract
 * @dev Contains all state variables used in the MasterChef implementation
 */
abstract contract PonderMasterChefStorage {
    // Mutable state variables
    /// @notice Rate of PONDER token emissions per second
    uint256 internal _ponderPerSecond;

    /// @notice Sum of all allocation points across pools
    uint256 internal _totalAllocPoint;

    /// @notice Address that receives deposit fees
    address internal _teamReserve;

    /// @notice Address with admin privileges
    address internal _owner;

    /// @notice Address staged for ownership transfer
    address internal _pendingOwner;

    /// @notice Timestamp when farming begins
    uint256 internal _startTime;

    /// @notice Whether farming has been initialized
    bool internal _farmingStarted;

    // Complex data structures
    /// @notice Array of all pool information
    PonderMasterChefTypes.PoolInfo[] internal _poolInfo;

    /// @notice Mapping of user info by pool ID and address
    mapping(uint256 => mapping(address => PonderMasterChefTypes.UserInfo)) internal _userInfo;
}
