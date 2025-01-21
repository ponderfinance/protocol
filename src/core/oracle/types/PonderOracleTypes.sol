// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PonderOracleTypes
 * @notice Type definitions for the Ponder Oracle system
 * @dev Contains all shared constants, custom errors, and structs used in the Oracle
 */
library PonderOracleTypes {
    /**
     * @notice Price observation data point
     * @param timestamp Block timestamp of the observation
     * @param price0Cumulative Cumulative price for token0
     * @param price1Cumulative Cumulative price for token1
     */
    struct Observation {
        uint32 timestamp;
        uint224 price0Cumulative;
        uint224 price1Cumulative;
    }

    // Custom Errors
    error InvalidPair();
    error InvalidToken();
    error UpdateTooFrequent();
    error StalePrice();
    error InsufficientData();
    error InvalidPeriod();

    // Constants
    /// @notice Standard observation period
    uint256 public constant PERIOD = 24 hours;

    /// @notice Minimum time between price updates
    uint256 public constant MIN_UPDATE_DELAY = 5 minutes;

    /// @notice Number of observations to store (2 hours of 5-min updates)
    uint16 public constant OBSERVATION_CARDINALITY = 24;
}
