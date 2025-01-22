// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { FiveFiveFiveConstants } from "./FiveFiveFiveConstants.sol";
import { LaunchToken } from "../LaunchToken.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { PonderERC20 } from "../../core/token/PonderERC20.sol";

/// @title FiveFiveFiveRefundLib
/// @author taayyohh
/// @notice Library for handling refunds and cancellations
/// @dev Contains logic for processing refunds and LP withdrawals
library FiveFiveFiveRefundLib {
    using FiveFiveFiveConstants for uint256;
    using Address for address payable;


    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event RefundProcessed(
        address indexed user,
        uint256 kubAmount,
        uint256 ponderAmount,
        uint256 tokenAmount
    );

    event LaunchCancelled(
        uint256 indexed launchId,
        address indexed creator,
        uint256 kubCollected,
        uint256 ponderCollected
    );

    event LPTokensWithdrawn(
        uint256 indexed launchId,
        address indexed creator,
        uint256 timestamp
    );

    /*//////////////////////////////////////////////////////////////
                        REFUND PROCESSING
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes refund for a failed or cancelled launch

    function processRefund(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address claimer,
        PonderToken ponder
    ) external {
        // Checks
        if (!launch.base.cancelled && block.timestamp <= launch.base.launchDeadline) {
            revert FiveFiveFiveLauncherTypes.LaunchStillActive();
        }

        if (launch.base.launched ||
            launch.contributions.kubCollected + launch.contributions.ponderValueCollected >=
            FiveFiveFiveConstants.TARGET_RAISE) {
            revert FiveFiveFiveLauncherTypes.LaunchSucceeded();
        }

        // Get contributor info
        FiveFiveFiveLauncherTypes.ContributorInfo storage contributor = launch.contributors[claimer];
        if (contributor.kubContributed == 0 && contributor.ponderContributed == 0) {
            revert FiveFiveFiveLauncherTypes.NoContributionToRefund();
        }

        // Cache refund amounts
        uint256 kubToRefund = contributor.kubContributed;
        uint256 ponderToRefund = contributor.ponderContributed;
        uint256 tokensToReturn = contributor.tokensReceived;

        // Effects - clear state before transfers (CEI pattern)
        contributor.kubContributed = 0;
        contributor.ponderContributed = 0;
        contributor.tokensReceived = 0;
        contributor.ponderValue = 0;

        // Interactions
        // 1. Handle token return if any
        if (tokensToReturn > 0) {
            LaunchToken token = LaunchToken(launch.base.tokenAddress);
            if (token.allowance(claimer, address(this)) < tokensToReturn) {
                revert FiveFiveFiveLauncherTypes.TokenApprovalRequired();
            }
            token.transferFrom(claimer, address(this), tokensToReturn);
        }

        // 2. Process PONDER refund
        if (ponderToRefund > 0) {
            ponder.transfer(claimer, ponderToRefund);
        }

        // 3. Process KUB refund using OpenZeppelin's Address.sendValue
        if (kubToRefund > 0) {
            payable(claimer).sendValue(kubToRefund);
        }

        emit RefundProcessed(claimer, kubToRefund, ponderToRefund, tokensToReturn);
    }
    /*//////////////////////////////////////////////////////////////
                        LAUNCH CANCELLATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes launch cancellation
    function processLaunchCancellation(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        address caller,
        mapping(string => bool) storage usedNames,
        mapping(string => bool) storage usedSymbols
    ) external {
        // Validate launch exists
        if (launch.base.tokenAddress == address(0)) {
            revert FiveFiveFiveLauncherTypes.LaunchNotCancellable();
        }

        // Verify permissions and conditions
        if (caller != launch.base.creator) {
            revert FiveFiveFiveLauncherTypes.Unauthorized();
        }
        if (launch.base.launched) {
            revert FiveFiveFiveLauncherTypes.AlreadyLaunched();
        }
        if (launch.base.isFinalizingLaunch) {
            revert FiveFiveFiveLauncherTypes.LaunchBeingFinalized();
        }
        if (block.timestamp > launch.base.launchDeadline) {
            revert FiveFiveFiveLauncherTypes.LaunchDeadlinePassed();
        }

        // Free up name and symbol for reuse
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

    /*//////////////////////////////////////////////////////////////
                        LP WITHDRAWAL
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes LP token withdrawal
    function processLPWithdrawal(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        address caller
    ) external {
        // Verify withdrawal permissions and conditions
        if(caller != launch.base.creator) {
            revert FiveFiveFiveLauncherTypes.Unauthorized();
        }
        if(block.timestamp < launch.base.lpUnlockTime) {
            revert FiveFiveFiveLauncherTypes.LPStillLocked();
        }

        // Process withdrawals from both pairs
        _withdrawPairLP(launch.pools.memeKubPair, launch.base.creator);
        _withdrawPairLP(launch.pools.memePonderPair, launch.base.creator);

        emit LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Withdraws LP tokens from a specific pair
    function _withdrawPairLP(address pair, address recipient) private {
        if (pair == address(0)) return;

        uint256 balance = PonderERC20(pair).balanceOf(address(this));
        if (balance > 0) {
            PonderERC20(pair).transfer(recipient, balance);
        }
    }
}
