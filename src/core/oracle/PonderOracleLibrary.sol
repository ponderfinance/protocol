// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IPonderPair } from "../../core/pair/IPonderPair.sol";
import { UQ112x112 } from "../../libraries/UQ112x112.sol";

library PonderOracleLibrary {
    using UQ112x112 for uint224;

    /// @notice Maximum value for uint32 to handle timestamp overflow
    uint256 private constant UINT32_MAX = 2**32;

    /// @notice Maximum allowed time difference for price updates
    uint256 private constant MAX_TIME_ELAPSED = 2 hours;

    error ElapsedTimeZero();
    error InvalidTimeElapsed();

    /// @notice Get current cumulative prices from a Ponder pair
    /// @dev Uses uint32 timestamp for compatibility with Uniswap V2-style oracles
    /// @param pair The address of the Ponder pair
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
                revert InvalidTimeElapsed();
            }

            // Calculate cumulative prices if reserves are valid
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
        if (timeElapsed == 0) revert ElapsedTimeZero();

        // Calculate price difference
        uint256 priceDiff = priceCumulativeEnd - priceCumulativeStart;


        return (priceDiff * amountIn) / (timeElapsed * UQ112x112.Q112);
    }
}
