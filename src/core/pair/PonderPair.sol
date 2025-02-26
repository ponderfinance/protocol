// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PonderKAP20 } from "../token/PonderKAP20.sol";
import { IPonderPair } from "./IPonderPair.sol";
import { PonderFeesLib } from "./libraries/PonderFeesLib.sol";
import { PonderPairStorage } from "./storage/PonderPairStorage.sol";
import { PonderPairTypes } from "./types/PonderPairTypes.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";
import { IPonderCallee } from "./IPonderCallee.sol";
import { Math } from "../../libraries/Math.sol";
import { UQ112x112 } from "../../libraries/UQ112x112.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER PAIR CORE
//////////////////////////////////////////////////////////////*/

/// @title PonderPair
/// @author taayyohh
/// @notice Core AMM implementation for Ponder protocol
/// @dev Manages liquidity provision, swaps, and fee collection
/// @dev Implements constant product formula (x * y = k)
contract PonderPair is IPonderPair, PonderPairStorage, PonderKAP20("Ponder LP", "PONDER-LP"), ReentrancyGuard {
    using UQ112x112 for uint224;
    using PonderPairTypes for PonderPairTypes.SwapData;
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                       IMMUTABLE STATE
   //////////////////////////////////////////////////////////////*/

    /// @notice Factory contract that deployed this pair
    /// @dev Set during construction, cannot be modified
    address internal immutable _FACTORY;

    /// @notice Sets up pair with factory reference
    /// @dev Called once during contract deployment
    constructor() {
        _FACTORY = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                      VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fetches minimum liquidity requirement
    /// @dev Amount burned during first mint to prevent pool drain
    /// @return Minimum liquidity threshold as uint256
    function minimumLiquidity() external pure override returns (uint256) {
        return PonderPairTypes.MINIMUM_LIQUIDITY;
    }

    /// @notice Retrieves factory contract address
    /// @dev Returns immutable factory reference
    /// @return Factory contract address
    function factory() external view override returns (address) {
        return _FACTORY;
    }

    /// @notice Gets first token address
    /// @dev Token with lower address value
    /// @return Address of token0
    function token0() external view override returns (address) {
        return _token0;
    }

    /// @notice Gets second token address
    /// @dev Token with higher address value
    /// @return Address of token1
    function token1() external view override returns (address) {
        return _token1;
    }

    /// @notice Accumulated price data for token0
    /// @dev Used for TWAP oracle calculations
    /// @return Cumulative price value
    function price0CumulativeLast() external view override returns (uint256) {
        return _price0CumulativeLast;
    }

    /// @notice Accumulated price data for token1
    /// @dev Used for TWAP oracle calculations
    /// @return Cumulative price value
    function price1CumulativeLast() external view override returns (uint256) {
        return _price1CumulativeLast;
    }

    /// @notice Last recorded constant product value
    /// @dev Used for fee calculations
    /// @return Product of last reserves
    function kLast() external view override returns (uint256) {
        return _kLast;
    }

    /// @notice Fetches launcher contract reference
    /// @dev Retrieved from factory contract
    /// @return Launcher contract address
    function launcher() public view returns (address) {
        return IPonderFactory(_FACTORY).launcher();
    }

    /// @notice Fetches PONDER token reference
    /// @dev Retrieved from factory contract
    /// @return PONDER token address
    function ponder() public view returns (address) {
        return IPonderFactory(_FACTORY).ponder();
    }

    /// @notice Current reserve state and timestamp
    /// @dev Values are packed for gas efficiency
    /// @return reserve0_ Current token0 reserve
    /// @return reserve1_ Current token1 reserve
    /// @return blockTimestampLast_ Last update timestamp
    function getReserves() public view override returns (
        uint112 reserve0_,
        uint112 reserve1_,
        uint32 blockTimestampLast_
    ) {
        reserve0_ = _reserve0;
        reserve1_ = _reserve1;
        blockTimestampLast_ = _blockTimestampLast;
    }

    /*//////////////////////////////////////////////////////////////
                    LIQUIDITY MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes pair with token addresses
    /// @dev Can only be called once by factory
    /// @param token0_ First token address (lower sort order)
    /// @param token1_ Second token address (higher sort order)
    function initialize(address token0_, address token1_) external override {
        // Combine conditions for gas optimization
        if (msg.sender != _FACTORY || token0_ == address(0) || token1_ == address(0)) {
            revert IPonderPair.Auth();
        }

        _token0 = token0_;
        _token1 = token1_;
    }

    /// @notice Adds liquidity to the pair
    /// @dev Mints LP tokens proportional to contribution
    /// @param to Recipient of LP tokens
    /// @return liquidity Amount of LP tokens minted
    function mint(address to) external override nonReentrant returns (uint256 liquidity) {
        // Cache storage variables to minimize SLOADs
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        address token0_ = _token0;
        address token1_ = _token1;

        // Calculate amounts added by comparing current balances to reserves
        uint256 balance0 = IERC20(token0_).balanceOf(address(this));
        uint256 balance1 = IERC20(token1_).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0_;
        uint256 amount1 = balance1 - reserve1_;

        // Handle protocol fees
        bool feeOn = _mintFee(reserve0_, reserve1_);
        uint256 currentSupply = totalSupply();

        // First liquidity provision requires minimum amounts and burns MINIMUM_LIQUIDITY
        if (currentSupply == 0) {
            // Verify minimum liquidity requirements
            if (amount0 < PonderPairTypes.MINIMUM_LIQUIDITY ||
                amount1 < PonderPairTypes.MINIMUM_LIQUIDITY) {
                revert IPonderPair.InsufficientInitialLiquidity();
            }

            // Calculate initial liquidity based on geometric mean
            liquidity = Math.sqrt(amount0 * amount1) - PonderPairTypes.MINIMUM_LIQUIDITY;

            // Permanently lock MINIMUM_LIQUIDITY tokens
            _mint(address(1), PonderPairTypes.MINIMUM_LIQUIDITY);
        } else {
            // For subsequent mints, calculate liquidity proportional to contribution
            liquidity = Math.min(
                (amount0 * currentSupply) / reserve0_,
                (amount1 * currentSupply) / reserve1_
            );
        }

        // Ensure non-zero liquidity is minted
        if (liquidity <= 0) revert IPonderPair.InsufficientLiquidityMinted();

        // Mint LP tokens to recipient
        _mint(to, liquidity);

        // Update reserves and accumulators
        _update(balance0, balance1, reserve0_, reserve1_);

        // Update kLast if fees are enabled
        if (feeOn) _kLast = uint256(_reserve0) * _reserve1;

        emit Mint(msg.sender, amount0, amount1);
    }

    /// @notice Removes liquidity from the pair
    /// @dev Burns LP tokens and returns underlying assets
    /// @param to Recipient of withdrawn tokens
    /// @return amount0 Amount of token0 returned
    /// @return amount1 Amount of token1 returned
    function burn(address to) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        // Cache storage variables to minimize SLOADs
        address token0_ = _token0;
        address token1_ = _token1;
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();

        // Get current token balances and LP tokens to burn
        uint256 balance0 = IERC20(token0_).balanceOf(address(this));
        uint256 balance1 = IERC20(token1_).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        // Handle protocol fees
        bool feeOn = _mintFee(reserve0_, reserve1_);
        uint256 currentSupply = totalSupply();

        // Calculate token amounts to return, proportional to LP tokens burned
        amount0 = (liquidity * balance0) / currentSupply;
        amount1 = (liquidity * balance1) / currentSupply;
        if (amount0 <= 0 || amount1 <= 0) revert IPonderPair.InsufficientLiquidityBurned();

        // Burn LP tokens before external calls (CEI pattern)
        _burn(address(this), liquidity);

        // Calculate new balances after token transfers
        uint256 newBalance0 = balance0 - amount0;
        uint256 newBalance1 = balance1 - amount1;

        // Update reserves and accumulators
        _update(newBalance0, newBalance1, reserve0_, reserve1_);

        // Update kLast if fees are enabled
        if (feeOn) {
            _kLast = uint256(_reserve0) * _reserve1;
        }

        // Transfer tokens to recipient (after state updates)
        IERC20(token0_).safeTransfer(to, amount0);
        IERC20(token1_).safeTransfer(to, amount1);

        emit Burn(msg.sender, amount0, amount1, to);
    }

    /*//////////////////////////////////////////////////////////////
                       SWAP OPERATIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Executes token swap with exact outputs
    /// @dev Supports flash swaps via callback
    /// @custom:security Protected by reentrancy guard and validations
    /// @param amount0Out Exact amount of token0 to output
    /// @param amount1Out Exact amount of token1 to output
    /// @param to Recipient of output tokens
    /// @param data Optional flash swap callback data
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external override nonReentrant {
        // Input validation
        if (amount0Out == 0 && amount1Out == 0) revert IPonderPair.InsufficientOutputAmount();
        if (to == _token0 || to == _token1) revert IPonderPair.InvalidToAddress();

        // Cache storage variables
        address token0_ = _token0;
        address token1_ = _token1;

        // Initialize swap state
        PonderPairTypes.SwapState memory state = PonderPairTypes.SwapState({
            reserve0: 0,
            reserve1: 0,
            balance0: 0,
            balance1: 0,
            amount0In: 0,
            amount1In: 0,
            isPonderPair: false
        });

        // Load current reserves
        (state.reserve0, state.reserve1,) = getReserves();

        // Validate outputs against reserves
        if (amount0Out >= state.reserve0 || amount1Out >= state.reserve1) {
            revert IPonderPair.InsufficientLiquidity();
        }

        // Flash loan protection - update reserves before external calls
        _update(
            uint256(state.reserve0) - amount0Out,
            uint256(state.reserve1) - amount1Out,
            state.reserve0,
            state.reserve1
        );

        // Execute transfers and optional callback
        _executeTransfers(to, amount0Out, amount1Out, data);

        // Get actual balances after transfers
        state.balance0 = IERC20(token0_).balanceOf(address(this));
        state.balance1 = IERC20(token1_).balanceOf(address(this));

        // Calculate input amounts based on balance changes
        state.amount0In = state.balance0 > state.reserve0 - amount0Out
            ? state.balance0 - (state.reserve0 - amount0Out)
            : 0;
        state.amount1In = state.balance1 > state.reserve1 - amount1Out
            ? state.balance1 - (state.reserve1 - amount1Out)
            : 0;

        // Ensure sufficient input amounts
        if (state.amount0In == 0 && state.amount1In == 0) {
            revert IPonderPair.InsufficientInputAmount();
        }

        // Validate k-value with actual balances
        PonderPairTypes.SwapData memory swapData = PonderPairTypes.SwapData({
            amount0Out: amount0Out,
            amount1Out: amount1Out,
            amount0In: state.amount0In,
            amount1In: state.amount1In,
            balance0: state.balance0,
            balance1: state.balance1,
            reserve0: state.reserve0,
            reserve1: state.reserve1
        });

        if (!PonderFeesLib.validateKValue(swapData)) {
            revert IPonderPair.KValueCheckFailed();
        }

        // Check if this is a Ponder pair for fee calculation
        address ponderToken = ponder();
        state.isPonderPair = token0_ == ponderToken || token1_ == ponderToken;

        // Handle fees for both tokens
        _handleFees(state);

        // Update reserves with new balances
        _update(state.balance0, state.balance1, state.reserve0, state.reserve1);

        emit Swap(msg.sender, state.amount0In, state.amount1In, amount0Out, amount1Out, to);
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL FUNCTIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Handles token transfers and flash loan callbacks
    /// @dev Executes transfers then optional callback
    function _executeTransfers(
        address to,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) private {
        // Cache storage variables
        address token0_ = _token0;
        address token1_ = _token1;

        if (to == address(0)) revert PonderKAP20.ZeroAddress();

        // Transfer output tokens
        if (amount0Out > 0) IERC20(token0_).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(token1_).safeTransfer(to, amount1Out);

        // Execute callback if data is provided
        if (data.length > 0) {
            IPonderCallee(to).ponderCall(msg.sender, amount0Out, amount1Out, data);
        }
    }

    /// @notice Handles fees for both input tokens during a swap
    /// @dev Optimized to minimize external calls and gas usage
    /// @param state Current swap state
    function _handleFees(
        PonderPairTypes.SwapState memory state
    ) private {
        // Cache storage values
        address token0_ = _token0;
        address token1_ = _token1;
        address launcherAddr = launcher();

        // Handle token0 fees if any input
        if (state.amount0In > 0) {
            (uint256 protocolFee0, uint256 creatorFee0, address creator0) =
                                PonderFeesLib.calculateAndReturnProtocolFee(
                    token0_,
                    state.amount0In,
                    state.isPonderPair,
                    launcherAddr
                );

            _accumulatedFee0 += protocolFee0;

            if (creatorFee0 > 0) {
                if (creator0 != address(0)) {
                    IERC20(token0_).safeTransfer(creator0, creatorFee0);
                } else {
                    _accumulatedFee0 += creatorFee0;
                }
            }
        }

        // Handle token1 fees if any input
        if (state.amount1In > 0) {
            (uint256 protocolFee1, uint256 creatorFee1, address creator1) =
                                PonderFeesLib.calculateAndReturnProtocolFee(
                    token1_,
                    state.amount1In,
                    state.isPonderPair,
                    launcherAddr
                );

            _accumulatedFee1 += protocolFee1;

            if (creatorFee1 > 0) {
                if (creator1 != address(0)) {
                    IERC20(token1_).safeTransfer(creator1, creatorFee1);
                } else {
                    _accumulatedFee1 += creatorFee1;
                }
            }
        }
    }

    /// @notice Updates reserves and price accumulators
    /// @dev Optimized for gas efficiency
    /// @param balance0 New balance of token0
    /// @param balance1 New balance of token1
    /// @param _reserve0Old Previous reserve of token0
    /// @param _reserve1Old Previous reserve of token1
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0Old,
        uint112 _reserve1Old
    ) private {
        // Validate balances against uint112 max
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert Overflow();
        }

        // Use unchecked for gas optimization on timestamp operations
        unchecked {
        // Get current block timestamp (modulo 2^32 to fit in uint32)
            uint32 blockTimestamp = uint32(block.timestamp);
            uint32 timeElapsed = 0;

        // Calculate time elapsed since last update
            if (blockTimestamp > _blockTimestampLast) {
                timeElapsed = blockTimestamp - _blockTimestampLast;
            }

        // Update price accumulators if needed
            if (timeElapsed > 0 && _reserve0Old != 0 && _reserve1Old != 0) {
                // Accumulate price data for TWAP calculations
                _price0CumulativeLast += uint256(UQ112x112.encode(_reserve1Old).uqdiv(_reserve0Old)) * timeElapsed;
                _price1CumulativeLast += uint256(UQ112x112.encode(_reserve0Old).uqdiv(_reserve1Old)) * timeElapsed;
            }
        }

        // Update storage with new values
        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        _blockTimestampLast = uint32(block.timestamp);

        emit Sync(_reserve0, _reserve1);
    }

    /// @notice Handles protocol fee minting
    /// @dev Mints LP tokens for protocol fee collection
    /// @param reserve0_ Current reserve of token0
    /// @param reserve1_ Current reserve of token1
    /// @return feeOn Whether protocol fees are enabled
    function _mintFee(uint112 reserve0_, uint112 reserve1_) private returns (bool feeOn) {
        // Check if fees are enabled via factory
        address feeTo = IPonderFactory(_FACTORY).feeTo();
        feeOn = feeTo != address(0);

        // Cache kLast to minimize SLOADs
        uint256 _kLastOld = _kLast;

        if (feeOn) {
            if (_kLastOld != 0) {
                // Calculate square roots of K values for fee calculation
                uint256 rootK = Math.sqrt(uint256(reserve0_) * uint256(reserve1_));
                uint256 rootKLast = Math.sqrt(_kLastOld);

                if (rootK > rootKLast) {
                    // Calculate protocol fee as a portion of growth
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;

                    if (liquidity > 0) {
                        // Validate mint won't exceed total supply limits
                        if (totalSupply() + liquidity > type(uint256).max) {
                            revert Overflow();
                        }
                        // Mint fee tokens to protocol
                        _mint(feeTo, liquidity);
                    }
                }
            }
        } else if (_kLastOld != 0) {
            // If fees were enabled before but now disabled, reset kLast
            _kLast = 0;
        }
    }

    /*//////////////////////////////////////////////////////////////
                  MAINTENANCE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Forces balances to match reserves
    /// @dev Handles excess tokens and fee collection
    /// @param to Recipient of excess tokens
    function skim(address to) external override nonReentrant {
        if (to == address(0)) revert InvalidRecipient();

        // Cache storage variables
        address token0_ = _token0;
        address token1_ = _token1;
        address feeTo = IPonderFactory(_FACTORY).feeTo();
        (uint112 reserve0Current, uint112 reserve1Current,) = getReserves();

        // Handle protocol fees first
        uint256 fee0 = _accumulatedFee0;
        uint256 fee1 = _accumulatedFee1;

        // Transfer accumulated fees if fee recipient is set
        if (feeTo != address(0)) {
            if (fee0 > 0) {
                IERC20(token0_).safeTransfer(feeTo, fee0);
                _accumulatedFee0 = 0;
            }
            if (fee1 > 0) {
                IERC20(token1_).safeTransfer(feeTo, fee1);
                _accumulatedFee1 = 0;
            }
        }

        // Calculate excess after fees
        uint256 balance0After = IERC20(token0_).balanceOf(address(this));
        uint256 balance1After = IERC20(token1_).balanceOf(address(this));

        uint256 excess0 = balance0After > reserve0Current ? balance0After - reserve0Current : 0;
        uint256 excess1 = balance1After > reserve1Current ? balance1After - reserve1Current : 0;

        // Transfer excess tokens to recipient
        if (excess0 > 0) {
            IERC20(token0_).safeTransfer(to, excess0);
        }
        if (excess1 > 0) {
            IERC20(token1_).safeTransfer(to, excess1);
        }

        // Update reserves after transfers
        _update(
            IERC20(token0_).balanceOf(address(this)),
            IERC20(token1_).balanceOf(address(this)),
            reserve0Current,
            reserve1Current
        );
    }

    /// @notice Forces reserves to match balances
    /// @dev Updates reserves without moving tokens
    function sync() external override nonReentrant {
        // Cache storage variables
        address token0_ = _token0;
        address token1_ = _token1;

        // Get current state
        uint256 balance0 = IERC20(token0_).balanceOf(address(this));
        uint256 balance1 = IERC20(token1_).balanceOf(address(this));
        (uint112 reserve0Current, uint112 reserve1Current,) = getReserves();

        // Validate balances cover fees and are non-zero
        if (balance0 < _accumulatedFee0 || balance1 < _accumulatedFee1) {
            revert FeeStateInvalid();
        }
        if (balance0 == 0 || balance1 == 0) {
            revert InsufficientLiquidity();
        }

        // Update reserves with current balances
        _update(balance0, balance1, reserve0Current, reserve1Current);
    }
}
