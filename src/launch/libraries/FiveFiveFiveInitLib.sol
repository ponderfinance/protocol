// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { LaunchToken } from "../LaunchToken.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { FiveFiveFiveConstants } from "./FiveFiveFiveConstants.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";

/// @title FiveFiveFiveInitLib
/// @author taayyohh
/// @notice Library for managing launch initialization
/// @dev Handles token deployment and initial launch setup
library FiveFiveFiveInitLib {
    using FiveFiveFiveConstants for uint256;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes a new launch
    /// @param launch The launch info struct
    /// @param params Launch parameters
    /// @param creator The launch creator address
    /// @param caller The calling contract's address (launcher)
    /// @return token The address of the deployed token
    function initializeLaunch(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.LaunchParams calldata params,
        address creator,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        address caller
    ) external returns (address token) {
        // Validate launch parameters first
        validateLaunchParams(params);

        // Deploy token with correct caller context
        LaunchToken launchToken = new LaunchToken(
            params.name,
            params.symbol,
            caller,  // The launcher contract
            address(factory),
            payable(address(router)),
            address(ponder)
        );
        token = address(launchToken);

        // Initialize base info
        launch.base.tokenAddress = token;
        launch.base.name = params.name;
        launch.base.symbol = params.symbol;
        launch.base.imageURI = params.imageURI;
        launch.base.creator = creator;

        // Calculate and set token allocations
        uint256 totalSupply = launchToken.TOTAL_SUPPLY();
        launch.allocation.tokensForContributors = (totalSupply *
            FiveFiveFiveConstants.CONTRIBUTOR_PERCENT) / FiveFiveFiveConstants.BASIS_POINTS;
        launch.allocation.tokensForLP = (totalSupply *
            FiveFiveFiveConstants.LP_PERCENT) / FiveFiveFiveConstants.BASIS_POINTS;

        // Setup creator vesting
        uint256 creatorTokens = (totalSupply *
            FiveFiveFiveConstants.CREATOR_PERCENT) / FiveFiveFiveConstants.BASIS_POINTS;
        launchToken.setupVesting(creator, creatorTokens);

        // Set deadline
        launch.base.launchDeadline = block.timestamp + FiveFiveFiveConstants.LAUNCH_DURATION;

        // Initialize other states to default values
        launch.base.launched = false;
        launch.base.cancelled = false;
        launch.base.isFinalizingLaunch = false;
        launch.base.lpUnlockTime = 0;

        // Initialize contribution tracking
        launch.contributions.kubCollected = 0;
        launch.contributions.ponderCollected = 0;
        launch.contributions.ponderValueCollected = 0;
        launch.contributions.tokensDistributed = 0;

        // Initialize pool addresses to zero
        launch.pools.memeKubPair = address(0);
        launch.pools.memePonderPair = address(0);

        return token;
    }

    /*//////////////////////////////////////////////////////////////
                            VALIDATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates launch parameters before initialization
    /// @param params The launch parameters to validate
    function validateLaunchParams(
        FiveFiveFiveLauncherTypes.LaunchParams calldata params
    ) public pure {
        // Check for empty parameters
        if(bytes(params.imageURI).length == 0) {
            revert FiveFiveFiveLauncherTypes.ImageRequired();
        }
        if(bytes(params.name).length == 0 || bytes(params.name).length > 32) {
            revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }
        if(bytes(params.symbol).length == 0 || bytes(params.symbol).length > 8) {
            revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }

        // Validate name characters
        bytes memory nameBytes = bytes(params.name);
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

        // Validate symbol characters
        bytes memory symbolBytes = bytes(params.symbol);
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
                            TOKEN SETUP
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates token name and symbol uniqueness
    /// @param name The token name to validate
    /// @param symbol The token symbol to validate
    /// @param usedNames Mapping of used names
    /// @param usedSymbols Mapping of used symbols
    function validateTokenUniqueness(
        string memory name,
        string memory symbol,
        mapping(string => bool) storage usedNames,
        mapping(string => bool) storage usedSymbols
    ) external view {
        if(usedNames[name]) {
            revert FiveFiveFiveLauncherTypes.TokenNameExists();
        }
        if(usedSymbols[symbol]) {
            revert FiveFiveFiveLauncherTypes.TokenSymbolExists();
        }
    }
}
