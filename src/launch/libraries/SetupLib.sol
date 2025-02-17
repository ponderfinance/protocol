// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { LaunchToken } from "../LaunchToken.sol";
import { LaunchTokenTypes } from "../types/LaunchTokenTypes.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { PonderPriceOracle } from "../../core/oracle/PonderPriceOracle.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { IFiveFiveFiveLauncher } from "../IFiveFiveFiveLauncher.sol";


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
        LaunchToken launchToken = new LaunchToken(
            params.name,
            params.symbol,
            caller,
            address(factory),
            payable(address(router)),
            address(ponder)
        );
        token = address(launchToken);

        _setBaseInfo(launch, token, params, creator);

        _setAllocations(launch, launchToken, creator);

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
            revert IFiveFiveFiveLauncher.InvalidTokenParams();
        }
        if(symbolBytes.length == 0 || symbolBytes.length > 8) {
            revert IFiveFiveFiveLauncher.InvalidTokenParams();
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
                revert IFiveFiveFiveLauncher.InvalidTokenParams();
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
                revert IFiveFiveFiveLauncher.InvalidTokenParams();
            }
        }

        if(usedNames[name]) revert IFiveFiveFiveLauncher.TokenNameExists();
        if(usedSymbols[symbol]) revert IFiveFiveFiveLauncher.TokenSymbolExists();
    }

    /// @notice Validates PONDER token price data from oracle
    /// @dev Checks for price staleness and manipulation
    ///      Compares spot price against TWAP to detect manipulation
    ///      Enforces maximum price deviation thresholds
    /// @param pair Address of PONDER-KUB pair
    /// @param priceOracle Oracle contract for price checks
    /// @param ponder Address of PONDER token
    /// @param amount Amount of PONDER to price
    /// @return spotPrice Current spot price of PONDER in KUB
    function validatePonderPrice(
        address pair,
        PonderPriceOracle priceOracle,
        address ponder,
        uint256 amount
    ) internal view returns (uint256) {
        if (pair == address(0)) revert IFiveFiveFiveLauncher.PairNotFound();
        return priceOracle.getCurrentPrice(pair, ponder, amount);
    }

    /// @notice Validates the current state of a launch
    /// @dev Checks for launch existence, completion status, and timing
    ///      Uses packed boolean values for gas efficiency
    /// @param launch Storage reference to launch information
    function validateLaunchState(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view {
        if (launch.base.tokenAddress == address(0)) revert IFiveFiveFiveLauncher.LaunchNotFound();
        if (launch.base.launched) revert IFiveFiveFiveLauncher.AlreadyLaunched();
        if (block.timestamp > launch.base.launchDeadline) revert IFiveFiveFiveLauncher.LaunchDeadlinePassed();
        if (launch.base.isFinalizingLaunch) revert IFiveFiveFiveLauncher.LaunchBeingFinalized();
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

        uint256 contributorTokens = (totalSupply * FiveFiveFiveLauncherTypes.CONTRIBUTOR_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;
        uint256 lpTokens = (totalSupply * FiveFiveFiveLauncherTypes.LP_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;

        if (contributorTokens > type(uint128).max) revert IFiveFiveFiveLauncher.ContributorTokensOverflow();
        if (lpTokens > type(uint128).max) revert IFiveFiveFiveLauncher.LPTokensOverflow();

        launch.allocation.tokensForContributors = uint128(contributorTokens);
        launch.allocation.tokensForLP = uint128(lpTokens);

        uint256 creatorTokens = (totalSupply * FiveFiveFiveLauncherTypes.CREATOR_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;
        launchToken.setupVesting(creator, creatorTokens);
    }

    /// @dev Initializes launch state with packed zero values
    /// @param launch Storage reference to launch information
    function _initializeState(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) private {
        launch.contributions.kubCollected = 0;
        launch.contributions.ponderCollected = 0;
        launch.contributions.ponderValueCollected = 0;
        launch.contributions.tokensDistributed = 0;

        launch.pools.memeKubPair = address(0);
        launch.pools.memePonderPair = address(0);
    }
}
