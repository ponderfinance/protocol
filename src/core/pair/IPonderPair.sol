// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IPonderPair
 * @notice Interface for the PonderPair AMM contract
 * @dev Extends IERC20 for LP token functionality
 */
interface IPonderPair is IERC20 {
    /**
     * @notice Emitted when liquidity is added to the pair
     * @param sender Address of the liquidity provider
     * @param amount0 Amount of token0 added
     * @param amount1 Amount of token1 added
     */
    event Mint(
        address indexed sender,
        uint256 amount0,
        uint256 amount1
    );

    /**
     * @notice Emitted when liquidity is removed from the pair
     * @param sender Address triggering the liquidity removal
     * @param amount0 Amount of token0 removed
     * @param amount1 Amount of token1 removed
     * @param to Address receiving the withdrawn tokens
     */
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );

    /**
     * @notice Emitted when a swap occurs on the pair
     * @param sender Address initiating the swap
     * @param amount0In Amount of token0 being sold
     * @param amount1In Amount of token1 being sold
     * @param amount0Out Amount of token0 being bought
     * @param amount1Out Amount of token1 being bought
     * @param to Address receiving the bought tokens
     */
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    /**
     * @notice Emitted when reserves are synchronized
     * @param reserve0 Current reserve of token0
     * @param reserve1 Current reserve of token1
     */
    event Sync(
        uint112 reserve0,
        uint112 reserve1
    );

    /**
     * @notice Returns minimum liquidity required for pool initialization
     * @return Minimum liquidity amount
     */
    function minimumLiquidity() external pure returns (uint256);

    /**
     * @notice Returns the factory contract address
     * @return Address of the factory contract
     */
    function factory() external view returns (address);

    /**
     * @notice Returns the address of the first token in the pair
     * @return Address of token0
     */
    function token0() external view returns (address);

    /**
     * @notice Returns the address of the second token in the pair
     * @return Address of token1
     */
    function token1() external view returns (address);

    /**
     * @notice Returns the current reserves and last updated timestamp
     * @return _reserve0 Current reserve of token0
     * @return _reserve1 Current reserve of token1
     * @return _blockTimestampLast Timestamp of last reserve update
     */
    function getReserves() external view returns (
        uint112 _reserve0,
        uint112 _reserve1,
        uint32 _blockTimestampLast
    );

    /**
     * @notice Returns the cumulative price of token0 in terms of token1
     * @return Cumulative price value
     */
    function price0CumulativeLast() external view returns (uint256);

    /**
     * @notice Returns the cumulative price of token1 in terms of token0
     * @return Cumulative price value
     */
    function price1CumulativeLast() external view returns (uint256);

    /**
     * @notice Returns the last recorded K value (product of reserves)
     * @return Last K value
     */
    function kLast() external view returns (uint256);

    /**
     * @notice Adds liquidity to the pair
     * @param to Address receiving the LP tokens
     * @return liquidity Amount of LP tokens minted
     */
    function mint(address to) external returns (uint256 liquidity);

    /**
     * @notice Removes liquidity from the pair
     * @param to Address receiving the withdrawn tokens
     * @return amount0 Amount of token0 withdrawn
     * @return amount1 Amount of token1 withdrawn
     */
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /**
     * @notice Executes a token swap
     * @param amount0Out Amount of token0 to receive
     * @param amount1Out Amount of token1 to receive
     * @param to Address receiving the output tokens
     * @param data Additional data for flash loan functionality
     */
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    /**
     * @notice Force balances to match reserves
     * @param to Address receiving the excess tokens
     */
    function skim(address to) external;

    /**
     * @notice Force reserves to match balances
     */
    function sync() external;


    /**
        * @dev Initialize function uses underscore suffix naming convention
     * to explicitly avoid shadowing while maintaining clear parameter names
     * @notice Initializes the pair with token addresses
     * @param token0_ Address of the first token
     * @param token1_ Address of the second token
     */
    function initialize(address token0_, address token1_) external;
}
