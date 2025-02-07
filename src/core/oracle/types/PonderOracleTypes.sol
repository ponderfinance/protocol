// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER ORACLE TYPES
//////////////////////////////////////////////////////////////*/

/// @title PonderOracleTypes
/// @author taayyohh
/// @notice Type definitions for Ponder protocol's price oracle system
/// @dev Library containing all shared types, constants, and errors for the Oracle
library PonderOracleTypes {
    /*//////////////////////////////////////////////////////////////
                        OBSERVATION DATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Price observation data structure
    /// @dev Packed into 32 bytes for gas efficiency
    struct Observation {
        /// @notice Timestamp of observation
        /// @dev Unix timestamp truncated to uint32
        uint32 timestamp;

        /// @notice Token0 cumulative price
        /// @dev Accumulated price scaled to uint224
        uint224 price0Cumulative;

        /// @notice Token1 cumulative price
        /// @dev Accumulated price scaled to uint224
        uint224 price1Cumulative;
    }

    /*//////////////////////////////////////////////////////////////
                        CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Invalid trading pair address
    error InvalidPair();

    /// @notice Invalid token in trading pair
    error InvalidToken();

    /// @notice Update attempted too soon
    error UpdateTooFrequent();

    /// @notice Price data has expired
    error StalePrice();

    /// @notice Not enough observations recorded
    error InsufficientData();

    /// @notice Invalid time period requested
    error InvalidPeriod();

    /// @notice Pair already initialized
    error AlreadyInitialized();

    /// @notice Pair not yet initialized
    error NotInitialized();

    /// @notice Zero address provided
    error ZeroAddress();

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Standard observation timeframe
    /// @dev Default period for price calculations
    uint256 public constant PERIOD = 24 hours;

    /// @notice Update frequency limit
    /// @dev Minimum delay between price updates
    uint256 public constant MIN_UPDATE_DELAY = 5 minutes;

    /// @notice Observation buffer size
    /// @dev Stores 24 observations (2 hours at 5-min updates)
    uint16 public constant OBSERVATION_CARDINALITY = 24;
}
