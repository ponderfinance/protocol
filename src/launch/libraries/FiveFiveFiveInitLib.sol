// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { LaunchToken } from "../LaunchToken.sol";
import { LaunchTokenTypes } from "../types/LaunchTokenTypes.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { FiveFiveFiveConstants } from "./FiveFiveFiveConstants.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";

library FiveFiveFiveInitLib {
    using FiveFiveFiveConstants for uint256;

    function initializeLaunch(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.LaunchParams calldata params,
        address creator,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        address caller
    ) external returns (address token) {
        validateLaunchParams(params);

        LaunchToken launchToken = new LaunchToken(
            params.name,
            params.symbol,
            caller,
            address(factory),
            payable(address(router)),
            address(ponder)
        );
        token = address(launchToken);

        // Set base info
        launch.base.tokenAddress = token;
        launch.base.name = params.name;
        launch.base.symbol = params.symbol;
        launch.base.imageURI = params.imageURI;
        launch.base.creator = creator;
        launch.base.launchDeadline = block.timestamp + FiveFiveFiveConstants.LAUNCH_DURATION;

        // Calculate allocations
        uint256 totalSupply = LaunchTokenTypes.TOTAL_SUPPLY;
        _setAllocations(launch, launchToken, totalSupply, creator);

        // Initialize contribution tracking
        _initializeContributions(launch);

        return token;
    }

    function validateLaunchParams(
        FiveFiveFiveLauncherTypes.LaunchParams calldata params
    ) internal pure {
        if(bytes(params.imageURI).length == 0) revert FiveFiveFiveLauncherTypes.ImageRequired();
        if(!_isValidLength(params.name, params.symbol)) revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        if(!_isValidString(params.name, true)) revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        if(!_isValidString(params.symbol, false)) revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
    }

    function _isValidLength(string memory name, string memory symbol) internal pure returns (bool) {
        return bytes(name).length > 0 &&
        bytes(name).length <= 32 &&
        bytes(symbol).length > 0 &&
            bytes(symbol).length <= 8;
    }

    function _isValidString(string memory str, bool allowSpaces) internal pure returns (bool) {
        bytes memory b = bytes(str);
        for(uint256 i; i < b.length; i++) {
            bytes1 char = b[i];
            if(
                !(char >= 0x30 && char <= 0x39) && // 0-9
            !(char >= 0x41 && char <= 0x5A) && // A-Z
            !(char >= 0x61 && char <= 0x7A) && // a-z
            !(allowSpaces && (char == 0x20 || char == 0x2D || char == 0x5F)) // space, -, _
            ) return false;
        }
        return true;
    }

    function _setAllocations(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        LaunchToken launchToken,
        uint256 totalSupply,
        address creator
    ) internal {
        launch.allocation.tokensForContributors = (totalSupply *
            FiveFiveFiveConstants.CONTRIBUTOR_PERCENT) / FiveFiveFiveConstants.BASIS_POINTS;
        launch.allocation.tokensForLP = (totalSupply *
            FiveFiveFiveConstants.LP_PERCENT) / FiveFiveFiveConstants.BASIS_POINTS;

        uint256 creatorTokens = (totalSupply *
            FiveFiveFiveConstants.CREATOR_PERCENT) / FiveFiveFiveConstants.BASIS_POINTS;
        launchToken.setupVesting(creator, creatorTokens);
    }

    function _initializeContributions(FiveFiveFiveLauncherTypes.LaunchInfo storage launch) internal {
        launch.base.launched = false;
        launch.base.cancelled = false;
        launch.base.isFinalizingLaunch = false;
        launch.base.lpUnlockTime = 0;

        launch.contributions.kubCollected = 0;
        launch.contributions.ponderCollected = 0;
        launch.contributions.ponderValueCollected = 0;
        launch.contributions.tokensDistributed = 0;

        launch.pools.memeKubPair = address(0);
        launch.pools.memePonderPair = address(0);
    }

    function validateTokenUniqueness(
        string memory name,
        string memory symbol,
        mapping(string => bool) storage usedNames,
        mapping(string => bool) storage usedSymbols
    ) external view {
        if(usedNames[name]) revert FiveFiveFiveLauncherTypes.TokenNameExists();
        if(usedSymbols[symbol]) revert FiveFiveFiveLauncherTypes.TokenSymbolExists();
    }
}
