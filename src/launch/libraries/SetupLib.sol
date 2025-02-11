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


/*//////////////////////////////////////////////////////////////
                    LAUNCH SETUP AND VALIDATION
//////////////////////////////////////////////////////////////*/

/// @title SetupLib
/// @author taayyohh
/// @notice Library for initializing and validating token launches
/// @dev Implements gas-optimized storage patterns and comprehensive validation checks
///      Uses custom errors instead of require statements for gas efficiency
library SetupLib {
    using FiveFiveFiveLauncherTypes for FiveFiveFiveLauncherTypes.LaunchInfo;

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
     //////////////////////////////////////////////////////////////*/

    /// @notice Initializes a new token launch with validated parameters
    /// @dev Creates token contract and sets up initial state with optimized storage
    ///      Uses packed storage values to minimize gas costs
    ///      Sets up vesting schedule for creator allocation
    /// @param launch Storage reference to launch information
    /// @param params Struct containing launch parameters
    /// @param creator Address of the launch creator
    /// @param factory Interface for DEX factory
    /// @param router Interface for DEX router
    /// @param ponder PONDER token contract
    /// @param caller Address initiating the launch
    /// @return token Address of the newly created token contract
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

    /// @notice Validates token name and symbol parameters
    /// @dev Performs character-by-character validation using calldata
    ///      Checks for uniqueness against existing names and symbols
    ///      Enforces length and character set restrictions
    /// @param name Proposed token name
    /// @param symbol Proposed token symbol
    /// @param usedNames Mapping of previously used names
    /// @param usedSymbols Mapping of previously used symbols
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

    /// @notice Validates PONDER token price data from oracle
    /// @dev Checks for price staleness and manipulation
    ///      Compares spot price against TWAP to detect manipulation
    ///      Enforces maximum price deviation thresholds
    /// @param ponderKubPair Address of PONDER-KUB pair
    /// @param priceOracle Oracle contract for price checks
    /// @param ponder Address of PONDER token
    /// @param amount Amount of PONDER to price
    /// @return spotPrice Current spot price of PONDER in KUB
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

    /// @notice Validates the current state of a launch
    /// @dev Checks for launch existence, completion status, and timing
    ///      Uses packed boolean values for gas efficiency
    /// @param launch Storage reference to launch information
    function validateLaunchState(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view {
        if (launch.base.tokenAddress == address(0)) revert FiveFiveFiveLauncherTypes.LaunchNotFound();
        if (launch.base.launched) revert FiveFiveFiveLauncherTypes.AlreadyLaunched();
        if (block.timestamp > launch.base.launchDeadline) revert FiveFiveFiveLauncherTypes.LaunchDeadlinePassed();
        if (launch.base.isFinalizingLaunch) revert FiveFiveFiveLauncherTypes.LaunchBeingFinalized();
    }

    /*//////////////////////////////////////////////////////////////
                        PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sets base launch information with optimized storage packing
    /// @param launch Storage reference to launch information
    /// @param token Address of the launched token
    /// @param params Launch parameters struct
    /// @param creator Address of launch creator
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

    /// @dev Sets token allocations with safe uint256 calculations
    /// @param launch Storage reference to launch information
    /// @param launchToken Reference to launched token contract
    /// @param creator Address of launch creator
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

        // Instead of require() with a string, we use custom errors
        if (contributorTokens > type(uint128).max) revert FiveFiveFiveLauncherTypes.ContributorTokensOverflow();
        if (lpTokens > type(uint128).max) revert FiveFiveFiveLauncherTypes.LPTokensOverflow();

        // Set the packed values
        launch.allocation.tokensForContributors = uint128(contributorTokens);
        launch.allocation.tokensForLP = uint128(lpTokens);

        // Calculate creator allocation
        uint256 creatorTokens = (totalSupply * FiveFiveFiveLauncherTypes.CREATOR_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;
        launchToken.setupVesting(creator, creatorTokens);
    }

    /// @dev Initializes launch state with packed zero values
    /// @param launch Storage reference to launch information
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
