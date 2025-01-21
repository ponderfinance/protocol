// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PonderPairStorage
 * @notice Abstract contract defining storage layout for PonderPair
 * @dev Pure storage contract that only defines state variables
 */
abstract contract PonderPairStorage {
    /**
     * @notice Address of the factory that created this pair
     */
    address internal _factory;

    /**
     * @notice Address of the first token in the pair
     * @dev Token with the lower address value between the two pair tokens
     */
    address internal _token0;

    /**
     * @notice Address of the second token in the pair
     * @dev Token with the higher address value between the two pair tokens
     */
    address internal _token1;

    /**
     * @notice Reserve of token0
     * @dev Updated on every mint/burn/swap/sync
     */
    uint112 internal _reserve0;

    /**
     * @notice Reserve of token1
     * @dev Updated on every mint/burn/swap/sync
     */
    uint112 internal _reserve1;

    /**
     * @notice Timestamp of the last reserve update
     * @dev Used for price oracle functionality
     */
    uint32 internal _blockTimestampLast;

    /**
     * @notice Cumulative price of token0 in terms of token1
     * @dev Used for time-weighted average price (TWAP) calculations
     */
    uint256 internal _price0CumulativeLast;

    /**
     * @notice Cumulative price of token1 in terms of token0
     * @dev Used for time-weighted average price (TWAP) calculations
     */
    uint256 internal _price1CumulativeLast;

    /**
     * @notice Last recorded product of reserves (K value)
     * @dev Used for LP fee calculation when feeTo is set
     */
    uint256 internal _kLast;

    /**
     * @notice Reentrancy guard state
     * @dev 1 = not entered, 2 = entered
     */
    uint256 internal _unlocked = 1;

    /**
     * @notice Accumulated protocol fees for token0 pending collection
     * @dev Collected via skim function
     */
    uint256 internal _accumulatedFee0;

    /**
     * @notice Accumulated protocol fees for token1 pending collection
     * @dev Collected via skim function
     */
    uint256 internal _accumulatedFee1;
}
