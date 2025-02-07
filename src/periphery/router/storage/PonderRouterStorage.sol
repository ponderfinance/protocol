// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    ROUTER STORAGE LAYOUT
//////////////////////////////////////////////////////////////*/

/// @title PonderRouterStorage
/// @author taayyohh
/// @notice Storage layout contract for the Ponder Router
/// @dev Abstract base contract defining router storage slots
///      Uses storage gap pattern for upgradeable contracts
///      Separates storage concerns from implementation logic
abstract contract PonderRouterStorage {
    /*//////////////////////////////////////////////////////////////
                        STORAGE GAP
    //////////////////////////////////////////////////////////////*/

    /// @notice Gap for future storage variables
    /// @dev Reserved storage slots for future upgrades
    /// @dev 50 slots reserved to prevent storage collision
    /// @dev Must be private to prevent child contract access
    /// @dev Must be placed last to maintain upgrade safety
    uint256[50] private __gap;
}
