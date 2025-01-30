// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { LaunchToken } from "../LaunchToken.sol";
import { LaunchTokenTypes } from "../types/LaunchTokenTypes.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { PonderPriceOracle } from "../../core/oracle/PonderPriceOracle.sol";
import { PonderPair } from "../../core/pair/PonderPair.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";

/// @title SetupLib
/// @author taayyohh
/// @notice Library for launch initialization and validation
/// @dev Combines initialization and validation logic with optimized storage access
library SetupLib {
    using FiveFiveFiveLauncherTypes for FiveFiveFiveLauncherTypes.LaunchInfo;

    /// @notice Initializes a new token launch with validated parameters
    /// @dev Storage optimized initialization with packed values
    function initializeLaunch(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.LaunchParams calldata params,
        address creator,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        address caller
    ) external returns (address token) {
        // Create token
        LaunchToken launchToken = new LaunchToken(
            params.name,
            params.symbol,
            caller,
            address(factory),
            payable(address(router)),
            address(ponder)
        );
        token = address(launchToken);

        // Pack base info into minimal storage writes
        _setBaseInfo(launch, token, params, creator);

        // Pack allocation values and set in single write
        _setAllocations(launch, launchToken, creator);

        // Initialize state with packed values
        _initializeState(launch);

        return token;
    }

    /// @notice Validates token parameters and checks for uniqueness
    /// @dev Uses calldata for string params to save gas
    function validateTokenParams(
        string calldata name,
        string calldata symbol,
        mapping(string => bool) storage usedNames,
        mapping(string => bool) storage usedSymbols
    ) external view {
        bytes memory nameBytes = bytes(name);
        bytes memory symbolBytes = bytes(symbol);

        if(nameBytes.length == 0 || nameBytes.length > 32) {
            revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }
        if(symbolBytes.length == 0 || symbolBytes.length > 8) {
            revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
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

        if(usedNames[name]) revert FiveFiveFiveLauncherTypes.TokenNameExists();
        if(usedSymbols[symbol]) revert FiveFiveFiveLauncherTypes.TokenSymbolExists();
    }

    /// @notice Validates PONDER price data from oracle
    /// @dev Checks price staleness and deviation from TWAP
    function validatePonderPrice(
        address ponderKubPair,
        PonderPriceOracle priceOracle,
        address ponder,
        uint256 amount
    ) external view returns (uint256 spotPrice) {
        // Only need lastUpdateTime from getReserves for staleness check
        (, , uint32 lastUpdateTime) = PonderPair(ponderKubPair).getReserves();

        if (block.timestamp - lastUpdateTime > FiveFiveFiveLauncherTypes.PRICE_STALENESS_THRESHOLD) {
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
        uint256 maxDeviation = (twapPrice * 110) / 100;
        uint256 minDeviation = (twapPrice * 90) / 100;

        if (spotPrice > maxDeviation || spotPrice < minDeviation) {
            revert FiveFiveFiveLauncherTypes.ExcessivePriceDeviation();
        }

        return spotPrice;
    }

    /// @notice Validates the current launch state
    /// @dev Uses packed boolean checks
    function validateLaunchState(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view {
        if (launch.base.tokenAddress == address(0)) revert FiveFiveFiveLauncherTypes.LaunchNotFound();
        if (launch.base.launched) revert FiveFiveFiveLauncherTypes.AlreadyLaunched();
        if (block.timestamp > launch.base.launchDeadline) revert FiveFiveFiveLauncherTypes.LaunchDeadlinePassed();
        if (launch.base.isFinalizingLaunch) revert FiveFiveFiveLauncherTypes.LaunchBeingFinalized();
    }

    /// @dev Sets base info with optimized storage packing
    function _setBaseInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address token,
        FiveFiveFiveLauncherTypes.LaunchParams calldata params,
        address creator
    ) private {
        // Pack addresses into first slot
        launch.base.tokenAddress = token;
        launch.base.creator = creator;

        // Pack timestamps into uint40s in second slot
        launch.base.launchDeadline = uint40(block.timestamp + FiveFiveFiveLauncherTypes.LAUNCH_DURATION);
        launch.base.lpUnlockTime = 0;

        // Pack booleans together in same slot
        launch.base.launched = false;
        launch.base.cancelled = false;
        launch.base.isFinalizingLaunch = false;

        // Set strings in separate slots (no packing possible)
        launch.base.name = params.name;
        launch.base.symbol = params.symbol;
        launch.base.imageURI = params.imageURI;
    }

    /// @dev Sets allocations with proper uint256 calculations and uint128 casting
    function _setAllocations(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        LaunchToken launchToken,
        address creator
    ) private {
        uint256 totalSupply = LaunchTokenTypes.TOTAL_SUPPLY;

        // Calculate allocations using uint256 for precision, then safely cast to uint128
        uint256 contributorTokens = (totalSupply * FiveFiveFiveLauncherTypes.CONTRIBUTOR_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;
        uint256 lpTokens = (totalSupply * FiveFiveFiveLauncherTypes.LP_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;

        // Verify the values fit in uint128 before casting
        require(contributorTokens <= type(uint128).max, "Contributor tokens overflow");
        require(lpTokens <= type(uint128).max, "LP tokens overflow");

        // Set the packed values
        launch.allocation.tokensForContributors = uint128(contributorTokens);
        launch.allocation.tokensForLP = uint128(lpTokens);

        // Calculate creator allocation
        uint256 creatorTokens = (totalSupply * FiveFiveFiveLauncherTypes.CREATOR_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;
        launchToken.setupVesting(creator, creatorTokens);
    }

    /// @dev Initializes state with packed values and minimal storage writes
    function _initializeState(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) private {
        // Clear contributions in single write with zero values
        launch.contributions.kubCollected = 0;
        launch.contributions.ponderCollected = 0;
        launch.contributions.ponderValueCollected = 0;
        launch.contributions.tokensDistributed = 0;

        // Clear pool addresses in single write
        launch.pools.memeKubPair = address(0);
        launch.pools.memePonderPair = address(0);
    }
}
