// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PonderPairTypes } from "../types/PonderPairTypes.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ILaunchToken } from "../../../launch/ILaunchToken.sol";

/*//////////////////////////////////////////////////////////////
                       PONDER FEES LIBRARY
//////////////////////////////////////////////////////////////*/

/// @title PonderFeesLib
/// @author taayyohh
/// @notice Library for fee calculation and collection in Ponder protocol
/// @dev Extracts fee logic from PonderPair to reduce contract size and optimize gas
library PonderFeesLib {
    using SafeERC20 for IERC20;
    using PonderPairTypes for PonderPairTypes.SwapState;

    /*//////////////////////////////////////////////////////////////
                       FEE CALCULATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates protocol and creator fees based on token type
    /// @dev Handles launch token detection and fee structure application
    /// @param tokenAddress Address of the token to calculate fees for
    /// @param amountIn Input amount used for fee calculation
    /// @param isPonderPair Whether the pair includes the PONDER token
    /// @param launcherAddress Address of the launcher contract for validation
    /// @return protocolFee Amount of fee allocated to protocol
    /// @return creatorFee Amount of fee allocated to token creator
    function calculateFees(
        address tokenAddress,
        uint256 amountIn,
        bool isPonderPair,
        address launcherAddress
    ) internal view returns (uint256 protocolFee, uint256 creatorFee) {
        if (amountIn == 0) return (0, 0);

        try ILaunchToken(tokenAddress).isLaunchToken() returns (bool isLaunch) {
            if (isLaunch &&
                ILaunchToken(tokenAddress).launcher() == launcherAddress) {

                if (isPonderPair) {
                    protocolFee = (amountIn * PonderPairTypes.PONDER_PROTOCOL_FEE) /
                                    PonderPairTypes.FEE_DENOMINATOR;
                    creatorFee = (amountIn * PonderPairTypes.PONDER_CREATOR_FEE) /
                                    PonderPairTypes.FEE_DENOMINATOR;
                } else {
                    protocolFee = (amountIn * PonderPairTypes.KUB_PROTOCOL_FEE) /
                                    PonderPairTypes.FEE_DENOMINATOR;
                    creatorFee = (amountIn * PonderPairTypes.KUB_CREATOR_FEE) /
                                    PonderPairTypes.FEE_DENOMINATOR;
                }
            } else {
                protocolFee = (amountIn * PonderPairTypes.STANDARD_PROTOCOL_FEE) /
                                PonderPairTypes.FEE_DENOMINATOR;
            }
        } catch {
            protocolFee = (amountIn * PonderPairTypes.STANDARD_PROTOCOL_FEE) /
                            PonderPairTypes.FEE_DENOMINATOR;
        }

        return (protocolFee, creatorFee);
    }

    /// @notice Calculates fees and retrieves creator address in a single operation
    /// @dev Gas-optimized function that avoids duplicate calls and conditionals
    /// @param token Token address
    /// @param amountIn Amount of token swapped
    /// @param isPonderPair Whether this is a PONDER pair
    /// @param launcherAddress Address of the launcher contract
    /// @return protocolFee Amount of fee for protocol
    /// @return creatorFee Amount of fee for creator
    /// @return creator Address of the creator (or address(0) if none)
    function calculateAndReturnProtocolFee(
        address token,
        uint256 amountIn,
        bool isPonderPair,
        address launcherAddress
    ) internal view returns (uint256 protocolFee, uint256 creatorFee, address creator) {
        if (amountIn == 0) return (0, 0, address(0));

        (protocolFee, creatorFee) = calculateFees(token, amountIn, isPonderPair, launcherAddress);

        if (creatorFee > 0) {
            // Attempt to get creator, return address(0) if it fails
            try ILaunchToken(token).creator() returns (address c) {
                creator = c != address(0) ? c : address(0);
            } catch {
                // Keep creator as address(0)
            }
        }

        return (protocolFee, creatorFee, creator);
    }

    /// @notice Handles fees for a single token
    /// @dev Legacy function kept for compatibility - new implementations should use calculateAndReturnProtocolFee
    /// @param token Token address
    /// @param amountIn Amount of token swapped
    /// @param isPonderPair Whether this is a PONDER pair
    /// @param launcherAddress Address of the launcher contract
    /// @param accumulatedFee Current accumulated fee for this token
    /// @return newAccumulatedFee Updated accumulated fee
    function handleTokenFee(
        address token,
        uint256 amountIn,
        bool isPonderPair,
        address launcherAddress,
        uint256 accumulatedFee
    ) internal returns (uint256 newAccumulatedFee) {
        if (amountIn == 0) return accumulatedFee;

        (uint256 protocolFeeAmount, uint256 creatorFeeAmount, address creator) =
                        calculateAndReturnProtocolFee(token, amountIn, isPonderPair, launcherAddress);

        // Update accumulated fees
        newAccumulatedFee = accumulatedFee + protocolFeeAmount;

        // Only transfer to creator if we have a valid creator address
        if (creatorFeeAmount > 0) {
            if (creator != address(0)) {
                IERC20(token).safeTransfer(creator, creatorFeeAmount);
            } else {
                newAccumulatedFee += creatorFeeAmount;
            }
        }

        return newAccumulatedFee;
    }

    /*//////////////////////////////////////////////////////////////
                       SWAP VALIDATION LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates constant product invariant for swaps
    /// @dev Ensures K value doesn't decrease after accounting for fees
    /// @param swapData Swap state data including balances and amounts
    /// @return bool True if K value is maintained after the swap
    function validateKValue(PonderPairTypes.SwapData memory swapData) internal pure returns (bool) {
        // Use unchecked for gas optimization since overflow is unlikely with realistic values
        unchecked {
            uint256 balance0Adjusted = swapData.balance0 * 1000 - (swapData.amount0In * 3);
            uint256 balance1Adjusted = swapData.balance1 * 1000 - (swapData.amount1In * 3);

            return balance0Adjusted * balance1Adjusted >=
                uint256(swapData.reserve0) * uint256(swapData.reserve1) * (1000 * 1000);
        }
    }

    /**
     * @notice Checks for overflow when storing reserves
     * @dev Prevents uint112 overflow in reserve values
     * @param balance0 Balance of token0
     * @param balance1 Balance of token1
     * @return reservesValid Whether reserves can be stored without overflow
     */
    function validateReserveOverflow(
        uint256 balance0,
        uint256 balance1
    ) internal pure returns (bool reservesValid) {
        return balance0 <= type(uint112).max && balance1 <= type(uint112).max;
    }

    /// @notice Validates swap outputs against reserves
    /// @dev Simple validation to ensure output amounts don't exceed reserves
    /// @param amount0Out Amount of token0 to output
    /// @param amount1Out Amount of token1 to output
    /// @param reserve0 Current reserve of token0
    /// @param reserve1 Current reserve of token1
    /// @return isValid Whether the swap amounts are valid
    function validateOutputAmounts(
        uint256 amount0Out,
        uint256 amount1Out,
        uint112 reserve0,
        uint112 reserve1
    ) internal pure returns (bool isValid) {
        // Check that outputs don't exceed reserves
        return (amount0Out < reserve0 && amount1Out < reserve1);
    }

    /// @notice Validates sync operation requirements
    /// @dev Checks that balances are sufficient for accumulated fees
    /// @param balance0 Current balance of token0
    /// @param balance1 Current balance of token1
    /// @param accumulatedFee0 Accumulated fees for token0
    /// @param accumulatedFee1 Accumulated fees for token1
    /// @return isValid Whether the sync operation is valid
    function validateSync(
        uint256 balance0,
        uint256 balance1,
        uint256 accumulatedFee0,
        uint256 accumulatedFee1
    ) internal pure returns (bool isValid) {
        // Combined condition for gas optimization
        return balance0 >= accumulatedFee0 &&
        balance1 >= accumulatedFee1 &&
        balance0 > 0 &&
            balance1 > 0;
    }
}
