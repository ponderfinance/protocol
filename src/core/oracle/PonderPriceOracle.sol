// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPonderPriceOracle } from "./IPonderPriceOracle.sol";
import { PonderOracleStorage } from "./storage/PonderOracleStorage.sol";
import { PonderOracleTypes } from "./types/PonderOracleTypes.sol";
import { PonderOracleLibrary } from "./PonderOracleLibrary.sol";
import { IPonderPair } from "../pair/IPonderPair.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title PonderPriceOracle
 * @notice Price oracle for Ponder pairs with TWAP support and fallback mechanisms
 */
contract PonderPriceOracle is IPonderPriceOracle, PonderOracleStorage {
    using PonderOracleTypes for *;

    // Immutable state variables
    address public immutable FACTORY;
    address public immutable BASE_TOKEN;
    address public immutable STABLECOIN;

    constructor(address _factory, address _baseToken, address _stablecoin) {
        FACTORY = _factory;
        BASE_TOKEN = _baseToken;
        STABLECOIN = _stablecoin;
    }

    /// @inheritdoc IPonderPriceOracle
    function factory() external view returns (address) {
        return FACTORY;
    }

    /// @inheritdoc IPonderPriceOracle
    function baseToken() external view returns (address) {
        return BASE_TOKEN;
    }

    /// @inheritdoc IPonderPriceOracle
    function stableCoin() external view returns (address) {
        return STABLECOIN;
    }

    /// @inheritdoc IPonderPriceOracle
    function observationLength(address pair) external view returns (uint256) {
        return _observations[pair].length;
    }

    /// @inheritdoc IPonderPriceOracle
    function update(address pair) external {
        if (block.timestamp < _lastUpdateTime[pair] + PonderOracleTypes.MIN_UPDATE_DELAY) {
            revert PonderOracleTypes.UpdateTooFrequent();
        }
        if (!_isValidPair(pair)) {
            revert PonderOracleTypes.InvalidPair();
        }

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
                            PonderOracleLibrary.currentCumulativePrices(pair);

        PonderOracleTypes.Observation[] storage history = _observations[pair];

        if (history.length == 0) {
            // Initialize history array
            history.push(PonderOracleTypes.Observation({
                timestamp: blockTimestamp,
                price0Cumulative: uint224(price0Cumulative),
                price1Cumulative: uint224(price1Cumulative)
            }));

            for (uint16 i = 1; i < PonderOracleTypes.OBSERVATION_CARDINALITY; i++) {
                history.push(history[0]);
            }
            _currentIndex[pair] = 0;
        } else {
            uint256 index = (_currentIndex[pair] + 1) % PonderOracleTypes.OBSERVATION_CARDINALITY;
            history[index] = PonderOracleTypes.Observation({
                timestamp: blockTimestamp,
                price0Cumulative: uint224(price0Cumulative),
                price1Cumulative: uint224(price1Cumulative)
            });
            _currentIndex[pair] = index;
        }

        _lastUpdateTime[pair] = block.timestamp;

        emit OracleUpdated(pair, price0Cumulative, price1Cumulative, blockTimestamp);
    }

    /// @inheritdoc IPonderPriceOracle
    function consult(
        address pair,
        address tokenIn,
        uint256 amountIn,
        uint32 period
    ) external view returns (uint256 amountOut) {
        if (period == 0 || period > PonderOracleTypes.PERIOD) revert PonderOracleTypes.InvalidPeriod();
        if (amountIn == 0) return 0;

        // Check observation array is initialized
        if (_observations[pair].length == 0) revert PonderOracleTypes.InsufficientData();

        // Check oracle has recent data
        if (block.timestamp > _lastUpdateTime[pair] + PonderOracleTypes.PERIOD) {
            revert PonderOracleTypes.StalePrice();
        }

        // Get latest cumulative price
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
                            PonderOracleLibrary.currentCumulativePrices(pair);

        // Get historical price data
        (uint256 oldPrice0Cumulative, uint256 oldPrice1Cumulative, uint256 oldTimestamp) =
                        _getHistoricalPrices(pair, blockTimestamp - period);

        // Verify have enough elapsed time for accurate TWAP
        uint32 timeElapsed = blockTimestamp - uint32(oldTimestamp);
        if (timeElapsed < PonderOracleTypes.MIN_UPDATE_DELAY || timeElapsed > period) {
            revert PonderOracleTypes.InsufficientData();
        }

        IPonderPair pairContract = IPonderPair(pair);

        if (tokenIn == pairContract.token0()) {
            return PonderOracleLibrary.computeAmountOut(
                oldPrice0Cumulative,
                price0Cumulative,
                timeElapsed,
                amountIn
            );
        } else if (tokenIn == pairContract.token1()) {
            return PonderOracleLibrary.computeAmountOut(
                oldPrice1Cumulative,
                price1Cumulative,
                timeElapsed,
                amountIn
            );
        }

        revert PonderOracleTypes.InvalidToken();
    }

    /// @inheritdoc IPonderPriceOracle
    function getCurrentPrice(
        address pair,
        address tokenIn,
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        if (!_isValidPair(pair)) revert PonderOracleTypes.InvalidPair();

        IPonderPair pairContract = IPonderPair(pair);
        (uint112 reserve0, uint112 reserve1,) = pairContract.getReserves();

        bool isToken0 = tokenIn == pairContract.token0();
        if (!isToken0 && tokenIn != pairContract.token1()) revert PonderOracleTypes.InvalidToken();

        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(isToken0 ? pairContract.token1() : pairContract.token0()).decimals();

        uint256 reserveIn = uint256(isToken0 ? reserve0 : reserve1);
        uint256 reserveOut = uint256(isToken0 ? reserve1 : reserve0);

        // Normalize reserves to handle decimal differences
        if (decimalsIn > decimalsOut) {
            reserveOut = reserveOut * (10 ** (decimalsIn - decimalsOut));
        } else if (decimalsOut > decimalsIn) {
            reserveIn = reserveIn * (10 ** (decimalsOut - decimalsIn));
        }

        if (reserveIn == 0) return 0;

        uint256 quote = (amountIn * reserveOut) / reserveIn;

        // Adjust quote based on decimal differences
        if (decimalsIn > decimalsOut) {
            quote = quote / (10 ** (decimalsIn - decimalsOut));
        } else if (decimalsOut > decimalsIn) {
            quote = quote * (10 ** (decimalsOut - decimalsIn));
        }

        return quote;
    }

    /// @inheritdoc IPonderPriceOracle
    function getPriceInStablecoin(
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        // Try direct stablecoin pair first
        address stablePair = IPonderFactory(FACTORY).getPair(tokenIn, STABLECOIN);
        if (stablePair != address(0)) {
            return this.getCurrentPrice(stablePair, tokenIn, amountIn);
        }

        return 0;
    }

    /**
     * @notice Get historical cumulative prices for a pair
     * @param pair Address of the pair
     * @param targetTimestamp Target timestamp to find prices for
     * @return price0Cumulative Historical cumulative price for token0
     * @return price1Cumulative Historical cumulative price for token1
     * @return timestamp Timestamp of the observation
     */
    function _getHistoricalPrices(
        address pair,
        uint256 targetTimestamp
    ) internal view returns (uint256, uint256, uint256) {
        PonderOracleTypes.Observation[] storage history = _observations[pair];
        uint256 currentIdx = _currentIndex[pair];

        for (uint16 i = 0; i < PonderOracleTypes.OBSERVATION_CARDINALITY; i++) {
            uint256 index = (currentIdx + PonderOracleTypes.OBSERVATION_CARDINALITY - i) %
                            PonderOracleTypes.OBSERVATION_CARDINALITY;
            if (history[index].timestamp <= targetTimestamp) {
                return (
                    history[index].price0Cumulative,
                    history[index].price1Cumulative,
                    history[index].timestamp
                );
            }
        }

        // If no observation found, return oldest
        uint256 oldestIndex = (currentIdx + 1) % PonderOracleTypes.OBSERVATION_CARDINALITY;
        return (
            history[oldestIndex].price0Cumulative,
            history[oldestIndex].price1Cumulative,
            history[oldestIndex].timestamp
        );
    }

    /// @inheritdoc IPonderPriceOracle
    function lastUpdateTime(address pair) external view returns (uint256) {
        return _lastUpdateTime[pair];
    }

    /// @inheritdoc IPonderPriceOracle
    function observations(address pair, uint256 index) external view returns (
        uint32 timestamp,
        uint224 price0Cumulative,
        uint224 price1Cumulative
    ) {
        PonderOracleTypes.Observation storage observation = _observations[pair][index];
        return (
            observation.timestamp,
            observation.price0Cumulative,
            observation.price1Cumulative
        );
    }

    /**
     * @notice Check if a pair exists in the factory
     * @param pair Address to check
     * @return bool True if pair is valid
     */
    function _isValidPair(address pair) internal view returns (bool) {
        return IPonderFactory(FACTORY).getPair(
            IPonderPair(pair).token0(),
            IPonderPair(pair).token1()
        ) == pair;
    }
}
