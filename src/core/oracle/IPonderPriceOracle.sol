// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER ORACLE INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderPriceOracle
/// @author taayyohh
/// @notice Interface for Ponder protocol's price oracle system
/// @dev Defines the external interface for price feeds and TWAP calculations
interface IPonderPriceOracle {
    /*//////////////////////////////////////////////////////////////
                        PRICE QUERIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Get time-weighted average price
    /// @dev Calculates TWAP over specified period using stored observations
    /// @param pair Address of the Ponder pair
    /// @param tokenIn Address of input token
    /// @param amountIn Amount of input tokens
    /// @param period Time period for TWAP calculation
    /// @return amountOut Equivalent amount in output tokens
    function consult(
        address pair,
        address tokenIn,
        uint256 amountIn,
        uint32 period
    ) external view returns (uint256 amountOut);

    /// @notice Get current spot price
    /// @dev Returns instantaneous price from pair reserves
    /// @param pair Address of the Ponder pair
    /// @param tokenIn Address of input token
    /// @param amountIn Amount of input tokens
    /// @return amountOut Equivalent amount in output tokens
    function getCurrentPrice(
        address pair,
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut);


    /*//////////////////////////////////////////////////////////////
                    OBSERVATION MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Get historical observation
    /// @dev Retrieves specific price observation from storage
    /// @param pair Address of the pair
    /// @param index Index in the observations array
    /// @return timestamp Block timestamp of observation
    /// @return price0Cumulative Cumulative price for token0
    /// @return price1Cumulative Cumulative price for token1
    function observations(address pair, uint256 index) external view returns (
        uint32 timestamp,
        uint224 price0Cumulative,
        uint224 price1Cumulative
    );

    /// @notice Get observation count
    /// @dev Returns number of stored observations for pair
    /// @param pair Address of the Ponder pair
    /// @return Number of stored observations
    function observationLength(address pair) external view returns (uint256);

    /// @notice Update price data
    /// @dev Records new price observation for pair
    /// @param pair Address of the Ponder pair
    function update(address pair) external;

    /// @notice Get last update time
    /// @dev Returns timestamp of most recent observation
    /// @param pair Address of the pair
    /// @return Last update timestamp
    function lastUpdateTime(address pair) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                    IMMUTABLE REFERENCES
    //////////////////////////////////////////////////////////////*/

    /// @notice Get factory address
    /// @dev Returns immutable factory contract reference
    function factory() external view returns (address);

    /// @notice Get base token address
    /// @dev Returns immutable routing token reference
    function baseToken() external view returns (address);


    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Price update event
    /// @param pair Pair being updated
    /// @param price0Cumulative New token0 price
    /// @param price1Cumulative New token1 price
    /// @param blockTimestamp Update timestamp
    event OracleUpdated(
        address indexed pair,
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    );

    /// @notice Pair initialization event
    /// @param pair Pair being initialized
    /// @param timestamp Initialization time
    event PairInitialized(address indexed pair, uint32 timestamp);
}
