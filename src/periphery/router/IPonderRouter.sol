// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Ponder Router Interface
/// @notice Interface for the PonderRouter contract that handles swaps and liquidity
/// @dev Defines all external functions and events for the router
interface IPonderRouter {
    /// @notice Emitted when liquidity is added with ETH
    /// @param token The token paired with ETH
    /// @param to Address receiving LP tokens
    /// @param amountToken Amount of token added
    /// @param amountETH Amount of ETH added
    /// @param liquidity Amount of LP tokens minted
    event LiquidityETHAdded(
        address indexed token,
        address indexed to,
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    );

    /// @notice Emitted when ETH is swapped for exact tokens
    /// @param sender Address initiating the swap
    /// @param ethAmount Amount of ETH used
    /// @param tokenAmount Amount of tokens received
    /// @param path Token path used for swap
    /// @param to Address receiving tokens
    event SwapETHForExactTokens(
        address indexed sender,
        uint256 ethAmount,
        uint256 tokenAmount,
        address[] path,
        address indexed to
    );

    /// @notice Emitted when excess ETH is refunded
    /// @param to Address receiving refund
    /// @param amount Amount of ETH refunded
    event ETHRefunded(
        address indexed to,
        uint256 amount
    );

    /// @notice Emitted when ETH refund fails
    /// @param recipient Intended refund recipient
    /// @param amount Amount that failed to refund
    /// @param reason Failure reason
    event ETHRefundFailed(
        address indexed recipient,
        uint256 amount,
        bytes reason
    );

    /// @notice Emitted when a swap with high price impact occurs
    /// @param inputAmount Amount of input tokens
    /// @param outputAmount Amount of output tokens
    /// @param priceImpact Calculated price impact in basis points
    event PriceImpactWarning(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 priceImpact
    );

    /// @notice Emitted when ETH for exact tokens swap starts
    /// @param sender Address initiating the swap
    /// @param ethValue Amount of ETH sent
    /// @param expectedOutput Expected token output
    /// @param deadline Transaction deadline
    event SwapETHForExactTokensStarted(
        address indexed sender,
        uint256 ethValue,
        uint256 expectedOutput,
        uint256 deadline
    );

    /// @notice Add liquidity to a token pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param amountADesired Desired amount of tokenA
    /// @param amountBDesired Desired amount of tokenB
    /// @param amountAMin Minimum amount of tokenA
    /// @param amountBMin Minimum amount of tokenB
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
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Add liquidity to an ETH pair
    /// @param token Token to pair with ETH
    /// @param amountTokenDesired Desired amount of token
    /// @param amountTokenMin Minimum amount of token
    /// @param amountETHMin Minimum amount of ETH
    /// @param to Address to receive LP tokens
    /// @param deadline Maximum timestamp for execution
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    /// @notice Remove liquidity from a pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountAMin Minimum amount of tokenA
    /// @param amountBMin Minimum amount of tokenB
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
    ) external returns (uint256 amountA, uint256 amountB);

    /// @notice Remove liquidity from an ETH pair
    /// @param token Token paired with ETH
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountTokenMin Minimum amount of token
    /// @param amountETHMin Minimum amount of ETH
    /// @param to Address to receive tokens and ETH
    /// @param deadline Maximum timestamp for execution
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    /// @notice Remove liquidity from an ETH pair supporting fee-on-transfer tokens
    /// @param token Token paired with ETH
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountTokenMin Minimum amount of token
    /// @param amountETHMin Minimum amount of ETH
    /// @param to Address to receive tokens and ETH
    /// @param deadline Maximum timestamp for execution
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

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
    ) external returns (uint256[] memory amounts);

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
    ) external returns (uint256[] memory amounts);

    /// @notice Swap exact ETH for tokens
    /// @param amountOutMin Minimum amount of tokens
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive tokens
    /// @param deadline Maximum timestamp for execution
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    /// @notice Swap tokens for exact ETH
    /// @param amountOut Exact amount of ETH to receive
    /// @param amountInMax Maximum amount of input tokens
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive ETH
    /// @param deadline Maximum timestamp for execution
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swap exact tokens for ETH
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum amount of ETH
    /// @param path Array of token addresses in swap path
    /// @param to Address to receive ETH
    /// @param deadline Maximum timestamp for execution
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

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
    ) external payable returns (uint256[] memory amounts);

    /// @notice Support for fee-on-transfer tokens
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    /// @notice Support for fee-on-transfer tokens with ETH
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    /// @notice Support for fee-on-transfer tokens to ETH
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    /// @notice Get amounts out for a trade
    /// @param amountIn Input amount
    /// @param path Array of token addresses
    /// @return amounts Array of amounts
    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) external view returns (uint256[] memory amounts);

    /// @notice Get amounts in for a trade
    /// @param amountOut Output amount
    /// @param path Array of token addresses
    /// @return amounts Array of amounts
    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) external view returns (uint256[] memory amounts);


    /// @notice Get reserves for a pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return reserveA Reserve of tokenA
    /// @return reserveB Reserve of tokenB
    function getReserves(
        address tokenA,
        address tokenB
    ) external view returns (uint256 reserveA, uint256 reserveB);

    /// @notice Quote swap amount
    /// @param amountA Amount of first token
    /// @param reserveA Reserve of first token
    /// @param reserveB Reserve of second token
    /// @return amountB Quoted amount of second token
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    /// @notice Get the WETH address
    /// @return Address of the WETH contract
    function weth() external view returns (address);
}
