// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "../../factory/IPonderFactory.sol";
import { IPonderRouter } from "../../../periphery/router/IPonderRouter.sol";
import { IPonderStaking } from "../../staking/IPonderStaking.sol";

/*//////////////////////////////////////////////////////////////
                        FEE DISTRIBUTOR STORAGE
//////////////////////////////////////////////////////////////*/

/// @title FeeDistributorStorage
/// @author taayyohh
/// @notice Storage layout for the protocol's fee distribution system
/// @dev Abstract contract that defines the storage layout for fee distribution
abstract contract FeeDistributorStorage {
    /*//////////////////////////////////////////////////////////////
                        PROTOCOL STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The protocol's factory contract for managing pairs
    IPonderFactory public factory;

    /// @notice The protocol's router contract for swap operations
    IPonderRouter public router;

    /// @notice The address of the protocol's PONDER token
    address public ponder;

    /// @notice The protocol's staking contract for PONDER tokens
    IPonderStaking public staking;

    /*//////////////////////////////////////////////////////////////
                        DISTRIBUTION TRACKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Tracks the last distribution timestamp for each pair
    /// @dev Maps pair address to timestamp of their last fee distribution
    mapping(address => uint256) public lastPairDistribution;

    /// @notice Tracks which pairs have been processed in the current distribution cycle
    /// @dev Internal mapping to prevent double processing of pairs
    mapping(address => bool) internal processedPairs;

    /*//////////////////////////////////////////////////////////////
                        ADMIN STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the contract owner
    /// @dev Has full administrative privileges
    address public owner;

    /// @notice Address of the pending owner during ownership transfer
    /// @dev Must accept ownership to complete transfer
    address public pendingOwner;

    /*//////////////////////////////////////////////////////////////
                        TIMING STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Timestamp of the last global fee distribution
    /// @dev Used to track and manage distribution intervals
    uint256 public lastDistributionTimestamp;
}
