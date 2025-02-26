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

    /// @notice Data structure for Time Weighted Average Price calculations
    /// @dev Packed structure used in interpolation calculations
    struct TWAPData {
        /// @notice First observation timestamp
        /// @dev Timestamp of the earlier price point
        uint32 firstObs;

        /// @notice Second observation timestamp
        /// @dev Timestamp of the later price point
        uint32 secondObs;

        /// @notice First token0 cumulative price
        /// @dev Earlier cumulative price for token0
        uint224 firstPrice0;

        /// @notice Second token0 cumulative price
        /// @dev Later cumulative price for token0
        uint224 secondPrice0;

        /// @notice First token1 cumulative price
        /// @dev Earlier cumulative price for token1
        uint224 firstPrice1;

        /// @notice Second token1 cumulative price
        /// @dev Later cumulative price for token1
        uint224 secondPrice1;
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Standard observation timeframe
    /// @dev Default period for price calculations
    uint256 public constant PERIOD = 24 hours;

    /// @notice Update frequency limit
    /// @dev Minimum delay between price updates
    uint256 public constant MIN_UPDATE_DELAY = 2 minutes;

    /// @notice Observation buffer size
    /// @dev Stores 24 observations (2 hours at 5-min updates)
    uint16 public constant OBSERVATION_CARDINALITY = 24;
}
