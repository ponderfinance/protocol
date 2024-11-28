// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IPonderFactory.sol";
import "../interfaces/IPonderPair.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../libraries/TransferHelper.sol";
import "./KKUBUnwrapper.sol";

/// @title Ponder Router for swapping tokens and managing liquidity
/// @notice Handles routing of trades and liquidity provision between pairs
/// @dev Manages interactions with PonderPair contracts and handles unwrapping of KKUB
contract PonderRouter {
    error ExpiredDeadline();
    error InsufficientOutputAmount();
    error InsufficientAAmount();
    error InsufficientBAmount();
    error InsufficientLiquidity();
    error InvalidPath();
    error IdenticalAddresses();
    error ZeroAddress();
    error ExcessiveInputAmount();

    /// @notice Address of KKUBUnwrapper contract used for unwrapping KKUB
    address payable public immutable kkubUnwrapper;
    /// @notice Factory contract for creating and managing pairs
    IPonderFactory public immutable factory;
    /// @notice Address of WETH/KKUB contract
    address public immutable WETH;

    /// @dev Modifier to check if deadline has passed
    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert ExpiredDeadline();
        _;
    }

    /// @notice Contract constructor
    /// @param _factory Address of PonderFactory contract
    /// @param _WETH Address of WETH/KKUB contract
    /// @param _kkubUnwrapper Address of KKUBUnwrapper contract
    constructor(address _factory, address _WETH, address _kkubUnwrapper) {
        factory = IPonderFactory(_factory);
        WETH = _WETH;
        kkubUnwrapper = payable(_kkubUnwrapper);
    }

    receive() external payable {
        assert(msg.sender == WETH);
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
        if (factory.getPair(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB);
        }

        (uint256 reserveA, uint256 reserveB) = getReserves(tokenA, tokenB);

        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) revert InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                if (amountAOptimal < amountAMin) revert InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /// @notice Add liquidity to a pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param amountADesired Desired amount of tokenA
    /// @param amountBDesired Desired amount of tokenB
    /// @param amountAMin Minimum acceptable amount of tokenA
    /// @param amountBMin Minimum acceptable amount of tokenB
    /// @param to Address to receive LP tokens
    /// @param deadline Maximum timestamp for execution
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(
            tokenA, tokenB,
            amountADesired, amountBDesired,
            amountAMin, amountBMin
        );
        address pair = factory.getPair(tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IPonderPair(pair).mint(to);
    }

    /// @notice Add liquidity to an ETH/KKUB pair
    /// @param token Token address to pair with ETH/KKUB
    /// @param amountTokenDesired Desired amount of token
    /// @param amountTokenMin Minimum acceptable amount of token
    /// @param amountETHMin Minimum acceptable amount of ETH/KKUB
    /// @param to Address to receive LP tokens
    /// @param deadline Maximum timestamp for execution
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external virtual payable ensure(deadline) returns (uint256 amountToken, uint256 amountETH, uint256 liquidity) {
        (amountToken, amountETH) = _addLiquidity(
            token, WETH,
            amountTokenDesired, msg.value,
            amountTokenMin, amountETHMin
        );

        address pair = factory.getPair(token, WETH);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWETH(WETH).deposit{value: amountETH}();
        assert(IWETH(WETH).transfer(pair, amountETH));
        liquidity = IPonderPair(pair).mint(to);

        if (msg.value > amountETH) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amountETH);
        }
    }

    /// @notice Remove liquidity from a pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountAMin Minimum amount of tokenA to receive
    /// @param amountBMin Minimum amount of tokenB to receive
    /// @param to Address to receive tokens
    /// @param deadline Maximum timestamp for execution
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public virtual ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = factory.getPair(tokenA, tokenB);
        IPonderPair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountA, amountB) = IPonderPair(pair).burn(to);
        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountB < amountBMin) revert InsufficientBAmount();
    }

    /// @notice Remove liquidity from an ETH/KKUB pair and unwrap KKUB
    /// @param token Token address paired with ETH/KKUB
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountTokenMin Minimum amount of token to receive
    /// @param amountETHMin Minimum amount of ETH to receive
    /// @param to Address to receive tokens and ETH
    /// @param deadline Maximum timestamp for execution
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual ensure(deadline) returns (uint256 amountToken, uint256 amountETH) {
        (amountToken, amountETH) = removeLiquidity(
            token, WETH,
            liquidity,
            amountTokenMin, amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IERC20(WETH).approve(kkubUnwrapper, amountETH);
        KKUBUnwrapper(kkubUnwrapper).unwrapKKUB(amountETH, to);
    }

    /// @notice Remove liquidity from an ETH/KKUB pair supporting fee-on-transfer tokens
    /// @param token Token address paired with ETH/KKUB
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountTokenMin Minimum amount of token to receive
    /// @param amountETHMin Minimum amount of ETH to receive
    /// @param to Address to receive tokens and ETH
    /// @param deadline Maximum timestamp for execution
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) public virtual ensure(deadline) returns (uint256 amountETH) {
        (, amountETH) = removeLiquidity(
            token, WETH,
            liquidity,
            amountTokenMin, amountETHMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IERC20(WETH).approve(kkubUnwrapper, amountETH);
        KKUBUnwrapper(kkubUnwrapper).unwrapKKUB(amountETH, to);
    }

    /// @notice Internal swap function
    /// @param amounts Array of token amounts
    /// @param path Array of token addresses in swap path
    /// @param _to Address to receive output tokens
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? factory.getPair(output, path[i + 2]) : _to;
            IPonderPair(factory.getPair(input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /// @notice Swap exact tokens for tokens
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum amount of output tokens
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive output tokens
    /// @param deadline Maximum timestamp for execution
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
        TransferHelper.safeTransferFrom(path[0], msg.sender, factory.getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    /// @notice Swap tokens for exact tokens
    /// @param amountOut Exact amount of output tokens
    /// @param amountInMax Maximum amount of input tokens
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive tokens
    /// @param deadline Maximum timestamp for execution
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) revert ExcessiveInputAmount();
        TransferHelper.safeTransferFrom(path[0], msg.sender, factory.getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
    }

    /// @notice Swap exact ETH for tokens
    /// @param amountOutMin Minimum amount of tokens to receive
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive tokens
    /// @param deadline Maximum timestamp for execution
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual payable ensure(deadline) returns (uint256[] memory amounts) {
        if (path[0] != WETH) revert InvalidPath();
        amounts = getAmountsOut(msg.value, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(factory.getPair(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }

    /// @notice Swap tokens for exact ETH using KKUB unwrapper
    /// @param amountOut Exact amount of ETH to receive
    /// @param amountInMax Maximum amount of tokens to spend
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive ETH
    /// @param deadline Maximum timestamp for execution
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WETH) revert InvalidPath();
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > amountInMax) revert ExcessiveInputAmount();
        TransferHelper.safeTransferFrom(path[0], msg.sender, factory.getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        IERC20(WETH).approve(kkubUnwrapper, amountOut);
        KKUBUnwrapper(kkubUnwrapper).unwrapKKUB(amountOut, to);
    }

    /// @notice Swap exact tokens for ETH using KKUB unwrapper
    /// @param amountIn Amount of tokens to spend
    /// @param amountOutMin Minimum amount of ETH to receive
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive ETH
    /// @param deadline Maximum timestamp for execution
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WETH) revert InvalidPath();
        amounts = getAmountsOut(amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) revert InsufficientOutputAmount();
        TransferHelper.safeTransferFrom(path[0], msg.sender, factory.getPair(path[0], path[1]), amounts[0]);
        _swap(amounts, path, address(this));
        uint256 amountOut = amounts[amounts.length - 1];
        IERC20(WETH).approve(kkubUnwrapper, amountOut);
        KKUBUnwrapper(kkubUnwrapper).unwrapKKUB(amountOut, to);
    }

    /// @notice Swap ETH for exact tokens
    /// @param amountOut Exact amount of tokens to receive
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive tokens
    /// @param deadline Maximum timestamp for execution
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual payable ensure(deadline) returns (uint256[] memory amounts) {
        if (path[0] != WETH) revert InvalidPath();
        amounts = getAmountsIn(amountOut, path);
        if (amounts[0] > msg.value) revert ExcessiveInputAmount();
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(factory.getPair(path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) {
            TransferHelper.safeTransferETH(msg.sender, msg.value - amounts[0]);
        }
    }

    /// @notice Swap exact tokens for tokens supporting fee-on-transfer tokens
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum amount of output tokens
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive tokens
    /// @param deadline Maximum timestamp for execution
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) {
        TransferHelper.safeTransferFrom(path[0], msg.sender, factory.getPair(path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert InsufficientOutputAmount();
        }
    }

    /// @notice Swap exact ETH for tokens supporting fee-on-transfer tokens
    /// @param amountOutMin Minimum amount of tokens to receive
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive tokens
    /// @param deadline Maximum timestamp for execution
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual payable ensure(deadline) {
        if (path[0] != WETH) revert InvalidPath();
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        assert(IWETH(WETH).transfer(factory.getPair(path[0], path[1]), amountIn));
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert InsufficientOutputAmount();
        }
    }

    /// @notice Swap exact tokens for ETH supporting fee-on-transfer tokens using KKUB unwrapper
    /// @param amountIn Amount of tokens to swap
    /// @param amountOutMin Minimum amount of ETH to receive
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive ETH
    /// @param deadline Maximum timestamp for execution
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual ensure(deadline) {
        if (path[path.length - 1] != WETH) revert InvalidPath();
        TransferHelper.safeTransferFrom(path[0], msg.sender, factory.getPair(path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        if (amountOut < amountOutMin) revert InsufficientOutputAmount();
        IERC20(WETH).approve(kkubUnwrapper, amountOut);
        KKUBUnwrapper(kkubUnwrapper).unwrapKKUB(amountOut, to);
    }

    /// @notice Internal swap function for fee-on-transfer tokens
    /// @param path Array of token addresses in swap path
    /// @param _to Address to receive tokens
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = sortTokens(input, output);
            IPonderPair pair = IPonderPair(factory.getPair(input, output));
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
            address to = i < path.length - 2 ? factory.getPair(output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /// @notice Get amount of tokenB for a given amount of tokenA
    /// @param amountA Amount of tokenA
    /// @param reserveA Reserve of tokenA in pair
    /// @param reserveB Reserve of tokenB in pair
    /// @return amountB Amount of tokenB
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB)
    public
    pure
    virtual
    returns (uint256 amountB)
    {
        if (amountA == 0) revert InsufficientAmount();
        if (reserveA == 0 || reserveB == 0) revert InsufficientLiquidity();
        amountB = (amountA * reserveB) / reserveA;
    }

    /// @notice Get reserves for a pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return reserveA Reserve of tokenA
    /// @return reserveB Reserve of tokenB
    function getReserves(address tokenA, address tokenB)
    public
    view
    returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = IPonderPair(factory.getPair(tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @notice Sort token addresses
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return token0 Lower token address
    /// @return token1 Higher token address
    function sortTokens(address tokenA, address tokenB)
    public
    pure
    returns (address token0, address token1)
    {
        if (tokenA == tokenB) revert IdenticalAddresses();
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert ZeroAddress();
    }

    /// @notice Get output amounts for path
    /// @param amountIn Input amount
    /// @param path Array of token addresses
    /// @return amounts Array of input/output amounts for path
    function getAmountsOut(uint256 amountIn, address[] memory path)
    public
    view
    virtual
    returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert InvalidPath();
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    /// @notice Get required input amount for desired output
    /// @param amountOut Desired output amount
    /// @param path Array of token addresses
    /// @return amounts Array of input/output amounts for path
    function getAmountsIn(uint256 amountOut, address[] memory path)
    public
    view
    virtual
    returns (uint256[] memory amounts)
    {
        if (path.length < 2) revert InvalidPath();
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
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
    public
    pure
    virtual
    returns (uint256 amountOut)
    {
        if (amountIn == 0) revert InsufficientInputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
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
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
    public
    pure
    virtual
    returns (uint256 amountIn)
    {
        if (amountOut == 0) revert InsufficientOutputAmount();
        if (reserveIn == 0 || reserveOut == 0) revert InsufficientLiquidity();
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    error InsufficientAmount();
    error InsufficientInputAmount();
}
