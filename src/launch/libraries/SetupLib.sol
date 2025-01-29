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
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant LAUNCH_DURATION = 7 days;
    uint256 private constant PRICE_STALENESS_THRESHOLD = 2 hours;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant CREATOR_PERCENT = 1000;      // 10%
    uint256 private constant LP_PERCENT = 2000;           // 20%
    uint256 private constant CONTRIBUTOR_PERCENT = 7000;  // 70%

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error LaunchNotFound();
    error AlreadyLaunched();
    error ImageRequired();
    error InvalidTokenParams();
    error TokenNameExists();
    error TokenSymbolExists();
    error LaunchDeadlinePassed();
    error LaunchBeingFinalized();
    error StalePrice();
    error ExcessivePriceDeviation();
    error InsufficientPriceHistory();

    /*//////////////////////////////////////////////////////////////
                        LAUNCH INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes a new token launch with validated parameters
    /// @dev Combines previous initializeLaunch with inline validation
    function initializeLaunch(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.LaunchParams calldata params,
        address creator,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        address caller
    ) external returns (address token) {
        // Create token with optimized parameters
        LaunchToken launchToken = new LaunchToken(
            params.name,
            params.symbol,
            caller,
            address(factory),
            payable(address(router)),
            address(ponder)
        );
        token = address(launchToken);

        // Set base info with single storage write
        _setBaseInfo(launch, token, params, creator);

        // Calculate and set allocations
        _setAllocations(launch, launchToken, creator);

        // Initialize contribution tracking with minimal storage operations
        _initializeState(launch);

        return token;
    }

    /// @notice Validates token parameters and checks for uniqueness
    /// @dev Validates name and symbol format and uniqueness
    function validateTokenParams(
        string memory name,
        string memory symbol,
        mapping(string => bool) storage usedNames,
        mapping(string => bool) storage usedSymbols
    ) external view {
        // Check image URI
        bytes memory nameBytes = bytes(name);
        bytes memory symbolBytes = bytes(symbol);

        // Length checks first
        if(nameBytes.length == 0 || nameBytes.length > 32) {
            revert InvalidTokenParams();
        }
        if(symbolBytes.length == 0 || symbolBytes.length > 8) {
            revert InvalidTokenParams();
        }

        // Uniqueness checks
        if(usedNames[name]) {
            revert TokenNameExists();
        }
        if(usedSymbols[symbol]) {
            revert TokenSymbolExists();
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
                revert InvalidTokenParams();
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
                revert InvalidTokenParams();
            }
        }
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

        // Check price staleness
        if (block.timestamp - lastUpdateTime > PRICE_STALENESS_THRESHOLD) {
            revert StalePrice();
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
            revert InsufficientPriceHistory();
        }

        // Verify price is within acceptable bounds
        uint256 maxDeviation = (twapPrice * 110) / 100; // 10% max deviation
        uint256 minDeviation = (twapPrice * 90) / 100;  // 10% min deviation

        if (spotPrice > maxDeviation || spotPrice < minDeviation) {
            revert ExcessivePriceDeviation();
        }

        return spotPrice;
    }

    /// @notice Validates the current launch state
    /// @dev Checks for active, non-expired launch
    function validateLaunchState(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view {
        if (launch.base.tokenAddress == address(0)) revert LaunchNotFound();
        if (launch.base.launched) revert AlreadyLaunched();
        if (block.timestamp > launch.base.launchDeadline) revert LaunchDeadlinePassed();
        if (launch.base.isFinalizingLaunch) revert LaunchBeingFinalized();
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sets base launch information with optimized storage access
    function _setBaseInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address token,
        FiveFiveFiveLauncherTypes.LaunchParams calldata params,
        address creator
    ) private {
        launch.base.tokenAddress = token;
        launch.base.name = params.name;
        launch.base.symbol = params.symbol;
        launch.base.imageURI = params.imageURI;
        launch.base.creator = creator;
        launch.base.launchDeadline = block.timestamp + LAUNCH_DURATION;
    }

    /// @dev Sets token allocations with optimized calculations
    function _setAllocations(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        LaunchToken launchToken,
        address creator
    ) private {
        uint256 totalSupply = LaunchTokenTypes.TOTAL_SUPPLY;

        // Calculate allocations using constants
        launch.allocation.tokensForContributors = (totalSupply * CONTRIBUTOR_PERCENT) / BASIS_POINTS;
        launch.allocation.tokensForLP = (totalSupply * LP_PERCENT) / BASIS_POINTS;

        // Set creator allocation
        uint256 creatorTokens = (totalSupply * CREATOR_PERCENT) / BASIS_POINTS;
        launchToken.setupVesting(creator, creatorTokens);
    }

    /// @dev Initializes launch state with minimal storage operations
    function _initializeState(FiveFiveFiveLauncherTypes.LaunchInfo storage launch) private {
        // Single storage write for base flags
        launch.base.launched = false;
        launch.base.cancelled = false;
        launch.base.isFinalizingLaunch = false;
        launch.base.lpUnlockTime = 0;

        // Single storage write for contributions
        launch.contributions.kubCollected = 0;
        launch.contributions.ponderCollected = 0;
        launch.contributions.ponderValueCollected = 0;
        launch.contributions.tokensDistributed = 0;

        // Single storage write for pool addresses
        launch.pools.memeKubPair = address(0);
        launch.pools.memePonderPair = address(0);
    }
}
