// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { PonderOracleTypes } from "../types/PonderOracleTypes.sol";

/**
 * @title PonderOracleStorage
 * @notice Storage layout for the Ponder Oracle contract
 * @dev Contains all state variables used in the Oracle implementation
 */
abstract contract PonderOracleStorage {
    // Complex data structures
    /// @notice Price observations for each pair
    mapping(address => PonderOracleTypes.Observation[]) internal _observations;

    /// @notice Current observation index for each pair
    mapping(address => uint256) internal _currentIndex;

    /// @notice Last update timestamp for each pair
    mapping(address => uint256) internal _lastUpdateTime;

    /// @notice Mapping to track initialized pairs
    mapping(address => bool) internal _initializedPairs;
}
