// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../core/oracle/PonderPriceOracle.sol";
import "../../core/token/PonderToken.sol";
import "../../periphery/router/IPonderRouter.sol";
import "../../core/factory/IPonderFactory.sol";
import {FiveFiveFiveLauncherTypes} from "../types/FiveFiveFiveLauncherTypes.sol";

/// @title FiveFiveFiveLauncherStorage
/// @author taayyohh
/// @notice Storage contract for the 555 token launch platform
/// @dev Contains all state variables and constants used by the launcher
contract FiveFiveFiveLauncherStorage is FiveFiveFiveLauncherTypes {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Duration settings
    uint256 public constant LAUNCH_DURATION = 7 days;
    uint256 public constant LP_LOCK_PERIOD = 180 days;
    uint256 public constant PRICE_STALENESS_THRESHOLD = 2 hours;

    /// @notice Target raise and contribution limits
    uint256 public constant TARGET_RAISE = 5555 ether;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_PONDER_PERCENT = 2000; // 20% max PONDER contribution

    /// @notice KUB distribution percentages in basis points
    uint256 public constant KUB_TO_MEME_KUB_LP = 6000;    // 60% to token-KUB LP
    uint256 public constant KUB_TO_PONDER_KUB_LP = 2000;  // 20% to PONDER-KUB LP
    uint256 public constant KUB_TO_MEME_PONDER_LP = 2000; // 20% to token-PONDER LP

    /// @notice PONDER distribution percentages in basis points
    uint256 public constant PONDER_TO_MEME_PONDER = 8000; // 80% to token-PONDER LP
    uint256 public constant PONDER_TO_BURN = 2000;        // 20% to burn

    /// @notice Token distribution percentages in basis points
    uint256 public constant CREATOR_PERCENT = 1000;      // 10% to creator
    uint256 public constant LP_PERCENT = 2000;           // 20% to LP
    uint256 public constant CONTRIBUTOR_PERCENT = 7000;  // 70% to contributors

    /// @notice Minimum contribution and liquidity requirements
    uint256 public constant MIN_KUB_CONTRIBUTION = 0.01 ether;   // Minimum 0.01 KUB
    uint256 public constant MIN_PONDER_CONTRIBUTION = 0.1 ether; // Minimum 0.1 PONDER
    uint256 public constant MIN_POOL_LIQUIDITY = 50 ether;      // Minimum 50 KUB worth for pool

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Protocol admin state
    address public owner;
    address public feeCollector;

    /// @notice Launch tracking state
    uint256 public launchCount;
    mapping(uint256 => LaunchInfo) public launches;

    /// @notice Token name and symbol tracking
    mapping(string => bool) public usedNames;
    mapping(string => bool) public usedSymbols;
}
