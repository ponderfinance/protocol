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
/// @dev Combines contribution and refund logic with optimized operations
library FundsLib {
    using Address for address payable;
    using SafeERC20 for PonderERC20;
    using SafeERC20 for PonderToken;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 private constant TARGET_RAISE = 5555 ether;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_PONDER_PERCENT = 2000; // 20%
    uint256 private constant MIN_KUB_CONTRIBUTION = 0.01 ether;
    uint256 private constant MIN_PONDER_CONTRIBUTION = 0.1 ether;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();
    error ExcessiveContribution();
    error ContributionTooSmall();
    error TokenApprovalRequired();
    error TokenTransferFailed();
    error NoContributionToRefund();
    error LaunchStillActive();
    error LaunchSucceeded();
    error InsufficientBalance();
    error LaunchNotCancellable();
    error LaunchBeingFinalized();
    error LaunchDeadlinePassed();

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);
    event RefundProcessed(address indexed user, uint256 kubAmount, uint256 ponderAmount, uint256 tokenAmount);
    event LaunchCancelled(uint256 indexed launchId, address indexed creator, uint256 kubCollected, uint256 ponderCollected);
    event LPTokensWithdrawn(uint256 indexed launchId, address indexed creator, uint256 timestamp);

    /*//////////////////////////////////////////////////////////////
                        CONTRIBUTION HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes KUB contribution for a launch
    /// @dev Validates contribution and updates state
    function processKubContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        uint256 amount,
        address contributor
    ) external returns (bool) {
        // Validate amount
        if (amount < MIN_KUB_CONTRIBUTION) revert ContributionTooSmall();

        // Calculate new total and validate
        uint256 newTotal = launch.contributions.kubCollected +
                            launch.contributions.ponderValueCollected +
                    amount;
        if (newTotal > TARGET_RAISE) revert ExcessiveContribution();

        // Calculate tokens to distribute
        uint256 tokensToDistribute = (amount * launch.allocation.tokensForContributors) / TARGET_RAISE;

        // Update state
        launch.contributions.kubCollected += amount;
        launch.contributions.tokensDistributed += tokensToDistribute;

        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
        info.kubContributed += amount;
        info.tokensReceived += tokensToDistribute;

        // Emit events
        emit TokensDistributed(launchId, contributor, tokensToDistribute);
        emit KUBContributed(launchId, contributor, amount);

        // Transfer tokens last (CEI pattern)
        if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute)) {
            revert TokenTransferFailed();
        }

        return newTotal == TARGET_RAISE;
    }

    /// @notice Processes PONDER contribution for a launch
    /// @dev Validates contribution and PONDER transfer
    function processPonderContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        uint256 amount,
        uint256 kubValue,
        address contributor,
        PonderToken ponder
    ) external returns (bool) {
        // Validate contribution
        if (amount < MIN_PONDER_CONTRIBUTION) revert ContributionTooSmall();

        // Validate PONDER cap
        uint256 totalPonderValue = launch.contributions.ponderValueCollected + kubValue;
        uint256 maxPonderValue = (TARGET_RAISE * MAX_PONDER_PERCENT) / BASIS_POINTS;
        if (totalPonderValue > maxPonderValue) revert ExcessiveContribution();

        // Calculate new total and validate
        uint256 newTotal = launch.contributions.kubCollected + totalPonderValue;
        if (newTotal > TARGET_RAISE) revert ExcessiveContribution();

        // Calculate tokens
        uint256 tokensToDistribute = (kubValue * launch.allocation.tokensForContributors) / TARGET_RAISE;

        // Check allowance
        if (ponder.allowance(contributor, address(this)) < amount) {
            revert TokenApprovalRequired();
        }

        // Emit events before external calls
        emit TokensDistributed(launchId, contributor, tokensToDistribute);
        emit PonderContributed(launchId, contributor, amount, kubValue);

        // Transfer PONDER (CEI pattern)
        if (!ponder.transferFrom(contributor, address(this), amount)) {
            revert TokenTransferFailed();
        }

        // Update state after successful transfer
        launch.contributions.ponderCollected += amount;
        launch.contributions.ponderValueCollected += kubValue;
        launch.contributions.tokensDistributed += tokensToDistribute;

        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
        info.ponderContributed += amount;
        info.ponderValue += kubValue;
        info.tokensReceived += tokensToDistribute;

        // Transfer tokens last
        if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute)) {
            revert TokenTransferFailed();
        }

        return newTotal == TARGET_RAISE;
    }

    /*//////////////////////////////////////////////////////////////
                            REFUND HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes refund for a failed or cancelled launch
    /// @dev Returns both KUB and PONDER contributions
    function processRefund(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address claimer,
        PonderToken ponder
    ) external {
        // Validate refund conditions
        _validateRefund(launch, claimer);

        // Cache values before state changes
        uint256 kubToRefund = launch.contributors[claimer].kubContributed;
        uint256 ponderToRefund = launch.contributors[claimer].ponderContributed;
        uint256 tokensToReturn = launch.contributors[claimer].tokensReceived;

        // Clear contributor state
        delete launch.contributors[claimer];

        // Emit event before transfers
        emit RefundProcessed(claimer, kubToRefund, ponderToRefund, tokensToReturn);

        // Process token returns and refunds (CEI pattern)
        _processTokenReturn(launch.base.tokenAddress, claimer, tokensToReturn);
        _processRefundTransfers(claimer, kubToRefund, ponderToRefund, ponder);
    }

    /*//////////////////////////////////////////////////////////////
                        LAUNCH MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes launch cancellation
    /// @dev Only callable by creator before deadline
    function processLaunchCancellation(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        address caller,
        mapping(string => bool) storage usedNames,
        mapping(string => bool) storage usedSymbols
    ) external {
        // Validate cancellation conditions
        _validateCancellation(launch, caller);

        // Free up name and symbol
        usedNames[launch.base.name] = false;
        usedSymbols[launch.base.symbol] = false;

        // Mark as cancelled
        launch.base.cancelled = true;

        emit LaunchCancelled(
            launchId,
            caller,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    /// @notice Processes LP token withdrawal
    /// @dev Only callable by creator after lock period
    function processLPWithdrawal(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        address sender
    ) external {
        if(sender != launch.base.creator) revert Unauthorized();
        if(block.timestamp < launch.base.lpUnlockTime) revert LaunchNotCancellable();

        emit LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);

        // Process withdrawals from both pairs last (CEI pattern)
        _withdrawPairLP(launch.pools.memeKubPair, launch.base.creator);
        _withdrawPairLP(launch.pools.memePonderPair, launch.base.creator);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Validates refund conditions
    function _validateRefund(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address claimer
    ) private view {
        if (!launch.base.cancelled && block.timestamp <= launch.base.launchDeadline) {
            revert LaunchStillActive();
        }

        if (launch.base.launched ||
            launch.contributions.kubCollected + launch.contributions.ponderValueCollected >= TARGET_RAISE) {
            revert LaunchSucceeded();
        }

        if (launch.contributors[claimer].kubContributed == 0 &&
            launch.contributors[claimer].ponderContributed == 0) {
            revert NoContributionToRefund();
        }
    }

    /// @dev Handles token return process
    function _processTokenReturn(
        address tokenAddress,
        address claimer,
        uint256 tokenAmount
    ) private {
        if (tokenAmount > 0) {
            LaunchToken token = LaunchToken(tokenAddress);

            if (token.balanceOf(claimer) < tokenAmount) revert InsufficientBalance();
            if (token.allowance(claimer, address(this)) < tokenAmount) revert TokenApprovalRequired();

            if (!token.transferFrom(claimer, address(this), tokenAmount)) {
                revert TokenTransferFailed();
            }
        }
    }

    /// @dev Processes refund transfers
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

    /// @dev Validates launch cancellation conditions
    function _validateCancellation(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address caller
    ) private view {
        if (launch.base.tokenAddress == address(0)) revert LaunchNotCancellable();
        if (caller != launch.base.creator) revert Unauthorized();
        if (launch.base.launched) revert LaunchNotCancellable();
        if (launch.base.isFinalizingLaunch) revert LaunchBeingFinalized();
        if (block.timestamp > launch.base.launchDeadline) revert LaunchDeadlinePassed();
    }

    /// @dev Withdraws LP tokens from a specific pair
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
