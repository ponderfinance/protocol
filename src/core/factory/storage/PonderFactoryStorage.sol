// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title PonderFactoryStorage
 * @notice Storage layout for the Ponder Factory contract
 * @dev Contains all state variables used in the factory implementation
 */
abstract contract PonderFactoryStorage {
    /**
     * @notice Address that receives protocol fees
     * @dev Must be set by feeToSetter and cannot be zero address
     */
    address internal _feeTo;

    /**
     * @notice Address authorized to update fee collection settings
     * @dev Has authority to change feeTo, migrator, and launcher addresses
     */
    address internal _feeToSetter;

    /**
     * @notice Address of the migrator contract
     * @dev Used for potential future migrations of liquidity
     */
    address internal _migrator;

    /**
     * @notice Address of the launcher contract
     * @dev Core contract for launching new features and tokens
     */
    address internal _launcher;

    /**
     * @notice Address of the PONDER token
     * @dev The protocol's governance token
     */
    address internal _ponder;

    /**
     * @notice Address of the pending launcher during timelock period
     * @dev Reset to zero address after launcher update is applied
     */
    address internal _pendingLauncher;

    /**
     * @notice Timestamp when pending launcher can be applied
     * @dev Must be waited for before applyLauncher can be called
     */
    uint256 internal _launcherDelay;

    /**
     * @notice Maps token pairs to their corresponding pair contract
     * @dev tokenA => tokenB => pair address
     */
    mapping(address => mapping(address => address)) internal _getPair;

    /**
     * @notice Array of all pair addresses created by the factory
     * @dev Used for enumeration and tracking of all pairs
     */
    address[] internal _allPairs;
}
