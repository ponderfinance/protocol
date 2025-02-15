// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    FEE DISTRIBUTOR TYPES
//////////////////////////////////////////////////////////////*/

/// @title FeeDistributorTypes
/// @author taayyohh
/// @notice Type definitions and constants for the fee distribution system
/// @dev Library containing all custom errors and constants used in fee distribution
library FeeDistributorTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The denominator used for ratio calculations (100%)
    /// @dev Used as the denominator for calculating fee splits (e.g., 8000/10000 = 80%)
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Minimum amount of tokens required for operations
    /// @dev Used to prevent dust transactions and ensure economic viability
    uint256 public constant MINIMUM_AMOUNT = 1000;

    /// @notice Minimum time required between distributions
    /// @dev Rate limiting mechanism to prevent excessive distributions
    uint256 public constant DISTRIBUTION_COOLDOWN = 1 hours;

    /// @notice Maximum number of pairs that can be processed in a single distribution
    /// @dev Prevents excessive gas consumption in single transactions
    uint256 public constant MAX_PAIRS_PER_DISTRIBUTION = 10;
}
