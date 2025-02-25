// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { PonderKAP20 } from "../token/PonderKAP20.sol";
import { IPonderPair } from "./IPonderPair.sol";
import { PonderFeesLib } from "./libraries/PonderFeesLib.sol";
import { PonderPairStorage } from "./storage/PonderPairStorage.sol";
import { PonderPairTypes } from "./types/PonderPairTypes.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";
import { IPonderCallee } from "./IPonderCallee.sol";
import { ILaunchToken } from "../../launch/ILaunchToken.sol";
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
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0_;
        uint256 amount1 = balance1 - reserve1_;

        bool feeOn = _mintFee(reserve0_, reserve1_);
        uint256 currentSupply = totalSupply();


        // Strict equality required: Special initialization case for first LP token mint
        // slither-disable-next-line dangerous-strict-equalities
        if (currentSupply == 0) {
            if (amount0 < PonderPairTypes.MINIMUM_LIQUIDITY ||
                amount1 < PonderPairTypes.MINIMUM_LIQUIDITY) {
                revert IPonderPair.InsufficientInitialLiquidity();
            }
            liquidity = Math.sqrt(amount0 * amount1) - PonderPairTypes.MINIMUM_LIQUIDITY;
            _mint(address(1), PonderPairTypes.MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * currentSupply) / reserve0_,
                (amount1 * currentSupply) / reserve1_
            );
        }

        if (liquidity <= 0) revert IPonderPair.InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balance0, balance1, reserve0_, reserve1_);
        if (feeOn) _kLast = uint256(_reserve0) * _reserve1;

        emit Mint(msg.sender, amount0, amount1);
    }

    /// @notice Removes liquidity from the pair
    /// @dev Burns LP tokens and returns underlying assets
    /// @param to Recipient of withdrawn tokens
    /// @return amount0 Amount of token0 returned
    /// @return amount1 Amount of token1 returned
    function burn(address to) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        // CHECKS
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(reserve0_, reserve1_);
        uint256 currentSupply = totalSupply();

        amount0 = (liquidity * balance0) / currentSupply;
        amount1 = (liquidity * balance1) / currentSupply;
        if (amount0 <= 0 || amount1 <= 0) revert IPonderPair.InsufficientLiquidityBurned();

        // EFFECTS - Update all state variables before external calls
        _burn(address(this), liquidity);

        // Update reserves and accumulators before transfers
        uint256 newBalance0 = balance0 - amount0;
        uint256 newBalance1 = balance1 - amount1;
        _update(newBalance0, newBalance1, reserve0_, reserve1_);

        if (feeOn) {
            _kLast = uint256(_reserve0) * _reserve1;
        }

        // INTERACTIONS - External calls last
        IERC20(_token0).safeTransfer(to, amount0);
        IERC20(_token1).safeTransfer(to, amount1);

        emit Burn(msg.sender, amount0, amount1, to);
    }


    /*//////////////////////////////////////////////////////////////
                       SWAP OPERATIONS
   //////////////////////////////////////////////////////////////*/

    /// @notice Executes token swap with exact outputs
    /// @dev Supports flash swaps via callback
    /// @custom:security Protected by reentrancy guard and validations
    /// 1. ReentrancyGuard modifier
    /// 2. Initial state update before external calls
    /// 3. K-value invariant checks
    /// 4. Final state synchronization after validations
    /// @param amount0Out Exact amount of token0 to output
    /// @param amount1Out Exact amount of token1 to output
    /// @param to Recipient of output tokens
    /// @param data Optional flash swap callback data
    // slither-disable-next-line reentrancy-vulnerabilities
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external override nonReentrant {
        // CHECKS
        if (amount0Out == 0 && amount1Out == 0) revert IPonderPair.InsufficientOutputAmount();
        if (to == _token0 || to == _token1) revert IPonderPair.InvalidToAddress();

        // Initialize state struct with default values
        PonderPairTypes.SwapState memory state = PonderPairTypes.SwapState({
            reserve0: 0,
            reserve1: 0,
            balance0: 0,
            balance1: 0,
            amount0In: 0,
            amount1In: 0,
            isPonderPair: false
        });

        (state.reserve0, state.reserve1,) = getReserves();

        if (amount0Out >= state.reserve0 || amount1Out >= state.reserve1) {
            revert IPonderPair.InsufficientLiquidity();
        }

        // INITIAL EFFECTS - Flash loan protection
        _update(
            uint256(state.reserve0) - amount0Out,
            uint256(state.reserve1) - amount1Out,
            state.reserve0,
            state.reserve1
        );

        // INTERACTIONS
        _executeTransfers(to, amount0Out, amount1Out, data);

        // POST-INTERACTION VALIDATION & EFFECTS
        // Get actual balances after transfer
        state.balance0 = IERC20(_token0).balanceOf(address(this));
        state.balance1 = IERC20(_token1).balanceOf(address(this));

        state.amount0In = state.balance0 > state.reserve0 - amount0Out ?
            state.balance0 - (state.reserve0 - amount0Out) : 0;
        state.amount1In = state.balance1 > state.reserve1 - amount1Out ?
            state.balance1 - (state.reserve1 - amount1Out) : 0;

        if (state.amount0In <= 0 && state.amount1In <= 0) {
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

        // Use library for K-value validation instead of internal function
        if (!PonderFeesLib.validateKValue(swapData)) {
            revert IPonderPair.KValueCheckFailed();
        }

        state.isPonderPair = _token0 == ponder() || _token1 == ponder();

        // Handle fees with simplified logic
        _handleFees(state);

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
        if (to == address(0)) revert PonderKAP20.ZeroAddress();

        if (amount0Out > 0) IERC20(_token0).safeTransfer(to, amount0Out);
        if (amount1Out > 0) IERC20(_token1).safeTransfer(to, amount1Out);
        if (data.length > 0) {
            IPonderCallee(to).ponderCall(msg.sender, amount0Out, amount1Out, data);
        }
    }

    /// @notice Handles fees for a single token
    /// @dev Extracted function to reduce duplicate code
    /// @param token Token address
    /// @param amountIn Amount of token swapped
    /// @param isPonderPair Whether this is a PONDER pair
    /// @param isToken0 Whether this is token0 or token1
    function _handleTokenFee(
        address token,
        uint256 amountIn,
        bool isPonderPair,
        bool isToken0
    ) private {
        if (amountIn == 0) return;

        // Use library for fee calculation
        (uint256 protocolFeeAmount, uint256 creatorFeeAmount) = PonderFeesLib.calculateFees(
            token,
            amountIn,
            isPonderPair,
            launcher()
        );

        // Update accumulated fees
        if (isToken0) _accumulatedFee0 += protocolFeeAmount;
        else _accumulatedFee1 += protocolFeeAmount;

        // Handle creator fee transfer only if necessary
        if (creatorFeeAmount > 0) {
            address creator;
            bool hasCreator = false;

            try ILaunchToken(token).creator() returns (address c) {
                creator = c;
                hasCreator = creator != address(0);
            } catch {}

            if (hasCreator) IERC20(token).safeTransfer(creator, creatorFeeAmount);
            else if (isToken0) _accumulatedFee0 += creatorFeeAmount;
            else _accumulatedFee1 += creatorFeeAmount;
        }
    }

    /// @notice Handles token fees in swap operations
    /// @dev Updates accumulated fees and validates state
    function _handleFees(
        PonderPairTypes.SwapState memory state
    ) private {
        // Handle token0 fees with library function
        _accumulatedFee0 = PonderFeesLib.handleTokenFee(
            _token0,
            state.amount0In,
            state.isPonderPair,
            launcher(),
            _accumulatedFee0
        );

        // Handle token1 fees with library function
        _accumulatedFee1 = PonderFeesLib.handleTokenFee(
            _token1,
            state.amount1In,
            state.isPonderPair,
            launcher(),
            _accumulatedFee1
        );
    }

    /// @notice Updates reserves and price accumulators
    /// @dev Updates state and emits sync event
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0Old,
        uint112 _reserve1Old
    ) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert Overflow();
        }

        // The block.timestamp is used here for calculating elapsed
        // time and is wrapped to a 32-bit integer to handle overflow.
        // This is not used for randomness or unpredictability,
        // and the deterministic nature of block.timestamp is acceptable in this context.
        // slither-disable-next-line weak-prng
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);

        uint32 timeElapsed = blockTimestamp > _blockTimestampLast
            ? blockTimestamp - _blockTimestampLast
            : 0;

        if (timeElapsed > 0 && _reserve0Old != 0 && _reserve1Old != 0) {
            _price0CumulativeLast += uint256(UQ112x112.encode(_reserve1Old).uqdiv(_reserve0Old)) * timeElapsed;
            _price1CumulativeLast += uint256(UQ112x112.encode(_reserve0Old).uqdiv(_reserve1Old)) * timeElapsed;
        }

        _reserve0 = uint112(balance0);
        _reserve1 = uint112(balance1);
        _blockTimestampLast = blockTimestamp;

        emit Sync(_reserve0, _reserve1);
    }

    /// @notice Handles protocol fee minting
    /// @dev Mints LP tokens for protocol fee collection
    function _mintFee(uint112 reserve0_, uint112 reserve1_) private returns (bool feeOn) {
        address feeTo = IPonderFactory(_FACTORY).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLastOld = _kLast;

        if (feeOn) {
            if (_kLastOld != 0) {
                uint256 rootK = Math.sqrt(uint256(reserve0_) * uint256(reserve1_));
                uint256 rootKLast = Math.sqrt(_kLastOld);

                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;

                    if (liquidity > 0) {
                        // Validate mint won't exceed total supply limits
                        if (totalSupply() + liquidity > type(uint256).max) {
                            revert Overflow();
                        }
                        _mint(feeTo, liquidity);
                    }
                }
            }
        } else if (_kLastOld != 0) {
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

        address feeTo = IPonderFactory(_FACTORY).feeTo();

        (uint112 reserve0Current, uint112 reserve1Current,) = getReserves();

        // Handle protocol fees first
        uint256 fee0 = _accumulatedFee0;
        uint256 fee1 = _accumulatedFee1;

        if (feeTo != address(0)) {
            if (fee0 > 0) {
                IERC20(_token0).safeTransfer(feeTo, fee0);
                _accumulatedFee0 = 0;
            }
            if (fee1 > 0) {
                IERC20(_token1).safeTransfer(feeTo, fee1);
                _accumulatedFee1 = 0;
            }
        }

        // Calculate excess after fees
        uint256 balance0After = IERC20(_token0).balanceOf(address(this));
        uint256 balance1After = IERC20(_token1).balanceOf(address(this));

        uint256 excess0 = balance0After > reserve0Current ? balance0After - reserve0Current : 0;
        uint256 excess1 = balance1After > reserve1Current ? balance1After - reserve1Current : 0;

        if (excess0 > 0) {
            IERC20(_token0).safeTransfer(to, excess0);
        }
        if (excess1 > 0) {
            IERC20(_token1).safeTransfer(to, excess1);
        }

        _update(
            IERC20(_token0).balanceOf(address(this)),
            IERC20(_token1).balanceOf(address(this)),
            reserve0Current,
            reserve1Current
        );
    }


    /// @notice Forces reserves to match balances
    /// @dev Updates reserves without moving tokens
    function sync() external override nonReentrant {
        // Get current state
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        (uint112 reserve0Current, uint112 reserve1Current,) = getReserves();

        // Validate balances cover fees but don't enforce strict reserve comparison
        if (balance0 < _accumulatedFee0 || balance1 < _accumulatedFee1) {
            revert FeeStateInvalid();
        }

        // Don't allow zero balances
        if (balance0 == 0 || balance1 == 0) {
            revert InsufficientLiquidity();
        }

        _update(balance0, balance1, reserve0Current, reserve1Current);
    }
}
