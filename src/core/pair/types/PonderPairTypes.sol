// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER PAIR TYPES
//////////////////////////////////////////////////////////////*/

/// @title PonderPairTypes
/// @author taayyohh
/// @notice Core types and constants for Ponder's automated market maker
/// @dev Centralizes all type definitions, constants, and custom errors
///      Used throughout the Ponder protocol for consistency and gas optimization
library PonderPairTypes {
    /*//////////////////////////////////////////////////////////////
                        PROTOCOL CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Minimum liquidity required to initialize a pair
    /// @dev Permanently locked when first LP tokens are minted
    /// @dev Prevents first depositor from taking unfair share of fees
    uint256 internal constant MINIMUM_LIQUIDITY = 1000;

    /// @notice Base denominator for fee calculations
    /// @dev All fees are expressed as basis points (1 = 0.01%)
    /// @dev 10000 represents 100% for precision in fee math
    uint256 internal constant FEE_DENOMINATOR = 10000;

    /*//////////////////////////////////////////////////////////////
                            FEE STRUCTURE
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee allocated to liquidity providers
    /// @dev 25 basis points (0.25%) of each swap
    /// @dev Primary incentive for providing liquidity
    uint256 internal constant LP_FEE = 25;

    /// @notice Creator fee for Ponder token pairs
    /// @dev 4 basis points (0.04%) of each swap
    /// @dev Rewards pair creators for bootstrapping liquidity
    uint256 internal constant PONDER_CREATOR_FEE = 4;

    /// @notice Protocol fee for Ponder token pairs
    /// @dev 1 basis point (0.01%) of each swap
    /// @dev Sustainable revenue for protocol maintenance
    uint256 internal constant PONDER_PROTOCOL_FEE = 1;

    /// @notice Creator fee for KUB pairs
    /// @dev 1 basis point (0.01%) of each swap
    /// @dev Special rate for KUB-paired tokens
    uint256 internal constant KUB_CREATOR_FEE = 1;

    /// @notice Protocol fee for KUB pairs
    /// @dev 4 basis points (0.04%) of each swap
    /// @dev Enhanced protocol fee for KUB pairs
    uint256 internal constant KUB_PROTOCOL_FEE = 4;

    /// @notice Standard protocol fee
    /// @dev 5 basis points (0.05%) of each swap
    /// @dev Default fee for regular token pairs
    uint256 internal constant STANDARD_PROTOCOL_FEE = 5;

    /*//////////////////////////////////////////////////////////////
                        TECHNICAL CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Function selector for ERC20 transfer
    /// @dev Cached for gas optimization in transfer calls
    /// @dev Equals bytes4(keccak256("transfer(address,uint256)"))
    bytes4 internal constant SELECTOR = bytes4(keccak256(bytes("transfer(address,uint256)")));

    /*//////////////////////////////////////////////////////////////
                            CORE TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Comprehensive swap operation data
    /// @dev Encapsulates all data needed for swap execution
    /// @dev Used internally to track swap state and validate invariants
    struct SwapData {
        /// @notice Amount of token0 to output from swap
        uint256 amount0Out;
        /// @notice Amount of token1 to output from swap
        uint256 amount1Out;
        /// @notice Amount of token0 input into swap
        uint256 amount0In;
        /// @notice Amount of token1 input into swap
        uint256 amount1In;
        /// @notice Current balance of token0 in pair
        uint256 balance0;
        /// @notice Current balance of token1 in pair
        uint256 balance1;
        /// @notice Reserve of token0 before swap
        uint112 reserve0;
        /// @notice Reserve of token1 before swap
        uint112 reserve1;
    }

    /// @notice Data passed to swap callback
    /// @dev Contains all information needed by callee during swap
    struct SwapCallbackData {
        /// @notice Amount of token0 to output
        uint256 amount0Out;
        /// @notice Amount of token1 to output
        uint256 amount1Out;
        /// @notice Amount of token0 to input
        uint256 amount0In;
        /// @notice Amount of token1 to input
        uint256 amount1In;
        /// @notice Address of token0
        address token0;
        /// @notice Address of token1
        address token1;
        /// @notice Recipient of output tokens
        address to;
        /// @notice Additional data for callback
        bytes callbackData;
    }


    /// @notice Holds internal state during swap execution
    /// @dev Used to track swap progress and maintain CEI pattern
    /// @dev Separate from SwapData to maintain clear validation boundaries
    struct SwapState {
        /// @notice Current reserve of token0
        uint112 reserve0;
        /// @notice Current reserve of token1
        uint112 reserve1;
        /// @notice Current balance of token0
        uint256 balance0;
        /// @notice Current balance of token1
        uint256 balance1;
        /// @notice Amount of token0 being sold
        uint256 amount0In;
        /// @notice Amount of token1 being sold
        uint256 amount1In;
        /// @notice Whether pair includes PONDER token
        bool isPonderPair;
    }

    /// @notice Pool reserve state
    /// @dev Packed struct for gas efficient storage
    struct Reserves {
        /// @notice Current reserve of token0
        uint112 reserve0;
        /// @notice Current reserve of token1
        uint112 reserve1;
        /// @notice Timestamp of last reserve update
        uint32 blockTimestampLast;
    }
}
