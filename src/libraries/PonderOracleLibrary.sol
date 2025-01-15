// src/libraries/PonderOracleLibrary.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPonderPair.sol";
import "./UQ112x112.sol";

library PonderOracleLibrary {
    using UQ112x112 for uint224;

    // Helper function to get the latest cumulative price from a Ponder pair
    function currentCumulativePrices(
        address pair
    ) internal view returns (
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    ) {
        blockTimestamp = uint32(block.timestamp % 2**32);
        price0Cumulative = IPonderPair(pair).price0CumulativeLast();
        price1Cumulative = IPonderPair(pair).price1CumulativeLast();

        // If time has elapsed since the last update on the pair, calculate current price values
        (uint112 reserve0, uint112 reserve1, uint32 timestampLast) = IPonderPair(pair).getReserves();
        if (timestampLast != blockTimestamp) {
            uint32 timeElapsed = blockTimestamp - timestampLast;
            // Overflow is desired
            if (reserve0 != 0 && reserve1 != 0) {
                price0Cumulative += uint256(UQ112x112.encode(reserve1).uqdiv(reserve0)) * timeElapsed;
                price1Cumulative += uint256(UQ112x112.encode(reserve0).uqdiv(reserve1)) * timeElapsed;
            }
        }

        return (price0Cumulative, price1Cumulative, blockTimestamp);
    }

    // Calculate time-weighted average price from cumulative price observations
    function computeAmountOut(
        uint256 priceCumulativeStart,
        uint256 priceCumulativeEnd,
        uint32 timeElapsed,
        uint256 amountIn
    ) internal pure returns (uint256 amountOut) {
        require(timeElapsed > 0, 'PonderOracleLibrary: ELAPSED_TIME_ZERO');

        // Calculate the average price
        uint256 priceDiff = priceCumulativeEnd - priceCumulativeStart;
        uint256 priceAverage = (priceDiff * UQ112x112.Q112) / (timeElapsed * UQ112x112.Q112);

        // Calculate amount out using the average price
        return (amountIn * priceAverage) / UQ112x112.Q112;
    }
}
