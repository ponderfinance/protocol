// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IPonderPair.sol";
import "../interfaces/IPonderFactory.sol";
import "../libraries/PonderOracleLibrary.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title PonderPriceOracle
/// @notice Price oracle for Ponder pairs with TWAP support and fallback mechanisms
contract PonderPriceOracle {
    struct Observation {
        uint32 timestamp;
        uint224 price0Cumulative;
        uint224 price1Cumulative;
    }

    uint public constant PERIOD = 24 hours;
    uint public constant MIN_UPDATE_DELAY = 5 minutes;
    uint16 public constant OBSERVATION_CARDINALITY = 24; // Store 2 hours of 5-min updates

    address public immutable factory;
    address public immutable baseToken; // Base token for routing (e.g. WETH, KUB)
    address public immutable stablecoin; // Stablecoin for USD prices

    mapping(address => Observation[]) public observations;
    mapping(address => uint256) public currentIndex;
    mapping(address => uint256) public lastUpdateTime;

    error InvalidPair();
    error InvalidToken();
    error UpdateTooFrequent();
    error StalePrice();
    error InsufficientData();
    error InvalidPeriod();

    event OracleUpdated(
        address indexed pair,
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    );

    constructor(address _factory, address _baseToken, address _stablecoin) {
        factory = _factory;
        baseToken = _baseToken;
        stablecoin = _stablecoin;
    }

    /// @notice Get number of stored observations for a pair
    function observationLength(address pair) external view returns (uint256) {
        return observations[pair].length;
    }

    /// @notice Updates price accumulator for a pair
    function update(address pair) external {
        if (block.timestamp < lastUpdateTime[pair] + MIN_UPDATE_DELAY) {
            revert UpdateTooFrequent();
        }
        if (!_isValidPair(pair)) {
            revert InvalidPair();
        }

        (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) =
                            PonderOracleLibrary.currentCumulativePrices(pair);

        Observation[] storage history = observations[pair];

        if (history.length == 0) {
            // Initialize history array
            history.push(Observation({
                timestamp: blockTimestamp,
                price0Cumulative: uint224(price0Cumulative),
                price1Cumulative: uint224(price1Cumulative)
            }));

            for (uint16 i = 1; i < OBSERVATION_CARDINALITY; i++) {
                history.push(history[0]);
            }
            currentIndex[pair] = 0;
        } else {
            uint256 index = (currentIndex[pair] + 1) % OBSERVATION_CARDINALITY;
            history[index] = Observation({
                timestamp: blockTimestamp,
                price0Cumulative: uint224(price0Cumulative),
                price1Cumulative: uint224(price1Cumulative)
            });
            currentIndex[pair] = index;
        }

        lastUpdateTime[pair] = block.timestamp;

        emit OracleUpdated(pair, price0Cumulative, price1Cumulative, blockTimestamp);
    }

    /// @notice Get the TWAP price from the oracle
    function consult(
        address pair,
        address tokenIn,
        uint256 amountIn,
        uint32 period
    ) external view returns (uint256 amountOut) {
        if (period == 0 || period > PERIOD) revert InvalidPeriod();
        if (amountIn == 0) return 0;

        // Check observation array is initialized
        if (observations[pair].length == 0) revert InsufficientData();

        // Check oracle has recent data
        if (block.timestamp > lastUpdateTime[pair] + PERIOD) revert StalePrice();

        // Get latest cumulative price
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
                            PonderOracleLibrary.currentCumulativePrices(pair);

        // Get historical price data
        (uint256 oldPrice0Cumulative, uint256 oldPrice1Cumulative, uint256 oldTimestamp) =
                        _getHistoricalPrices(pair, blockTimestamp - period);

        // Verify have enough elapsed time for accurate TWAP
        uint32 timeElapsed = blockTimestamp - uint32(oldTimestamp);
        if (timeElapsed < MIN_UPDATE_DELAY || timeElapsed > period) revert InsufficientData();

        IPonderPair pairContract = IPonderPair(pair);

        if (tokenIn == pairContract.token0()) {
            return _computeAmountOut(
                oldPrice0Cumulative,
                price0Cumulative,
                timeElapsed,
                amountIn
            );
        } else if (tokenIn == pairContract.token1()) {
            return _computeAmountOut(
                oldPrice1Cumulative,
                price1Cumulative,
                timeElapsed,
                amountIn
            );
        }

        revert InvalidToken();
    }

    function getCurrentPrice(
        address pair,
        address tokenIn,
        uint256 amountIn
    ) public view returns (uint256 amountOut) {
        if (!_isValidPair(pair)) revert InvalidPair();

        IPonderPair pairContract = IPonderPair(pair);
        (uint112 reserve0, uint112 reserve1,) = pairContract.getReserves();

        bool isToken0 = tokenIn == pairContract.token0();
        if (!isToken0 && tokenIn != pairContract.token1()) revert InvalidToken();

        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(isToken0 ? pairContract.token1() : pairContract.token0()).decimals();

        uint256 reserveIn = uint256(isToken0 ? reserve0 : reserve1);
        uint256 reserveOut = uint256(isToken0 ? reserve1 : reserve0);

        // Normalize reserves to handle decimal differences
        if (decimalsIn > decimalsOut) {
            // Need to adjust reserveOut up to match decimalsIn
            reserveOut = reserveOut * (10 ** (decimalsIn - decimalsOut));
        } else if (decimalsOut > decimalsIn) {
            // Need to adjust reserveIn up to match decimalsOut
            reserveIn = reserveIn * (10 ** (decimalsOut - decimalsIn));
        }

        // Price calculation: (amountIn * reserveOut) / reserveIn
        if (reserveIn == 0) return 0;

        uint256 quote = (amountIn * reserveOut) / reserveIn;

        // If input decimals > output decimals, we need to scale down the result
        if (decimalsIn > decimalsOut) {
            quote = quote / (10 ** (decimalsIn - decimalsOut));
        }
            // If output decimals > input decimals, we need to scale up the result
        else if (decimalsOut > decimalsIn) {
            quote = quote * (10 ** (decimalsOut - decimalsIn));
        }

        return quote;
    }

    /// @notice Get price in stablecoin units through base token if needed
    function getPriceInStablecoin(
        address pair,
        address tokenIn,
        uint256 amountIn
    ) external view returns (uint256 amountOut) {
        if (amountIn == 0) return 0;

        // Try direct stablecoin pair first using TWAP
        address stablePair = IPonderFactory(factory).getPair(tokenIn, stablecoin);
        if (stablePair != address(0)) {
            return this.getCurrentPrice(stablePair, tokenIn, amountIn);
        }

        return 0;
    }

    function _getHistoricalPrices(
        address pair,
        uint256 targetTimestamp
    ) internal view returns (uint256, uint256, uint256) {
        Observation[] storage history = observations[pair];
        uint256 currentIdx = currentIndex[pair];

        for (uint16 i = 0; i < OBSERVATION_CARDINALITY; i++) {
            uint256 index = (currentIdx + OBSERVATION_CARDINALITY - i) % OBSERVATION_CARDINALITY;
            if (history[index].timestamp <= targetTimestamp) {
                return (
                    history[index].price0Cumulative,
                    history[index].price1Cumulative,
                    history[index].timestamp
                );
            }
        }

        // If no observation found, return oldest
        uint256 oldestIndex = (currentIdx + 1) % OBSERVATION_CARDINALITY;
        return (
            history[oldestIndex].price0Cumulative,
            history[oldestIndex].price1Cumulative,
            history[oldestIndex].timestamp
        );
    }

    function _computeAmountOut(
        uint256 priceCumulativeStart,
        uint256 priceCumulativeEnd,
        uint32 timeElapsed,
        uint256 amountIn
    ) internal pure returns (uint256) {
        uint256 priceAverage = (priceCumulativeEnd - priceCumulativeStart) / timeElapsed;
        return (amountIn * priceAverage) >> 112;
    }

    function _isValidPair(address pair) internal view returns (bool) {
        return IPonderFactory(factory).getPair(
            IPonderPair(pair).token0(),
            IPonderPair(pair).token1()
        ) == pair;
    }
}
