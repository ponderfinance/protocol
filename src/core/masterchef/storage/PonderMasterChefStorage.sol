// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PonderMasterChefTypes } from "../types/PonderMasterChefTypes.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER MASTERCHEF STORAGE
//////////////////////////////////////////////////////////////*/

/// @title PonderMasterChefStorage
/// @author taayyohh
/// @notice Storage layout for Ponder protocol's farming rewards system
/// @dev Abstract contract defining state variables for MasterChef implementation
abstract contract PonderMasterChefStorage {
    /*//////////////////////////////////////////////////////////////
                        REWARDS CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Current PONDER token emission rate
    /// @dev Number of PONDER tokens distributed per second across all pools
    uint256 internal _ponderPerSecond;

    /// @notice Total allocation points for reward distribution
    /// @dev Sum of all pool weights, used to calculate reward share per pool
    uint256 internal _totalAllocPoint;

    /*//////////////////////////////////////////////////////////////
                        PROTOCOL ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Protocol team treasury address
    /// @dev Receives deposit fees from farming operations
    address internal _teamReserve;

    /// @notice Contract administrator address
    /// @dev Has permission to modify protocol parameters
    address internal _owner;

    /// @notice Staged address for ownership transfer
    /// @dev Part of two-step ownership transfer pattern
    address internal _pendingOwner;

    /*//////////////////////////////////////////////////////////////
                            TIMING STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Farming start timestamp
    /// @dev Unix timestamp when rewards begin accruing
    uint256 internal _startTime;

    /// @notice Farming initialization status
    /// @dev Tracks whether farming has been activated
    bool internal _farmingStarted;

    /*//////////////////////////////////////////////////////////////
                        FARMING STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pool configuration data
    /// @dev Array containing settings and state for all farming pools
    PonderMasterChefTypes.PoolInfo[] internal _poolInfo;

    /// @notice User staking positions
    /// @dev Maps pool ID and user address to staking information
    /// @dev poolId => user address => user staking info
    mapping(uint256 => mapping(address => PonderMasterChefTypes.UserInfo)) internal _userInfo;
}
