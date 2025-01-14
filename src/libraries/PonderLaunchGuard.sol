// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPonderPair.sol";
import "../interfaces/IPonderFactory.sol";
import "../interfaces/IPonderPriceOracle.sol";
import "../interfaces/IERC20.sol";

library PonderLaunchGuard {
    // Existing constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_LIQUIDITY = 1000 ether;
    uint256 public constant MAX_LIQUIDITY = 5000 ether;
    uint256 public constant MIN_PONDER_PERCENT = 500;   // 5%
    uint256 public constant MAX_PONDER_PERCENT = 2000;  // 20%
    uint256 public constant MAX_PRICE_IMPACT = 500;     // 5%

    // New TWAP-related constants
    uint256 public constant TWAP_PERIOD = 30 minutes;
    uint256 public constant SPOT_TWAP_DEVIATION_LIMIT = 300; // 3% max deviation between spot and TWAP
    uint256 public constant PRICE_CHECK_PERIOD = 5 minutes;
    uint256 public constant RESERVE_CHANGE_LIMIT = 2000; // 20% max reserve change in PRICE_CHECK_PERIOD

    struct ValidationResult {
        uint256 kubValue;          // Value in KUB terms
        uint256 priceImpact;       // Impact in basis points
        uint256 maxPonderPercent;  // Maximum PONDER acceptance
    }

    struct PriceState {
        uint256 spotPrice;
        uint256 twapPrice;
        uint112 reserve0;
        uint112 reserve1;
        uint32 timestamp;
    }

    error InsufficientLiquidity();
    error ExcessivePriceImpact();
    error InvalidPrice();
    error ExcessivePriceDeviation();
    error StalePrice();
    error SuddenReserveChange();
    error ContributionTooLarge();
    error ZeroAmount();

    function validatePonderContribution(
        address pair,
        address oracle,
        uint256 amount
    ) external view returns (ValidationResult memory result) {
        if (amount == 0) revert ZeroAmount();

        // Get reserves and verify minimum liquidity
        (uint112 reserve0, uint112 reserve1,) = IPonderPair(pair).getReserves();
        uint256 totalLiquidity = uint256(reserve0) * reserve1;
        if (totalLiquidity < MIN_LIQUIDITY) revert InsufficientLiquidity();

        // Get TWAP price from oracle
        result.kubValue = IPonderPriceOracle(oracle).getCurrentPrice(
            pair,
            IPonderPair(pair).token0(),
            amount
        );
        if (result.kubValue == 0) revert InvalidPrice();

        // Calculate and validate price impact
        result.priceImpact = _calculatePriceImpact(
            reserve1, // ponder reserve
            reserve0, // kub reserve
            amount
        );
        if (result.priceImpact > MAX_PRICE_IMPACT) revert ExcessivePriceImpact();

        // Use fixed maximum percentage instead of scaling
        result.maxPonderPercent = MAX_PONDER_PERCENT;

        return result;
    }

    function _getPriceState(
        address pair,
        address oracle
    ) internal view returns (PriceState memory state) {
        // Get current reserves and timestamp
        (state.reserve0, state.reserve1, state.timestamp) = IPonderPair(pair).getReserves();

        // Check for staleness
        if (block.timestamp - state.timestamp > PRICE_CHECK_PERIOD) revert StalePrice();

        // Get TWAP price
        state.twapPrice = IPonderPriceOracle(oracle).consult(
            pair,
            IPonderPair(pair).token0(),
            1e18,
            uint32(TWAP_PERIOD)
        );

        // Get spot price
        state.spotPrice = IPonderPriceOracle(oracle).getCurrentPrice(
            pair,
            IPonderPair(pair).token0(),
            1e18
        );

        return state;
    }

    function _calculateDeviation(
        uint256 price1,
        uint256 price2
    ) internal pure returns (uint256) {
        if (price1 == 0 || price2 == 0) revert InvalidPrice();

        return price1 > price2 ?
            ((price1 - price2) * BASIS_POINTS) / price1 :
            ((price2 - price1) * BASIS_POINTS) / price2;
    }

    // Existing functions remain unchanged
    function validateKubContribution(
        uint256 amount,
        uint256 totalRaised,
        uint256 targetRaise
    ) external pure returns (uint256 acceptedAmount) {
        if (amount == 0) revert ZeroAmount();

        uint256 remaining = targetRaise > totalRaised ?
            targetRaise - totalRaised : 0;

        return amount > remaining ? remaining : amount;
    }

    function _calculatePonderCap(uint256 liquidity) internal pure returns (uint256) {
        if (liquidity >= MAX_LIQUIDITY) {
            return MAX_PONDER_PERCENT;
        }

        if (liquidity <= MIN_LIQUIDITY) {
            return MIN_PONDER_PERCENT;
        }

        uint256 range = MAX_LIQUIDITY - MIN_LIQUIDITY;
        uint256 excess = liquidity - MIN_LIQUIDITY;
        uint256 percentRange = MAX_PONDER_PERCENT - MIN_PONDER_PERCENT;

        return MIN_PONDER_PERCENT + (excess * percentRange) / range;
    }

    function _calculatePriceImpact(
        uint256 ponderReserve,
        uint256 kubReserve,
        uint256 ponderAmount
    ) internal pure returns (uint256) {
        uint256 k = ponderReserve * kubReserve;
        uint256 newPonderReserve = ponderReserve + ponderAmount;
        uint256 newKubReserve = k / newPonderReserve;

        uint256 oldPrice = (kubReserve * BASIS_POINTS) / ponderReserve;
        uint256 newPrice = (newKubReserve * BASIS_POINTS) / newPonderReserve;

        return newPrice > oldPrice ?
            ((newPrice - oldPrice) * BASIS_POINTS) / oldPrice :
            ((oldPrice - newPrice) * BASIS_POINTS) / oldPrice;
    }

    function getAcceptablePonderAmount(
        uint256 totalRaise,
        uint256 currentKub,
        uint256 currentPonderValue,
        uint256 maxPonderPercent
    ) external pure returns (uint256) {
        uint256 maxPonderValue = (totalRaise * maxPonderPercent) / BASIS_POINTS;
        uint256 currentTotal = currentKub + currentPonderValue;

        if (currentTotal >= totalRaise) return 0;
        if (currentPonderValue >= maxPonderValue) return 0;

        uint256 remainingPonderValue = maxPonderValue - currentPonderValue;
        uint256 remainingTotal = totalRaise - currentTotal;

        return remainingPonderValue < remainingTotal ?
            remainingPonderValue : remainingTotal;
    }
}
