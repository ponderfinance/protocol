// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../types/FiveFiveFiveLauncherTypes.sol";
import "./FiveFiveFiveConstants.sol";
import "./FiveFiveFiveValidation.sol";
import "../LaunchToken.sol";
import "../../core/token/PonderToken.sol";

/// @title FiveFiveFiveContributionLib
/// @author taayyohh
/// @notice Library for managing contributions to token launches
/// @dev Handles KUB and PONDER contributions and calculation logic
library FiveFiveFiveContributionLib {
    using FiveFiveFiveConstants for uint256;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokensDistributed(
        uint256 indexed launchId,
        address indexed recipient,
        uint256 amount
    );

    event KUBContributed(
        uint256 indexed launchId,
        address contributor,
        uint256 amount
    );

    event PonderContributed(
        uint256 indexed launchId,
        address contributor,
        uint256 amount,
        uint256 kubValue
    );

    /*//////////////////////////////////////////////////////////////
                        KUB CONTRIBUTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes KUB contribution for a launch
    /// @param launch The launch info struct
    /// @param launchId The launch ID
    /// @param amount Amount of KUB being contributed
    /// @param contributor Address of the contributor
    /// @return shouldFinalize Whether the launch should be finalized
    function processKubContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        uint256 amount,
        address contributor
    ) external returns (bool shouldFinalize) {
        // Validate contribution first
        (uint256 newTotal, bool shouldFin) = FiveFiveFiveValidation.validateKubContribution(
            launch,
            amount
        );

        // Calculate token distribution
        uint256 tokensToDistribute = (amount * launch.allocation.tokensForContributors) /
                        FiveFiveFiveConstants.TARGET_RAISE;

        // Update launch state
        launch.contributions.kubCollected += amount;
        launch.contributions.tokensDistributed += tokensToDistribute;

        // Update contributor state
        FiveFiveFiveLauncherTypes.ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.kubContributed += amount;
        contributorInfo.tokensReceived += tokensToDistribute;

        // Transfer tokens
        LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute);

        // Emit events
        emit TokensDistributed(launchId, contributor, tokensToDistribute);
        emit KUBContributed(launchId, contributor, amount);

        return shouldFin;
    }

    /*//////////////////////////////////////////////////////////////
                        PONDER CONTRIBUTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes PONDER contribution for a launch
    /// @param launch The launch info struct
    /// @param launchId The launch ID
    /// @param amount Amount of PONDER being contributed
    /// @param kubValue KUB value of PONDER contribution
    /// @param contributor Address of the contributor
    /// @param ponder PONDER token contract
    /// @return shouldFinalize Whether the launch should be finalized
    function processPonderContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        uint256 amount,
        uint256 kubValue,
        address contributor,
        PonderToken ponder
    ) external returns (bool shouldFinalize) {
        // Initial validation
        shouldFinalize = FiveFiveFiveValidation.validatePonderContribution(
            launch,
            amount,
            kubValue
        );

        // Calculate token distribution
        uint256 tokensToDistribute = (kubValue * launch.allocation.tokensForContributors) /
                        FiveFiveFiveConstants.TARGET_RAISE;

        // Transfer PONDER first
        ponder.transferFrom(contributor, address(this), amount);

        // Update launch state AFTER transfer
        launch.contributions.ponderCollected += amount;
        launch.contributions.ponderValueCollected += kubValue;
        launch.contributions.tokensDistributed += tokensToDistribute;

        // Update contributor info
        FiveFiveFiveLauncherTypes.ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.ponderContributed += amount;
        contributorInfo.ponderValue += kubValue;
        contributorInfo.tokensReceived += tokensToDistribute;

        // Transfer tokens
        LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute);

        // Emit events
        emit TokensDistributed(launchId, contributor, tokensToDistribute);
        emit PonderContributed(launchId, contributor, amount, kubValue);

        return shouldFinalize;
    }

    /*//////////////////////////////////////////////////////////////
                        CONTRIBUTION UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates contribution amounts and distributions
    /// @param launch The launch info struct
    /// @param kubAmount Amount of KUB
    /// @param ponderAmount Amount of PONDER
    /// @param ponderKubValue KUB value of PONDER amount
    /// @return result Struct containing all calculation results
    function calculateContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 kubAmount,
        uint256 ponderAmount,
        uint256 ponderKubValue
    ) public view returns (FiveFiveFiveLauncherTypes.ContributionResult memory result) {
        uint256 totalContribution = kubAmount + ponderKubValue;
        uint256 currentTotal = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;

        // Check if contribution exceeds remaining needed
        if (currentTotal + totalContribution > FiveFiveFiveConstants.TARGET_RAISE) {
            // Calculate refund
            uint256 excess = currentTotal + totalContribution - FiveFiveFiveConstants.TARGET_RAISE;
            result.refund = excess;

            // Adjust actual contribution
            result.contribution = totalContribution - excess;
        } else {
            result.contribution = totalContribution;
            result.refund = 0;
        }

        // Calculate tokens to distribute
        result.tokensToDistribute = (result.contribution * launch.allocation.tokensForContributors) /
                        FiveFiveFiveConstants.TARGET_RAISE;

        return result;
    }
}
