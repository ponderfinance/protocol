// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { FiveFiveFiveConstants } from "./FiveFiveFiveConstants.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { PonderPriceOracle } from "../../core/oracle/PonderPriceOracle.sol";
import { PonderPair } from "../../core/pair/PonderPair.sol";


/// @title FiveFiveFiveValidation
/// @author taayyohh
/// @notice Validation functions for the 555 token launch platform
/// @dev Pure and view functions for common validations
library FiveFiveFiveValidation {
    using FiveFiveFiveConstants for uint256;

    /*//////////////////////////////////////////////////////////////
                        LAUNCH VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates the current launch state
    /// @param launch The launch info struct to validate
    function validateLaunchState(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view {
        if (launch.base.tokenAddress == address(0)) {
            revert FiveFiveFiveLauncherTypes.LaunchNotFound();
        }
        if (launch.base.launched) {
            revert FiveFiveFiveLauncherTypes.AlreadyLaunched();
        }
        if (launch.base.cancelled) {
            revert FiveFiveFiveLauncherTypes.LaunchNotCancellable();
        }
        if (block.timestamp > launch.base.launchDeadline) {
            revert FiveFiveFiveLauncherTypes.LaunchExpired();
        }
        if (launch.base.isFinalizingLaunch) {
            revert FiveFiveFiveLauncherTypes.LaunchBeingFinalized();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates token name and symbol parameters
    /// @param name Token name to validate
    /// @param symbol Token symbol to validate
    /// @param usedNames Mapping of used names
    /// @param usedSymbols Mapping of used symbols
    function validateTokenParams(
        string memory name,
        string memory symbol,
        mapping(string => bool) storage usedNames,
        mapping(string => bool) storage usedSymbols
    ) external view {
        bytes memory nameBytes = bytes(name);
        bytes memory symbolBytes = bytes(symbol);

        // Length checks first
        if(nameBytes.length == 0 || nameBytes.length > 32) {
            revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }
        if(symbolBytes.length == 0 || symbolBytes.length > 8) {
            revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }

        // Uniqueness checks
        if(usedNames[name]) {
            revert FiveFiveFiveLauncherTypes.TokenNameExists();
        }
        if(usedSymbols[symbol]) {
            revert FiveFiveFiveLauncherTypes.TokenSymbolExists();
        }

        // Name character validation
        for(uint256 i = 0; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            if(!(
                (char >= 0x30 && char <= 0x39) || // 0-9
                (char >= 0x41 && char <= 0x5A) || // A-Z
                (char >= 0x61 && char <= 0x7A) || // a-z
                char == 0x20 || // space
                char == 0x2D || // -
                char == 0x5F    // _
            )) {
                revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
            }
        }

        // Symbol character validation
        for(uint256 i = 0; i < symbolBytes.length; i++) {
            bytes1 char = symbolBytes[i];
            if(!(
                (char >= 0x30 && char <= 0x39) || // 0-9
                (char >= 0x41 && char <= 0x5A) || // A-Z
                (char >= 0x61 && char <= 0x7A)    // a-z
            )) {
                revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        CONTRIBUTION VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates KUB contribution parameters
    /// @param launch The launch info struct
    /// @param amount Amount of KUB to contribute
    /// @return newTotal The new total after contribution
    /// @return shouldFinalize Whether the launch should be finalized
    function validateKubContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 amount
    ) external view returns (uint256 newTotal, bool shouldFinalize) {
        // First validate minimum contribution
        if(amount < FiveFiveFiveConstants.MIN_KUB_CONTRIBUTION) {
            revert FiveFiveFiveLauncherTypes.ContributionTooSmall();
        }

        // Calculate new totals
        uint256 currentTotal = launch.contributions.kubCollected +
                            launch.contributions.ponderValueCollected;
        newTotal = currentTotal + amount;

        // Check against target
        if(amount > FiveFiveFiveConstants.TARGET_RAISE - currentTotal) {
            revert FiveFiveFiveLauncherTypes.ExcessiveContribution();
        }

        // Determine if this will complete the raise
        shouldFinalize = (newTotal == FiveFiveFiveConstants.TARGET_RAISE);

        return (newTotal, shouldFinalize);
    }

    /// @notice Validates PONDER contribution parameters
    /// @param launch The launch info struct
    /// @param amount Amount of PONDER to contribute
    /// @param kubValue KUB value of the PONDER amount
    /// @return shouldFinalize Whether the launch should be finalized
    function validatePonderContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 amount,
        uint256 kubValue
    ) external view returns (bool shouldFinalize) {
        // Check minimum contribution
        if(amount < FiveFiveFiveConstants.MIN_PONDER_CONTRIBUTION) {
            revert FiveFiveFiveLauncherTypes.ContributionTooSmall();
        }

        // Check against PONDER cap
        uint256 totalPonderValue = launch.contributions.ponderValueCollected + kubValue;
        uint256 maxPonderValue = (FiveFiveFiveConstants.TARGET_RAISE *
            FiveFiveFiveConstants.MAX_PONDER_PERCENT) /
                        FiveFiveFiveConstants.BASIS_POINTS;

        if (totalPonderValue > maxPonderValue) {
            revert FiveFiveFiveLauncherTypes.ExcessivePonderContribution();
        }

        // Check against remaining needed
        uint256 remaining = FiveFiveFiveConstants.TARGET_RAISE -
            (launch.contributions.kubCollected +
                launch.contributions.ponderValueCollected);

        if (kubValue > remaining) {
            revert FiveFiveFiveLauncherTypes.ExcessiveContribution();
        }

        // Check if this will complete the raise
        shouldFinalize = (launch.contributions.kubCollected +
        totalPonderValue == FiveFiveFiveConstants.TARGET_RAISE);

        return shouldFinalize;
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates PONDER price data from oracle
    /// @param ponderKubPair The PONDER-KUB pair address
    /// @param priceOracle The price oracle contract
    /// @param ponder PONDER token address
    /// @param amount Amount of PONDER to check
    /// @return spotPrice The current valid spot price
    function validatePonderPrice(
        address ponderKubPair,
        PonderPriceOracle priceOracle,
        address ponder,
        uint256 amount
    ) external view returns (uint256 spotPrice) {
        (, , uint32 lastUpdateTime) = PonderPair(ponderKubPair).getReserves();

        // Check price staleness
        if (block.timestamp - lastUpdateTime >
            FiveFiveFiveConstants.PRICE_STALENESS_THRESHOLD) {
            revert FiveFiveFiveLauncherTypes.StalePrice();
        }

        // Get spot price
        spotPrice = priceOracle.getCurrentPrice(
            ponderKubPair,
            ponder,
            amount
        );

        // Get TWAP for manipulation check
        uint256 twapPrice = priceOracle.consult(
            ponderKubPair,
            ponder,
            amount,
            1 hours
        );

        if (twapPrice == 0) {
            revert FiveFiveFiveLauncherTypes.InsufficientPriceHistory();
        }

        // Verify price is within acceptable bounds
        uint256 maxDeviation = (twapPrice * 110) / 100; // 10% max deviation
        uint256 minDeviation = (twapPrice * 90) / 100;  // 10% min deviation

        if (spotPrice > maxDeviation || spotPrice < minDeviation) {
            revert FiveFiveFiveLauncherTypes.ExcessivePriceDeviation();
        }

        return spotPrice;
    }
}
