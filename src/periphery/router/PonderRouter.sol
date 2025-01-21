// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

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
import { PonderRouterSwapLib } from "./libraries/PonderRouterSwapLib.sol";
import { PonderRouterLiquidityLib } from "./libraries/PonderRouterLiquidityLib.sol";
import { PonderRouterMathLib } from "./libraries/PonderRouterMathLib.sol";

contract PonderRouter is IPonderRouter, PonderRouterStorage, ReentrancyGuard {
    using PonderRouterTypes for *;
    using PonderRouterSwapLib for *;
    using PonderRouterLiquidityLib for *;
    using PonderRouterMathLib for *;

    address payable public immutable KKUB_UNWRAPPER;
    IPonderFactory public immutable FACTORY;
    address public immutable WETH;

    constructor(
        address _factory,
        address _weth,
        address _kkubUnwrapper
    ) {
        if (_factory == address(0) || _weth == address(0) || _kkubUnwrapper == address(0))
            revert PonderRouterTypes.ZeroAddress();

        FACTORY = IPonderFactory(_factory);
        WETH = _weth;
        KKUB_UNWRAPPER = payable(_kkubUnwrapper);
    }

    receive() external payable {
        assert(msg.sender == WETH);
    }

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert PonderRouterTypes.ExpiredDeadline();
        _;
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    ) {
        (amountA, amountB) = PonderRouterLiquidityLib.addLiquidity(
            tokenA, tokenB,
            amountADesired, amountBDesired,
            amountAMin, amountBMin,
            FACTORY
        );

        address pair = FACTORY.getPair(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IPonderPair(pair).mint(to);
    }

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) nonReentrant returns (
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    ) {
        if(token == address(0) || to == address(0)) revert PonderRouterTypes.ZeroAddress();
        if(msg.value < amountETHMin) revert PonderRouterTypes.InsufficientETH();
        if(amountTokenDesired == 0) revert PonderRouterTypes.InvalidAmount();

    address pair = FACTORY.getPair(token, WETH);
        if(pair == address(0)) {
            pair = FACTORY.createPair(token, WETH);
        }

        (amountToken, amountETH) = PonderRouterLiquidityLib.addLiquidity(
            token,
            WETH,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin,
            FACTORY
        );

        if(amountETH > msg.value) revert PonderRouterTypes.InsufficientETH();

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IPonderPair(pair).mint(to);

        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }

        emit LiquidityETHAdded(token, to, amountToken, amountETH, liquidity);
    }

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = FACTORY.getPair(tokenA, tokenB);
        IPonderPair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountA, amountB) = IPonderPair(pair).burn(to);
        if (amountA < amountAMin) revert PonderRouterTypes.InsufficientAAmount();
        if (amountB < amountBMin) revert PonderRouterTypes.InsufficientBAmount();
    }

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
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

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public override ensure(deadline) returns (uint256 amountETH) {
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

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = PonderRouterMathLib.getAmountsOutMultiHop(amountIn, path, FACTORY);
        if (amounts[amounts.length - 1] < amountOutMin)
            revert PonderRouterTypes.InsufficientOutputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amountIn
        );

        PonderRouterSwapLib.executeSwap(amounts, path, to, false, FACTORY);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = PonderRouterMathLib.getAmountsInMultiHop(amountOut, path, FACTORY);
        if (amounts[0] > amountInMax) revert PonderRouterTypes.ExcessiveInputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]
        );

        PonderRouterSwapLib.executeSwap(amounts, path, to, false, FACTORY);
    }

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[0] != WETH) revert PonderRouterTypes.InvalidPath();

        amounts = PonderRouterMathLib.getAmountsOutMultiHop(msg.value, path, FACTORY);
        if (amounts[amounts.length - 1] < amountOutMin)
            revert PonderRouterTypes.InsufficientOutputAmount();

        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(FACTORY.getPair(path[0], path[1]), amounts[0]));

        PonderRouterSwapLib.executeSwap(amounts, path, to, false, FACTORY);
    }

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WETH) revert PonderRouterTypes.InvalidPath();

        amounts = PonderRouterMathLib.getAmountsInMultiHop(amountOut, path, FACTORY);
        if (amounts[0] > amountInMax) revert PonderRouterTypes.ExcessiveInputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]
        );

        PonderRouterSwapLib.executeSwap(amounts, path, address(this), false, FACTORY);

        IERC20(WETH).approve(KKUB_UNWRAPPER, amountOut);
        KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountOut, to);
    }

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WETH) revert PonderRouterTypes.InvalidPath();

        amounts = PonderRouterMathLib.getAmountsOutMultiHop(amountIn, path, FACTORY);
        if (amounts[amounts.length - 1] < amountOutMin)
            revert PonderRouterTypes.InsufficientOutputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]
        );

        PonderRouterSwapLib.executeSwap(amounts, path, address(this), false, FACTORY);

        IERC20(WETH).approve(KKUB_UNWRAPPER, amounts[amounts.length - 1]);
        KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amounts[amounts.length - 1], to);
    }

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[0] != WETH) revert PonderRouterTypes.InvalidPath();

        amounts = PonderRouterMathLib.getAmountsInMultiHop(amountOut, path, FACTORY);
        if (amounts[0] > msg.value) revert PonderRouterTypes.ExcessiveInputAmount();

        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(FACTORY.getPair(path[0], path[1]), amounts[0]));

        PonderRouterSwapLib.executeSwap(amounts, path, to, false, FACTORY);

        if (msg.value > amounts[0]) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amountIn
        );

        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        PonderRouterSwapLib.executeSwap(new uint256[](path.length), path, to, true, FACTORY);

        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert PonderRouterTypes.InsufficientOutputAmount();
        }
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) {
        if (path[0] != WETH) revert PonderRouterTypes.InvalidPath();

        IWETH(WETH).deposit{value: msg.value}();
        assert(IWETH(WETH).transfer(FACTORY.getPair(path[0], path[1]), msg.value));

        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        PonderRouterSwapLib.executeSwap(new uint256[](path.length), path, to, true, FACTORY);

        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert PonderRouterTypes.InsufficientOutputAmount();
        }
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) {
        if (path[path.length - 1] != WETH) revert PonderRouterTypes.InvalidPath();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amountIn
        );

        PonderRouterSwapLib.executeSwap(new uint256[](path.length), path, address(this), true, FACTORY);

        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        if (amountOut < amountOutMin) revert PonderRouterTypes.InsufficientOutputAmount();

        IERC20(WETH).approve(KKUB_UNWRAPPER, amountOut);
        KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountOut, to);
    }

    /// @inheritdoc IPonderRouter
    function getReserves(
        address tokenA,
        address tokenB
    ) public view override returns (uint256 reserveA, uint256 reserveB) {
        return PonderRouterSwapLib.getReserves(tokenA, tokenB, FACTORY);
    }

    /// @inheritdoc IPonderRouter
    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) public view override returns (uint256[] memory amounts) {
        return PonderRouterMathLib.getAmountsOutMultiHop(amountIn, path, FACTORY);
    }

    /// @inheritdoc IPonderRouter
    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) public view override returns (uint256[] memory amounts) {
        return PonderRouterMathLib.getAmountsInMultiHop(amountOut, path, FACTORY);
    }

    /// @inheritdoc IPonderRouter
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure override returns (uint256 amountB) {
        return PonderRouterMathLib.quote(amountA, reserveA, reserveB);
    }

    /// @inheritdoc IPonderRouter
    function weth() external view override returns (address) {
        return WETH;
    }
}
