// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IPonderPair } from "../../core/pair/IPonderPair.sol";
import { IPonderPriceOracle } from "../../core/oracle/IPonderPriceOracle.sol";

library PonderLaunchGuard {
    // Existing constants
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_LIQUIDITY = 1000 ether;
    uint256 public constant MAX_LIQUIDITY = 5000 ether;
    uint256 public constant MIN_PONDER_PERCENT = 500;   // 5%
    uint256 public constant MAX_PONDER_PERCENT = 2000;  // 20%
    uint256 public constant MAX_PRICE_IMPACT = 500;     // 5%
    uint256 public constant TWAP_PERIOD = 30 minutes;
    uint256 public constant SPOT_TWAP_DEVIATION_LIMIT = 300; // 3% max deviation between spot and TWAP
    uint256 public constant PRICE_CHECK_PERIOD = 5 minutes;
    uint256 public constant RESERVE_CHANGE_LIMIT = 2000; // 20% max reserve change in PRICE_CHECK_PERIOD
    uint256 public constant MIN_OBSERVATION_COUNT = 3;  // Minimum required observations
    uint256 public constant MAX_RESERVE_IMBALANCE = 9500;    // 95%
    uint256 public constant MIN_RESERVE_IMBALANCE = 500;     // 5%
    uint256 public constant MIN_KUB_CONTRIBUTION = 0.01 ether;  // Minimum KUB contribution
    uint256 public constant MAX_INDIVIDUAL_CAP = 1000 ether;    // Maximum individual contribution

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

    struct ContributionResult {
        uint256 acceptedAmount;     // Amount accepted for this contribution
        uint256 remainingAllowed;   // Remaining amount that can be raised
        bool targetReached;         // Whether target has been reached
    }


    error InsufficientLiquidity();
    error ExcessivePriceImpact();
    error InvalidPrice();
    error InvalidTotalRaised();
    error TargetReached();
    error ExcessivePriceDeviation();
    error StalePrice();
    error SuddenReserveChange();
    error ContributionTooSmall();
    error ContributionTooLarge();
    error ZeroAmount();
    error StaleOracle();
    error InsufficientHistory();
    error ReserveImbalance();

    function validatePonderContribution(
        address pair,
        address oracle,
        uint256 amount
    ) external view returns (ValidationResult memory result) {
        if (amount == 0) revert ZeroAmount();

        // Get current price state including TWAP
        PriceState memory priceState = _getPriceState(pair, oracle);

        // Verify reserves meet minimum liquidity first
        uint256 totalLiquidity = uint256(priceState.reserve0) * priceState.reserve1;
        if (totalLiquidity < MIN_LIQUIDITY) revert InsufficientLiquidity();

        // Calculate KUB value using spot price
        result.kubValue = priceState.spotPrice * amount / 1e18;
        if (result.kubValue == 0) revert InvalidPrice();

        // Check price impact after liquidity validation
        result.priceImpact = _calculatePriceImpact(
            priceState.reserve1, // ponder reserve
            priceState.reserve0, // kub reserve
            amount
        );
        if (result.priceImpact > MAX_PRICE_IMPACT) revert ExcessivePriceImpact();

        // Check reserve imbalance
        uint256 ratio;
        if (priceState.reserve0 >= priceState.reserve1) {
            ratio = (uint256(priceState.reserve0) * BASIS_POINTS) /
                (uint256(priceState.reserve0) + uint256(priceState.reserve1));
        } else {
            ratio = (uint256(priceState.reserve1) * BASIS_POINTS) /
                (uint256(priceState.reserve0) + uint256(priceState.reserve1));
        }
        if (ratio > MAX_RESERVE_IMBALANCE || ratio < MIN_RESERVE_IMBALANCE) {
            revert ReserveImbalance();
        }

        // Compare spot price to TWAP to detect manipulation
        if (priceState.twapPrice > 0) {  // Only check if TWAP is available
            uint256 priceDeviation = _calculateDeviation(
                priceState.spotPrice,
                priceState.twapPrice
            );
            if (priceDeviation > SPOT_TWAP_DEVIATION_LIMIT) {
                revert ExcessivePriceDeviation();
            }
        }

        // Lock to fixed maximum percentage
        result.maxPonderPercent = MAX_PONDER_PERCENT;

        return result;
    }

    function _getPriceState(
        address pair,
        address oracle
    ) internal view returns (PriceState memory state) {
        // Get current reserves and timestamp
        (state.reserve0, state.reserve1, state.timestamp) = IPonderPair(pair).getReserves();

        // Get current spot price
        state.spotPrice = IPonderPriceOracle(oracle).getCurrentPrice(
            pair,
            IPonderPair(pair).token0(),
            1e18
        );

        // Try to get TWAP price for configured period
        try IPonderPriceOracle(oracle).consult(
            pair,
            IPonderPair(pair).token0(),
            1e18,
            uint32(TWAP_PERIOD)
        ) returns (uint256 twapPrice) {
            state.twapPrice = twapPrice;
        } catch {
            // If TWAP fails (e.g., insufficient history), leave as 0
            state.twapPrice = 0;
        }

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
    /**
    * @notice Validates and calculates accepted KUB contribution amount
     * @param amount Amount of KUB being contributed
     * @param totalRaised Total amount already raised
     * @param targetRaise Target amount to raise
     * @param contributorTotal Total amount already contributed by this contributor
     * @return result ContributionResult struct containing validation results
     */
    function validateKubContribution(
        uint256 amount,
        uint256 totalRaised,
        uint256 targetRaise,
        uint256 contributorTotal
    ) external pure returns (ContributionResult memory result) {
        // Input validation
        if (amount < MIN_KUB_CONTRIBUTION) revert ContributionTooSmall();
        if (amount > MAX_INDIVIDUAL_CAP) revert ContributionTooLarge();
        if (totalRaised > targetRaise) revert InvalidTotalRaised();
        if (totalRaised == targetRaise) revert TargetReached();

        // Calculate remaining allowed for this contributor
        uint256 remainingIndividual = MAX_INDIVIDUAL_CAP > contributorTotal ?
            MAX_INDIVIDUAL_CAP - contributorTotal : 0;

        // Calculate remaining until target
        uint256 remainingTotal = targetRaise - totalRaised;

        // Calculate accepted amount (minimum of all constraints)
        result.acceptedAmount = amount;
        if (result.acceptedAmount > remainingIndividual) {
            result.acceptedAmount = remainingIndividual;
        }
        if (result.acceptedAmount > remainingTotal) {
            result.acceptedAmount = remainingTotal;
        }

        // Set remaining allowed
        result.remainingAllowed = remainingTotal - result.acceptedAmount;

        // Check if target will be reached
        result.targetReached = (totalRaised + result.acceptedAmount) == targetRaise;

        return result;
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
        if (ponderReserve == 0 || kubReserve == 0) return type(uint256).max;

        uint256 k = ponderReserve * kubReserve;
        uint256 newPonderReserve = ponderReserve + ponderAmount;
        uint256 newKubReserve = k / newPonderReserve;

        uint256 oldPrice = (kubReserve * BASIS_POINTS) / ponderReserve;
        uint256 newPrice = (newKubReserve * BASIS_POINTS) / newPonderReserve;

        return oldPrice > newPrice ?
            ((oldPrice - newPrice) * BASIS_POINTS) / oldPrice :
            ((newPrice - oldPrice) * BASIS_POINTS) / oldPrice;
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
