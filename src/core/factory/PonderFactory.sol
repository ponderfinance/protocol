// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { IPonderFactory } from "./IPonderFactory.sol";
import { PonderFactoryStorage } from "./storage/PonderFactoryStorage.sol";
import { PonderFactoryTypes } from "./types/PonderFactoryTypes.sol";
import { PonderPair } from "../pair/PonderPair.sol";

/**
 * @title PonderFactory
 * @notice Factory contract for creating and managing Ponder trading pairs
 * @dev Handles pair creation, fee settings, and protocol admin functions
 */
contract PonderFactory is IPonderFactory, PonderFactoryStorage {
    using PonderFactoryTypes for *;

    /**
     * @notice Initializes the factory with administrative addresses
     * @param feeToSetter_ Address allowed to change fee related parameters
     * @param launcher_ Initial launcher address
     * @param ponder_ Initial Ponder token address
     */
    constructor(
        address feeToSetter_,
        address launcher_,
        address ponder_
    ) {
        if (feeToSetter_ == address(0)) revert PonderFactoryTypes.ZeroAddress();
        if (launcher_ == address(0)) revert PonderFactoryTypes.ZeroAddress();
        if (ponder_ == address(0)) revert PonderFactoryTypes.ZeroAddress();

        _feeToSetter = feeToSetter_;
        _launcher = launcher_;
        _ponder = ponder_;
    }

    /**
     * @notice Returns the address that receives protocol fees
     * @return Address of the fee receiver
     */
    function feeTo() external view returns (address) {
        return _feeTo;
    }

    /**
     * @notice Returns the address that can modify fee settings
     * @return Address of the fee setter
     */
    function feeToSetter() external view returns (address) {
        return _feeToSetter;
    }

    /**
     * @notice Returns the current launcher address
     * @return Address of the launcher
     */
    function launcher() external view returns (address) {
        return _launcher;
    }

    /**
     * @notice Returns the Ponder token address
     * @return Address of the Ponder token
     */
    function ponder() external view returns (address) {
        return _ponder;
    }

    /**
     * @notice Returns the migrator contract address
     * @return Address of the migrator
     */
    function migrator() external view returns (address) {
        return _migrator;
    }

    /**
     * @notice Returns the pending launcher address
     * @return Address of the pending launcher
     */
    function pendingLauncher() external view returns (address) {
        return _pendingLauncher;
    }

    /**
     * @notice Returns the timestamp when launcher change can be applied
     * @return Timestamp of launcher delay
     */
    function launcherDelay() external view returns (uint256) {
        return _launcherDelay;
    }

    /**
     * @notice Returns the address of the pair for given token addresses
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return Address of the pair
     */
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return _getPair[tokenA][tokenB];
    }

    /**
     * @notice Returns the address of a pair by its index
     * @param index Index in the allPairs array
     * @return Address of the pair
     */
    function allPairs(uint256 index) external view returns (address) {
        return _allPairs[index];
    }

    /**
     * @notice Returns the total number of pairs created
     * @return Number of pairs created
     */
    function allPairsLength() external view returns (uint256) {
        return _allPairs.length;
    }

    /**
     * @notice Modifier to restrict function access to fee setter
     */
    modifier onlyFeeToSetter() {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        _;
    }

    /**
     * @notice Creates a new pair for two tokens
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pair Address of the created pair
     */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        // Checks
        if (tokenA == tokenB) revert PonderFactoryTypes.IdenticalAddresses();
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        if (token0 == address(0)) revert PonderFactoryTypes.ZeroAddress();
        if (_getPair[token0][token1] != address(0)) revert PonderFactoryTypes.PairExists();

        // Effects
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new PonderPair{salt: salt}());
        _getPair[token0][token1] = pair;
        _getPair[token1][token0] = pair;
        _allPairs.push(pair);

        // Interactions
        PonderPair(pair).initialize(token0, token1);

        emit PairCreated(token0, token1, pair, _allPairs.length);
    }

    /**
     * @notice Sets the fee receiving address
     * @param newFeeTo New fee receiver address
     */
    function setFeeTo(address newFeeTo) external onlyFeeToSetter {
        if (newFeeTo == address(0)) revert PonderFactoryTypes.InvalidFeeReceiver();
        address oldFeeTo = _feeTo;
        _feeTo = newFeeTo;
        emit FeeToUpdated(oldFeeTo, newFeeTo);
    }

    /**
     * @notice Changes the fee setter address
     * @param newFeeToSetter New fee setter address
     */
    function setFeeToSetter(address newFeeToSetter) external onlyFeeToSetter {
        if (newFeeToSetter == address(0)) revert PonderFactoryTypes.ZeroAddress();
        _feeToSetter = newFeeToSetter;
    }

    /**
     * @notice Sets the migrator contract address
     * @param newMigrator New migrator address
     */
    function setMigrator(address newMigrator) external onlyFeeToSetter {
        if (newMigrator == address(0)) revert PonderFactoryTypes.ZeroAddress();
        _migrator = newMigrator;
    }

    /**
     * @notice Initiates or completes launcher address change
     * @param newLauncher New launcher address
     */
    function setLauncher(address newLauncher) external onlyFeeToSetter {
        if (newLauncher == address(0)) revert PonderFactoryTypes.InvalidLauncher();

        if (_launcher == address(0)) {
            _launcher = newLauncher;
            emit LauncherUpdated(address(0), newLauncher);
        } else {
            _pendingLauncher = newLauncher;
            _launcherDelay = block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK;
            emit LauncherUpdated(_launcher, newLauncher);
        }
    }

    /**
     * @notice Applies pending launcher change after timelock
     */
    function applyLauncher() external onlyFeeToSetter {
        if (block.timestamp < _launcherDelay) revert PonderFactoryTypes.TimelockNotFinished();
        if (_pendingLauncher == address(0)) revert PonderFactoryTypes.InvalidLauncher();

        address oldLauncher = _launcher;
        _launcher = _pendingLauncher;
        _pendingLauncher = address(0);
        _launcherDelay = 0;

        emit LauncherUpdated(oldLauncher, _launcher);
    }

    /**
     * @notice Updates the Ponder token address
     * @param newPonder New Ponder token address
     */
    function setPonder(address newPonder) external onlyFeeToSetter {
        if (newPonder == address(0)) revert PonderFactoryTypes.ZeroAddress();

        address oldPonder = _ponder;
        _ponder = newPonder;
        emit LauncherUpdated(oldPonder, newPonder);
    }
}
