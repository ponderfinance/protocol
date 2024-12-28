// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IFeeDistributor
 * @notice Interface for the FeeDistributor contract that handles protocol fee distribution
 */
interface IFeeDistributor {
    /// @notice Emitted when fees are distributed
    event FeesDistributed(
        uint256 totalAmount,
        uint256 stakingAmount,
        uint256 treasuryAmount,
        uint256 teamAmount
    );

    /// @notice Emitted when fees are collected from pairs
    event FeesCollected(address indexed token, uint256 amount);

    /// @notice Emitted when collected fees are converted to PONDER
    event FeesConverted(
        address indexed token,
        uint256 tokenAmount,
        uint256 ponderAmount
    );

    /// @notice Emitted when distribution ratios are updated
    event DistributionRatiosUpdated(
        uint256 stakingRatio,
        uint256 treasuryRatio,
        uint256 teamRatio
    );

    /// @notice Distributes collected fees to stakeholders
    function distribute() external;

    /// @notice Converts collected fees to PONDER
    /// @param token Address of the token to convert
    function convertFees(address token) external;

    /// @notice Updates fee distribution ratios
    /// @param _stakingRatio Percentage for xPONDER stakers (in basis points)
    /// @param _treasuryRatio Percentage for treasury (in basis points)
    /// @param _teamRatio Percentage for team (in basis points)
    function updateDistributionRatios(
        uint256 _stakingRatio,
        uint256 _treasuryRatio,
        uint256 _teamRatio
    ) external;

    /// @notice Returns current distribution ratios
    function getDistributionRatios() external view returns (
        uint256 stakingRatio,
        uint256 treasuryRatio,
        uint256 teamRatio
    );
}
