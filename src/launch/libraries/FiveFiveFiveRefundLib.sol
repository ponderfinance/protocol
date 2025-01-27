// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { FiveFiveFiveConstants } from "./FiveFiveFiveConstants.sol";
import { LaunchToken } from "../LaunchToken.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { PonderERC20 } from "../../core/token/PonderERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FiveFiveFiveRefundLib
/// @author taayyohh
/// @notice Library for handling refunds and cancellations
/// @dev Contains logic for processing refunds and LP withdrawals
library FiveFiveFiveRefundLib {
    using SafeERC20 for PonderERC20;
    using SafeERC20 for PonderToken;
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
    ) internal {
        // CHECKS
        if (!launch.base.cancelled && block.timestamp <= launch.base.launchDeadline) {
            revert FiveFiveFiveLauncherTypes.LaunchStillActive();
        }

        if (launch.base.launched ||
            launch.contributions.kubCollected + launch.contributions.ponderValueCollected >=
            FiveFiveFiveConstants.TARGET_RAISE) {
            revert FiveFiveFiveLauncherTypes.LaunchSucceeded();
        }

        FiveFiveFiveLauncherTypes.ContributorInfo storage contributor = launch.contributors[claimer];
        if (contributor.kubContributed == 0 && contributor.ponderContributed == 0) {
            revert FiveFiveFiveLauncherTypes.NoContributionToRefund();
        }

        // Cache values before state changes
        uint256 kubToRefund = contributor.kubContributed;
        uint256 ponderToRefund = contributor.ponderContributed;
        uint256 tokensToReturn = contributor.tokensReceived;

        // EFFECTS - Clear state
        contributor.kubContributed = 0;
        contributor.ponderContributed = 0;
        contributor.tokensReceived = 0;
        contributor.ponderValue = 0;

        // Emit event before external interactions
        emit RefundProcessed(claimer, kubToRefund, ponderToRefund, tokensToReturn);

        // INTERACTIONS - Handle token returns and refunds
        if (tokensToReturn > 0) {
            LaunchToken token = LaunchToken(launch.base.tokenAddress);

            if (token.balanceOf(claimer) < tokensToReturn) {
                revert FiveFiveFiveLauncherTypes.InsufficientBalance();
            }

            uint256 currentAllowance = token.allowance(claimer, address(this));
            if (currentAllowance < tokensToReturn) {
                revert FiveFiveFiveLauncherTypes.TokenApprovalRequired();
            }

            bool success = token.transferFrom(claimer, address(this), tokensToReturn);
            if (!success) {
                revert FiveFiveFiveLauncherTypes.TokenTransferFailed();
            }

            if (token.balanceOf(address(this)) < tokensToReturn) {
                revert FiveFiveFiveLauncherTypes.TokenTransferFailed();
            }
        }

        if (ponderToRefund > 0) {
            ponder.safeTransfer(claimer, ponderToRefund);
        }

        if (kubToRefund > 0) {
            payable(claimer).sendValue(kubToRefund);
        }
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
    ) internal {
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
    ) internal {
        // Verify withdrawal permissions and conditions
        if(caller != launch.base.creator) {
            revert FiveFiveFiveLauncherTypes.Unauthorized();
        }
        if(block.timestamp < launch.base.lpUnlockTime) {
            revert FiveFiveFiveLauncherTypes.LPStillLocked();
        }

        // Emit event before external calls
        emit LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);

        // Process withdrawals from both pairs last
        _withdrawPairLP(launch.pools.memeKubPair, launch.base.creator);
        _withdrawPairLP(launch.pools.memePonderPair, launch.base.creator);
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Withdraws LP tokens from a specific pair
    function _withdrawPairLP(address pair, address recipient) private {
        if (pair == address(0)) return;

        uint256 balance = PonderERC20(pair).balanceOf(address(this));
        if (balance > 0) {
            PonderERC20(pair).safeTransfer(recipient, balance);
        }
    }
}
