// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER PAIR STORAGE
//////////////////////////////////////////////////////////////*/

/// @title PonderPairStorage
/// @author taayyohh
/// @notice Storage layout for Ponder protocol's liquidity pair contracts
/// @dev Abstract contract defining state variables for pair implementation
///      Must be inherited by the main implementation contract
abstract contract PonderPairStorage {
    /*//////////////////////////////////////////////////////////////
                        TOKEN REFERENCES
    //////////////////////////////////////////////////////////////*/

    /// @notice First token in trading pair
    /// @dev Token with lower address value (token0 < token1)
    /// @dev Immutable after initialization
    address internal _token0;

    /// @notice Second token in trading pair
    /// @dev Token with higher address value (token1 > token0)
    /// @dev Immutable after initialization
    address internal _token1;

    /*//////////////////////////////////////////////////////////////
                        POOL RESERVES
    //////////////////////////////////////////////////////////////*/

    /// @notice Current token0 liquidity
    /// @dev Updated on every mint/burn/swap/sync
    /// @dev Packed with _reserve1 and _blockTimestampLast for gas efficiency
    uint112 internal _reserve0;

    /// @notice Current token1 liquidity
    /// @dev Updated on every mint/burn/swap/sync
    /// @dev Packed with _reserve0 and _blockTimestampLast for gas efficiency
    uint112 internal _reserve1;

    /// @notice Last reserve update time
    /// @dev Used by oracle for price tracking
    /// @dev Packed with reserves in single storage slot
    uint32 internal _blockTimestampLast;

    /*//////////////////////////////////////////////////////////////
                        PRICE TRACKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Token0 price accumulator
    /// @dev Tracks token0 price in terms of token1
    /// @dev Used for TWAP calculations by oracle
    uint256 internal _price0CumulativeLast;

    /// @notice Token1 price accumulator
    /// @dev Tracks token1 price in terms of token0
    /// @dev Used for TWAP calculations by oracle
    uint256 internal _price1CumulativeLast;

    /*//////////////////////////////////////////////////////////////
                        PROTOCOL FEES
    //////////////////////////////////////////////////////////////*/

    /// @notice Last K value
    /// @dev Used for protocol fee calculation
    /// @dev K = reserve0 * reserve1
    uint256 internal _kLast;

    /// @notice Pending token0 fees
    /// @dev Protocol fees awaiting collection
    /// @dev Retrieved via skim function
    uint256 internal _accumulatedFee0;

    /// @notice Pending token1 fees
    /// @dev Protocol fees awaiting collection
    /// @dev Retrieved via skim function
    uint256 internal _accumulatedFee1;
}
