// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    ROUTER INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderRouter
/// @author taayyohh
/// @notice Interface for the Ponder protocol's router contract
/// @dev Provides functionality for:
///      - Liquidity provision and removal
///      - Token swaps with various input/output configurations
///      - ETH/Token pair operations
///      - Fee-on-transfer token support
interface IPonderRouter {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when liquidity is added to an ETH pair
    /// @param token Token address paired with ETH
    /// @param to Recipient of LP tokens
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
    /// @param ethAmount Amount of ETH spent
    /// @param tokenAmount Amount of tokens received
    /// @param path Array of addresses defining swap route
    /// @param to Recipient of output tokens
    event SwapETHForExactTokens(
        address indexed sender,
        uint256 ethAmount,
        uint256 tokenAmount,
        address[] path,
        address indexed to
    );

    /// @notice Emitted when excess ETH is returned
    /// @param to Recipient of refund
    /// @param amount Amount of ETH refunded
    event ETHRefunded(
        address indexed to,
        uint256 amount
    );

    /// @notice Emitted when ETH refund fails
    /// @param recipient Intended refund recipient
    /// @param amount Failed refund amount
    /// @param reason Failure details
    event ETHRefundFailed(
        address indexed recipient,
        uint256 amount,
        bytes reason
    );

    /// @notice Emitted for swaps with significant price impact
    /// @param inputAmount Amount of input tokens
    /// @param outputAmount Amount of output tokens
    /// @param priceImpact Impact in basis points
    event PriceImpactWarning(
        uint256 inputAmount,
        uint256 outputAmount,
        uint256 priceImpact
    );

    /// @notice Emitted when ETH for exact tokens swap begins
    /// @param sender Swap initiator
    /// @param ethValue ETH amount sent
    /// @param expectedOutput Expected token output
    /// @param deadline Transaction deadline
    event SwapETHForExactTokensStarted(
        address indexed sender,
        uint256 ethValue,
        uint256 expectedOutput,
        uint256 deadline
    );

    /*//////////////////////////////////////////////////////////////
                        LIQUIDITY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds liquidity to a token pair
    /// @dev Calculates optimal amounts based on current reserves
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param amountADesired Desired amount of first token
    /// @param amountBDesired Desired amount of second token
    /// @param amountAMin Minimum acceptable first token amount
    /// @param amountBMin Minimum acceptable second token amount
    /// @param to Recipient of LP tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amountA Actual amount of first token used
    /// @return amountB Actual amount of second token used
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
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Adds liquidity to an ETH pair
    /// @dev Handles ETH wrapping and optimal amount calculation
    /// @param token Token to pair with ETH
    /// @param amountTokenDesired Desired token amount
    /// @param amountTokenMin Minimum token amount
    /// @param amountETHMin Minimum ETH amount
    /// @param to Recipient of LP tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amountToken Actual token amount used
    /// @return amountETH Actual ETH amount used
    /// @return liquidity Amount of LP tokens minted
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    /// @notice Removes liquidity from a token pair
    /// @dev Burns LP tokens and returns underlying assets
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountAMin Minimum acceptable first token amount
    /// @param amountBMin Minimum acceptable second token amount
    /// @param to Recipient of underlying tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amountA Amount of first token returned
    /// @return amountB Amount of second token returned
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    /// @notice Removes liquidity from an ETH pair
    /// @dev Burns LP tokens and handles ETH unwrapping
    /// @param token Token paired with ETH
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountTokenMin Minimum token amount
    /// @param amountETHMin Minimum ETH amount
    /// @param to Recipient of token and ETH
    /// @param deadline Maximum timestamp for execution
    /// @return amountToken Amount of token returned
    /// @return amountETH Amount of ETH returned
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    /// @notice Removes liquidity from ETH pair with fee-on-transfer support
    /// @dev Handles tokens that take fees on transfers
    /// @param token Token paired with ETH
    /// @param liquidity Amount of LP tokens to burn
    /// @param amountTokenMin Minimum token amount
    /// @param amountETHMin Minimum ETH amount
    /// @param to Recipient of token and ETH
    /// @param deadline Maximum timestamp for execution
    /// @return amountETH Amount of ETH returned
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    /*//////////////////////////////////////////////////////////////
                        SWAP FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Swaps exact input tokens for output tokens
    /// @dev Multiple pairs can be used for routing
    /// @param amountIn Exact amount to swap
    /// @param amountOutMin Minimum output required
    /// @param path Array of token addresses for routing
    /// @param to Recipient of output tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps tokens for exact output tokens
    /// @dev Calculates required input amount
    /// @param amountOut Exact output amount desired
    /// @param amountInMax Maximum input amount
    /// @param path Array of token addresses for routing
    /// @param to Recipient of output tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps exact ETH for tokens
    /// @dev Handles ETH wrapping
    /// @param amountOutMin Minimum tokens required
    /// @param path Array of token addresses for routing
    /// @param to Recipient of tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    /// @notice Swaps tokens for exact ETH
    /// @dev Handles ETH unwrapping
    /// @param amountOut Exact ETH amount desired
    /// @param amountInMax Maximum input tokens
    /// @param path Array of token addresses for routing
    /// @param to Recipient of ETH
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps exact tokens for ETH
    /// @dev Handles ETH unwrapping
    /// @param amountIn Exact input token amount
    /// @param amountOutMin Minimum ETH required
    /// @param path Array of token addresses for routing
    /// @param to Recipient of ETH
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    /// @notice Swaps ETH for exact tokens
    /// @dev Handles ETH wrapping and refunds excess
    /// @param amountOut Exact token amount desired
    /// @param path Array of token addresses for routing
    /// @param to Recipient of tokens
    /// @param deadline Maximum timestamp for execution
    /// @return amounts Array of input/output amounts for path
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    /*//////////////////////////////////////////////////////////////
                    FEE-ON-TRANSFER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Swap exact tokens supporting fee-on-transfer
    /// @dev Handles tokens that take fees on transfers
    /// @param amountIn Exact input amount
    /// @param amountOutMin Minimum output required
    /// @param path Array of token addresses for routing
    /// @param to Recipient of tokens
    /// @param deadline Maximum timestamp for execution
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    /// @notice Swap exact ETH supporting fee-on-transfer
    /// @dev Handles ETH wrapping and fee-on-transfer tokens
    /// @param amountOutMin Minimum tokens required
    /// @param path Array of token addresses for routing
    /// @param to Recipient of tokens
    /// @param deadline Maximum timestamp for execution
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    /// @notice Swap exact tokens for ETH supporting fee-on-transfer
    /// @dev Handles ETH unwrapping and fee-on-transfer tokens
    /// @param amountIn Exact token amount
    /// @param amountOutMin Minimum ETH required
    /// @param path Array of token addresses for routing
    /// @param to Recipient of ETH
    /// @param deadline Maximum timestamp for execution
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates output amounts for a path
    /// @dev Simulates swap without execution
    /// @param amountIn Input amount
    /// @param path Array of token addresses
    /// @return amounts Array of amounts for each hop
    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) external view returns (uint256[] memory amounts);

    /// @notice Calculates input amounts for a path
    /// @dev Simulates swap without execution
    /// @param amountOut Desired output amount
    /// @param path Array of token addresses
    /// @return amounts Array of amounts for each hop
    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) external view returns (uint256[] memory amounts);

    /// @notice Gets reserves for a token pair
    /// @dev Used for price calculations
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return reserveA Reserve of first token
    /// @return reserveB Reserve of second token
    function getReserves(
        address tokenA,
        address tokenB
    ) external view returns (uint256 reserveA, uint256 reserveB);

    /// @notice Calculates equivalent token amount
    /// @dev Based on constant product formula
    /// @param amountA Amount of first token
    /// @param reserveA Reserve of first token
    /// @param reserveB Reserve of second token
    /// @return amountB Equivalent amount of second token
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    /// @notice Gets wrapped native token address
    /// @dev Used for ETH<>Token operations
    /// @return KKUB contract address
    function kkub() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                        TRANSACTION ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Timing and deadline errors
    error ExpiredDeadline();              /// @dev Transaction exceeded time limit
    error Locked();                       /// @dev Reentrancy guard triggered

    /*//////////////////////////////////////////////////////////////
                            AMOUNT ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Amount validation errors
    error InsufficientOutputAmount();     /// @dev Output below minimum
    error InsufficientAAmount();          /// @dev First token amount too low
    error InsufficientBAmount();          /// @dev Second token amount too low
    error InsufficientAmount();           /// @dev Generic amount too low
    error InsufficientInputAmount();      /// @dev Input amount too low
    error ExcessiveInputAmount();         /// @dev Input exceeds maximum
    error InvalidAmount();                /// @dev Amount validation failed
    error ZeroOutput();                   /// @dev Output calculated as zero

    /*//////////////////////////////////////////////////////////////
                            LIQUIDITY ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Pool and liquidity errors
    error InsufficientLiquidity();        /// @dev Pool liquidity too low
    error ExcessivePriceImpact(           /// @dev Price impact too high
        uint256 impact                    /// @dev Impact in basis points
    );

    /*//////////////////////////////////////////////////////////////
                            PATH ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Path validation errors
    error InvalidPath();                  /// @dev Swap path is invalid
    error IdenticalAddresses();           /// @dev Attempting same-token swap
    error PairNonexistent();             /// @dev Trading pair not found
    error PairCreationFailed();          /// @dev Failed to create pair

    /*//////////////////////////////////////////////////////////////
                            ETH HANDLING ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice ETH-specific errors
    error InsufficientETH();             /// @dev Not enough ETH sent
    error InvalidETHAmount();            /// @dev ETH amount invalid
    error RefundFailed();                /// @dev ETH refund failed
    error UnwrapFailed();                /// @dev KKUB unwrap failed

    /*//////////////////////////////////////////////////////////////
                            TOKEN ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Token operation errors
    error ZeroAddress();                 /// @dev Invalid zero address
    error TransferFailed();              /// @dev Token transfer failed
    error ApprovalFailed();              /// @dev Token approval failed
    error InsufficientKkubBalance();     /// @dev Not enough KKUB
    error KKUBApprovalFailure();          /// @dev KKUB approval failed
}
