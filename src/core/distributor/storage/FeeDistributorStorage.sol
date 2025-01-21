// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IPonderFactory } from "../../factory/IPonderFactory.sol";
import { IPonderRouter } from "../../../periphery/router/IPonderRouter.sol";
import { IPonderStaking } from "../../staking/IPonderStaking.sol";

/// @title FeeDistributorStorage
/// @notice Storage layout for the fee distribution system
abstract contract FeeDistributorStorage {
    // Immutable protocol contracts
    IPonderFactory public immutable FACTORY;
    IPonderRouter public immutable ROUTER;
    address public immutable PONDER;
    IPonderStaking public immutable STAKING;

    // Mapping for fee distribution tracking
    mapping(address => uint256) public lastPairDistribution;
    mapping(address => bool) internal processedPairs;

    // Admin addresses
    address public team;
    address public owner;
    address public pendingOwner;

    // Distribution configuration
    uint256 public stakingRatio = 8000;  // 80%
    uint256 public teamRatio = 2000;     // 20%

    // Timing tracking
    uint256 public lastDistributionTimestamp;

    /// @notice Constructor to initialize immutable variables
    /// @dev This pattern allows child contracts to initialize storage while maintaining immutability
    constructor(
        address _factory,
        address _router,
        address _ponder,
        address _staking
    ) {
        FACTORY = IPonderFactory(_factory);
        ROUTER = IPonderRouter(_router);
        PONDER = _ponder;
        STAKING = IPonderStaking(_staking);
    }
}
