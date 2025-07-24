// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IFeeDistributor } from "./IFeeDistributor.sol";
import { FeeDistributorStorage } from "./storage/FeeDistributorStorage.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPonderPair } from "../pair/IPonderPair.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { IPonderStaking } from "../staking/IPonderStaking.sol";
import { IPonderPriceOracle } from "../oracle/IPonderPriceOracle.sol";

/*//////////////////////////////////////////////////////////////
                        FEE DISTRIBUTOR V2
//////////////////////////////////////////////////////////////*/

/// @title FeeDistributorV2
/// @author taayyohh
/// @notice Enhanced fee distributor with dynamic minimums and LP token handling
/// @dev Implements dynamic thresholds based on USD value and proper LP token processing
contract FeeDistributorV2 is IFeeDistributor, FeeDistributorStorage, ReentrancyGuard {
    
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Minimum USD value required for fee operations ($1.00)
    uint256 public constant MINIMUM_USD_VALUE = 1e18; // $1.00 in 18 decimals
    
    /// @notice Maximum number of pairs that can be processed in a single distribution
    uint256 public constant MAX_PAIRS_PER_DISTRIBUTION = 10;
    
    /// @notice Minimum time required between distributions
    uint256 public constant DISTRIBUTION_COOLDOWN = 1 hours;
    
    /// @notice Slippage tolerance for swaps (0.5%)
    uint256 public constant SLIPPAGE_TOLERANCE = 995; // 99.5%
    uint256 public constant SLIPPAGE_BASE = 1000;

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
    
    /// @notice The protocol's price oracle for USD value calculations
    IPonderPriceOracle public immutable PRICE_ORACLE;

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR
   //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the enhanced fee distributor
    /// @param _factory Address of the protocol factory contract
    /// @param _router Address of the protocol router contract
    /// @param _ponder Address of the PONDER token contract
    /// @param _staking Address of the protocol staking contract
    /// @param _priceOracle Address of the price oracle contract
    constructor(
        address _factory,
        address _router,
        address _ponder,
        address _staking,
        address _priceOracle
    ) {
        if (_factory == address(0)) revert IFeeDistributor.ZeroAddress();
        if (_router == address(0)) revert IFeeDistributor.ZeroAddress();
        if (_ponder == address(0)) revert IFeeDistributor.ZeroAddress();
        if (_staking == address(0)) revert IFeeDistributor.ZeroAddress();
        if (_priceOracle == address(0)) revert IFeeDistributor.ZeroAddress();

        FACTORY = IPonderFactory(_factory);
        ROUTER = IPonderRouter(_router);
        PONDER = _ponder;
        STAKING = IPonderStaking(_staking);
        PRICE_ORACLE = IPonderPriceOracle(_priceOracle);

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

    /// @notice Converts collected token fees into PONDER tokens with dynamic minimum
    /// @param token Address of the token to convert to PONDER
    function convertFees(address token) external nonReentrant {
        if (token == PONDER) return;

        uint256 amount = IERC20(token).balanceOf(address(this));
        
        // Check if amount meets minimum USD value requirement
        if (!_meetsMinimumUSDValue(token, amount)) {
            revert IFeeDistributor.InvalidAmount();
        }

        // Handle LP tokens specially
        if (_isLPToken(token)) {
            _processLPToken(token, amount);
            return;
        }

        // Process regular tokens
        _convertTokenToPonder(token, amount);
    }

    /// @notice Distributes accumulated PONDER tokens to stakeholders
    function distribute() external nonReentrant {
        _distribute();
    }

    /// @notice Internal distribution logic for accumulated PONDER tokens
    function _distribute() internal {
        if (lastDistributionTimestamp != 0) {
            uint256 timeElapsed = block.timestamp - lastDistributionTimestamp;
            if (timeElapsed < DISTRIBUTION_COOLDOWN) {
                revert IFeeDistributor.DistributionTooFrequent();
            }
        }

        uint256 totalAmount = IERC20(PONDER).balanceOf(address(this));
        if (!_meetsMinimumUSDValue(PONDER, totalAmount)) {
            revert IFeeDistributor.InvalidAmount();
        }

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

    /// @notice Processes complete fee distribution cycle for multiple pairs
    /// @param pairs Array of pair addresses to process
    function distributePairFees(address[] calldata pairs) external nonReentrant {
        _validatePairs(pairs);
        _markPairsForProcessing(pairs);

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
                uint256 tokenBalance = IERC20(token).balanceOf(address(this));
                if (_meetsMinimumUSDValue(token, tokenBalance)) {
                    if (_isLPToken(token)) {
                        _processLPToken(token, tokenBalance);
                    } else {
                        _convertTokenToPonder(token, tokenBalance);
                    }
                    anyFeesConverted = true;
                }
            }
        }

        // Check final state
        uint256 postConversionPonderBalance = IERC20(PONDER).balanceOf(address(this));

        if (_meetsMinimumUSDValue(PONDER, postConversionPonderBalance) &&
            (anyFeesConverted || postConversionPonderBalance > preConversionPonderBalance)) {
            _distribute();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        LP TOKEN HANDLING
    //////////////////////////////////////////////////////////////*/

    /// @notice Processes LP tokens by removing liquidity and converting underlying tokens
    /// @param lpToken Address of the LP token to process
    /// @param amount Amount of LP tokens to process
    function _processLPToken(address lpToken, uint256 amount) internal {
        IPonderPair pair = IPonderPair(lpToken);
        
        // Get underlying tokens
        address token0 = pair.token0();
        address token1 = pair.token1();
        
        // Approve router to spend LP tokens
        if (!IERC20(lpToken).approve(address(ROUTER), amount)) {
            revert IFeeDistributor.ApprovalFailed();
        }
        
        // Remove liquidity
        try ROUTER.removeLiquidity(
            token0,
            token1,
            amount,
            0, // Accept any amount of token0
            0, // Accept any amount of token1
            address(this),
            block.timestamp
        ) returns (uint256 amount0, uint256 amount1) {
            emit LPTokenProcessed(lpToken, amount, amount0, amount1);
            
            // Convert underlying tokens to PONDER if they meet minimum
            if (token0 != PONDER && _meetsMinimumUSDValue(token0, amount0)) {
                _convertTokenToPonder(token0, amount0);
            }
            if (token1 != PONDER && _meetsMinimumUSDValue(token1, amount1)) {
                _convertTokenToPonder(token1, amount1);
            }
        } catch {
            revert LPProcessingFailed();
        }
    }

    /// @notice Checks if a token is an LP token
    /// @param token Address to check
    /// @return True if token is an LP token
    function _isLPToken(address token) internal view returns (bool) {
        try IPonderPair(token).factory() returns (address factory) {
            if (factory != address(FACTORY)) return false;
            
            try IPonderPair(token).token0() returns (address token0) {
                try IPonderPair(token).token1() returns (address token1) {
                    // Verify this is actually registered in our factory
                    address registeredPair = FACTORY.getPair(token0, token1);
                    return registeredPair == token;
                } catch { return false; }
            } catch { return false; }
        } catch { return false; }
    }

    /*//////////////////////////////////////////////////////////////
                        DYNAMIC MINIMUMS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if token amount meets minimum USD value requirement
    /// @param token Address of the token
    /// @param amount Amount of tokens
    /// @return True if amount meets minimum USD value
    function _meetsMinimumUSDValue(address token, uint256 amount) internal view returns (bool) {
        if (amount == 0) return false;
        
        // Get the pair for this token against base token (KKUB)
        address baseToken = PRICE_ORACLE.baseToken(); // This should be KKUB
        address pair = FACTORY.getPair(token, baseToken);
        
        if (pair == address(0)) {
            // No direct pair exists, fall back to conservative minimum
            return amount >= 1000;
        }
        
        try PRICE_ORACLE.getCurrentPrice(pair, token, amount) returns (uint256 baseTokenOut) {
            // Assume base token (KKUB) represents ~$1 KUB
            // For minimum $1 USD worth, we need reasonable amount of base tokens
            // This is a simplified approach using base token value as proxy for USD
            
            // Get token decimals to normalize comparison
            uint256 tokenDecimals = 18;
            try IERC20Metadata(token).decimals() returns (uint8 dec) {
                tokenDecimals = dec;
            } catch {}
            
            // Require equivalent of 1 base token (normalized for decimals)
            uint256 minimumBaseTokens = 1 * (10 ** 18); // 1 base token in 18 decimals
            
            return baseTokenOut >= minimumBaseTokens;
        } catch {
            // If price oracle fails, fall back to conservative minimum
            return amount >= 1000;
        }
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Converts a regular token to PONDER
    /// @param token Address of token to convert
    /// @param amount Amount to convert
    function _convertTokenToPonder(address token, uint256 amount) internal {
        if (token == PONDER) return;
        
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

        // Perform swap
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

    /// @notice Calculates minimum PONDER output for token conversion
    /// @param token Address of input token
    /// @param amountIn Amount of input token
    /// @return minOut Minimum acceptable PONDER output
    function _calculateMinimumPonderOut(
        address token,
        uint256 amountIn
    ) internal view returns (uint256 minOut) {
        address pair = FACTORY.getPair(token, PONDER);
        if (pair == address(0)) revert IFeeDistributor.PairNotFound();

        (uint112 reserve0, uint112 reserve1,) = IPonderPair(pair).getReserves();
        bool isToken0 = IPonderPair(pair).token0() == token;

        (uint112 tokenReserve, uint112 ponderReserve) = isToken0 ?
            (reserve0, reserve1) :
            (reserve1, reserve0);

        if (tokenReserve == 0 || ponderReserve == 0) revert IFeeDistributor.InvalidReserves();

        uint256 amountOut = ROUTER.getAmountsOut(amountIn, _getPath(token, PONDER))[1];
        return (amountOut * SLIPPAGE_TOLERANCE) / SLIPPAGE_BASE;
    }

    /// @notice Creates token swap path
    /// @param tokenIn Address of input token
    /// @param tokenOut Address of output token
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

    /// @notice Validates pairs for batch processing
    /// @param pairs Array of pair addresses to validate
    function _validatePairs(address[] calldata pairs) internal view {
        if (pairs.length == 0 || pairs.length > MAX_PAIRS_PER_DISTRIBUTION)
            revert IFeeDistributor.InvalidPairCount();

        for (uint256 i = 0; i < pairs.length; i++) {
            address currentPair = pairs[i];
            if (currentPair == address(0) || processedPairs[currentPair])
                revert IFeeDistributor.InvalidPair();

            if (block.timestamp - lastPairDistribution[currentPair] < DISTRIBUTION_COOLDOWN)
                revert IFeeDistributor.DistributionTooFrequent();
        }
    }

    /// @notice Marks pairs for processing
    /// @param pairs Array of pair addresses to mark
    function _markPairsForProcessing(address[] calldata pairs) internal {
        for (uint256 i = 0; i < pairs.length; i++) {
            processedPairs[pairs[i]] = true;
            lastPairDistribution[pairs[i]] = block.timestamp;
        }
    }

    /// @notice Extracts unique tokens from pairs, excluding LP tokens
    /// @param pairs Array of pair addresses
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

    /*//////////////////////////////////////////////////////////////
                      ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Migrate fees from old FeeDistributor contract
    /// @param oldDistributor Address of the old FeeDistributor
    /// @param tokens Array of token addresses to migrate
    function migrateFees(address oldDistributor, address[] calldata tokens) external onlyOwner {
        if (oldDistributor == address(0)) revert IFeeDistributor.ZeroAddress();
        
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 balance = IERC20(token).balanceOf(oldDistributor);
            
            if (balance > 0) {
                // Use low-level call to emergencyTokenRecover on old contract
                bytes memory data = abi.encodeWithSignature(
                    "emergencyTokenRecover(address,address,uint256)",
                    token,
                    address(this),
                    balance
                );
                
                (bool success,) = oldDistributor.call(data);
                if (success) {
                    emit FeesCollected(token, balance);
                } else {
                    // Skip tokens that can't be migrated
                    continue;
                }
            }
        }
    }

    /// @notice Emergency function to recover stuck tokens
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
    /// @param newOwner Address of proposed new owner
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert IFeeDistributor.ZeroAddress();
        pendingOwner = newOwner;
    }

    /// @notice Completes ownership transfer process
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert IFeeDistributor.NotPendingOwner();
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns minimum USD value required for operations
    /// @return Minimum USD value threshold
    function minimumUSDValue() external pure returns (uint256) {
        return MINIMUM_USD_VALUE;
    }
    
    /// @notice Legacy compatibility - returns dynamic minimum based on USD value
    /// @dev This maintains compatibility with existing interfaces
    function minimumAmount() external pure returns (uint256) {
        return 0; // Dynamic minimums make this obsolete
    }

    /// @notice Checks if token amount meets minimum requirements
    /// @param token Token address to check
    /// @param amount Amount to check
    /// @return True if meets minimum USD value
    function meetsMinimum(address token, uint256 amount) external view returns (bool) {
        return _meetsMinimumUSDValue(token, amount);
    }

    /// @notice Checks if address is an LP token
    /// @param token Address to check
    /// @return True if token is LP token
    function isLPToken(address token) external view returns (bool) {
        return _isLPToken(token);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when LP tokens are processed
    event LPTokenProcessed(
        address indexed lpToken,
        uint256 lpAmount,
        uint256 amount0,
        uint256 amount1
    );

    /*//////////////////////////////////////////////////////////////
                            ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when LP token processing fails
    error LPProcessingFailed();

    /*//////////////////////////////////////////////////////////////
                        MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to contract owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert IFeeDistributor.NotOwner();
        _;
    }
}