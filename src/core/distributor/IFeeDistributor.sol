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

    /// @notice Emitted when protocol fees are distributed to stakeholders
    /// @dev Triggered during successful fee distribution
    /// @param totalAmount Total amount of PONDER tokens distributed
    /// @param stakingAmount Amount sent to staking rewards
    /// @param teamAmount Amount sent to team wallet
    event FeesDistributed(
        uint256 totalAmount,
        uint256 stakingAmount,
        uint256 teamAmount
    );

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

    /// @notice Emitted when fee distribution ratios are modified
    /// @dev Sum of ratios must equal BASIS_POINTS (10000)
    /// @param stakingRatio New ratio for staking rewards (in basis points)
    /// @param teamRatio New ratio for team allocation (in basis points)
    event DistributionRatiosUpdated(
        uint256 stakingRatio,
        uint256 teamRatio
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
                        CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates the ratio split for fee distribution
    /// @dev Only callable by owner. Ratios must sum to BASIS_POINTS
    /// @param _stakingRatio New percentage for staking rewards (in basis points)
    /// @param _teamRatio New percentage for team wallet (in basis points)
    function updateDistributionRatios(
        uint256 _stakingRatio,
        uint256 _teamRatio
    ) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns current fee distribution ratio configuration
    /// @dev Values are in basis points (100% = 10000)
    /// @return stakingRatio Current ratio for staking rewards
    /// @return teamRatio Current ratio for team allocation
    function getDistributionRatios() external view returns (
        uint256 stakingRatio,
        uint256 teamRatio
    );

    /// @notice Returns minimum amount required for operations
    /// @dev Used to prevent dust transactions
    /// @return Minimum token amount threshold
    function minimumAmount() external pure returns (uint256);
}
