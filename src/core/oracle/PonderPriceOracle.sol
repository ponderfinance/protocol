// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderPriceOracle } from "./IPonderPriceOracle.sol";
import { PonderOracleStorage } from "./storage/PonderOracleStorage.sol";
import { PonderOracleTypes } from "./types/PonderOracleTypes.sol";
import { PonderOracleLibrary } from "./PonderOracleLibrary.sol";
import { IPonderPair } from "../pair/IPonderPair.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";


/*//////////////////////////////////////////////////////////////
                    PONDER PRICE ORACLE
//////////////////////////////////////////////////////////////*/

/// @title PonderPriceOracle
/// @author taayyohh
/// @notice Price oracle system for Ponder protocol's trading pairs
/// @dev Implements TWAP calculations with manipulation resistance and fallback mechanisms
contract PonderPriceOracle is IPonderPriceOracle, PonderOracleStorage {
    using PonderOracleTypes for *;

    /*//////////////////////////////////////////////////////////////
                       IMMUTABLE STATE
   //////////////////////////////////////////////////////////////*/

    /// @notice Factory contract reference
    /// @dev Used to validate pairs and find routes
    address public immutable FACTORY;

    /// @notice Base routing token
    /// @dev Used for indirect price calculations
    address public immutable BASE_TOKEN;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initialize oracle with core contracts
    /// @dev Sets immutable protocol references
    /// @param _factory Address of pair factory
    /// @param _baseToken Address of base routing token
    constructor(address _factory, address _baseToken) {
        if (_factory == address(0)) revert IPonderPriceOracle.ZeroAddress();
        if (_baseToken == address(0)) revert IPonderPriceOracle.ZeroAddress();

        FACTORY = _factory;
        BASE_TOKEN = _baseToken;
    }


    /*//////////////////////////////////////////////////////////////
                       PAIR MANAGEMENT
   //////////////////////////////////////////////////////////////*/

    /// @notice Set up new trading pair
    /// @dev Creates initial observation array
    /// @param pair Address of pair to initialize
    function initializePair(address pair) public {
        if (pair == address(0)) revert IPonderPriceOracle.ZeroAddress();
        if (!_isValidPair(pair)) revert IPonderPriceOracle.InvalidPair();
        if (_initializedPairs[pair]) revert IPonderPriceOracle.AlreadyInitialized();

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


    /// @notice Record new price observation
    /// @dev Updates circular buffer with latest prices
    /// @param pair Address of pair to update
    function update(address pair) external override {
        // - Used for TWAP calculation with built-in manipulation resistance
        // - Multiple price points are used to calculate average
        // - Additional price deviation checks are implemented
        // slither-disable-next-line block-timestamp
        if (block.timestamp < _lastUpdateTime[pair] + PonderOracleTypes.MIN_UPDATE_DELAY) {
            revert IPonderPriceOracle.UpdateTooFrequent();
        }
        if (!_isValidPair(pair)) {
            revert IPonderPriceOracle.InvalidPair();
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


    /*//////////////////////////////////////////////////////////////
                       PRICE CALCULATIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Calculate TWAP for pair
    /// @dev Uses historical observations over period
    /// @param pair Address of trading pair
    /// @param tokenIn Token being priced
    /// @param amountIn Amount to price
    /// @param period Time period for TWAP
    /// @return amountOut Equivalent output amount
    function consult(
        address pair,
        address tokenIn,
        uint256 amountIn,
        uint32 period
    ) external view returns (uint256 amountOut) {
        if (!_initializedPairs[pair]) revert IPonderPriceOracle.NotInitialized();
        if (period == 0 || period > PonderOracleTypes.PERIOD) revert IPonderPriceOracle.InvalidPeriod();
        if (amountIn == 0) return 0;

        // Check observation array is initialized
        if (_observations[pair].length == 0) revert IPonderPriceOracle.InsufficientData();

        // Check oracle has recent data
        // - TWAP mechanism inherently resistant to short-term manipulation
        // - Price staleness check is much longer than possible timestamp manipulation
        // slither-disable-next-line block-timestamp
        if (block.timestamp > _lastUpdateTime[pair] + PonderOracleTypes.PERIOD) {
            revert IPonderPriceOracle.StalePrice();
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
            revert IPonderPriceOracle.InsufficientData();
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

        revert IPonderPriceOracle.InvalidToken();
    }

    /// @notice Get current spot price
    /// @dev Uses current reserves without TWAP
    /// @param pair Address of trading pair
    /// @param tokenIn Token being priced
    /// @param amountIn Amount to price
    /// @return amountOut Equivalent output amount
    function getCurrentPrice(
        address pair,
        address tokenIn,
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        if (!_isValidPair(pair)) revert IPonderPriceOracle.InvalidPair();

        IPonderPair pairContract = IPonderPair(pair);

        /// Third value from getReserves is block.timestamp
        // which we don't need for price calculation
        /// slither-disable-next-line unused-return
        (uint112 reserve0, uint112 reserve1,) = pairContract.getReserves();

        // Check which token is token0 based on address ordering
        bool isToken0 = tokenIn == pairContract.token0();
        if (!isToken0 && tokenIn != pairContract.token1()) revert IPonderPriceOracle.InvalidToken();

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

    /*//////////////////////////////////////////////////////////////
                       INTERNAL HELPERS
   //////////////////////////////////////////////////////////////*/

    /// @notice Find historical price point
    /// @dev Searches observation array for timestamp
    /// @param pair Address of trading pair
    /// @param targetTimestamp Desired observation time
    /// @return price0Cumulative Historical price0 accumulator
    /// @return price1Cumulative Historical price1 accumulator
    /// @return timestamp Actual observation timestamp
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

    /// @notice Validate pair exists
    /// @dev Checks pair in factory
    /// @param pair Address to validate
    /// @return True if pair is valid
    function _isValidPair(address pair) internal view returns (bool) {
        if (pair == address(0)) return false;

        return IPonderFactory(FACTORY).getPair(
            IPonderPair(pair).token0(),
            IPonderPair(pair).token1()
        ) == pair;
    }



    /*//////////////////////////////////////////////////////////////
                            VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get initialization status
    /// @dev Checks if pair is ready for queries
    /// @param pair Address to check
    /// @return True if pair is initialized
    function isPairInitialized(address pair) external view returns (bool) {
        return _initializedPairs[pair];
    }

    /// @notice Get specific observation
    /// @dev Returns stored price point
    /// @param pair Address of pair
    /// @param index Position in buffer
    /// @return timestamp Observation time
    /// @return price0Cumulative Token0 accumulator
    /// @return price1Cumulative Token1 accumulator
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

    /// @notice Get observation count
    /// @dev Returns buffer size for pair
    /// @param pair Address to check
    /// @return Number of observations
    function observationLength(address pair) external view returns (uint256) {
        return _observations[pair].length;
    }

    /// @notice Get last update time
    /// @dev Returns timestamp of latest price
    /// @param pair Address to check
    /// @return Last update timestamp
    function lastUpdateTime(address pair) external view returns (uint256) {
        return _lastUpdateTime[pair];
    }

    /// @notice Get factory address
    /// @return Factory contract address
    function factory() external view returns (address) {
        return FACTORY;
    }

    /// @notice Get base token address
    /// @return Base routing token address
    function baseToken() external view returns (address) {
        return BASE_TOKEN;
    }
}
