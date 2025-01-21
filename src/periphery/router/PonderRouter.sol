// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderPair } from "../../core/pair/IPonderPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IWETH } from "../unwrapper/IWETH.sol";
import { TransferHelper } from "../../libraries/TransferHelper.sol";
import { KKUBUnwrapper } from "../unwrapper/KKUBUnwrapper.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { PonderRouterTypes } from "./types/PonderRouterTypes.sol";
import { PonderRouterStorage } from "./storage/PonderRouterStorage.sol";
import { IPonderRouter } from "./IPonderRouter.sol";

/// @title Ponder Router Implementation
/// @notice Handles routing of trades and liquidity provision between pairs
/// @dev Implements core swap and liquidity logic inheriting from interface and storage
contract PonderRouter is IPonderRouter, PonderRouterStorage, ReentrancyGuard {
    using PonderRouterTypes for *;

    /// @notice Address of KKUBUnwrapper contract
    address payable public immutable KKUB_UNWRAPPER;

    /// @notice Factory contract for creating and managing pairs
    IPonderFactory public immutable FACTORY;

    /// @notice Address of WETH/KKUB contract
    address public immutable WETH;

    /// @notice Contract constructor
    /// @param _factory Address of PonderFactory contract
    /// @param _weth Address of WETH/KKUB contract
    /// @param _kkubUnwrapper Address of KKUBUnwrapper contract
    constructor(
        address _factory,
        address _weth,
        address _kkubUnwrapper
    ) {
        FACTORY = IPonderFactory(_factory);
        WETH = _weth;
        KKUB_UNWRAPPER = payable(_kkubUnwrapper);
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    /// @dev Modifier to check if deadline has passed
    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert PonderRouterTypes.ExpiredDeadline();
        _;
    }

    /// @notice Internal function to calculate optimal liquidity amounts
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param amountADesired Desired amount of tokenA
    /// @param amountBDesired Desired amount of tokenB
    /// @param amountAMin Minimum acceptable amount of tokenA
    /// @param amountBMin Minimum acceptable amount of tokenB
    /// @return amountA Final amount of tokenA
    /// @return amountB Final amount of tokenB
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal virtual returns (uint256 amountA, uint256 amountB) {
        if (FACTORY.getPair(tokenA, tokenB) == address(0)) {
            FACTORY.createPair(tokenA, tokenB);
        }

        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);

        if (reserveA == 0 && reserveB == 0) {
            if (amountADesired < amountAMin || amountBDesired < amountBMin) {
                revert PonderRouterTypes.InsufficientAmount();
            }
            amountA = amountADesired;
            amountB = amountBDesired > amountBMin ? amountBDesired : amountBMin;
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert PonderRouterTypes.InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) revert PonderRouterTypes.InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// @inheritdoc IPonderRouter
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    ) {
        (amountA, amountB) = _addLiquidity(
            tokenA, tokenB,
            amountADesired, amountBDesired,
            amountAMin, amountBMin
        );
        address pair = FACTORY.getPair(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IPonderPair(pair).mint(to);
    }

    /// @inheritdoc IPonderRouter
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external virtual override payable nonReentrant ensure(deadline) returns (
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    ) {
        if(token == address(0) || to == address(0)) revert PonderRouterTypes.ZeroAddress();
        if(msg.value == 0) revert PonderRouterTypes.InsufficientETH();
        if(amountTokenDesired == 0) revert PonderRouterTypes.InvalidAmount();

        address pair = FACTORY.getPair(token, WETH);
        if(pair == address(0)) {
            pair = FACTORY.createPair(token, WETH);
        }

        (amountToken, amountETH) = _addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin
        );

        if(amountETH > msg.value) revert PonderRouterTypes.InsufficientETH();

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IPonderPair(pair).mint(to);

        uint256 refund = msg.value - amountETH;
        if (refund > 0) {
            TransferHelper.safeTransferETH(msg.sender, refund);
        }

        emit LiquidityETHAdded(token, to, amountToken, amountETH, liquidity);
    }

    /// @inheritdoc IPonderRouter
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = FACTORY.getPair(tokenA, tokenB);
        IPonderPair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountA, amountB) = IPonderPair(pair).burn(to);
        if (amountA < amountAMin) revert PonderRouterTypes.InsufficientAAmount();
        if (amountB < amountBMin) revert PonderRouterTypes.InsufficientBAmount();
    }

    /// @inheritdoc IPonderRouter
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IERC20(WETH).approve(KKUB_UNWRAPPER, amountETH);
        KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountETH, to);
    }

    /// @inheritdoc IPonderRouter
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual override ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(
            token,
            WETH,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IERC20(WETH).approve(KKUB_UNWRAPPER, amountETH);
        KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountETH, to);
    }

    /// @notice Internal swap function
    /// @param amounts Array of token amounts
    /// @param path Array of token addresses in swap path
    /// @param _to Address to receive output tokens
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);

            address pair = FACTORY.getPair(input, output);
            if (pair == address(0)) {
                (address sortedToken0, address sortedToken1) = sortTokens(input, output);
                pair = FACTORY.getPair(sortedToken0, sortedToken1);
            }

            uint256 amountOut = amounts[i + 1];
            address token0 = IPonderPair(pair).token0();
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? FACTORY.getPair(output, path[i + 2]) : _to;
            IPonderPair(pair).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /// @inheritdoc IPonderRouter
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin)
            revert PonderRouterTypes.InsufficientOutputAmount();

        uint256[] memory realAmounts = getAmountsOut(amountIn, path);
        if (realAmounts[realAmounts.length - 1] < amountOutMin)
            revert PonderRouterTypes.InsufficientOutputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amountIn
        );

        _swap(amounts, path, to);
        return amounts;
    }

/// @inheritdoc IPonderRouter
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) revert PonderRouterTypes.ExcessiveInputAmount();
        TransferHelper.safeTransferFrom(path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

/// @inheritdoc IPonderRouter
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) returns (uint256[] memory amounts) {
        if (path[0] != WETH) revert PonderRouterTypes.InvalidPath();
        amounts = getAmountsOut(msg.value, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert PonderRouterTypes.InsufficientOutputAmount();
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(FACTORY.getPair(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

/// @inheritdoc IPonderRouter
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WETH) revert PonderRouterTypes.InvalidPath();
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) revert PonderRouterTypes.ExcessiveInputAmount();
        TransferHelper.safeTransferFrom(path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IERC20(WETH).approve(KKUB_UNWRAPPER, amountOut);
        KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountOut, to);
    }

/// @inheritdoc IPonderRouter
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WETH) revert PonderRouterTypes.InvalidPath();
        amounts = getAmountsOut(amountIn, path);

        if (amounts[amounts.length - 1] < amountOutMin) revert PonderRouterTypes.InsufficientOutputAmount();

        TransferHelper.safeTransferFrom(path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]);

        _swap(amounts, path, address(this));

        uint256 amountOut = amounts[amounts.length - 1];
        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));

        if (wethBalance < amountOut) revert PonderRouterTypes.InsufficientWethBalance();
        if (!IERC20(WETH).approve(KKUB_UNWRAPPER, amountOut)) revert PonderRouterTypes.WethApprovalFailed();

        KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountOut, to);
    }

/// @inheritdoc IPonderRouter
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) returns (uint256[] memory amounts) {
        if (to == address(0)) revert PonderRouterTypes.ZeroAddress();
        if (path[0] != WETH) revert PonderRouterTypes.InvalidPath();
        if (path.length < 2) revert PonderRouterTypes.InvalidPath();
        if (amountOut == 0) revert PonderRouterTypes.ZeroOutput();

        emit SwapETHForExactTokensStarted(msg.sender, msg.value, amountOut, deadline);

        amounts = getAmountsIn(amountOut, path);

        uint256 priceImpact = calculatePriceImpact(amounts[0], amountOut);
        if (priceImpact > 1000) {
            emit PriceImpactWarning(amounts[0], amountOut, priceImpact);
        }
        if (priceImpact > 2000) {
            revert PonderRouterTypes.ExcessivePriceImpact(priceImpact);
        }

        if (amounts[0] > msg.value) revert PonderRouterTypes.ExcessiveInputAmount();

        IWETH(WETH).deposit{value: amounts[0]}();

        if (!IWETH(WETH).transfer(FACTORY.getPair(path[0], path[1]), amounts[0])) {
            revert PonderRouterTypes.TransferFailed();
        }

        _swap(amounts, path, to);

        if (msg.value > amounts[0]) {
            (bool success, bytes memory reason) = msg.sender.call{value: msg.value - amounts[0]}("");
            if (!success) {
                emit ETHRefundFailed(msg.sender, msg.value - amounts[0], reason);
                revert PonderRouterTypes.RefundFailed();
            }
            emit ETHRefunded(msg.sender, msg.value - amounts[0]);
        }

        emit SwapETHForExactTokens(
            msg.sender,
            amounts[0],
            amountOut,
            path,
            to
        );
    }

    /// @notice Calculate price impact for a swap
/// @param inputAmount Amount being input to the swap
/// @param outputAmount Amount being output from the swap
/// @return Price impact in basis points (1% = 100)
    function calculatePriceImpact(
        uint256 inputAmount,
        uint256 outputAmount
    ) internal pure returns (uint256) {
        return ((inputAmount - outputAmount) * 10000) / inputAmount;
    }

/// @inheritdoc IPonderRouter
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert PonderRouterTypes.InsufficientOutputAmount();
        }
    }

/// @inheritdoc IPonderRouter
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override payable ensure(deadline) {
        if (path[0] != WETH) revert PonderRouterTypes.InvalidPath();
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(FACTORY.getPair(path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert PonderRouterTypes.InsufficientOutputAmount();
        }
    }

/// @inheritdoc IPonderRouter
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override ensure(deadline) {
        if (path[path.length - 1] != WETH) revert PonderRouterTypes.InvalidPath();
        TransferHelper.safeTransferFrom(path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        if (amountOut < amountOutMin) revert PonderRouterTypes.InsufficientOutputAmount();
        IERC20(WETH).approve(KKUB_UNWRAPPER, amountOut);
        KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountOut, to);
    }

/// @notice Internal swap function for fee-on-transfer tokens
/// @param path Array of token addresses in swap path
/// @param _to Address to receive tokens
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            IPonderPair pair = IPonderPair(FACTORY.getPair(input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
                amountOutput = getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? FACTORY.getPair(output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /// @inheritdoc IPonderRouter
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure virtual returns (uint256 amountB) {
        if (amountA == 0) revert PonderRouterTypes.InsufficientAmount();
        if (reserveA == 0 || reserveB == 0) revert PonderRouterTypes.InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

/// @inheritdoc IPonderRouter
    function getReserves(
        address tokenA,
        address tokenB
    ) public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IPonderPair(FACTORY.getPair(token0, token1)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @notice Sort token addresses
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return token0 Lower token address
    /// @return token1 Higher token address
    function sortTokens(
        address tokenA,
        address tokenB
    ) public pure returns (address token0, address token1) {
        if (tokenA == tokenB) revert PonderRouterTypes.IdenticalAddresses();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert PonderRouterTypes.ZeroAddress();
    }

    /// @inheritdoc IPonderRouter
    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        if (path.length < 2 || path.length > PonderRouterTypes.MAX_PATH_LENGTH) revert PonderRouterTypes.InvalidPath();
        if (amountIn == 0) revert PonderRouterTypes.InsufficientInputAmount();

        amounts = new uint256[](path.length);
        amounts[0] = amountIn;

        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(path[i], path[i + 1]);

            if (
                reserveIn < PonderRouterTypes.MIN_VIABLE_LIQUIDITY ||
                reserveOut < PonderRouterTypes.MIN_VIABLE_LIQUIDITY)
            {
                revert PonderRouterTypes.InsufficientLiquidity();
            }

            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);

            if (amounts[i + 1] == 0) revert PonderRouterTypes.InsufficientOutputAmount();
        }

        return amounts;
    }

/// @inheritdoc IPonderRouter
    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) public view virtual override returns (uint256[] memory amounts) {
        if (path.length < 2) revert PonderRouterTypes.InvalidPath();
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }

/// @notice Calculate output amount for an exact input amount
/// @param amountIn Amount of input tokens
/// @param reserveIn Input token reserve
/// @param reserveOut Output token reserve
/// @return amountOut Amount of output tokens
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual returns (uint256 amountOut) {
        if (amountIn == 0) revert PonderRouterTypes.InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert PonderRouterTypes.InsufficientLiquidity();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Calculate required input amount for an exact output amount
    /// @param amountOut Desired output amount
    /// @param reserveIn Input token reserve
    /// @param reserveOut Output token reserve
    /// @return amountIn Required input amount
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure virtual returns (uint256 amountIn) {
        if (amountOut == 0) revert PonderRouterTypes.InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert PonderRouterTypes.InsufficientLiquidity();
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /// @inheritdoc IPonderRouter
    function weth() external view override returns (address) {
        return WETH;
    }
}
