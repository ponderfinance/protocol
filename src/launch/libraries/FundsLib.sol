// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { LaunchToken } from "../LaunchToken.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { PonderERC20 } from "../../core/token/PonderERC20.sol";

/// @title FundsLib
/// @author taayyohh
/// @notice Library for handling contributions, refunds, and fund management
/// @dev Optimized for packed storage values and gas efficiency
library FundsLib {
    using Address for address payable;
    using SafeERC20 for PonderERC20;
    using SafeERC20 for PonderToken;
    using FiveFiveFiveLauncherTypes for FiveFiveFiveLauncherTypes.LaunchInfo;

    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);
    event RefundProcessed(address indexed user, uint256 kubAmount, uint256 ponderAmount, uint256 tokenAmount);
    event LaunchCancelled(uint256 indexed launchId, address indexed creator, uint256 kubCollected, uint256 ponderCollected);
    event LPTokensWithdrawn(uint256 indexed launchId, address indexed creator, uint256 timestamp);

    /// @notice Processes KUB contribution with packed storage handling
    function processKubContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        uint256 amount,
        address contributor
    ) external returns (bool) {
        if (amount < FiveFiveFiveLauncherTypes.MIN_KUB_CONTRIBUTION)
            revert FiveFiveFiveLauncherTypes.ContributionTooSmall();

        unchecked {
        // Safe math: contributions are bounded by TARGET_RAISE
            uint256 newTotal = launch.contributions.kubCollected +
                                launch.contributions.ponderValueCollected +
                        amount;
            if (newTotal > FiveFiveFiveLauncherTypes.TARGET_RAISE)
                revert FiveFiveFiveLauncherTypes.ExcessiveContribution();

        // Calculate tokens using packed uint128 allocation
            uint256 tokensToDistribute = (amount * uint256(launch.allocation.tokensForContributors)) /
                            FiveFiveFiveLauncherTypes.TARGET_RAISE;

        // Update packed contribution values
            launch.contributions.kubCollected += amount;
            launch.contributions.tokensDistributed += tokensToDistribute;

        // Update packed contributor info
            FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
            info.kubContributed = uint128(uint256(info.kubContributed) + amount);
            info.tokensReceived = uint128(uint256(info.tokensReceived) + tokensToDistribute);

            emit TokensDistributed(launchId, contributor, tokensToDistribute);
            emit KUBContributed(launchId, contributor, amount);

            if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute)) {
                revert FiveFiveFiveLauncherTypes.TokenTransferFailed();
            }

            return newTotal == FiveFiveFiveLauncherTypes.TARGET_RAISE;
        }
    }

    /// @notice Processes PONDER contribution with packed storage
    function processPonderContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        uint256 amount,
        uint256 kubValue,
        address contributor,
        PonderToken ponder
    ) external returns (bool) {
        if (amount < FiveFiveFiveLauncherTypes.MIN_PONDER_CONTRIBUTION)
            revert FiveFiveFiveLauncherTypes.ContributionTooSmall();

        unchecked {
        // Safe math: contributions are bounded
            uint256 totalPonderValue = launch.contributions.ponderValueCollected + kubValue;
            uint256 maxPonderValue = (FiveFiveFiveLauncherTypes.TARGET_RAISE *
                FiveFiveFiveLauncherTypes.MAX_PONDER_PERCENT) / FiveFiveFiveLauncherTypes.BASIS_POINTS;

            if (totalPonderValue > maxPonderValue)
                revert FiveFiveFiveLauncherTypes.ExcessiveContribution();

            uint256 newTotal = launch.contributions.kubCollected + totalPonderValue;
            if (newTotal > FiveFiveFiveLauncherTypes.TARGET_RAISE)
                revert FiveFiveFiveLauncherTypes.ExcessiveContribution();

        // Calculate tokens using packed allocation
            uint256 tokensToDistribute = (kubValue * uint256(launch.allocation.tokensForContributors)) /
                            FiveFiveFiveLauncherTypes.TARGET_RAISE;

            if (ponder.allowance(contributor, address(this)) < amount) {
                revert FiveFiveFiveLauncherTypes.TokenApprovalRequired();
            }

            emit TokensDistributed(launchId, contributor, tokensToDistribute);
            emit PonderContributed(launchId, contributor, amount, kubValue);

            if (!ponder.transferFrom(contributor, address(this), amount)) {
                revert FiveFiveFiveLauncherTypes.TokenTransferFailed();
            }

        // Update packed storage values
            launch.contributions.ponderCollected += amount;
            launch.contributions.ponderValueCollected += kubValue;
            launch.contributions.tokensDistributed += tokensToDistribute;

        // Update packed contributor info
            FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
            info.ponderContributed = uint128(uint256(info.ponderContributed) + amount);
            info.ponderValue = uint128(uint256(info.ponderValue) + kubValue);
            info.tokensReceived = uint128(uint256(info.tokensReceived) + tokensToDistribute);

            if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute)) {
                revert FiveFiveFiveLauncherTypes.TokenTransferFailed();
            }

            return newTotal == FiveFiveFiveLauncherTypes.TARGET_RAISE;
        }
    }

    /// @notice Processes refund with packed value handling
    function processRefund(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address claimer,
        PonderToken ponder
    ) external {
        // Validate refund conditions
        _validateRefund(launch, claimer);

        // Get packed values before clearing storage
        FiveFiveFiveLauncherTypes.ContributorInfo memory info = launch.contributors[claimer];
        uint256 kubToRefund = uint256(info.kubContributed);
        uint256 ponderToRefund = uint256(info.ponderContributed);
        uint256 tokensToReturn = uint256(info.tokensReceived);

        // Clear storage in single operation
        delete launch.contributors[claimer];

        emit RefundProcessed(claimer, kubToRefund, ponderToRefund, tokensToReturn);

        // Process returns and refunds
        _processTokenReturn(launch.base.tokenAddress, claimer, tokensToReturn);
        _processRefundTransfers(claimer, kubToRefund, ponderToRefund, ponder);
    }

    /// @notice Processes launch cancellation with optimized storage
    function processLaunchCancellation(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        address caller,
        mapping(string => bool) storage usedNames,
        mapping(string => bool) storage usedSymbols
    ) external {
        _validateCancellation(launch, caller);

        // Free name and symbol
        usedNames[launch.base.name] = false;
        usedSymbols[launch.base.symbol] = false;

        // Update packed state
        launch.base.cancelled = true;

        emit LaunchCancelled(
            launchId,
            caller,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    /// @notice Processes LP withdrawal with timestamp handling
    function processLPWithdrawal(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        address sender
    ) external {
        if(sender != launch.base.creator) revert FiveFiveFiveLauncherTypes.Unauthorized();

        unchecked {
        // Safe comparison: timestamps are uint40
            if(block.timestamp < launch.base.lpUnlockTime)
                revert FiveFiveFiveLauncherTypes.LaunchNotCancellable();
        }

        emit LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);

        _withdrawPairLP(launch.pools.memeKubPair, launch.base.creator);
        _withdrawPairLP(launch.pools.memePonderPair, launch.base.creator);
    }

    /// @dev Validates refund conditions with packed timestamp
    function _validateRefund(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address claimer
    ) private view {
        unchecked {
        // Safe comparison: launchDeadline is uint40
            if (!launch.base.cancelled && block.timestamp <= launch.base.launchDeadline) {
                revert FiveFiveFiveLauncherTypes.LaunchStillActive();
            }
        }

        if (launch.base.launched ||
            launch.contributions.kubCollected + launch.contributions.ponderValueCollected >=
            FiveFiveFiveLauncherTypes.TARGET_RAISE) {
            revert FiveFiveFiveLauncherTypes.LaunchSucceeded();
        }

        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[claimer];
        if (info.kubContributed == 0 && info.ponderContributed == 0) {
            revert FiveFiveFiveLauncherTypes.NoContributionToRefund();
        }
    }

    /// @dev Processes token return with balance checks
    function _processTokenReturn(
        address tokenAddress,
        address claimer,
        uint256 tokenAmount
    ) private {
        if (tokenAmount > 0) {
            LaunchToken token = LaunchToken(tokenAddress);

            if (token.balanceOf(claimer) < tokenAmount)
                revert FiveFiveFiveLauncherTypes.InsufficientBalance();
            if (token.allowance(claimer, address(this)) < tokenAmount)
                revert FiveFiveFiveLauncherTypes.TokenApprovalRequired();

            if (!token.transferFrom(claimer, address(this), tokenAmount)) {
                revert FiveFiveFiveLauncherTypes.TokenTransferFailed();
            }
        }
    }

    /// @dev Processes refund transfers safely
    function _processRefundTransfers(
        address claimer,
        uint256 kubAmount,
        uint256 ponderAmount,
        PonderToken ponder
    ) private {
        if (ponderAmount > 0) {
            ponder.safeTransfer(claimer, ponderAmount);
        }
        if (kubAmount > 0) {
            payable(claimer).sendValue(kubAmount);
        }
    }

    /// @dev Validates cancellation conditions with packed timestamps
    function _validateCancellation(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address caller
    ) private view {
        if (launch.base.tokenAddress == address(0))
            revert FiveFiveFiveLauncherTypes.LaunchNotCancellable();
        if (caller != launch.base.creator)
            revert FiveFiveFiveLauncherTypes.Unauthorized();
        if (launch.base.launched)
            revert FiveFiveFiveLauncherTypes.LaunchNotCancellable();
        if (launch.base.isFinalizingLaunch)
            revert FiveFiveFiveLauncherTypes.LaunchBeingFinalized();

        unchecked {
        // Safe comparison: launchDeadline is uint40
            if (block.timestamp > launch.base.launchDeadline)
                revert FiveFiveFiveLauncherTypes.LaunchDeadlinePassed();
        }
    }

    /// @dev Withdraws LP tokens with balance check
    function _withdrawPairLP(
        address pair,
        address recipient
    ) private {
        if (pair == address(0)) return;
        uint256 balance = PonderERC20(pair).balanceOf(address(this));
        if (balance > 0) {
            PonderERC20(pair).safeTransfer(recipient, balance);
        }
    }
}
