// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IFeeDistributor } from "./IFeeDistributor.sol";
import { FeeDistributorStorage } from "./storage/FeeDistributorStorage.sol";
import { FeeDistributorTypes } from "./types/FeeDistributorTypes.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPonderPair } from "../pair/IPonderPair.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { IPonderStaking } from "../staking/IPonderStaking.sol";

/*//////////////////////////////////////////////////////////////
                        FEE DISTRIBUTOR
//////////////////////////////////////////////////////////////*/

/// @title FeeDistributor
/// @author taayyohh
/// @notice Manages the collection, conversion, and distribution of protocol fees
/// @dev Implements core fee management logic with reentrancy protection
contract FeeDistributor is IFeeDistributor, FeeDistributorStorage, ReentrancyGuard {
    using FeeDistributorTypes for *;

    /*//////////////////////////////////////////////////////////////
                    PROTOCOL STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The protocol's factory contract for managing pairs
    IPonderFactory public immutable FACTORY;

    /// @notice The protocol's router contract for swap operations
    IPonderRouter public immutable ROUTER;

    /// @notice The address of the protocol's PONDER token
    address public immutable PONDER;

    /// @notice The protocol's staking contract for PONDER tokens
    IPonderStaking public immutable STAKING;

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
   //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the fee distributor with core protocol settings
    /// @dev Sets up initial state and approves router for token conversions
    /// @param _factory Address of the protocol factory contract
    /// @param _router Address of the protocol router contract
    /// @param _ponder Address of the PONDER token contract
    /// @param _staking Address of the protocol staking contract
    constructor(
        address _factory,
        address _router,
        address _ponder,
        address _staking
    ) {
        if (_factory == address(0)) revert IFeeDistributor.ZeroAddress();
        if (_router == address(0)) revert IFeeDistributor.ZeroAddress();
        if (_ponder == address(0)) revert IFeeDistributor.ZeroAddress();
        if (_staking == address(0)) revert IFeeDistributor.ZeroAddress();

        FACTORY = IPonderFactory(_factory);
        ROUTER = IPonderRouter(_router);
        PONDER = _ponder;
        STAKING = IPonderStaking(_staking);

        owner = msg.sender;

        // Approve router for all conversions
        if (!IERC20(_ponder).approve(_router, type(uint256).max)) {
            revert IFeeDistributor.ApprovalFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        CORE FEE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Collects fees from a specific trading pair
    /// @param pair Address of the trading pair to collect fees from
    function _collectFeesFromPair(address pair) internal {
        if (pair == address(0)) revert InvalidPairAddress();

        IPonderPair pairContract = IPonderPair(pair);

        // Cache token addresses first
        (address token0, address token1) = (pairContract.token0(), pairContract.token1());

        // Get initial balances
        uint256 initialBalance0 = IERC20(token0).balanceOf(address(this));
        uint256 initialBalance1 = IERC20(token1).balanceOf(address(this));

        // Execute pair operations
        pairContract.sync();
        pairContract.skim(address(this));

        // Calculate collected amounts
        uint256 finalBalance0 = IERC20(token0).balanceOf(address(this));
        uint256 finalBalance1 = IERC20(token1).balanceOf(address(this));

        uint256 collected0 = finalBalance0 - initialBalance0;
        uint256 collected1 = finalBalance1 - initialBalance1;

        if (collected0 > 0) emit FeesCollected(token0, collected0);
        if (collected1 > 0) emit FeesCollected(token1, collected1);
    }

    /// @notice External wrapper for collecting fees from a single pair
    /// @param pair Address of the trading pair to collect fees from
    function collectFeesFromPair(address pair) external nonReentrant {
        _collectFeesFromPair(pair);
    }

    /// @notice Converts collected token fees into PONDER tokens
    /// @dev Includes slippage protection and minimum output verification
    /// @param token Address of the token to convert to PONDER
    function convertFees(address token) external nonReentrant {
        if (token == PONDER) return;

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount < FeeDistributorTypes.MINIMUM_AMOUNT) revert IFeeDistributor.InvalidAmount();

        // Calculate minimum output with slippage protection
        uint256 minOutAmount = _calculateMinimumPonderOut(token, amount);

        // Approve router
        if (!IERC20(token).approve(address(ROUTER), amount)) {
            revert IFeeDistributor.ApprovalFailed();
        }

        // Setup path
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = PONDER;

        // Perform swap with strict output requirements
        try ROUTER.swapExactTokensForTokens(
            amount,
            minOutAmount,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            emit FeesConverted(token, amount, amounts[1]);
        } catch {
            revert IFeeDistributor.SwapFailed();
        }
    }

    /// @notice Distributes accumulated PONDER tokens to stakeholders
    /// @dev Triggers the internal distribution mechanism
    function distribute() external nonReentrant {
        _distribute();
    }

    /// @notice Internal distribution logic for accumulated PONDER tokens
    /// @dev Splits tokens between staking rewards and team wallet based on ratios
    function _distribute() internal {
        // - Only used for rate limiting fee distributions
        // - Small timestamp manipulation doesn't significantly impact distribution mechanics
        // - No critical value calculations depend on this timestamp
        // slither-disable-next-line block.timestamp
        if (lastDistributionTimestamp != 0) {
            uint256 timeElapsed = block.timestamp - lastDistributionTimestamp;
            if (timeElapsed < FeeDistributorTypes.DISTRIBUTION_COOLDOWN) {
                revert IFeeDistributor.DistributionTooFrequent();
            }
        }

        uint256 totalAmount = IERC20(PONDER).balanceOf(address(this));
        if (totalAmount < FeeDistributorTypes.MINIMUM_AMOUNT) revert IFeeDistributor.InvalidAmount();

        // Update timestamp BEFORE transfers
        lastDistributionTimestamp = block.timestamp;

        // Send 100% to staking as team has separate allocation
        if (!IERC20(PONDER).transfer(address(STAKING), totalAmount)) {
            revert IFeeDistributor.TransferFailed();
        }

        emit FeesDistributed(totalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                     BATCH OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates an array of pairs for batch fee distribution
    /// @dev Checks array bounds, addresses, and distribution cooldowns
    /// @param pairs Array of pair addresses to validate
    function validatePairs(address[] calldata pairs) internal view {
        if (pairs.length == 0 || pairs.length > FeeDistributorTypes.MAX_PAIRS_PER_DISTRIBUTION)
            revert IFeeDistributor.InvalidPairCount();

        for (uint256 i = 0; i < pairs.length; i++) {
            address currentPair = pairs[i];
            if (currentPair == address(0) || processedPairs[currentPair])
                revert IFeeDistributor.InvalidPair();

            if (block.timestamp - lastPairDistribution[currentPair] < FeeDistributorTypes.DISTRIBUTION_COOLDOWN)
                revert IFeeDistributor.DistributionTooFrequent();
        }
    }

    /// @notice Marks pairs as being processed in current distribution cycle
    /// @dev Updates processing state and distribution timestamps
    /// @param pairs Array of pair addresses to mark
    function markPairsForProcessing(address[] calldata pairs) internal {
        for (uint256 i = 0; i < pairs.length; i++) {
            processedPairs[pairs[i]] = true;
            lastPairDistribution[pairs[i]] = block.timestamp;
        }
    }

    /// @notice Processes complete fee distribution cycle for multiple pairs
    /// @param pairs Array of pair addresses to process
    function distributePairFees(address[] calldata pairs) external nonReentrant {
        validatePairs(pairs);

        markPairsForProcessing(pairs);

        uint256 preConversionPonderBalance = IERC20(PONDER).balanceOf(address(this));
        bool anyFeesConverted = false;

        address[] memory uniqueTokens = _getUniqueTokens(pairs);

        // Process all pairs first
        for (uint256 i = 0; i < pairs.length; i++) {
            _collectFeesFromPair(pairs[i]);
            processedPairs[pairs[i]] = false;
        }

        // Then process all unique tokens
        for (uint256 i = 0; i < uniqueTokens.length; i++) {
            address token = uniqueTokens[i];
            if (token != PONDER) {
                // Cache balance check
                uint256 tokenBalance = IERC20(token).balanceOf(address(this));
                if (tokenBalance >= FeeDistributorTypes.MINIMUM_AMOUNT) {
                    // Pre-calculate slippage and path
                    uint256 minOutAmount = _calculateMinimumPonderOut(token, tokenBalance);
                    _convertFeesWithSlippage(token, tokenBalance, minOutAmount);
                    anyFeesConverted = true;
                }
            }
        }

        // Check final state
        uint256 postConversionPonderBalance = IERC20(PONDER).balanceOf(address(this));

        if (postConversionPonderBalance >= FeeDistributorTypes.MINIMUM_AMOUNT &&
            (anyFeesConverted || postConversionPonderBalance > preConversionPonderBalance)) {
            _distribute();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        CALCULATION HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates minimum PONDER output for token conversion
    /// @dev Includes 0.5% slippage tolerance and reserve checks
    /// @param token Address of input token
    /// @param amountIn Amount of input token
    /// @return minOut Minimum acceptable PONDER output
    function _calculateMinimumPonderOut(
        address token,
        uint256 amountIn
    ) internal view returns (uint256 minOut) {
        address pair = FACTORY.getPair(token, PONDER);
        if (pair == address(0)) revert IFeeDistributor.PairNotFound();

        // Cache all external calls
        (uint112 reserve0, uint112 reserve1,) = IPonderPair(pair).getReserves();
        bool isToken0 = IPonderPair(pair).token0() == token;

        (uint112 tokenReserve, uint112 ponderReserve) = isToken0 ?
            (reserve0, reserve1) :
            (reserve1, reserve0);

        if (tokenReserve == 0 || ponderReserve == 0) revert IFeeDistributor.InvalidReserves();

        uint256 reserveRatio = (uint256(tokenReserve) * 1e18) / uint256(ponderReserve);
        if (reserveRatio > 100e18 || reserveRatio < 1e16) revert IFeeDistributor.SwapFailed();

        uint256 amountOut = ROUTER.getAmountsOut(amountIn, _getPath(token, PONDER))[1];
        return (amountOut * 995) / 1000;
    }

    /// @notice Creates token swap path for router
    /// @dev Generates direct path from input token to PONDER
    /// @param tokenIn Address of input token
    /// @param tokenOut Address of output token (PONDER)
    /// @return path Array containing swap path
    function _getPath(address tokenIn, address tokenOut)
    internal
    pure
    returns (address[] memory path)
    {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    /// @notice Executes fee conversion with slippage protection
    /// @dev Handles approvals and executes swap via router
    /// @param token Address of token to convert
    /// @param amountIn Amount of input token
    /// @param minOutAmount Minimum acceptable PONDER output
    function _convertFeesWithSlippage(
        address token,
        uint256 amountIn,
        uint256 minOutAmount
    ) internal {
        if (token == PONDER) return;
        if (amountIn > type(uint96).max) revert AmountTooLarge();

        // Check and update approval in one step if needed
        uint256 currentAllowance = IERC20(token).allowance(address(this), address(ROUTER));
        if (currentAllowance < amountIn) {
            if (!IERC20(token).approve(address(ROUTER), type(uint256).max)) {
                revert ApprovalFailed();
            }
        }

        // Cache path creation
        address[] memory path = _getPath(token, PONDER);

        try ROUTER.swapExactTokensForTokens(
            amountIn,
            minOutAmount,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            emit FeesConverted(token, amountIn, amounts[1]);
        } catch {
            revert SwapFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                      ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Extracts unique tokens from a set of pairs
    /// @dev Filters out PONDER token and duplicates
    /// @param pairs Array of pair addresses to process
    /// @return tokens Array of unique token addresses
    function _getUniqueTokens(address[] calldata pairs) internal view returns (address[] memory tokens) {
        address[] memory tempTokens = new address[](pairs.length * 2);
        uint256 count = 0;

        for (uint256 i = 0; i < pairs.length; i++) {
            address token0 = IPonderPair(pairs[i]).token0();
            address token1 = IPonderPair(pairs[i]).token1();

            bool found0 = false;
            bool found1 = false;

            for (uint256 j = 0; j < count; j++) {
                if (tempTokens[j] == token0) found0 = true;
                if (tempTokens[j] == token1) found1 = true;
            }

            if (!found0 && token0 != PONDER) {
                tempTokens[count++] = token0;
            }
            if (!found1 && token1 != PONDER) {
                tempTokens[count++] = token1;
            }
        }

        tokens = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            tokens[i] = tempTokens[i];
        }
    }

    /// @notice Emergency function to recover stuck tokens
    /// @dev Allows owner to rescue tokens in case of contract issues
    /// @param token Address of token to recover
    /// @param to Address to send recovered tokens to
    /// @param amount Amount of tokens to recover
    function emergencyTokenRecover(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert IFeeDistributor.InvalidRecipient();
        if (amount == 0) revert IFeeDistributor.InvalidRecoveryAmount();

        emit EmergencyTokenRecovered(token, to, amount);

        if (!IERC20(token).transfer(to, amount)) {
            revert IFeeDistributor.TransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        OWNERSHIP MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Initiates transfer of contract ownership
    /// @dev First step of two-step ownership transfer
    /// @param newOwner Address of proposed new owner
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert IFeeDistributor.ZeroAddress();
        pendingOwner = newOwner;
    }

    /// @notice Completes ownership transfer process
    /// @dev Can only be called by pending owner
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert IFeeDistributor.NotPendingOwner();
        owner = pendingOwner;
        pendingOwner = address(0);
    }


    /*//////////////////////////////////////////////////////////////
                            VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns minimum amount required for operations
    /// @dev Used for validating transaction viability
    /// @return Minimum amount threshold
    function minimumAmount() external pure returns (uint256) {
        return FeeDistributorTypes.MINIMUM_AMOUNT;
    }

    /*//////////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to contract owner
    /// @dev Reverts if caller is not the current owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert IFeeDistributor.NotOwner();
        _;
    }
}
