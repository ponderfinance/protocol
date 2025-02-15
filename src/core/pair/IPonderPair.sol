// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*//////////////////////////////////////////////////////////////
                    PONDER PAIR INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderPair
/// @author taayyohh
/// @notice Core interface for Ponder's automated market maker pairs
/// @dev Extends IERC20 to support LP token functionality
/// @dev Implements constant product AMM with fee collection
interface IPonderPair is IERC20 {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when liquidity is added to the pair
    /// @dev Triggered during successful mint operations
    /// @param sender Address initiating the liquidity provision
    /// @param amount0 Quantity of token0 deposited
    /// @param amount1 Quantity of token1 deposited
    event Mint(
        address indexed sender,
        uint256 amount0,
        uint256 amount1
    );

    /// @notice Emitted when liquidity is removed from the pair
    /// @dev Triggered during successful burn operations
    /// @param sender Address initiating the liquidity withdrawal
    /// @param amount0 Quantity of token0 withdrawn
    /// @param amount1 Quantity of token1 withdrawn
    /// @param to Recipient of the withdrawn tokens
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );

    /// @notice Emitted when tokens are swapped
    /// @dev Contains all swap parameters for off-chain tracking
    /// @param sender Address initiating the swap
    /// @param amount0In Quantity of token0 being sold
    /// @param amount1In Quantity of token1 being sold
    /// @param amount0Out Quantity of token0 being bought
    /// @param amount1Out Quantity of token1 being bought
    /// @param to Recipient of the bought tokens
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    /// @notice Emitted when reserves are updated
    /// @dev Used for tracking pool state and TWAP updates
    /// @param reserve0 Updated reserve of token0
    /// @param reserve1 Updated reserve of token1
    event Sync(
        uint112 reserve0,
        uint112 reserve1
    );

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum liquidity required for pool initialization
    /// @dev This amount is burned on first mint to prevent pool draining
    /// @return Minimum liquidity threshold
    function minimumLiquidity() external pure returns (uint256);

    /// @notice Address of the factory that created this pair
    /// @dev Immutable after initialization
    /// @return Factory contract address
    function factory() external view returns (address);

    /// @notice First token of the pair by address sort order
    /// @dev Immutable after initialization
    /// @return Address of token0
    function token0() external view returns (address);

    /// @notice Second token of the pair by address sort order
    /// @dev Immutable after initialization
    /// @return Address of token1
    function token1() external view returns (address);

    /// @notice Current reserves and last update timestamp
    /// @dev Values are packed for gas efficiency
    /// @return _reserve0 Current reserve of token0
    /// @return _reserve1 Current reserve of token1
    /// @return _blockTimestampLast Block timestamp of last reserve update
    function getReserves() external view returns (
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    );

    /// @notice Accumulated price oracle data for token0
    /// @dev Used for TWAP calculations
    /// @return Cumulative price of token0 in terms of token1
    function price0CumulativeLast() external view returns (uint256);

    /// @notice Accumulated price oracle data for token1
    /// @dev Used for TWAP calculations
    /// @return Cumulative price of token1 in terms of token0
    function price1CumulativeLast() external view returns (uint256);

    /// @notice Last recorded reserve product (K value)
    /// @dev Used for fee calculations
    /// @return Product of last recorded reserves
    function kLast() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        STATE-CHANGING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Adds liquidity to the pair
    /// @dev Requires prior token approval
    /// @param to Recipient of the liquidity tokens
    /// @return liquidity Amount of LP tokens minted
    function mint(address to) external returns (uint256 liquidity);

    /// @notice Removes liquidity from the pair
    /// @dev Requires prior LP token approval
    /// @param to Recipient of the withdrawn tokens
    /// @return amount0 Amount of token0 returned
    /// @return amount1 Amount of token1 returned
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /// @notice Swaps tokens using the pair
    /// @dev Supports flash swaps when data parameter is populated
    /// @param amount0Out Quantity of token0 to receive
    /// @param amount1Out Quantity of token1 to receive
    /// @param to Recipient of output tokens
    /// @param data Optional data for flash swap callback
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /// @notice Forces balances to match reserves
    /// @dev Sends excess tokens to specified recipient
    /// @param to Address receiving excess tokens
    function skim(address to) external;

    /// @notice Forces reserves to match balances
    /// @dev Updates reserves without moving tokens
    function sync() external;

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the pair with token addresses
    /// @dev Can only be called once by factory
    /// @dev Parameters use underscore suffix to avoid shadowing
    /// @param token0_ Address of first token (lower sort order)
    /// @param token1_ Address of second token (higher sort order)
    function initialize(address token0_, address token1_) external;

    /*//////////////////////////////////////////////////////////////
                         CUSTOM ERRORS
 //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when reentrancy lock is active
    error Locked();

    /// @notice Thrown when caller lacks permissions
    error Forbidden();

    /// @notice Thrown when token transfer fails
    error TransferFailed();

    /// @notice Thrown when output amount is below minimum
    error InsufficientOutputAmount();

    /// @notice Thrown for invalid recipient address
    error InvalidToAddress();

    /// @notice Thrown when pool lacks required liquidity
    error InsufficientLiquidity();

    /// @notice Thrown when LP token burn amount is too low
    error InsufficientLiquidityBurned();

    /// @notice Thrown when initial liquidity is below minimum
    error InsufficientInitialLiquidity();

    /// @notice Thrown when LP token mint would be zero
    error InsufficientLiquidityMinted();

    /// @notice Thrown when swap output is below minimum
    error InsufficientOutput();

    /// @notice Thrown when recipient address is zero
    error InvalidRecipient();

    /// @notice Thrown when pool lacks swap liquidity
    error InsufficientLiquiditySwap();

    /// @notice Thrown when swap input is too low
    error InsufficientInputAmount();

    /// @notice Thrown when K value validation fails
    error KValueCheckFailed();

    /// @notice Thrown when constant product invariant breaks
    error InvariantViolation();

    /// @notice Thrown on arithmetic overflow
    error Overflow();

    /// @notice Thrown when address is zero
    error ZeroAddress();
}
