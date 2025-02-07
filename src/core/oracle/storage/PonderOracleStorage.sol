// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PonderOracleTypes } from "../types/PonderOracleTypes.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER ORACLE STORAGE
//////////////////////////////////////////////////////////////*/

/// @title PonderOracleStorage
/// @author taayyohh
/// @notice Storage layout for Ponder protocol's price oracle system
/// @dev Abstract contract defining the state variables for the Oracle implementation
///      Must be inherited by the main implementation contract
abstract contract PonderOracleStorage {
    /*//////////////////////////////////////////////////////////////
                        PRICE OBSERVATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Historical price observations for each pair
    /// @dev Stores circular buffer of price-timestamp observations
    /// @dev pair address => array of price observations
    mapping(address => PonderOracleTypes.Observation[]) internal _observations;

    /// @notice Current observation index in circular buffer
    /// @dev Tracks position for writing new observations
    /// @dev pair address => current array index
    mapping(address => uint256) internal _currentIndex;

    /*//////////////////////////////////////////////////////////////
                        TIMING STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Most recent observation timestamp
    /// @dev Used to enforce minimum update intervals
    /// @dev pair address => last update timestamp
    mapping(address => uint256) internal _lastUpdateTime;

    /*//////////////////////////////////////////////////////////////
                    INITIALIZATION STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pair initialization status
    /// @dev Prevents duplicate initialization of pairs
    /// @dev pair address => initialization status
    mapping(address => bool) internal _initializedPairs;
}
