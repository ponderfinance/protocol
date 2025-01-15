// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/IFeeDistributor.sol";
import "../interfaces/IPonderFactory.sol";
import "../interfaces/IPonderPair.sol";
import "../interfaces/IPonderRouter.sol";
import "../interfaces/IPonderStaking.sol";
import "../interfaces/IERC20.sol";
import "../libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FeeDistributor
 * @notice Handles collection and distribution of protocol fees from trading
 * @dev Collects fees from pairs, converts to PONDER, and distributes to xPONDER stakers and team
 */
contract FeeDistributor is IFeeDistributor, ReentrancyGuard {
    mapping(address => uint256) public lastPairDistribution;
    mapping(address => bool) private processedPairs;

    /// @notice Factory contract reference for pair creation and fee collection
    IPonderFactory public immutable factory;

    /// @notice Router contract used for token conversions
    IPonderRouter public immutable router;

    /// @notice PONDER token address
    address public immutable ponder;

    /// @notice xPONDER staking contract that receives 80% of fees
    IPonderStaking public immutable staking;

    /// @notice Team address that receives 20% of protocol fees
    address public team;

    /// @notice Contract owner address
    address public owner;

    /// @notice Pending owner for 2-step ownership transfer
    address public pendingOwner;

    /// @notice Distribution ratio for xKOI stakers (80%)
    uint256 public stakingRatio = 8000;

    /// @notice Distribution ratio for team (20%)
    uint256 public teamRatio = 2000;

    /// @notice Minimum amount for conversion to prevent dust
    uint256 public constant MINIMUM_AMOUNT = 1000;

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    uint256 public constant DISTRIBUTION_COOLDOWN = 1 hours;
    uint256 public constant MAX_PAIRS_PER_DISTRIBUTION = 10;
    uint256 public lastDistributionTimestamp; // Rename for clarity

    /// @notice Custom errors
    error InvalidRatio();
    error RatioSumIncorrect();
    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();
    error InvalidAmount();
    error SwapFailed();
    error TransferFailed();
    error InsufficientOutputAmount();
    error PairNotFound();
    error InvalidPairCount();
    error InvalidPair();
    error DistributionTooFrequent();
    error InsufficientAccumulation();

    /**
     * @notice Contract constructor
     * @param _factory Factory contract address
     * @param _router Router contract address for swaps
     * @param _ponder KOI token address
     * @param _staking xKOI staking contract address
     * @param _team Team address that receives 20% of fees
     */
    constructor(
        address _factory,
        address _router,
        address _ponder,
        address _staking,
        address _team
    ) {
        if (_factory == address(0) || _router == address(0) || _ponder == address(0) ||
        _staking == address(0) || _team == address(0)) {
            revert ZeroAddress();
        }

        factory = IPonderFactory(_factory);
        router = IPonderRouter(_router);
        ponder = _ponder;
        staking = IPonderStaking(_staking);
        team = _team;
        owner = msg.sender;

        // Approve router for all conversions
        IERC20(_ponder).approve(_router, type(uint256).max);
    }

    /**
        * @notice Safely collects fees from a specific pair using CEI pattern
     * @param pair Address of the pair to collect fees from
     * @dev Implements Checks-Effects-Interactions pattern with reentrancy guard
     */
    function collectFeesFromPair(address pair) public nonReentrant {
        // CHECKS
        require(pair != address(0), "Invalid pair address");
        IPonderPair pairContract = IPonderPair(pair);
        address token0 = pairContract.token0();
        address token1 = pairContract.token1();

        // Cache initial balances
        uint256 initialBalance0 = IERC20(token0).balanceOf(address(this));
        uint256 initialBalance1 = IERC20(token1).balanceOf(address(this));

        // EFFECTS - None for this function

        // INTERACTIONS - Performed last
        // Single sync call instead of multiple
        pairContract.sync();

        // Collect fees
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
        if (token == ponder) return;

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount < MINIMUM_AMOUNT) revert InvalidAmount();

        // Reuse same protection as distributePairFees
        uint256 minOutAmount = _calculateMinimumPonderOut(token, amount);

        // Approve router
        IERC20(token).approve(address(router), amount);

        // Setup path
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = ponder;

        // Perform swap with strict output requirements
        try router.swapExactTokensForTokens(
            amount,
            minOutAmount,
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            emit FeesConverted(token, amount, amounts[1]);
        } catch {
            revert SwapFailed();
        }
    }

    event DistributionAttempt(uint256 currentTime, uint256 lastDistribution, uint256 timeSinceLastDistribution);

    /**
     * @notice Distributes converted fees to stakers and team
     * @dev Splits fees 80/20 between xPONDER stakers and team
     */
    function _distribute() internal {
        // Check cooldown first
        if (lastDistributionTimestamp != 0) {
            uint256 timeElapsed = block.timestamp - lastDistributionTimestamp;
            if (timeElapsed < DISTRIBUTION_COOLDOWN) {
                revert DistributionTooFrequent();
            }
        }

        uint256 totalAmount = IERC20(ponder).balanceOf(address(this));
        if (totalAmount < MINIMUM_AMOUNT) revert InvalidAmount();

        // Update timestamp BEFORE transfers
        lastDistributionTimestamp = block.timestamp;

        // Calculate splits
        uint256 stakingAmount = (totalAmount * stakingRatio) / BASIS_POINTS;
        uint256 teamAmount = (totalAmount * teamRatio) / BASIS_POINTS;

        // Transfer to staking
        if (stakingAmount > 0) {
            if (!IERC20(ponder).transfer(address(staking), stakingAmount)) {
                revert TransferFailed();
            }
        }

        // Transfer to team
        if (teamAmount > 0) {
            if (!IERC20(ponder).transfer(team, teamAmount)) {
                revert TransferFailed();
            }
        }

        emit FeesDistributed(totalAmount, stakingAmount, teamAmount);
    }

    function distribute() external nonReentrant {
        _distribute();
    }

    /**
     * @notice Distributes fees from specific pairs
     * @param pairs Array of pair addresses to collect and distribute fees from
     */
    function distributePairFees(address[] calldata pairs) external nonReentrant {
        // Check array bounds
        if (pairs.length == 0 || pairs.length > MAX_PAIRS_PER_DISTRIBUTION)
            revert InvalidPairCount();

        // First collect from all pairs with safety checks
        for (uint256 i = 0; i < pairs.length; i++) {
            address currentPair = pairs[i];

            // Validate pair
            if (currentPair == address(0) || processedPairs[currentPair])
                revert InvalidPair();

            // Check if enough time has passed since last distribution
            if (block.timestamp - lastPairDistribution[currentPair] < DISTRIBUTION_COOLDOWN)
                revert DistributionTooFrequent();

            // Mark as processed
            processedPairs[currentPair] = true;

            // Update last distribution time
            lastPairDistribution[currentPair] = block.timestamp;

            // Try to collect fees
            try this.collectFeesFromPair(currentPair) {
                // Reset processed flag after successful collection
                processedPairs[currentPair] = false;
            } catch {
                // Reset processed flag and continue if collection fails
                processedPairs[currentPair] = false;
                continue;
            }
        }

        // Convert collected fees to PONDER with slippage protection
        address[] memory uniqueTokens = _getUniqueTokens(pairs);
        uint256 preBalance = IERC20(ponder).balanceOf(address(this));

        for (uint256 i = 0; i < uniqueTokens.length; i++) {
            address token = uniqueTokens[i];
            uint256 tokenBalance = IERC20(token).balanceOf(address(this));

            if (tokenBalance >= MINIMUM_AMOUNT) {
                // Add slippage check for conversion
                uint256 minOutAmount = _calculateMinimumPonderOut(token, tokenBalance);
                _convertFeesWithSlippage(token, tokenBalance, minOutAmount);
            }
        }

        // Verify minimum accumulated PONDER
        uint256 postBalance = IERC20(ponder).balanceOf(address(this));
        if (postBalance - preBalance < MINIMUM_AMOUNT) revert InsufficientAccumulation();

        // Distribute converted PONDER
        if (IERC20(ponder).balanceOf(address(this)) >= MINIMUM_AMOUNT) {
            _distribute();
        }
    }

    /**
 * @notice Calculates minimum PONDER output for a given token input with 1% max slippage
 * @param token Input token address
 * @param amountIn Amount of input tokens
 * @return minOut Minimum amount of PONDER to receive
 */
    function _calculateMinimumPonderOut(
        address token,
        uint256 amountIn
    ) internal view returns (uint256 minOut) {
        address pair = factory.getPair(token, ponder);
        if (pair == address(0)) revert PairNotFound();

        (uint112 reserve0, uint112 reserve1, ) = IPonderPair(pair).getReserves();

        (uint112 tokenReserve, uint112 ponderReserve) =
            IPonderPair(pair).token0() == token ?
                (reserve0, reserve1) :
                (reserve1, reserve0);

        // Add check for extreme reserve imbalance
        if (tokenReserve == 0 || ponderReserve == 0) revert("Invalid reserves");

        uint256 reserveRatio = (uint256(tokenReserve) * 1e18) / uint256(ponderReserve);
        if (reserveRatio > 100e18 || reserveRatio < 1e16) revert SwapFailed();

        uint256 amountOut = router.getAmountsOut(
            amountIn,
            _getPath(token, ponder)
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
     * @param token Input token to convert
     * @param amountIn Amount of input tokens
     * @param minOutAmount Minimum amount of PONDER to receive
     */
    function _convertFeesWithSlippage(
        address token,
        uint256 amountIn,
        uint256 minOutAmount
    ) internal {
        if (token == ponder) return;

        // Approve router if needed
        IERC20(token).approve(address(router), amountIn);

        // Setup path for swap
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = ponder;

        try router.swapExactTokensForTokens(
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


    /**
     * @notice Updates fee distribution ratios
     * @param _stakingRatio New staking ratio (in basis points)
     * @param _teamRatio New team ratio (in basis points)
     */
    function updateDistributionRatios(
        uint256 _stakingRatio,
        uint256 _teamRatio
    ) external onlyOwner {
        if (_stakingRatio + _teamRatio != BASIS_POINTS) {
            revert RatioSumIncorrect();
        }

        stakingRatio = _stakingRatio;
        teamRatio = _teamRatio;

        emit DistributionRatiosUpdated(_stakingRatio,  _teamRatio);
    }

    /**
     * @notice Updates team address
     * @param _team New team address
     */
    function setTeam(address _team) external onlyOwner {
        if (_team == address(0)) revert ZeroAddress();
        team = _team;
    }

    /**
     * @notice Returns current distribution ratios
     * @return _stakingRatio Current staking ratio
     * @return _teamRatio Current team ratio
     */
    function getDistributionRatios() external view returns (
        uint256 _stakingRatio,
        uint256 _teamRatio
    ) {
        return (stakingRatio, teamRatio);
    }

    /**
     * @notice Initiates ownership transfer
     * @param newOwner Address of new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
    }

    /**
     * @notice Completes ownership transfer
     */
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /**
     * @notice Gets unique tokens from pairs for conversion
     * @param pairs Array of pair addresses
     * @return tokens Array of unique token addresses
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

            if (!found0 && token0 != ponder) {
                tempTokens[count++] = token0;
            }
            if (!found1 && token1 != ponder) {
                tempTokens[count++] = token1;
            }
        }

        tokens = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            tokens[i] = tempTokens[i];
        }
    }

    /**
   * @notice Emergency function to rescue tokens in case of failed collection
     * @dev Only callable by owner with timelock
     */
    function emergencyTokenRecover(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Invalid amount");

        IERC20(token).transfer(to, amount);
        emit EmergencyTokenRecovered(token, to, amount);
    }


    /// @notice Modifier for owner-only functions
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
}
