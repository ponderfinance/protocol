// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
    /**
     * @notice Initializes the factory with required addresses
     * @param feeToSetter_ Address authorized to set fee collection address
     * @param launcher_ Address of the launcher contract
     * @param ponder_ Address of the PONDER token
     */
    constructor(
        address feeToSetter_,
        address launcher_,
        address ponder_
    ) {
        _feeToSetter = feeToSetter_;
        _launcher = launcher_;
        _ponder = ponder_;
    }

    /// @inheritdoc IPonderFactory
    function feeTo() external view returns (address) {
        return _feeTo;
    }

    /// @inheritdoc IPonderFactory
    function feeToSetter() external view returns (address) {
        return _feeToSetter;
    }

    /// @inheritdoc IPonderFactory
    function launcher() external view returns (address) {
        return _launcher;
    }

    /// @inheritdoc IPonderFactory
    function ponder() external view returns (address) {
        return _ponder;
    }

    /// @inheritdoc IPonderFactory
    function migrator() external view returns (address) {
        return _migrator;
    }

    /// @inheritdoc IPonderFactory
    function pendingLauncher() external view returns (address) {
        return _pendingLauncher;
    }

    /// @inheritdoc IPonderFactory
    function launcherDelay() external view returns (uint256) {
        return _launcherDelay;
    }

    /// @inheritdoc IPonderFactory
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return _getPair[tokenA][tokenB];
    }

    /// @inheritdoc IPonderFactory
    function allPairs(uint256 index) external view returns (address) {
        return _allPairs[index];
    }

    /// @inheritdoc IPonderFactory
    function allPairsLength() external view returns (uint256) {
        return _allPairs.length;
    }

    /// @inheritdoc IPonderFactory
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert PonderFactoryTypes.IdenticalAddresses();

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        if (token0 == address(0)) revert PonderFactoryTypes.ZeroAddress();
        if (_getPair[token0][token1] != address(0)) revert PonderFactoryTypes.PairExists();

        bytes memory bytecode = type(PonderPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        // solhint-disable-next-line no-inline-assembly
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        PonderPair(pair).initialize(token0, token1);

        _getPair[token0][token1] = pair;
        _getPair[token1][token0] = pair;
        _allPairs.push(pair);

        emit PairCreated(token0, token1, pair, _allPairs.length);
    }

    /// @inheritdoc IPonderFactory
    function setFeeTo(address newFeeTo) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        if (newFeeTo == address(0)) revert PonderFactoryTypes.InvalidFeeReceiver();

        address oldFeeTo = _feeTo;
        _feeTo = newFeeTo;
        emit FeeToUpdated(oldFeeTo, newFeeTo);
    }

    /// @inheritdoc IPonderFactory
    function setFeeToSetter(address newFeeToSetter) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        _feeToSetter = newFeeToSetter;
    }

    /// @inheritdoc IPonderFactory
    function setMigrator(address newMigrator) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        _migrator = newMigrator;
    }

    /// @inheritdoc IPonderFactory
    function setLauncher(address newLauncher) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        if (newLauncher == address(0)) revert PonderFactoryTypes.InvalidLauncher();

        _pendingLauncher = newLauncher;
        _launcherDelay = block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK;

        emit LauncherUpdated(_launcher, newLauncher);
    }

    /// @inheritdoc IPonderFactory
    function applyLauncher() external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        if (block.timestamp < _launcherDelay) revert PonderFactoryTypes.TimelockNotFinished();
        if (_pendingLauncher == address(0)) revert PonderFactoryTypes.InvalidLauncher();

        address oldLauncher = _launcher;
        _launcher = _pendingLauncher;

        // Reset pending state
        _pendingLauncher = address(0);
        _launcherDelay = 0;

        emit LauncherUpdated(oldLauncher, _launcher);
    }

    /// @inheritdoc IPonderFactory
    function setPonder(address newPonder) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        address oldPonder = _ponder;
        _ponder = newPonder;
        emit LauncherUpdated(oldPonder, newPonder);
    }
}
