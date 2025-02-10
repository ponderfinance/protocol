// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    FEE DISTRIBUTOR INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IFeeDistributor
/// @author taayyohh
/// @notice Interface for the protocol's fee distribution system
/// @dev Defines core events and functions for collecting and distributing protocol fees
interface IFeeDistributor {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when protocol fees are distributed to staking
    /// @param totalAmount Total amount of PONDER tokens distributed
    event FeesDistributed(uint256 totalAmount);

    /// @notice Emitted when tokens are recovered in emergency situations
    /// @dev Only callable by contract owner
    /// @param token Address of the recovered token
    /// @param to Destination address for recovered tokens
    /// @param amount Amount of tokens recovered
    event EmergencyTokenRecovered(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    /// @notice Emitted when fees are collected from trading pairs
    /// @dev Triggered after successful fee collection
    /// @param token Address of the collected token
    /// @param amount Amount of tokens collected
    event FeesCollected(
        address indexed token,
        uint256 amount
    );

    /// @notice Emitted when collected fees are converted to PONDER tokens
    /// @dev Provides input and output amounts for transparency
    /// @param token Address of the input token
    /// @param tokenAmount Amount of input tokens converted
    /// @param ponderAmount Amount of PONDER tokens received
    event FeesConverted(
        address indexed token,
        uint256 tokenAmount,
        uint256 ponderAmount
    );


    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Triggers distribution of accumulated protocol fees
    /// @dev Splits PONDER tokens between staking rewards and team wallet
    function distribute() external;

    /// @notice Converts accumulated fees from other tokens to PONDER
    /// @dev Includes slippage protection and minimum output verification
    /// @param token Address of the token to convert to PONDER
    function convertFees(address token) external;


    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns minimum amount required for operations
    /// @dev Used to prevent dust transactions
    /// @return Minimum token amount threshold
    function minimumAmount() external pure returns (uint256);
}
