// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { LaunchToken } from "../LaunchToken.sol";
import { IFiveFiveFiveLauncher } from "../IFiveFiveFiveLauncher.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { PonderERC20 } from "../../core/token/PonderERC20.sol";
import { PonderPriceOracle } from "../../core/oracle/PonderPriceOracle.sol";
import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";

/*//////////////////////////////////////////////////////////////
                        FUNDS LIBRARY
//////////////////////////////////////////////////////////////*/

/// @title FundsLib
/// @author taayyohh
/// @notice Core library for launch contribution management and fund handling
/// @dev Optimized for packed storage values and gas efficiency
///      All monetary values handled in wei (1e18)
///      Uses packed uint128 for storage optimization
library FundsLib {
    /*//////////////////////////////////////////////////////////////
                        DEPENDENCIES
    //////////////////////////////////////////////////////////////*/
    using Address for address payable;
    using SafeERC20 for PonderERC20;
    using SafeERC20 for PonderToken;
    using FiveFiveFiveLauncherTypes for FiveFiveFiveLauncherTypes.LaunchInfo;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when launch tokens are distributed to contributors
    /// @param launchId Unique identifier of the launch
    /// @param recipient Address receiving the tokens
    /// @param amount Number of tokens distributed, in wei (1e18)
    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);

    /// @notice Emitted when KUB is contributed to a launch
    /// @param launchId Unique identifier of the launch
    /// @param contributor Address making the contribution
    /// @param amount Amount of KUB contributed, in wei (1e18)
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);

    /// @notice Emitted when PONDER tokens are contributed
    /// @param launchId Unique identifier of the launch
    /// @param contributor Address making the contribution
    /// @param amount Amount of PONDER contributed, in wei (1e18)
    /// @param kubValue KUB equivalent value of contributed PONDER
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);

    /// @notice Emitted when a refund is processed for a contributor
    /// @param user Address receiving the refund
    /// @param kubAmount Amount of KUB refunded, in wei (1e18)
    /// @param ponderAmount Amount of PONDER refunded, in wei (1e18)
    /// @param tokenAmount Amount of launch tokens returned, in wei (1e18)
    event RefundProcessed(address indexed user, uint256 kubAmount, uint256 ponderAmount, uint256 tokenAmount);

    /// @notice Emitted when a launch is cancelled by creator
    /// @param launchId Unique identifier of the cancelled launch
    /// @param creator Address of launch creator
    /// @param kubCollected Total KUB collected before cancellation
    /// @param ponderCollected Total PONDER collected before cancellation
    event LaunchCancelled(
        uint256 indexed launchId,
        address indexed creator,
        uint256 kubCollected,
        uint256 ponderCollected
    );

    /// @notice Emitted when LP tokens are withdrawn from a launch
    /// @param launchId Unique identifier of the launch
    /// @param creator Address of launch creator receiving LP tokens
    /// @param timestamp Block timestamp of withdrawal
    event LPTokensWithdrawn(uint256 indexed launchId, address indexed creator, uint256 timestamp);


    /*//////////////////////////////////////////////////////////////
                       EXTERNAL FUNCTIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Processes a KUB contribution to a launch
    /// @dev Uses packed storage for gas optimization
    /// @dev Updates contribution tracking and token distribution atomically
    /// @dev Enforces minimum contribution and target raise limits
    /// @param launch Launch information storage
    /// @param launchId Unique identifier of the launch
    /// @param amount Amount of KUB to contribute, in wei (1e18)
    /// @param contributor Address making the contribution
    /// @return success True if target raise is reached after contribution
    function processKubContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        uint256 amount,
        address contributor
    ) external returns (bool) {
        // Calculate remaining amount needed
        uint256 currentTotal = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        uint256 remaining = FiveFiveFiveLauncherTypes.TARGET_RAISE - currentTotal;

        // Skip minimum check if this would complete the launch
        if (amount != remaining) {
            if (amount < FiveFiveFiveLauncherTypes.MIN_KUB_CONTRIBUTION)
                revert IFiveFiveFiveLauncher.ContributionTooSmall();
        }

        unchecked {
        // Safe math: contributions are bounded by TARGET_RAISE
            uint256 newTotal = currentTotal + amount;
            if (newTotal > FiveFiveFiveLauncherTypes.TARGET_RAISE)
                revert IFiveFiveFiveLauncher.ExcessiveContribution();

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
                revert IFiveFiveFiveLauncher.TokenTransferFailed();
            }

            return newTotal == FiveFiveFiveLauncherTypes.TARGET_RAISE;
        }
    }

    /// @notice Processes refund for a contributor
    /// @dev Handles both KUB and PONDER refunds
    /// @dev Returns launch tokens to contract
    /// @dev Clears contributor storage after successful refund
    /// @param launch Launch information storage
    /// @param claimer Address claiming the refund
    /// @param ponder PONDER token contract reference
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

    /// @notice Processes launch cancellation
    /// @dev Frees name and symbol registrations
    /// @dev Updates launch state to cancelled
    /// @dev Can only be called by launch creator before deadline
    /// @param launch Launch information storage
    /// @param launchId Unique identifier of the launch
    /// @param caller Address initiating the cancellation
    /// @param usedNames Registry of used launch names
    /// @param usedSymbols Registry of used launch symbols
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

    /// @notice Processes LP token withdrawal
    /// @dev Transfers LP tokens to launch creator
    /// @dev Can only be called after LP unlock time
    /// @dev Handles both MEME/KUB and MEME/PONDER pairs
    /// @param launch Launch information storage
    /// @param launchId Unique identifier of the launch
    /// @param sender Address initiating the withdrawal
    function processLPWithdrawal(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        address sender
    ) external {
        if(sender != launch.base.creator) revert IFiveFiveFiveLauncher.Unauthorized();

        unchecked {
        // Safe comparison: timestamps are uint40
            if(block.timestamp < launch.base.lpUnlockTime)
                revert IFiveFiveFiveLauncher.LaunchNotCancellable();
        }

        emit LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);

        _withdrawPairLP(launch.pools.memeKubPair, launch.base.creator);
        _withdrawPairLP(launch.pools.memePonderPair, launch.base.creator);
    }

    /*//////////////////////////////////////////////////////////////
                        PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates refund eligibility conditions
    /// @dev Checks launch status and contributor balance
    /// @dev Verifies launch hasn't succeeded or been launched
    /// @dev Ensures contributor has valid contribution to refund
    /// @param launch Launch information storage
    /// @param claimer Address attempting to claim refund
    function _validateRefund(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address claimer
    ) private view {
        unchecked {
        // Safe comparison: launchDeadline is uint40
            if (!launch.base.cancelled && block.timestamp <= launch.base.launchDeadline) {
                revert IFiveFiveFiveLauncher.LaunchStillActive();
            }
        }

        if (launch.base.launched ||
            launch.contributions.kubCollected + launch.contributions.ponderValueCollected >=
            FiveFiveFiveLauncherTypes.TARGET_RAISE) {
            revert IFiveFiveFiveLauncher.LaunchSucceeded();
        }

        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[claimer];
        if (info.kubContributed == 0 && info.ponderContributed == 0) {
            revert IFiveFiveFiveLauncher.NoContributionToRefund();
        }
    }

    /// @notice Processes return of launch tokens to contract
    /// @dev Verifies token balance and allowance
    /// @dev Handles token transfer back to contract
    /// @param tokenAddress Address of launch token contract
    /// @param claimer Address returning tokens
    /// @param tokenAmount Amount of tokens to return, in wei (1e18)
    function _processTokenReturn(
        address tokenAddress,
        address claimer,
        uint256 tokenAmount
    ) private {
        if (tokenAmount > 0) {
            LaunchToken token = LaunchToken(tokenAddress);

            if (token.balanceOf(claimer) < tokenAmount)
                revert IFiveFiveFiveLauncher.InsufficientBalance();
            if (token.allowance(claimer, address(this)) < tokenAmount)
                revert IFiveFiveFiveLauncher.TokenApprovalRequired();

            if (!token.transferFrom(claimer, address(this), tokenAmount)) {
                revert IFiveFiveFiveLauncher.TokenTransferFailed();
            }
        }
    }

    /// @notice Processes refund transfers to contributor
    /// @dev Handles both KUB and PONDER refunds
    /// @dev Uses safe transfer methods for tokens
    /// @param claimer Address receiving refund
    /// @param kubAmount Amount of KUB to refund, in wei (1e18)
    /// @param ponderAmount Amount of PONDER to refund, in wei (1e18)
    /// @param ponder PONDER token contract reference
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

    /// @notice Validates launch cancellation conditions
    /// @dev Checks creator authorization
    /// @dev Verifies launch state and timing
    /// @dev Ensures launch isn't being finalized
    /// @param launch Launch information storage
    /// @param caller Address attempting cancellation
    function _validateCancellation(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        address caller
    ) private view {
        if (launch.base.tokenAddress == address(0))
            revert IFiveFiveFiveLauncher.LaunchNotCancellable();
        if (caller != launch.base.creator)
            revert IFiveFiveFiveLauncher.Unauthorized();
        if (launch.base.launched)
            revert IFiveFiveFiveLauncher.LaunchNotCancellable();
        if (launch.base.isFinalizingLaunch)
            revert IFiveFiveFiveLauncher.LaunchBeingFinalized();

        unchecked {
        // Safe comparison: launchDeadline is uint40
            if (block.timestamp > launch.base.launchDeadline)
                revert IFiveFiveFiveLauncher.LaunchDeadlinePassed();
        }
    }

    /// @notice Withdraws LP tokens from trading pairs
    /// @dev Handles safe transfer of available LP tokens
    /// @dev Skips if pair address is zero
    /// @param pair Address of LP token contract
    /// @param recipient Address to receive LP tokens
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

    /// @notice Validates or uses cached PONDER price validation
    /// @dev Performs full validation only if cache is stale
    function validatePonderPrice(
        FiveFiveFiveLauncherTypes.ContributionContext memory context,
        address pair,
        PonderPriceOracle oracle,
        address ponder
    ) internal view returns (bool needsTwapValidation) {
        // Always get current spot price
        context.priceInfo.spotPrice = oracle.getCurrentPrice(
            pair,
            ponder,
            context.ponderAmount
        );

        // If no previous validation or validation is stale, need full TWAP check
        if (!context.priceInfo.isValidated || isPriceValidationStale(context.priceInfo.validatedAt)) {
            return true;
        }

        // Use cached TWAP for validation
        uint256 maxDeviation = (context.priceInfo.twapPrice * 110) / 100;
        uint256 minDeviation = (context.priceInfo.twapPrice * 90) / 100;

        if (context.priceInfo.spotPrice > maxDeviation || context.priceInfo.spotPrice < minDeviation) {
            revert IFiveFiveFiveLauncher.ExcessivePriceDeviation();
        }

        // Update KUB value with new spot price
        context.priceInfo.kubValue = context.priceInfo.spotPrice;
        return false;
    }

    /// @notice Checks if cached price validation has expired
    /// @dev Pure helper function for validation state
    function isPriceValidationStale(uint32 validatedAt) internal view returns (bool) {
        return block.timestamp > validatedAt + FiveFiveFiveLauncherTypes.PRICE_VALIDATION_PERIOD;
    }

    /// @notice Performs full TWAP validation and updates cache
/// @dev Called only when cache is stale or non-existent
    function performTwapValidation(
        FiveFiveFiveLauncherTypes.ContributionContext memory context,
        address pair,
        PonderPriceOracle oracle,
        address ponder
    ) internal view {
        uint256 twapPrice = oracle.consult(
            pair,
            ponder,
            context.ponderAmount,
            1 hours
        );

        if (twapPrice == 0) {
            revert IFiveFiveFiveLauncher.InsufficientPriceHistory();
        }

        // Validate spot price against TWAP
        uint256 maxDeviation = (twapPrice * 110) / 100;
        uint256 minDeviation = (twapPrice * 90) / 100;

        if (context.priceInfo.spotPrice > maxDeviation || context.priceInfo.spotPrice < minDeviation) {
            revert IFiveFiveFiveLauncher.ExcessivePriceDeviation();
        }

        // Update cache
        context.priceInfo.twapPrice = twapPrice;
        context.priceInfo.kubValue = context.priceInfo.spotPrice;
        context.priceInfo.validatedAt = uint32(block.timestamp);
        context.priceInfo.isValidated = true;
    }

    /// @notice Process PONDER contribution with cached validation
    /// @dev Main entry point for PONDER contributions
    function processPonderContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        FiveFiveFiveLauncherTypes.ContributionContext memory context,
        address contributor,
        PonderToken ponder,
        IPonderFactory factory,
        IPonderRouter router,
        PonderPriceOracle oracle
    ) internal returns (bool) {
        // Get PONDER-KUB pair
        address pair = factory.getPair(address(ponder), router.kkub());

        // Validate price using cache when possible
        bool needsTwapValidation = validatePonderPrice(
            context,
            pair,
            oracle,
            address(ponder)
        );

        // Perform full TWAP validation if needed
        if (needsTwapValidation) {
            performTwapValidation(context, pair, oracle, address(ponder));
        }

        // Validate contribution limits
        validateContributionLimits(launch, context);

        // Process contribution
        return processValidatedContribution(launch, launchId, context, contributor, ponder);
    }

    // Helper function to validate contribution limits
    function validateContributionLimits(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.ContributionContext memory context
    ) internal view {
        // Calculate remaining amounts
        uint256 currentTotal = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        uint256 remaining = FiveFiveFiveLauncherTypes.TARGET_RAISE - currentTotal;

        // Calculate total PONDER value after this contribution
        uint256 totalPonderValue = launch.contributions.ponderValueCollected + context.priceInfo.kubValue;
        uint256 maxPonderValue = (FiveFiveFiveLauncherTypes.TARGET_RAISE *
            FiveFiveFiveLauncherTypes.MAX_PONDER_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;

        // Skip minimum check if this would complete the PONDER allocation
        if (totalPonderValue != maxPonderValue) {
            if (context.ponderAmount < FiveFiveFiveLauncherTypes.MIN_PONDER_CONTRIBUTION)
                revert IFiveFiveFiveLauncher.ContributionTooSmall();
        }

        // Check PONDER contribution limit (20%)
        if (totalPonderValue > maxPonderValue) {
            revert IFiveFiveFiveLauncher.ExcessiveContribution();
        }

        // Check total raise limit
        uint256 newTotal = launch.contributions.kubCollected + totalPonderValue;
        if (newTotal > FiveFiveFiveLauncherTypes.TARGET_RAISE) {
            revert IFiveFiveFiveLauncher.ExcessiveContribution();
        }
    }

// Process contribution after validation
    function processValidatedContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        FiveFiveFiveLauncherTypes.ContributionContext memory context,
        address contributor,
        PonderToken ponder
    ) internal returns (bool) {
        // Calculate tokens to distribute
        context.tokensToDistribute = (context.priceInfo.kubValue *
            uint256(launch.allocation.tokensForContributors)) /
                        FiveFiveFiveLauncherTypes.TARGET_RAISE;

        // Check allowance
        if (ponder.allowance(contributor, address(this)) < context.ponderAmount) {
            revert IFiveFiveFiveLauncher.TokenApprovalRequired();
        }

        // Update state
        launch.contributions.ponderCollected += context.ponderAmount;
        launch.contributions.ponderValueCollected += context.priceInfo.kubValue;
        launch.contributions.tokensDistributed += context.tokensToDistribute;

        // Update contributor info
        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
        info.ponderContributed = uint128(uint256(info.ponderContributed) + context.ponderAmount);
        info.ponderValue = uint128(uint256(info.ponderValue) + context.priceInfo.kubValue);
        info.tokensReceived = uint128(uint256(info.tokensReceived) + context.tokensToDistribute);

        // Execute transfers
        if (!ponder.transferFrom(contributor, address(this), context.ponderAmount)) {
            revert IFiveFiveFiveLauncher.TokenTransferFailed();
        }

        if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, context.tokensToDistribute)) {
            revert IFiveFiveFiveLauncher.TokenTransferFailed();
        }

        // Emit events
        emit TokensDistributed(launchId, contributor, context.tokensToDistribute);
        emit PonderContributed(launchId, contributor, context.ponderAmount, context.priceInfo.kubValue);

        // Check if launch should be finalized
        return launch.contributions.kubCollected + launch.contributions.ponderValueCollected ==
            FiveFiveFiveLauncherTypes.TARGET_RAISE;
    }
}
