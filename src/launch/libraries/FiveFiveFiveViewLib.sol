// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { FiveFiveFiveConstants} from "./FiveFiveFiveConstants.sol";

/// @title FiveFiveFiveViewLib
/// @author taayyohh
/// @notice Library for view functions to access launch data
/// @dev Contains all read-only functions to reduce main contract size
library FiveFiveFiveViewLib {
    using FiveFiveFiveConstants for uint256;

    /*//////////////////////////////////////////////////////////////
                        CONTRIBUTOR INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets information about a specific contributor's participation
    /// @param launch The launch info struct
    /// @param contributor Address of the contributor
    /// @return kubContributed Amount of KUB contributed
    /// @return ponderContributed Amount of PONDER contributed
    /// @return ponderValue KUB value of PONDER contribution
    /// @return tokensReceived Amount of tokens received
    function getContributorInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address contributor
    ) external view returns (
        uint256 kubContributed,
        uint256 ponderContributed,
        uint256 ponderValue,
        uint256 tokensReceived
    ) {
        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
        return (
            info.kubContributed,
            info.ponderContributed,
            info.ponderValue,
            info.tokensReceived
        );
    }

    /*//////////////////////////////////////////////////////////////
                        CONTRIBUTION INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets overall contribution information for a launch
    /// @param launch The launch info struct
    /// @return kubCollected Total KUB collected
    /// @return ponderCollected Total PONDER collected
    /// @return ponderValueCollected KUB value of collected PONDER
    /// @return totalValue Total value collected (KUB + PONDER value)
    function getContributionInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view returns (
        uint256 kubCollected,
        uint256 ponderCollected,
        uint256 ponderValueCollected,
        uint256 totalValue
    ) {
        FiveFiveFiveLauncherTypes.ContributionState storage contributions = launch.contributions;
        return (
            contributions.kubCollected,
            contributions.ponderCollected,
            contributions.ponderValueCollected,
            contributions.kubCollected + contributions.ponderValueCollected
        );
    }

    /*//////////////////////////////////////////////////////////////
                            POOL INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets information about a launch's liquidity pools
    /// @param launch The launch info struct
    /// @return memeKubPair Address of token-KUB pair
    /// @return memePonderPair Address of token-PONDER pair
    /// @return hasSecondaryPool Whether PONDER pool exists
    function getPoolInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view returns (
        address memeKubPair,
        address memePonderPair,
        bool hasSecondaryPool
    ) {
        FiveFiveFiveLauncherTypes.PoolInfo storage pools = launch.pools;
        return (
            pools.memeKubPair,
            pools.memePonderPair,
            pools.memePonderPair != address(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                            LAUNCH INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets basic information about a launch
    /// @param launch The launch info struct
    /// @return tokenAddress Address of launched token
    /// @return name Token name
    /// @return symbol Token symbol
    /// @return imageURI Token image URI
    /// @return kubRaised Amount of KUB raised
    /// @return launched Whether launch is complete
    /// @return lpUnlockTime When LP tokens can be withdrawn
    function getLaunchInfo(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view returns (
        address tokenAddress,
        string memory name,
        string memory symbol,
        string memory imageURI,
        uint256 kubRaised,
        bool launched,
        uint256 lpUnlockTime
    ) {
        return (
            launch.base.tokenAddress,
            launch.base.name,
            launch.base.symbol,
            launch.base.imageURI,
            launch.contributions.kubCollected,
            launch.base.launched,
            launch.base.lpUnlockTime
        );
    }

    /*//////////////////////////////////////////////////////////////
                        REQUIREMENTS INFO
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets minimum requirements for contributions and liquidity
    /// @return minKub Minimum KUB contribution
    /// @return minPonder Minimum PONDER contribution
    /// @return minPoolLiquidity Minimum pool liquidity required
    function getMinimumRequirements() external pure returns (
        uint256 minKub,
        uint256 minPonder,
        uint256 minPoolLiquidity
    ) {
        return (
            FiveFiveFiveConstants.MIN_KUB_CONTRIBUTION,
            FiveFiveFiveConstants.MIN_PONDER_CONTRIBUTION,
            FiveFiveFiveConstants.MIN_POOL_LIQUIDITY
        );
    }

    /*//////////////////////////////////////////////////////////////
                        REMAINING FUNDS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates remaining amounts that can be raised
    /// @param launch The launch info struct
    /// @return remainingTotal Total remaining amount that can be raised
    /// @return remainingPonderValue Remaining amount that can be raised in PONDER
    function getRemainingToRaise(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) external view returns (
        uint256 remainingTotal,
        uint256 remainingPonderValue
    ) {
        // Calculate total remaining
        uint256 total = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        uint256 remaining = total >= FiveFiveFiveConstants.TARGET_RAISE ?
            0 : FiveFiveFiveConstants.TARGET_RAISE - total;

        // Calculate remaining PONDER capacity
        uint256 maxPonderValue = (FiveFiveFiveConstants.TARGET_RAISE *
            FiveFiveFiveConstants.MAX_PONDER_PERCENT) /
                        FiveFiveFiveConstants.BASIS_POINTS;
        uint256 currentPonderValue = launch.contributions.ponderValueCollected;
        uint256 remainingPonder = currentPonderValue >= maxPonderValue ?
            0 : maxPonderValue - currentPonderValue;

        // Return minimum of overall remaining and remaining PONDER capacity
        return (remaining, remainingPonder < remaining ? remainingPonder : remaining);
    }
}
