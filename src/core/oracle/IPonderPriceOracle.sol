// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IPonderPriceOracle
 * @notice Interface for the Ponder Price Oracle
 * @dev Defines all external functions and events for the Oracle system
 */
interface IPonderPriceOracle {
    /**
     * @notice Get the TWAP price from the oracle
     * @param pair Address of the Ponder pair
     * @param tokenIn Address of input token
     * @param amountIn Amount of input tokens
     * @param period Time period for TWAP calculation
     * @return amountOut Equivalent amount in output tokens
     */
    function consult(
        address pair,
        address tokenIn,
        uint256 amountIn,
        uint32 period
    ) external view returns (uint256 amountOut);

    /**
     * @notice Get the current spot price from the pair
     * @param pair Address of the Ponder pair
     * @param tokenIn Address of input token
     * @param amountIn Amount of input tokens
     * @return amountOut Equivalent amount in output tokens
     */
    function getCurrentPrice(
        address pair,
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    /**
     * @notice Get price in stablecoin through base token if needed
     * @param tokenIn Address of input token
     * @param amountIn Amount of input tokens
     * @return amountOut Equivalent amount in stablecoin
     */
    function getPriceInStablecoin(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut);


    /**
     * @notice Get an observation at a specific index for a pair
     * @param pair Address of the pair
     * @param index Index in the observations array
     * @return timestamp Block timestamp of the observation
     * @return price0Cumulative Cumulative price for token0
     * @return price1Cumulative Cumulative price for token1
     */
    function observations(address pair, uint256 index) external view returns (
        uint32 timestamp,
        uint224 price0Cumulative,
        uint224 price1Cumulative
    );

    /**
     * @notice Get number of stored observations for a pair
     * @param pair Address of the Ponder pair
     * @return Number of observations
     */
    function observationLength(address pair) external view returns (uint256);

    /**
     * @notice Updates price accumulator for a pair
     * @param pair Address of the Ponder pair
     */
    function update(address pair) external;

    /**
    * @notice Get the last update time for a pair
     * @param pair Address of the pair
     * @return Last time the pair's price was updated
     */
    function lastUpdateTime(address pair) external view returns (uint256);

    /**
     * @notice Get immutable factory contract address
     */
    function factory() external view returns (address);

    /**
     * @notice Get immutable base token address
     */
    function baseToken() external view returns (address);

    /**
     * @notice Get immutable stablecoin address
     */
    function stableCoin() external view returns (address);

    /**
     * @notice Emitted when oracle prices are updated
     * @param pair Address of the updated pair
     * @param price0Cumulative New cumulative price for token0
     * @param price1Cumulative New cumulative price for token1
     * @param blockTimestamp Block timestamp of the update
     */
    event OracleUpdated(
        address indexed pair,
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    );
}
