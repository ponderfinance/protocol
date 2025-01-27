// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderPriceOracle } from "./IPonderPriceOracle.sol";
import { PonderOracleStorage } from "./storage/PonderOracleStorage.sol";
import { PonderOracleTypes } from "./types/PonderOracleTypes.sol";
import { PonderOracleLibrary } from "./PonderOracleLibrary.sol";
import { IPonderPair } from "../pair/IPonderPair.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";

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
        if (_factory == address(0)) revert PonderOracleTypes.ZeroAddress();
        if (_baseToken == address(0)) revert PonderOracleTypes.ZeroAddress();
        if (_stablecoin == address(0)) revert PonderOracleTypes.ZeroAddress();


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

    function initializePair(address pair) public {
        if (pair == address(0)) revert PonderOracleTypes.ZeroAddress();
        if (!_isValidPair(pair)) revert PonderOracleTypes.InvalidPair();
        if (_initializedPairs[pair]) revert PonderOracleTypes.AlreadyInitialized();

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
                            PonderOracleLibrary.currentCumulativePrices(pair);

        PonderOracleTypes.Observation memory firstObservation = PonderOracleTypes.Observation({
            timestamp: blockTimestamp,
            price0Cumulative: uint224(price0Cumulative),
            price1Cumulative: uint224(price1Cumulative)
        });

        // Initialize the observations array
        for (uint16 i = 0; i < PonderOracleTypes.OBSERVATION_CARDINALITY; i++) {
            _observations[pair].push(firstObservation);
        }

        _currentIndex[pair] = 0;
        _lastUpdateTime[pair] = block.timestamp;
        _initializedPairs[pair] = true;

        emit PairInitialized(pair, blockTimestamp);
    }


    /// @inheritdoc IPonderPriceOracle
    function update(address pair) external override {
        // - Used for TWAP calculation with built-in manipulation resistance
        // - Multiple price points are used to calculate average
        // - Additional price deviation checks are implemented
        // slither-disable-next-line block-timestamp
        if (block.timestamp < _lastUpdateTime[pair] + PonderOracleTypes.MIN_UPDATE_DELAY) {
            revert PonderOracleTypes.UpdateTooFrequent();
        }
        if (!_isValidPair(pair)) {
            revert PonderOracleTypes.InvalidPair();
        }

        if (!_initializedPairs[pair]) {
            initializePair(pair);
            return;
        }

        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
                            PonderOracleLibrary.currentCumulativePrices(pair);

        uint256 index = (_currentIndex[pair] + 1) % PonderOracleTypes.OBSERVATION_CARDINALITY;
        _observations[pair][index] = PonderOracleTypes.Observation({
            timestamp: blockTimestamp,
            price0Cumulative: uint224(price0Cumulative),
            price1Cumulative: uint224(price1Cumulative)
        });
        _currentIndex[pair] = index;
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
        if (!_initializedPairs[pair]) revert PonderOracleTypes.NotInitialized();
        if (period == 0 || period > PonderOracleTypes.PERIOD) revert PonderOracleTypes.InvalidPeriod();
        if (amountIn == 0) return 0;

        // Check observation array is initialized
        if (_observations[pair].length == 0) revert PonderOracleTypes.InsufficientData();

        // Check oracle has recent data
        // - TWAP mechanism inherently resistant to short-term manipulation
        // - Price staleness check is much longer than possible timestamp manipulation
        // slither-disable-next-line block-timestamp
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

        /// Third value from getReserves is block.timestamp
        // which we don't need for price calculation
        /// slither-disable-next-line unused-return
        (uint112 reserve0, uint112 reserve1,) = pairContract.getReserves();

        // Check which token is token0 based on address ordering
        bool isToken0 = tokenIn == pairContract.token0();
        if (!isToken0 && tokenIn != pairContract.token1()) revert PonderOracleTypes.InvalidToken();

        // Get reserves matching input token
        uint256 reserveIn = uint256(isToken0 ? reserve0 : reserve1);
        uint256 reserveOut = uint256(isToken0 ? reserve1 : reserve0);

        if (reserveIn == 0) return 0;

        // Calculate base quote
        // If we're calculating KUB -> USDT where KUB is 18 decimals and USDT is 6:
        // amountIn = 1e18
        // reserveIn = 100e18 (100 KUB)
        // reserveOut = 3000e6 (3000 USDT)
        // quote = (1e18 * 3000e6) / 100e18 = 30e6
        uint256 quote = (amountIn * reserveOut) / reserveIn;

        // No need to adjust decimals further since the reserves are already stored
        // in their native decimal precision in the pair
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
            return getCurrentPrice(stablePair, tokenIn, amountIn);
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
        if (pair == address(0)) return false;

        return IPonderFactory(FACTORY).getPair(
            IPonderPair(pair).token0(),
            IPonderPair(pair).token1()
        ) == pair;
    }

    /// @notice Check if a pair has been initialized
    /// @param pair Address of the pair to check
    /// @return bool True if the pair has been initialized
    function isPairInitialized(address pair) external view returns (bool) {
        return _initializedPairs[pair];
    }
}
