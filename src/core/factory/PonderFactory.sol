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
    using PonderFactoryTypes for *;

    constructor(
        address feeToSetter_,
        address launcher_,
        address ponder_
    ) {
        _feeToSetter = feeToSetter_;
        _launcher = launcher_;
        _ponder = ponder_;
    }

    // View Functions
    function feeTo() external view returns (address) {
        return _feeTo;
    }

    function feeToSetter() external view returns (address) {
        return _feeToSetter;
    }

    function launcher() external view returns (address) {
        return _launcher;
    }

    function ponder() external view returns (address) {
        return _ponder;
    }

    function migrator() external view returns (address) {
        return _migrator;
    }

    function pendingLauncher() external view returns (address) {
        return _pendingLauncher;
    }

    function launcherDelay() external view returns (uint256) {
        return _launcherDelay;
    }

    function getPair(address tokenA, address tokenB) external view returns (address) {
        return _getPair[tokenA][tokenB];
    }

    function allPairs(uint256 index) external view returns (address) {
        return _allPairs[index];
    }

    function allPairsLength() external view returns (uint256) {
        return _allPairs.length;
    }

    // External Functions
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert PonderFactoryTypes.IdenticalAddresses();

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        if (token0 == address(0)) revert PonderFactoryTypes.ZeroAddress();
        if (_getPair[token0][token1] != address(0)) revert PonderFactoryTypes.PairExists();

        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        pair = address(new PonderPair{salt: salt}());

        PonderPair(pair).initialize(token0, token1);

        _getPair[token0][token1] = pair;
        _getPair[token1][token0] = pair;
        _allPairs.push(pair);

        emit PairCreated(token0, token1, pair, _allPairs.length);
    }

    function setFeeTo(address newFeeTo) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        if (newFeeTo == address(0)) revert PonderFactoryTypes.InvalidFeeReceiver();

        address oldFeeTo = _feeTo;
        _feeTo = newFeeTo;
        emit FeeToUpdated(oldFeeTo, newFeeTo);
    }

    function setFeeToSetter(address newFeeToSetter) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        _feeToSetter = newFeeToSetter;
    }

    function setMigrator(address newMigrator) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        _migrator = newMigrator;
    }

    function setLauncher(address newLauncher) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        if (newLauncher == address(0)) revert PonderFactoryTypes.InvalidLauncher();

        _pendingLauncher = newLauncher;
        _launcherDelay = block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK;

        emit LauncherUpdated(_launcher, newLauncher);
    }

    function applyLauncher() external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        if (block.timestamp < _launcherDelay) revert PonderFactoryTypes.TimelockNotFinished();
        if (_pendingLauncher == address(0)) revert PonderFactoryTypes.InvalidLauncher();

        address oldLauncher = _launcher;
        _launcher = _pendingLauncher;

        _pendingLauncher = address(0);
        _launcherDelay = 0;

        emit LauncherUpdated(oldLauncher, _launcher);
    }

    function setPonder(address newPonder) external {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        address oldPonder = _ponder;
        _ponder = newPonder;
        emit LauncherUpdated(oldPonder, newPonder);
    }
}
