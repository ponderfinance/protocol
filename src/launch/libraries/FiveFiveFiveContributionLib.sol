// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { FiveFiveFiveConstants } from "./FiveFiveFiveConstants.sol";
import { FiveFiveFiveValidation } from "./FiveFiveFiveValidation.sol";
import { LaunchToken } from "../LaunchToken.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";


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
    ) internal returns (bool shouldFinalize) {
        // CHECKS
        (,bool shouldFin) = FiveFiveFiveValidation.validateKubContribution(
            launch,
            amount
        );

        // Calculate token distribution
        uint256 tokensToDistribute = (amount * launch.allocation.tokensForContributors) /
                        FiveFiveFiveConstants.TARGET_RAISE;

        // EFFECTS - Update all state
        launch.contributions.kubCollected += amount;
        launch.contributions.tokensDistributed += tokensToDistribute;

        FiveFiveFiveLauncherTypes.ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.kubContributed += amount;
        contributorInfo.tokensReceived += tokensToDistribute;

        // Emit events before external interactions
        emit TokensDistributed(launchId, contributor, tokensToDistribute);
        emit KUBContributed(launchId, contributor, amount);

        // INTERACTIONS - External call last
        if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute)) {
            revert FiveFiveFiveLauncherTypes.TokenTransferFailed();
        }

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
    ) internal returns (bool shouldFinalize) {
        // CHECKS
        if (contributor != msg.sender) {
            revert FiveFiveFiveLauncherTypes.Unauthorized();
        }

        shouldFinalize = FiveFiveFiveValidation.validatePonderContribution(
            launch,
            amount,
            kubValue
        );

        uint256 tokensToDistribute = (kubValue * launch.allocation.tokensForContributors) /
                        FiveFiveFiveConstants.TARGET_RAISE;

        uint256 allowance = ponder.allowance(contributor, address(this));
        if (allowance < amount) {
            revert FiveFiveFiveLauncherTypes.TokenApprovalRequired();
        }

        // Emit events before external interactions
        emit TokensDistributed(launchId, contributor, tokensToDistribute);
        emit PonderContributed(launchId, contributor, amount, kubValue);

        // INTERACTIONS - All external calls last
        bool success = ponder.transferFrom(contributor, address(this), amount);
        if (!success) {
            revert FiveFiveFiveLauncherTypes.KubTransferFailed();
        }

        // EFFECTS - Update state after successful transfer
        launch.contributions.ponderCollected += amount;
        launch.contributions.ponderValueCollected += kubValue;
        launch.contributions.tokensDistributed += tokensToDistribute;

        FiveFiveFiveLauncherTypes.ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.ponderContributed += amount;
        contributorInfo.ponderValue += kubValue;
        contributorInfo.tokensReceived += tokensToDistribute;

        // Final interaction
        if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute)) {
            revert FiveFiveFiveLauncherTypes.TokenTransferFailed();
        }

        return shouldFinalize;
    }
    /*//////////////////////////////////////////////////////////////
                        CONTRIBUTION UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates contribution amounts and distributions
    /// @param launch The launch info struct
    /// @param kubAmount Amount of KUB
    /// @param ponderKubValue KUB value of PONDER amount
    /// @return result Struct containing all calculation results
    function calculateContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 kubAmount,
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
