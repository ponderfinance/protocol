// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderPair } from "../../core/pair/IPonderPair.sol";
import { UQ112x112 } from "../../libraries/UQ112x112.sol";
import { IPonderPriceOracle } from "../../core/oracle/IPonderPriceOracle.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER ORACLE LIBRARY
//////////////////////////////////////////////////////////////*/

/// @title PonderOracleLibrary
/// @author taayyohh
/// @notice Helper functions for Ponder protocol's oracle calculations
/// @dev Library providing core price accumulation and TWAP logic
library PonderOracleLibrary {
    using UQ112x112 for uint224;

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum uint32 value
    /// @dev Used for timestamp overflow handling
    /// @dev 2^32 = 4,294,967,296
    uint256 private constant UINT32_MAX = 2**32;

    /// @notice Maximum timeframe for updates
    /// @dev Prevents extreme price manipulation
    /// @dev 2 hours in seconds
    uint256 private constant MAX_TIME_ELAPSED = 2 hours;



    /*//////////////////////////////////////////////////////////////
                    PRICE CALCULATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get latest cumulative prices
    /// @dev Calculates up-to-date price accumulation including current block
    /// @param pair Address of Ponder pair to query
    /// @return price0Cumulative Accumulated price of token0 in terms of token1
    /// @return price1Cumulative Accumulated price of token1 in terms of token0
    /// @return blockTimestamp Current block timestamp as uint32
    function currentCumulativePrices(
        address pair
    ) internal view returns (
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    ) {
        // Safe downcast of block.timestamp to uint32
        // This is not used for randomness, but for timestamp overflow handling
        blockTimestamp = uint32(block.timestamp);

        price0Cumulative = IPonderPair(pair).price0CumulativeLast();
        price1Cumulative = IPonderPair(pair).price1CumulativeLast();

        // Get current pair state
        (uint112 reserve0, uint112 reserve1, uint32 timestampLast) = IPonderPair(pair).getReserves();

        // Only update price if time has elapsed and reserves are valid
        if (timestampLast != blockTimestamp) {
            uint32 timeElapsed;

            // Handle uint32 overflow
            if (blockTimestamp >= timestampLast) {
                timeElapsed = blockTimestamp - timestampLast;
            } else {
                timeElapsed = uint32(UINT32_MAX - timestampLast + blockTimestamp);
            }

            // Ensure time elapsed is reasonable
            if (timeElapsed > MAX_TIME_ELAPSED) {
                revert IPonderPriceOracle.InvalidTimeElapsed();
            }

            // Calculate cumulative prices if reserves are valid
            if (reserve0 != 0 && reserve1 != 0) {
                price0Cumulative += uint256(UQ112x112.encode(reserve1).uqdiv(reserve0)) * timeElapsed;
                price1Cumulative += uint256(UQ112x112.encode(reserve0).uqdiv(reserve1)) * timeElapsed;
            }
        }

        return (price0Cumulative, price1Cumulative, blockTimestamp);
    }


    /// @notice Calculate TWAP from observations
    /// @dev Computes amount out based on cumulative price difference
    /// @param priceCumulativeStart Price accumulator at start
    /// @param priceCumulativeEnd Price accumulator at end
    /// @param timeElapsed Time between observations
    /// @param amountIn Input amount for price calculation
    /// @return amountOut Output amount based on TWAP
    function computeAmountOut(
        uint256 priceCumulativeStart,
        uint256 priceCumulativeEnd,
        uint32 timeElapsed,
        uint256 amountIn
    ) internal pure returns (uint256 amountOut) {
        if (timeElapsed == 0) revert IPonderPriceOracle.ElapsedTimeZero();

        // Calculate price difference
        uint256 priceDiff = priceCumulativeEnd - priceCumulativeStart;

        return (priceDiff * amountIn) / (timeElapsed * UQ112x112.Q112);
    }
}
