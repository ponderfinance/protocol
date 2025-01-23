// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { PonderERC20 } from "../token/PonderERC20.sol";
import { IPonderPair } from "./IPonderPair.sol";
import { PonderPairStorage } from "./storage/PonderPairStorage.sol";
import { PonderPairTypes } from "./types/PonderPairTypes.sol";
import { IPonderFactory } from "../factory/IPonderFactory.sol";
import { IPonderCallee } from "./IPonderCallee.sol";
import { ILaunchToken } from "./ILaunchToken.sol";
import { Math } from "../../libraries/Math.sol";
import { UQ112x112 } from "../../libraries/UQ112x112.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PonderPair
 * @notice Implementation of Ponder's AMM pair contract
 * @dev Handles swaps, liquidity provision, and fee collection for token pairs
 */
contract PonderPair is IPonderPair, PonderPairStorage, PonderERC20("Ponder LP", "PONDER-LP"), ReentrancyGuard {
    using UQ112x112 for uint224;
    using PonderPairTypes for PonderPairTypes.SwapData;
    using SafeERC20 for IERC20;

    /**
     * @dev Sets the factory address
     */
    constructor() {
        _factory = msg.sender;
    }


    /**
     * @inheritdoc IPonderPair
     */
    function minimumLiquidity() external pure override returns (uint256) {
        return PonderPairTypes.MINIMUM_LIQUIDITY;
    }

    /**
     * @inheritdoc IPonderPair
     */
    function factory() external view override returns (address) {
        return _factory;
    }

    /**
     * @inheritdoc IPonderPair
     */
    function token0() external view override returns (address) {
        return _token0;
    }

    /**
     * @inheritdoc IPonderPair
     */
    function token1() external view override returns (address) {
        return _token1;
    }

    /**
     * @inheritdoc IPonderPair
     */
    function price0CumulativeLast() external view override returns (uint256) {
        return _price0CumulativeLast;
    }

    /**
     * @inheritdoc IPonderPair
     */
    function price1CumulativeLast() external view override returns (uint256) {
        return _price1CumulativeLast;
    }

    /**
     * @inheritdoc IPonderPair
     */
    function kLast() external view override returns (uint256) {
        return _kLast;
    }

    /**
     * @notice Returns the launcher contract address
     * @return Address of the launcher contract
     */
    function launcher() public view returns (address) {
        return IPonderFactory(_factory).launcher();
    }

    /**
     * @notice Returns the PONDER token address
     * @return Address of the PONDER token
     */
    function ponder() public view returns (address) {
        return IPonderFactory(_factory).ponder();
    }

    /**
     * @inheritdoc IPonderPair
     */
    function initialize(address token0_, address token1_) external override {
        if (msg.sender != _factory) revert PonderPairTypes.Forbidden();
        _token0 = token0_;
        _token1 = token1_;
    }

    /**
     * @inheritdoc IPonderPair
     */
    function getReserves() public view override returns (
        uint112 reserve0_,
        uint112 reserve1_,
        uint32 blockTimestampLast_
    ) {
        reserve0_ = _reserve0;
        reserve1_ = _reserve1;
        blockTimestampLast_ = _blockTimestampLast;
    }

    /**
     * @dev Safely transfers tokens using low-level call
     * @param token Token address to transfer
     * @param to Recipient address
     * @param value Amount to transfer
     */
    function _safeTransfer(address token, address to, uint256 value) private {
        IERC20(token).safeTransfer(to, value);
    }

    /**
     * @dev Executes token transfers and flash loan callback if applicable
     */
    function _executeTransfers(
        address to,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) private {
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
        if (data.length > 0) {
            IPonderCallee(to).ponderCall(msg.sender, amount0Out, amount1Out, data);
        }
    }

    /**
     * @dev Handles fee collection for token swaps
     */
    function _handleTokenFees(
        address token,
        uint256 amountIn,
        bool isPonderPair,
        address token0Address,
        address token1Address,
        uint256 amount0Out,
        uint256 amount1Out
    ) private {
        if (amountIn == 0) return;

        address feeTo = IPonderFactory(_factory).feeTo();
        if (feeTo == address(0)) return;

        bool isTokenOutput = (token == token0Address && amount0Out > 0) ||
            (token == token1Address && amount1Out > 0);
        if (isTokenOutput) return;

        uint256 protocolFeeAmount = 0;
        uint256 creatorFeeAmount = 0;

        try ILaunchToken(token).isLaunchToken() returns (bool isLaunch) {
            if (isLaunch && ILaunchToken(token).launcher() == launcher() && amountIn > 0) {
                address creator = ILaunchToken(token).creator();

                if (isPonderPair) {
                    protocolFeeAmount = (amountIn * PonderPairTypes.PONDER_PROTOCOL_FEE) /
                                    PonderPairTypes.FEE_DENOMINATOR;
                    creatorFeeAmount = (amountIn * PonderPairTypes.PONDER_CREATOR_FEE) /
                                    PonderPairTypes.FEE_DENOMINATOR;
                } else {
                    protocolFeeAmount = (amountIn * PonderPairTypes.KUB_PROTOCOL_FEE) /
                                    PonderPairTypes.FEE_DENOMINATOR;
                    creatorFeeAmount = (amountIn * PonderPairTypes.KUB_CREATOR_FEE) /
                                    PonderPairTypes.FEE_DENOMINATOR;
                }

                if (creatorFeeAmount > 0) {
                    _safeTransfer(token, creator, creatorFeeAmount);
                }
            } else {
                protocolFeeAmount = (amountIn * PonderPairTypes.STANDARD_PROTOCOL_FEE) /
                                PonderPairTypes.FEE_DENOMINATOR;
            }
        } catch {
            protocolFeeAmount = (amountIn * PonderPairTypes.STANDARD_PROTOCOL_FEE) /
                            PonderPairTypes.FEE_DENOMINATOR;
        }

        if (token == _token0) {
            _accumulatedFee0 += protocolFeeAmount;
        } else {
            _accumulatedFee1 += protocolFeeAmount;
        }
    }

    /**
     * @inheritdoc IPonderPair
     */
    struct SwapState {
        uint112 reserve0;
        uint112 reserve1;
        uint256 balance0;
        uint256 balance1;
        uint256 amount0In;
        uint256 amount1In;
        bool isPonderPair;
    }

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external override nonReentrant {
        // CHECKS
        if (amount0Out == 0 && amount1Out == 0) revert PonderPairTypes.InsufficientOutputAmount();
        if (to == _token0 || to == _token1) revert PonderPairTypes.InvalidToAddress();

        SwapState memory state;
        (state.reserve0, state.reserve1,) = getReserves();

        if (amount0Out >= state.reserve0 || amount1Out >= state.reserve1) {
            revert PonderPairTypes.InsufficientLiquidity();
        }

        _update(
            uint256(state.reserve0) - amount0Out,
            uint256(state.reserve1) - amount1Out,
            state.reserve0,
            state.reserve1
        );

        // INTERACTIONS
        _executeSwap(to, amount0Out, amount1Out, data);

        // Post-interaction validations and fee handling
        _validateAndProcessSwap(
            state,
            amount0Out,
            amount1Out
        );

        emit Swap(msg.sender, state.amount0In, state.amount1In, amount0Out, amount1Out, to);
    }

    function _executeSwap(
        address to,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) private {
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
        if (data.length > 0) {
            IPonderCallee(to).ponderCall(msg.sender, amount0Out, amount1Out, data);
        }
    }

    function _validateAndProcessSwap(
        SwapState memory state,
        uint256 amount0Out,
        uint256 amount1Out
    ) private {
        // Get post-transfer balances
        state.balance0 = IERC20(_token0).balanceOf(address(this));
        state.balance1 = IERC20(_token1).balanceOf(address(this));

        state.amount0In = state.balance0 > state.reserve0 - amount0Out ?
            state.balance0 - (state.reserve0 - amount0Out) : 0;
        state.amount1In = state.balance1 > state.reserve1 - amount1Out ?
            state.balance1 - (state.reserve1 - amount1Out) : 0;

        if (state.amount0In == 0 && state.amount1In == 0) {
            revert PonderPairTypes.InsufficientInputAmount();
        }

        _validateKValue(state, amount0Out, amount1Out);

        state.isPonderPair = _token0 == ponder() || _token1 == ponder();
        _handleFees(state, amount0Out, amount1Out);

        _update(state.balance0, state.balance1, state.reserve0, state.reserve1);
    }

    function _validateKValue(
        SwapState memory state,
        uint256 amount0Out,
        uint256 amount1Out
    ) private pure {
        uint256 balance0Adjusted = state.balance0 * 1000 - (state.amount0In * 3);
        uint256 balance1Adjusted = state.balance1 * 1000 - (state.amount1In * 3);
        uint256 initialK = uint256(state.reserve0) * uint256(state.reserve1);

        if (!(balance0Adjusted * balance1Adjusted >= initialK * (1000 * 1000))) {
            revert PonderPairTypes.KValueCheckFailed();
        }
    }

    function _handleFees(
        SwapState memory state,
        uint256 amount0Out,
        uint256 amount1Out
    ) private {
        if (state.amount0In > 0) {
            _handleTokenFees(
                _token0,
                state.amount0In,
                state.isPonderPair,
                _token0,
                _token1,
                amount0Out,
                amount1Out
            );
        }
        if (state.amount1In > 0) {
            _handleTokenFees(
                _token1,
                state.amount1In,
                state.isPonderPair,
                _token0,
                _token1,
                amount0Out,
                amount1Out
            );
        }
    }

    /**
     * @dev Validates K value hasn't decreased after fees
     * @param data Swap data for validation
     * @return bool indicating if K value is valid
     */
    function _validateKValue(PonderPairTypes.SwapData memory data) private pure returns (bool) {
        uint256 balance0Adjusted = data.balance0 * 1000 - (data.amount0In * 3);
        uint256 balance1Adjusted = data.balance1 * 1000 - (data.amount1In * 3);

        return balance0Adjusted * balance1Adjusted >=
            uint256(data.reserve0) * uint256(data.reserve1) * (1000 * 1000);
    }

    /**
     * @inheritdoc IPonderPair
     */
    function burn(address to) external override nonReentrant returns (uint256 amount0, uint256 amount1) {
        // CHECKS
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(reserve0_, reserve1_);
        uint256 _totalSupply = totalSupply();

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        if (amount0 == 0 || amount1 == 0) revert PonderPairTypes.InsufficientLiquidityBurned();

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
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);

        emit Burn(msg.sender, amount0, amount1, to);
    }

    /**
     * @inheritdoc IPonderPair
     */
    function mint(address to) external override nonReentrant returns (uint256 liquidity) {
        (uint112 reserve0_, uint112 reserve1_,) = getReserves();
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 amount0 = balance0 - reserve0_;
        uint256 amount1 = balance1 - reserve1_;

        bool feeOn = _mintFee(reserve0_, reserve1_);
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            if (amount0 < PonderPairTypes.MINIMUM_LIQUIDITY ||
                amount1 < PonderPairTypes.MINIMUM_LIQUIDITY) {
                revert PonderPairTypes.InsufficientInitialLiquidity();
            }
            liquidity = Math.sqrt(amount0 * amount1) - PonderPairTypes.MINIMUM_LIQUIDITY;
            _mint(address(1), PonderPairTypes.MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * _totalSupply) / reserve0_,
                (amount1 * _totalSupply) / reserve1_
            );
        }

        if (liquidity == 0) revert PonderPairTypes.InsufficientLiquidityMinted();
        _mint(to, liquidity);

        _update(balance0, balance1, reserve0_, reserve1_);
        if (feeOn) _kLast = uint256(_reserve0) * _reserve1;

        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @dev Updates reserves and price accumulators
     */
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0Old,
        uint112 _reserve1Old
    ) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert PonderPairTypes.Overflow();
        }

        // slither-disable-next-line weak-prng
        // The block.timestamp is used here for calculating elapsed
        // time and is wrapped to a 32-bit integer to handle overflow.
        // This is not used for randomness or unpredictability,
        // and the deterministic nature of block.timestamp is acceptable in this context.
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

    /**
     * @dev Mint LP fee to feeTo address if enabled
     */
    function _mintFee(uint112 reserve0_, uint112 reserve1_) private returns (bool feeOn) {
        address feeTo = IPonderFactory(_factory).feeTo();
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
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLastOld != 0) {
            _kLast = 0;
        }
    }

    /**
     * @inheritdoc IPonderPair
     */
    function skim(address to) external override nonReentrant {
        address feeTo = IPonderFactory(_factory).feeTo();

        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));

        uint256 excess0 = balance0 > _reserve0 + _accumulatedFee0 ?
            balance0 - _reserve0 - _accumulatedFee0 : 0;
        uint256 excess1 = balance1 > _reserve1 + _accumulatedFee1 ?
            balance1 - _reserve1 - _accumulatedFee1 : 0;

        if (excess0 > 0) _safeTransfer(_token0, to, excess0);
        if (excess1 > 0) _safeTransfer(_token1, to, excess1);

        if (feeTo != address(0)) {
            if (_accumulatedFee0 > 0) {
                _safeTransfer(_token0, feeTo, _accumulatedFee0);
                _accumulatedFee0 = 0;
            }
            if (_accumulatedFee1 > 0) {
                _safeTransfer(_token1, feeTo, _accumulatedFee1);
                _accumulatedFee1 = 0;
            }
        }
    }

    /**
     * @inheritdoc IPonderPair
     */
    function sync() external override nonReentrant {
        _update(
            IERC20(_token0).balanceOf(address(this)),
            IERC20(_token1).balanceOf(address(this)),
            _reserve0,
            _reserve1
        );
    }
}
