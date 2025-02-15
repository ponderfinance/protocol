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
