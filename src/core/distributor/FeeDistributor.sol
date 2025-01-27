// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IFeeDistributor } from "./IFeeDistributor.sol";
import { FeeDistributorStorage } from "./storage/FeeDistributorStorage.sol";
import { FeeDistributorTypes } from "./types/FeeDistributorTypes.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPonderPair } from "../pair/IPonderPair.sol";

/// @title FeeDistributor
/// @notice Implementation of fee collection and distribution
contract FeeDistributor is IFeeDistributor, FeeDistributorStorage, ReentrancyGuard {
    using FeeDistributorTypes for *;

    constructor(
        address _factory,
        address _router,
        address _ponder,
        address _staking,
        address _team
    ) FeeDistributorStorage(_factory, _router, _ponder, _staking) {
        if (_team == address(0)) revert FeeDistributorTypes.ZeroAddress();
        team = _team;
        owner = msg.sender;

        // Approve router for all conversions
        if (!IERC20(_ponder).approve(_router, type(uint256).max)) {
            revert FeeDistributorTypes.ApprovalFailed();
        }
    }

    /**
     * @notice Collects fees from a specific pair using CEI pattern
     * @param pair Address of the pair to collect fees from
     */
    function collectFeesFromPair(address pair) public nonReentrant {
        // CHECKS
        if (pair == address(0)) revert FeeDistributorTypes.InvalidPairAddress();

        IPonderPair pairContract = IPonderPair(pair);
        address token0 = pairContract.token0();
        address token1 = pairContract.token1();

        // Cache initial balances
        uint256 initialBalance0 = IERC20(token0).balanceOf(address(this));
        uint256 initialBalance1 = IERC20(token1).balanceOf(address(this));

        // INTERACTIONS - Performed last
        pairContract.sync();
        pairContract.skim(address(this));

        // CHECKS - Verify collection success
        uint256 finalBalance0 = IERC20(token0).balanceOf(address(this));
        uint256 finalBalance1 = IERC20(token1).balanceOf(address(this));

        uint256 collected0 = finalBalance0 - initialBalance0;
        uint256 collected1 = finalBalance1 - initialBalance1;

        // Emit events after all state changes and interactions
        if (collected0 > 0) {
            emit FeesCollected(token0, collected0);
        }
        if (collected1 > 0) {
            emit FeesCollected(token1, collected1);
        }
    }

    /**
     * @notice Converts collected fees to PONDER
     * @param token Address of the token to convert
     */
    function convertFees(address token) external nonReentrant {
        if (token == PONDER) return;

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount < FeeDistributorTypes.MINIMUM_AMOUNT) revert FeeDistributorTypes.InvalidAmount();

        // Calculate minimum output with slippage protection
        uint256 minOutAmount = _calculateMinimumPonderOut(token, amount);

        // Approve router
        if (!IERC20(token).approve(address(ROUTER), amount)) {
            revert FeeDistributorTypes.ApprovalFailed();
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
            revert FeeDistributorTypes.SwapFailed();
        }
    }

    /**
     * @notice Distributes converted fees to stakeholders
     */
// External distribute function that users call
    function distribute() external nonReentrant {
        _distribute();
    }

    function _distribute() internal {
        // - Only used for rate limiting fee distributions
        // - Small timestamp manipulation doesn't significantly impact distribution mechanics
        // - No critical value calculations depend on this timestamp
        // slither-disable-next-line block.timestamp
        if (lastDistributionTimestamp != 0) {
            uint256 timeElapsed = block.timestamp - lastDistributionTimestamp;
            if (timeElapsed < FeeDistributorTypes.DISTRIBUTION_COOLDOWN) {
                revert FeeDistributorTypes.DistributionTooFrequent();
            }
        }

        uint256 totalAmount = IERC20(PONDER).balanceOf(address(this));
        if (totalAmount < FeeDistributorTypes.MINIMUM_AMOUNT) revert FeeDistributorTypes.InvalidAmount();

        // Update timestamp BEFORE transfers
        lastDistributionTimestamp = block.timestamp;

        // Calculate splits
        uint256 stakingAmount = (totalAmount * stakingRatio) / FeeDistributorTypes.BASIS_POINTS;
        uint256 teamAmount = (totalAmount * teamRatio) / FeeDistributorTypes.BASIS_POINTS;

        // Transfer to staking
        if (stakingAmount > 0) {
            if (!IERC20(PONDER).transfer(address(STAKING), stakingAmount)) {
                revert FeeDistributorTypes.TransferFailed();
            }
        }

        // Transfer to team
        if (teamAmount > 0) {
            if (!IERC20(PONDER).transfer(team, teamAmount)) {
                revert FeeDistributorTypes.TransferFailed();
            }
        }

        emit FeesDistributed(totalAmount, stakingAmount, teamAmount);
    }

    /// @notice Validates an array of pairs for fee distribution
    /// @dev Checks for array length, zero addresses, duplicate processing, and distribution cooldown
    /// @param pairs Array of pair addresses to validate
    function validatePairs(address[] calldata pairs) internal view {
        if (pairs.length == 0 || pairs.length > FeeDistributorTypes.MAX_PAIRS_PER_DISTRIBUTION)
            revert FeeDistributorTypes.InvalidPairCount();

        for (uint256 i = 0; i < pairs.length; i++) {
            address currentPair = pairs[i];
            if (currentPair == address(0) || processedPairs[currentPair])
                revert FeeDistributorTypes.InvalidPair();

            if (block.timestamp - lastPairDistribution[currentPair] < FeeDistributorTypes.DISTRIBUTION_COOLDOWN)
                revert FeeDistributorTypes.DistributionTooFrequent();
        }
    }



    /// @notice Marks pairs as being processed and updates their last distribution timestamp
    /// @dev Sets processedPairs mapping to true and updates lastPairDistribution timestamp
    /// @param pairs Array of pair addresses to mark for processing
    function markPairsForProcessing(address[] calldata pairs) internal {
        for (uint256 i = 0; i < pairs.length; i++) {
            processedPairs[pairs[i]] = true;
            lastPairDistribution[pairs[i]] = block.timestamp;
        }
    }

    /// @notice Collects fees from multiple pairs and handles any collection failures
    /// @dev Attempts to collect fees from each pair, catching and handling any failures
    /// @param pairs Array of pair addresses to collect fees from
    function collectFeesFromPairs(address[] calldata pairs) internal {
        for (uint256 i = 0; i < pairs.length; i++) {
            address currentPair = pairs[i];
            try this.collectFeesFromPair(currentPair) {
                processedPairs[currentPair] = false;
            } catch {
                processedPairs[currentPair] = false;
                continue;
            }
        }
    }

    /// @notice Converts collected fees from various tokens to PONDER tokens
    /// @dev Calculates minimum output amounts and performs conversions with slippage protection
    /// @param uniqueTokens Array of unique token addresses to convert
    /// @return preBalance The PONDER balance before conversions
    /// @return postBalance The PONDER balance after all conversions
    function convertCollectedFees(address[] memory uniqueTokens)
        internal
        returns
    (uint256 preBalance, uint256 postBalance) {
        preBalance = IERC20(PONDER).balanceOf(address(this));

        for (uint256 i = 0; i < uniqueTokens.length; i++) {
            address token = uniqueTokens[i];
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));

            if (tokenBalance >= FeeDistributorTypes.MINIMUM_AMOUNT) {
                uint256 minOutAmount = _calculateMinimumPonderOut(token, tokenBalance);
                _convertFeesWithSlippage(token, tokenBalance, minOutAmount);
            }
        }

        postBalance = IERC20(PONDER).balanceOf(address(this));
    }

    /**
    * @notice Distributes fees from specific pairs
     * @param pairs Array of pair addresses to collect and distribute fees from
     */
    function distributePairFees(address[] calldata pairs) external nonReentrant {
        // Step 1: Validate pairs
        validatePairs(pairs);

        // Step 2: Mark pairs for processing
        markPairsForProcessing(pairs);

        // Step 3: Collect fees
        collectFeesFromPairs(pairs);

        // Step 4: Get unique tokens and convert fees
        address[] memory uniqueTokens = _getUniqueTokens(pairs);
        (uint256 preBalance, uint256 postBalance) = convertCollectedFees(uniqueTokens);

        // Step 5: Verify and distribute
        if (postBalance - preBalance < FeeDistributorTypes.MINIMUM_AMOUNT) {
            revert FeeDistributorTypes.InsufficientAccumulation();
        }

        if (IERC20(PONDER).balanceOf(address(this)) >= FeeDistributorTypes.MINIMUM_AMOUNT) {
            _distribute();
        }
    }
    /**
     * @notice Calculates minimum PONDER output for a given token input with 0.5% max slippage
     */

    function _calculateMinimumPonderOut(
        address token,
        uint256 amountIn
    ) internal view returns (uint256 minOut) {
        address pair = FACTORY.getPair(token, PONDER);
        if (pair == address(0)) revert FeeDistributorTypes.PairNotFound();

        /// @dev Third value from getReserves is block.timestamp
        /// which we don't need for minimal output calculation
        /// slither-disable-next-line unused-return
        (uint112 reserve0, uint112 reserve1,) = IPonderPair(pair).getReserves();

        (uint112 tokenReserve, uint112 ponderReserve) =
            IPonderPair(pair).token0() == token ?
                (reserve0, reserve1) :
                (reserve1, reserve0);

        // Add check for extreme reserve imbalance
        if (tokenReserve == 0 || ponderReserve == 0) revert FeeDistributorTypes.InvalidReserves();

        uint256 reserveRatio = (uint256(tokenReserve) * 1e18) / uint256(ponderReserve);
        if (reserveRatio > 100e18 || reserveRatio < 1e16) revert FeeDistributorTypes.SwapFailed();

        uint256 amountOut = ROUTER.getAmountsOut(
            amountIn,
            _getPath(token, PONDER)
        )[1];

        // Make slippage tolerance more strict - 0.5% instead of 1%
        return (amountOut * 995) / 1000;
    }

    /**
     * @notice Helper to create path array for swaps
     */
    function _getPath(address tokenIn, address tokenOut)
    internal
    pure
    returns (address[] memory path)
    {
        path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
    }

    /**
     * @notice Helper function to convert fees with slippage protection
     */
    function _convertFeesWithSlippage(
        address token,
        uint256 amountIn,
        uint256 minOutAmount
    ) internal {
        if (token == PONDER) return;

        if (amountIn > type(uint96).max) revert FeeDistributorTypes.AmountTooLarge();

        // Approve router if needed
        uint256 currentAllowance = IERC20(token).allowance(address(this), address(ROUTER));
        if (currentAllowance < amountIn) {
            if (!IERC20(token).approve(address(ROUTER), type(uint256).max)) {
                revert FeeDistributorTypes.ApprovalFailed();
            }
        }

        // Setup path for swap
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = PONDER;

        try ROUTER.swapExactTokensForTokens(
            amountIn,
            minOutAmount,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            emit FeesConverted(token, amountIn, amounts[1]);
        } catch {
            revert FeeDistributorTypes.SwapFailed();
        }
    }

    /**
     * @notice Updates fee distribution ratios
     */
    function updateDistributionRatios(
        uint256 _stakingRatio,
        uint256 _teamRatio
    ) external onlyOwner {
        if (_stakingRatio + _teamRatio != FeeDistributorTypes.BASIS_POINTS) {
            revert FeeDistributorTypes.RatioSumIncorrect();
        }

        stakingRatio = _stakingRatio;
        teamRatio = _teamRatio;

        emit DistributionRatiosUpdated(_stakingRatio, _teamRatio);
    }

    /**
     * @notice Gets unique tokens from pairs for conversion
     */
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

    /**
     * @notice Emergency function to rescue tokens
     */
    function emergencyTokenRecover(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (to == address(0)) revert FeeDistributorTypes.InvalidRecipient();
        if (amount == 0) revert FeeDistributorTypes.InvalidRecoveryAmount();

        if (!IERC20(token).transfer(to, amount)) {
            revert FeeDistributorTypes.TransferFailed();
        }
        emit EmergencyTokenRecovered(token, to, amount);
    }

    /**
     * @notice Returns current distribution ratios
     */
    function getDistributionRatios() external view returns (
        uint256 _stakingRatio,
        uint256 _teamRatio
    ) {
        return (stakingRatio, teamRatio);
    }

    /**
     * @notice Updates team address
     */
    function setTeam(address _team) external onlyOwner {
        if (_team == address(0)) revert FeeDistributorTypes.ZeroAddress();
        team = _team;
    }

    /**
     * @notice Initiates ownership transfer
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert FeeDistributorTypes.ZeroAddress();
        pendingOwner = newOwner;
    }

    /**
     * @notice Completes ownership transfer
     */
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert FeeDistributorTypes.NotPendingOwner();
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function minimumAmount() external pure returns (uint256) {
        return FeeDistributorTypes.MINIMUM_AMOUNT;
    }

    /// @notice Modifier for owner-only functions
    modifier onlyOwner() {
        if (msg.sender != owner) revert FeeDistributorTypes.NotOwner();
        _;
    }
}
