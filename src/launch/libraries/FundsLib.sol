// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";
import { LaunchToken } from "../LaunchToken.sol";
import { IFiveFiveFiveLauncher } from "../IFiveFiveFiveLauncher.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { PonderKAP20 } from "../../core/token/PonderKAP20.sol";
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
    using SafeERC20 for PonderKAP20;
    using SafeERC20 for PonderToken;
    using FiveFiveFiveLauncherTypes for FiveFiveFiveLauncherTypes.LaunchInfo;

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
        uint256 currentTotal = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        uint256 remaining = FiveFiveFiveLauncherTypes.TARGET_RAISE - currentTotal;

        if (amount != remaining) {
            if (amount < FiveFiveFiveLauncherTypes.MIN_KUB_CONTRIBUTION)
                revert IFiveFiveFiveLauncher.ContributionTooSmall();
        }

        uint256 newTotal = currentTotal + amount;
        if (newTotal > FiveFiveFiveLauncherTypes.TARGET_RAISE)
            revert IFiveFiveFiveLauncher.ExcessiveContribution();

        uint256 tokensToDistribute = (amount * uint256(launch.allocation.tokensForContributors)) /
                        FiveFiveFiveLauncherTypes.TARGET_RAISE;

        launch.contributions.kubCollected += amount;
        launch.contributions.tokensDistributed += tokensToDistribute;

        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
        info.kubContributed = uint128(uint256(info.kubContributed) + amount);
        info.tokensReceived = uint128(uint256(info.tokensReceived) + tokensToDistribute);

        emit IFiveFiveFiveLauncher.TokensDistributed(launchId, contributor, tokensToDistribute);
        emit IFiveFiveFiveLauncher.KUBContributed(launchId, contributor, amount);

        if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute)) {
            revert IFiveFiveFiveLauncher.TokenTransferFailed();
        }

        return newTotal == FiveFiveFiveLauncherTypes.TARGET_RAISE;
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
        _validateRefund(launch, claimer);

        FiveFiveFiveLauncherTypes.ContributorInfo memory info = launch.contributors[claimer];
        uint256 kubToRefund = uint256(info.kubContributed);
        uint256 ponderToRefund = uint256(info.ponderContributed);
        uint256 tokensToReturn = uint256(info.tokensReceived);

        delete launch.contributors[claimer];

        emit IFiveFiveFiveLauncher.RefundProcessed(claimer, kubToRefund, ponderToRefund, tokensToReturn);

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

        usedNames[launch.base.name] = false;
        usedSymbols[launch.base.symbol] = false;

        launch.base.cancelled = true;

        emit IFiveFiveFiveLauncher.LaunchCancelled(
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

        if(block.timestamp < launch.base.lpUnlockTime)
            revert IFiveFiveFiveLauncher.LaunchNotCancellable();

        emit IFiveFiveFiveLauncher.LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);

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
        if (!launch.base.cancelled && block.timestamp <= launch.base.launchDeadline) {
            revert IFiveFiveFiveLauncher.LaunchStillActive();
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

        if (block.timestamp > launch.base.launchDeadline)
            revert IFiveFiveFiveLauncher.LaunchDeadlinePassed();
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
        uint256 balance = PonderKAP20(pair).balanceOf(address(this));
        if (balance > 0) {
            PonderKAP20(pair).safeTransfer(recipient, balance);
        }
    }

    /// @notice Validates current PONDER price against cached values or triggers full validation
    /// @dev Uses a caching mechanism to reduce oracle calls and gas costs
    /// @param context The contribution context containing price and validation state
    /// @param pair Address of the PONDER-KUB trading pair
    /// @param oracle Reference to the price oracle contract
    /// @param ponder Address of the PONDER token
    /// @return needsTwapValidation True if a full TWAP validation is required, false if cache is valid
    function validatePonderPrice(
        FiveFiveFiveLauncherTypes.ContributionContext memory context,
        address pair,
        PonderPriceOracle oracle,
        address ponder
    ) internal view returns (bool needsTwapValidation) {
        context.priceInfo.spotPrice = oracle.getCurrentPrice(
            pair,
            ponder,
            context.ponderAmount
        );

        if (!context.priceInfo.isValidated || isPriceValidationStale(context.priceInfo.validatedAt)) {
            return true;
        }

        uint256 maxDeviation = (context.priceInfo.twapPrice * 110) / 100;
        uint256 minDeviation = (context.priceInfo.twapPrice * 90) / 100;

        if (context.priceInfo.spotPrice > maxDeviation || context.priceInfo.spotPrice < minDeviation) {
            revert IFiveFiveFiveLauncher.ExcessivePriceDeviation();
        }

        context.priceInfo.kubValue = context.priceInfo.spotPrice;
        return false;
    }

    /// @notice Determines if a cached price validation has expired
    /// @dev Uses PRICE_VALIDATION_PERIOD constant to define staleness
    /// @param validatedAt Timestamp of the last price validation
    /// @return bool True if the cached validation is stale and needs updating
    function isPriceValidationStale(uint32 validatedAt) internal view returns (bool) {
        return block.timestamp > validatedAt + FiveFiveFiveLauncherTypes.PRICE_VALIDATION_PERIOD;
    }

    /// @notice Performs a complete TWAP price validation with oracle
    /// @dev Called when cache is invalid or non-existent
    /// @dev Updates the price cache upon successful validation
    /// @param context The contribution context to update with new validation
    /// @param pair Address of the PONDER-KUB trading pair
    /// @param oracle Reference to the price oracle contract
    /// @param ponder Address of the PONDER token
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

        uint256 maxDeviation = (twapPrice * 110) / 100;
        uint256 minDeviation = (twapPrice * 90) / 100;

        if (context.priceInfo.spotPrice > maxDeviation || context.priceInfo.spotPrice < minDeviation) {
            revert IFiveFiveFiveLauncher.ExcessivePriceDeviation();
        }

        context.priceInfo.twapPrice = twapPrice;
        context.priceInfo.kubValue = context.priceInfo.spotPrice;
        context.priceInfo.validatedAt = uint32(block.timestamp);
        context.priceInfo.isValidated = true;
    }

    /// @notice Main entry point for processing PONDER contributions
    /// @dev Handles price validation, contribution limits, and state updates
    /// @param launch The launch information storage
    /// @param launchId Unique identifier of the launch
    /// @param context The contribution context with amount and price data
    /// @param contributor Address making the contribution
    /// @param ponder Reference to the PONDER token contract
    /// @param factory Reference to the factory contract for pair lookup
    /// @param router Reference to the router contract for KUB wrapping
    /// @param oracle Reference to the price oracle contract
    /// @return bool True if the launch should be finalized after this contribution
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
        address pair = factory.getPair(address(ponder), router.kkub());

        bool needsTwapValidation = validatePonderPrice(
            context,
            pair,
            oracle,
            address(ponder)
        );

        if (needsTwapValidation) {
            uint256 lastUpdate = oracle.lastUpdateTime(pair);

            // Only update if enough time has passed
            if (block.timestamp >= lastUpdate + 120) {
                oracle.update(pair);
            }

            performTwapValidation(context, pair, oracle, address(ponder));
        }


        validateContributionLimits(launch, context);

        return processValidatedContribution(launch, launchId, context, contributor, ponder);
    }

    /// @notice Validates contribution amounts against launch limits
    /// @dev Checks minimum contribution, maximum PONDER allocation, and total raise limits
    /// @param launch The launch information storage
    /// @param context The contribution context containing amount and price data
    function validateContributionLimits(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.ContributionContext memory context
    ) internal view {
        uint256 totalPonderValue = launch.contributions.ponderValueCollected + context.priceInfo.kubValue;
        uint256 maxPonderValue = (FiveFiveFiveLauncherTypes.TARGET_RAISE *
            FiveFiveFiveLauncherTypes.MAX_PONDER_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;

        // Calculate remaining to hit total target raise
        uint256 currentTotal = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        uint256 remaining = FiveFiveFiveLauncherTypes.TARGET_RAISE - currentTotal;

        // Only enforce minimum if not completing the raise
        if (context.priceInfo.kubValue != remaining) {
            if (context.ponderAmount < FiveFiveFiveLauncherTypes.MIN_PONDER_CONTRIBUTION)
                revert IFiveFiveFiveLauncher.ContributionTooSmall();
        }

        // Check max PONDER allocation
        if (totalPonderValue > maxPonderValue) {
            revert IFiveFiveFiveLauncher.ExcessiveContribution();
        }

        // Check total raise limit
        uint256 newTotal = launch.contributions.kubCollected + totalPonderValue;
        if (newTotal > FiveFiveFiveLauncherTypes.TARGET_RAISE) {
            revert IFiveFiveFiveLauncher.ExcessiveContribution();
        }
    }

    /// @notice Processes a validated PONDER contribution
    /// @dev Updates state, handles token transfers, and emits events
    /// @param launch The launch information storage
    /// @param launchId Unique identifier of the launch
    /// @param context The validated contribution context
    /// @param contributor Address making the contribution
    /// @param ponder Reference to the PONDER token contract
    /// @return bool True if the launch should be finalized after this contribution
    function processValidatedContribution(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        FiveFiveFiveLauncherTypes.ContributionContext memory context,
        address contributor,
        PonderToken ponder
    ) internal returns (bool) {
        context.tokensToDistribute = (context.priceInfo.kubValue *
            uint256(launch.allocation.tokensForContributors)) /
                        FiveFiveFiveLauncherTypes.TARGET_RAISE;

        if (ponder.allowance(contributor, address(this)) < context.ponderAmount) {
            revert IFiveFiveFiveLauncher.TokenApprovalRequired();
        }

        launch.contributions.ponderCollected += context.ponderAmount;
        launch.contributions.ponderValueCollected += context.priceInfo.kubValue;
        launch.contributions.tokensDistributed += context.tokensToDistribute;

        FiveFiveFiveLauncherTypes.ContributorInfo storage info = launch.contributors[contributor];
        info.ponderContributed = uint128(uint256(info.ponderContributed) + context.ponderAmount);
        info.ponderValue = uint128(uint256(info.ponderValue) + context.priceInfo.kubValue);
        info.tokensReceived = uint128(uint256(info.tokensReceived) + context.tokensToDistribute);

        if (!ponder.transferFrom(contributor, address(this), context.ponderAmount)) {
            revert IFiveFiveFiveLauncher.TokenTransferFailed();
        }

        if (!LaunchToken(launch.base.tokenAddress).transfer(contributor, context.tokensToDistribute)) {
            revert IFiveFiveFiveLauncher.TokenTransferFailed();
        }

        emit IFiveFiveFiveLauncher.TokensDistributed(
            launchId,
            contributor,
            context.tokensToDistribute
        );

        emit IFiveFiveFiveLauncher.PonderContributed(
            launchId, contributor,
            context.ponderAmount,
            context.priceInfo.kubValue
        );

        return launch.contributions.kubCollected + launch.contributions.ponderValueCollected ==
            FiveFiveFiveLauncherTypes.TARGET_RAISE;
    }
}
