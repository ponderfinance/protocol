// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderPair } from "../../core/pair/IPonderPair.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IKKUB } from "../unwrapper/IKKUB.sol";
import { TransferHelper } from "../../libraries/TransferHelper.sol";
import { KKUBUnwrapper } from "../unwrapper/KKUBUnwrapper.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { PonderRouterTypes } from "./types/PonderRouterTypes.sol";
import { PonderRouterStorage } from "./storage/PonderRouterStorage.sol";
import { IPonderRouter } from "./IPonderRouter.sol";
import { PonderRouterSwapLib } from "./libraries/PonderRouterSwapLib.sol";
import { PonderRouterLiquidityLib } from "./libraries/PonderRouterLiquidityLib.sol";
import { PonderRouterMathLib } from "./libraries/PonderRouterMathLib.sol";


/*//////////////////////////////////////////////////////////////
                    ROUTER IMPLEMENTATION
//////////////////////////////////////////////////////////////*/

/// @title PonderRouter
/// @author taayyohh
/// @notice Main router contract for token swaps and liquidity operations
/// @dev Implements core DEX functionality with ETH and token support
///      Includes support for fee-on-transfer tokens
///      Uses external libraries for math and swap logic
contract PonderRouter is IPonderRouter, PonderRouterStorage, ReentrancyGuard {
    using PonderRouterTypes for *;
    using PonderRouterSwapLib for *;
    using PonderRouterLiquidityLib for *;
    using PonderRouterMathLib for *;

    /*//////////////////////////////////////////////////////////////
                          IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the KKUB unwrapper contract
    /// @dev Used to convert KKUB back to native KUB
    address payable public immutable KKUB_UNWRAPPER;

    /// @notice Address of the Ponder factory contract
    /// @dev Used for pair creation and lookup
    IPonderFactory public immutable FACTORY;

    /// @notice Address of the wrapped ETH contract
    /// @dev Native token wrapper for pool compatibility
    address public immutable KKUB;

    /*//////////////////////////////////////////////////////////////
                        CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the router with core contract addresses
    /// @param _factory Address of pair factory
    /// @param _kkub Address of wrapped ETH contract
    /// @param _kkubUnwrapper Address of KKUB unwrapper
    /// @dev Validates non-zero addresses
    constructor(
        address _factory,
        address _kkub,
        address _kkubUnwrapper
    ) {
        if (_factory == address(0) || _kkub == address(0) || _kkubUnwrapper == address(0))
            revert ZeroAddress();

        FACTORY = IPonderFactory(_factory);
        KKUB = _kkub;
        KKUB_UNWRAPPER = payable(_kkubUnwrapper);
    }

    /*//////////////////////////////////////////////////////////////
                    FALLBACK AND MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Accepts ETH transfers from KKUB only
    /// @dev Required for KKUB unwrapping operations
    receive() external payable {
        assert(msg.sender == KKUB);
    }

    /// @notice Ensures transaction hasn't expired
    /// @param deadline Maximum timestamp for execution
    /// @dev Reverts if current time exceeds deadline
    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert ExpiredDeadline();
        _;
    }

    /// @notice Adds liquidity to a token pair
    /// @param tokenA Address of the first token
    /// @param tokenB Address of the second token
    /// @param amountADesired Desired amount of first token to add
    /// @param amountBDesired Desired amount of second token to add
    /// @param amountAMin Minimum acceptable amount of first token
    /// @param amountBMin Minimum acceptable amount of second token
    /// @param to Address that will receive LP tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amountA Actual amount of first token added
    /// @return amountB Actual amount of second token added
    /// @return liquidity Amount of LP tokens minted
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

    /// @notice Adds liquidity to an ETH pair
    /// @param token Address of token to pair with ETH
    /// @param amountTokenDesired Desired amount of token to add
    /// @param amountTokenMin Minimum acceptable token amount
    /// @param amountETHMin Minimum acceptable ETH amount
    /// @param to Address that will receive LP tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amountToken Actual amount of token added
    /// @return amountETH Actual amount of ETH added
    /// @return liquidity Amount of LP tokens minted
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
        if(token == address(0) || to == address(0)) revert ZeroAddress();
        if(msg.value < amountETHMin) revert InsufficientETH();
        if(amountTokenDesired == 0) revert InvalidAmount();

    address pair = FACTORY.getPair(token, KKUB);
        if(pair == address(0)) {
            pair = FACTORY.createPair(token, KKUB);
        }

        (amountToken, amountETH) = PonderRouterLiquidityLib.addLiquidity(
            token,
            KKUB,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountETHMin,
            FACTORY
        );

        if(amountETH > msg.value) revert InsufficientETH();

        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IKKUB(KKUB).deposit{value: amountETH}();
        assert(IKKUB(KKUB).transfer(pair, amountETH));
        liquidity = IPonderPair(pair).mint(to);

        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }

        emit LiquidityETHAdded(token, to, amountToken, amountETH, liquidity);
    }

    /// @notice Removes liquidity from a token pair
    /// @param tokenA Address of the first token
    /// @param tokenB Address of the second token
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountAMin Minimum amount of first token to receive
    /// @param amountBMin Minimum amount of second token to receive
    /// @param to Address that will receive the tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amountA Amount of first token received
    /// @return amountB Amount of second token received
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

        bool success = IPonderPair(pair).transferFrom(msg.sender, pair, liquidity);
        if (!success) revert TransferFailed();

        (amountA, amountB) = IPonderPair(pair).burn(to);
        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountB < amountBMin) revert InsufficientBAmount();
    }

    /// @notice Removes liquidity from an ETH pair
    /// @param token Address of token paired with ETH
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountTokenMin Minimum token amount to receive
    /// @param amountETHMin Minimum ETH amount to receive
    /// @param to Address that will receive token and ETH
    /// @param deadline Maximum timestamp for execution
    /// @return amountToken Amount of token received
    /// @return amountETH Amount of ETH received
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
            KKUB,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);

        bool success = IERC20(KKUB).approve(KKUB_UNWRAPPER, amountETH);
        if (!success) revert ApprovalFailed();

        success = KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountETH, to);
        if (!success) revert UnwrapFailed();
    }

    /// @notice Removes liquidity from ETH pair with fee-on-transfer token support
    /// @param token Address of fee-on-transfer token
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountTokenMin Minimum token amount to receive
    /// @param amountETHMin Minimum ETH amount to receive
    /// @param to Address that will receive token and ETH
    /// @param deadline Maximum timestamp for execution
    /// @return amountETH Amount of ETH received
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
            KKUB,
            liquidity,
            amountTokenMin,
            amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));

        bool success = IERC20(KKUB).approve(KKUB_UNWRAPPER, amountETH);
        if (!success) revert ApprovalFailed();

        success = KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountETH, to);
        if (!success) revert UnwrapFailed();
    }

    /// @notice Swaps exact input tokens for output tokens
    /// @param amountIn Exact amount of input tokens
    /// @param amountOutMin Minimum output tokens to receive
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive output tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = PonderRouterMathLib.getAmountsOutMultiHop(amountIn, path, FACTORY);
        if (amounts[amounts.length - 1] < amountOutMin)
            revert InsufficientOutputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amountIn
        );

        PonderRouterSwapLib.executeSwap(amounts, path, to, false, FACTORY);
    }

    /// @notice Swaps tokens for exact output tokens
    /// @param amountOut Exact amount of output tokens to receive
    /// @param amountInMax Maximum input tokens to spend
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive output tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        amounts = PonderRouterMathLib.getAmountsInMultiHop(amountOut, path, FACTORY);
        if (amounts[0] > amountInMax) revert ExcessiveInputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]
        );

        PonderRouterSwapLib.executeSwap(amounts, path, to, false, FACTORY);
    }

    /// @notice Swaps exact ETH for tokens
    /// @param amountOutMin Minimum tokens to receive
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[0] != KKUB) revert InvalidPath();

        amounts = PonderRouterMathLib.getAmountsOutMultiHop(msg.value, path, FACTORY);
        if (amounts[amounts.length - 1] < amountOutMin)
            revert InsufficientOutputAmount();

        IKKUB(KKUB).deposit{value: amounts[0]}();
        assert(IKKUB(KKUB).transfer(FACTORY.getPair(path[0], path[1]), amounts[0]));

        PonderRouterSwapLib.executeSwap(amounts, path, to, false, FACTORY);
    }

    /// @notice Swaps tokens for exact ETH
    /// @param amountOut Exact ETH amount to receive
    /// @param amountInMax Maximum input tokens to spend
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive ETH
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != KKUB) revert InvalidPath();

        amounts = PonderRouterMathLib.getAmountsInMultiHop(amountOut, path, FACTORY);
        if (amounts[0] > amountInMax) revert ExcessiveInputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]
        );

        PonderRouterSwapLib.executeSwap(amounts, path, address(this), false, FACTORY);

        bool success = IERC20(KKUB).approve(KKUB_UNWRAPPER, amountOut);
        if (!success) revert ApprovalFailed();

        success = KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountOut, to);
        if (!success) revert UnwrapFailed();
    }

    /// @notice Swaps exact tokens for ETH
    /// @param amountIn Exact input tokens to spend
    /// @param amountOutMin Minimum ETH to receive
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive ETH
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != KKUB) revert InvalidPath();

        amounts = PonderRouterMathLib.getAmountsOutMultiHop(amountIn, path, FACTORY);
        if (amounts[amounts.length - 1] < amountOutMin)
            revert InsufficientOutputAmount();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amounts[0]
        );

        PonderRouterSwapLib.executeSwap(amounts, path, address(this), false, FACTORY);

        bool success = IERC20(KKUB).approve(KKUB_UNWRAPPER, amounts[amounts.length - 1]);
        if (!success) revert ApprovalFailed();

        success = KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amounts[amounts.length - 1], to);
        if (!success) revert UnwrapFailed();
    }

    /// @notice Swaps ETH for exact tokens
    /// @param amountOut Exact tokens to receive
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) returns (uint256[] memory amounts) {
        if (path[0] != KKUB) revert InvalidPath();

        amounts = PonderRouterMathLib.getAmountsInMultiHop(amountOut, path, FACTORY);
        if (amounts[0] > msg.value) revert ExcessiveInputAmount();

        IKKUB(KKUB).deposit{value: amounts[0]}();
        assert(IKKUB(KKUB).transfer(FACTORY.getPair(path[0], path[1]), amounts[0]));

        PonderRouterSwapLib.executeSwap(amounts, path, to, false, FACTORY);

        if (msg.value > amounts[0]) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
        }
    }

    /// @notice Swaps exact tokens for tokens, supporting fee-on-transfer tokens
    /// @param amountIn Exact input tokens to spend
    /// @param amountOutMin Minimum output tokens to receive
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive output tokens
    /// @param deadline Maximum timestamp for execution
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
            revert InsufficientOutputAmount();
        }
    }

    /// @notice Swaps exact ETH for tokens, supporting fee-on-transfer tokens
    /// @param amountOutMin Minimum tokens to receive
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive tokens
    /// @param deadline Maximum timestamp for execution
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable override ensure(deadline) {
        if (path[0] != KKUB) revert InvalidPath();

        IKKUB(KKUB).deposit{value: msg.value}();
        assert(IKKUB(KKUB).transfer(FACTORY.getPair(path[0], path[1]), msg.value));

        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        PonderRouterSwapLib.executeSwap(new uint256[](path.length), path, to, true, FACTORY);

        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert InsufficientOutputAmount();
        }
    }

    /// @notice Swaps exact tokens for ETH, supporting fee-on-transfer tokens
    /// @param amountIn Exact input tokens to spend
    /// @param amountOutMin Minimum ETH to receive
    /// @param path Array of token addresses for swap route
    /// @param to Address that will receive ETH
    /// @param deadline Maximum timestamp for execution
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override ensure(deadline) {
        if (path[path.length - 1] != KKUB) revert InvalidPath();

        TransferHelper.safeTransferFrom(
            path[0], msg.sender, FACTORY.getPair(path[0], path[1]), amountIn
        );

        PonderRouterSwapLib.executeSwap(new uint256[](path.length), path, address(this), true, FACTORY);

        uint256 amountOut = IERC20(KKUB).balanceOf(address(this));
        if (amountOut < amountOutMin) revert InsufficientOutputAmount();

        bool success = IERC20(KKUB).approve(KKUB_UNWRAPPER, amountOut);
        if (!success) revert ApprovalFailed();

        success = KKUBUnwrapper(KKUB_UNWRAPPER).unwrapKKUB(amountOut, to);
        if (!success) revert UnwrapFailed();
    }

    /// @notice Gets reserves for a token pair
    /// @param tokenA Address of first token
    /// @param tokenB Address of second token
    /// @return reserveA Reserve amount of first token
    /// @return reserveB Reserve amount of second token
    function getReserves(
        address tokenA,
        address tokenB
    ) public view override returns (uint256 reserveA, uint256 reserveB) {
        return PonderRouterSwapLib.getReserves(tokenA, tokenB, FACTORY);
    }

    /// @notice Calculates output amounts for a swap path
    /// @param amountIn Input amount
    /// @param path Array of token addresses defining swap route
    /// @return amounts Array of amounts at each hop in path
    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) public view override returns (uint256[] memory amounts) {
        return PonderRouterMathLib.getAmountsOutMultiHop(amountIn, path, FACTORY);
    }

    /// @notice Calculates input amounts for a swap path
    /// @param amountOut Desired output amount
    /// @param path Array of token addresses defining swap route
    /// @return amounts Array of amounts at each hop in path
    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) public view override returns (uint256[] memory amounts) {
        return PonderRouterMathLib.getAmountsInMultiHop(amountOut, path, FACTORY);
    }

    /// @notice Calculates equivalent token amount based on reserves
    /// @param amountA Amount of first token
    /// @param reserveA Reserve of first token
    /// @param reserveB Reserve of second token
    /// @return amountB Equivalent amount of second token
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure override returns (uint256 amountB) {
        return PonderRouterMathLib.quote(amountA, reserveA, reserveB);
    }

    /// @notice Gets the wrapped ETH contract address
    /// @return Address of the KKUB contract
    function kkub() external view override returns (address) {
        return KKUB;
    }
}
