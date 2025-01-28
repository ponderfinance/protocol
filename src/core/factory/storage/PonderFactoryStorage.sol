// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title PonderFactoryStorage
 * @notice Storage layout for the Ponder Factory contract
 * @dev Contains all state variables used in the factory implementation
 */
abstract contract PonderFactoryStorage {
    // State Variables
    address internal _feeTo;
    address internal _feeToSetter;
    address internal _launcher;
    address internal _ponder;
    address internal _pendingLauncher;
    uint256 internal _launcherDelay;

    // Mappings
    mapping(address => mapping(address => address)) internal _getPair;
    address[] internal _allPairs;
}
