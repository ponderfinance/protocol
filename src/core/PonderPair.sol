// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PonderERC20.sol";
import "../interfaces/IPonderPair.sol";
import "../interfaces/IPonderFactory.sol";
import "../interfaces/IPonderCallee.sol";
import "../interfaces/ILaunchToken.sol";
import "../libraries/Math.sol";
import "../libraries/UQ112x112.sol";

contract PonderPair is PonderERC20("Ponder LP", "PONDER-LP"), IPonderPair {
    using UQ112x112 for uint224;

    uint256 public constant override MINIMUM_LIQUIDITY = 1000;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public override factory;
    address public override token0;
    address public override token1;

    uint256 private constant FEE_DENOMINATOR = 10000;
    uint256 private constant STANDARD_FEE = 30;      // 0.3% (30/10000)
    uint256 private constant KUB_LP_FEE = 20;        // 0.2% (20/10000)
    uint256 private constant KUB_CREATOR_FEE = 10;   // 0.1% (10/10000)
    uint256 private constant PONDER_LP_FEE = 15;     // 0.15% (15/10000)
    uint256 private constant PONDER_CREATOR_FEE = 15; // 0.15% (15/10000)

    uint112 private reserve0;
    uint112 private reserve1;
    uint32 private blockTimestampLast;

    uint256 public override price0CumulativeLast;
    uint256 public override price1CumulativeLast;
    uint256 public override kLast;

    uint256 private unlocked = 1;

    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    constructor() {
        factory = msg.sender;
    }

    function launcher() public view returns (address) {
        return IPonderFactory(factory).launcher();
    }

    function ponder() public view returns (address) {
        return IPonderFactory(factory).ponder();
    }

    function initialize(address _token0, address _token1) external override {
        require(msg.sender == factory, "Forbidden");
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() public view override returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }

    function _executeTransfers(address to, uint256 amount0Out, uint256 amount1Out, bytes calldata data) private {
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);
        if (data.length > 0) IPonderCallee(to).ponderCall(msg.sender, amount0Out, amount1Out, data);
    }

    // Update the SwapData struct to include output flags
    struct SwapData {
        uint256 amount0Out;
        uint256 amount1Out;
        uint256 amount0In;
        uint256 amount1In;
        uint256 balance0;
        uint256 balance1;
        uint112 reserve0;
        uint112 reserve1;
    }

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

        address feeTo = IPonderFactory(factory).feeTo();
        uint256 totalFeeAmount = 0;

        // Check if this token is being sold (input) vs bought (output)
        bool isTokenOutput = (token == token0Address && amount0Out > 0) ||
            (token == token1Address && amount1Out > 0);

        // If token is being bought (output), only apply standard fee
        if (isTokenOutput) {
            if (feeTo != address(0)) {
                uint256 protocolFee = (amountIn * STANDARD_FEE) / FEE_DENOMINATOR;
                _safeTransfer(token, feeTo, protocolFee);
                totalFeeAmount += protocolFee;
            }
            return;
        }

        try ILaunchToken(token).isLaunchToken() returns (bool isLaunch) {
            // Only apply special fees when launch token is input (being sold)
            if (isLaunch && ILaunchToken(token).launcher() == launcher() && amountIn > 0) {
                address creator = ILaunchToken(token).creator();

                // Launch token -> PONDER pair fees
                if (isPonderPair) {
                    if (feeTo != address(0)) {
                        uint256 protocolFee = (amountIn * PONDER_LP_FEE) / FEE_DENOMINATOR;
                        _safeTransfer(token, feeTo, protocolFee);
                        totalFeeAmount += protocolFee;
                    }
                    uint256 creatorFee = (amountIn * PONDER_CREATOR_FEE) / FEE_DENOMINATOR;
                    _safeTransfer(token, creator, creatorFee);
                    totalFeeAmount += creatorFee;
                } else {
                    // Launch token -> KUB pair fees
                    if (feeTo != address(0)) {
                        uint256 protocolFee = (amountIn * KUB_LP_FEE) / FEE_DENOMINATOR;
                        _safeTransfer(token, feeTo, protocolFee);
                        totalFeeAmount += protocolFee;
                    }
                    uint256 creatorFee = (amountIn * KUB_CREATOR_FEE) / FEE_DENOMINATOR;
                    _safeTransfer(token, creator, creatorFee);
                    totalFeeAmount += creatorFee;
                }
            } else if (feeTo != address(0)) {
                // Standard 0.3% fee for all other cases
                uint256 protocolFee = (amountIn * STANDARD_FEE) / FEE_DENOMINATOR;
                _safeTransfer(token, feeTo, protocolFee);
                totalFeeAmount += protocolFee;
            }
        } catch {
            // Standard 0.3% fee for non-launch tokens
            if (feeTo != address(0)) {
                uint256 protocolFee = (amountIn * STANDARD_FEE) / FEE_DENOMINATOR;
                _safeTransfer(token, feeTo, protocolFee);
                totalFeeAmount += protocolFee;
            }
        }

        if (totalFeeAmount > amountIn) {
            revert FeeTooHigh(totalFeeAmount, amountIn);
        }
    }

    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external override lock {
        require(amount0Out > 0 || amount1Out > 0, "Insufficient output amount");
        require(to != token0 && to != token1, "Invalid to");

        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        require(amount0Out < _reserve0 && amount1Out < _reserve1, "Insufficient liquidity");

        // Execute initial transfers first
        _executeTransfers(to, amount0Out, amount1Out, data);

        // Store all our data in the struct to avoid stack too deep
        SwapData memory swapData;
        swapData.amount0Out = amount0Out;
        swapData.amount1Out = amount1Out;
        swapData.reserve0 = _reserve0;
        swapData.reserve1 = _reserve1;
        swapData.balance0 = IERC20(token0).balanceOf(address(this));
        swapData.balance1 = IERC20(token1).balanceOf(address(this));

        // Calculate amounts in (exactly like Uniswap V2)
        swapData.amount0In = swapData.balance0 > swapData.reserve0 - amount0Out ?
            swapData.balance0 - (swapData.reserve0 - amount0Out) : 0;
        swapData.amount1In = swapData.balance1 > swapData.reserve1 - amount1Out ?
            swapData.balance1 - (swapData.reserve1 - amount1Out) : 0;

        require(swapData.amount0In > 0 || swapData.amount1In > 0, "Insufficient input amount");

        // Validate K value
        require(_validateKValue(swapData), "K value check failed");

        // Handle fees after K check
        bool isPonderPair = token0 == ponder() || token1 == ponder();
        if (swapData.amount0In > 0) {
            _handleTokenFees(token0, swapData.amount0In, isPonderPair, token0, token1, amount0Out, amount1Out);
        }
        if (swapData.amount1In > 0) {
            _handleTokenFees(token1, swapData.amount1In, isPonderPair, token0, token1, amount0Out, amount1Out);
        }

        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            _reserve0,
            _reserve1
        );
        emit Swap(msg.sender, swapData.amount0In, swapData.amount1In, amount0Out, amount1Out, to);
    }

    function _calculateInputAmounts(SwapData memory data) private view returns (uint256, uint256) {
        uint256 amount0In = data.balance0 > data.reserve0 - data.amount0Out ?
            data.balance0 - (data.reserve0 - data.amount0Out) : 0;
        uint256 amount1In = data.balance1 > data.reserve1 - data.amount1Out ?
            data.balance1 - (data.reserve1 - data.amount1Out) : 0;

        // Validate the calculated amounts
        if (amount0In == 0 && amount1In == 0) {
            revert InsufficientInputCalculated(amount0In, amount1In, data.balance0, data.balance1);
        }

        return (amount0In, amount1In);
    }

    function _validateKValue(SwapData memory data) private pure returns (bool) {
        uint256 balance0Adjusted = data.balance0 * 1000 - (data.amount0In * 3);
        uint256 balance1Adjusted = data.balance1 * 1000 - (data.amount1In * 3);

        return balance0Adjusted * balance1Adjusted >=
            uint256(data.reserve0) * uint256(data.reserve1) * (1000 * 1000);
    }

    function burn(address to) external override lock returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        address _token0 = token0;
        address _token1 = token1;
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply();

        amount0 = (liquidity * balance0) / _totalSupply;
        amount1 = (liquidity * balance1) / _totalSupply;
        require(amount0 > 0 && amount1 > 0, "Insufficient liquidity burned");

        _burn(address(this), liquidity);

        // Single transfer for each token
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);

        // Update balances after transfer
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;

        emit Burn(msg.sender, amount0, amount1, to);
    }

    function mint(address to) external override lock returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply();

        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(
                (amount0 * _totalSupply) / _reserve0,
                (amount1 * _totalSupply) / _reserve1
            );
        }

        require(liquidity > 0, "INSUFFICIENT_LIQUIDITY_MINTED");
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1;

        emit Mint(msg.sender, amount0, amount1);
    }

    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= type(uint112).max && balance1 <= type(uint112).max, "OVERFLOW");
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IPonderFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast;
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * uint256(_reserve1));
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = rootK * 5 + rootKLast;
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    function skim(address to) external override lock {
        _safeTransfer(token0, to, IERC20(token0).balanceOf(address(this)) - reserve0);
        _safeTransfer(token1, to, IERC20(token1).balanceOf(address(this)) - reserve1);
    }

    function sync() external override lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
