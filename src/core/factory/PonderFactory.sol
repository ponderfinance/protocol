// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "./IPonderFactory.sol";
import { PonderFactoryStorage } from "./storage/PonderFactoryStorage.sol";
import { PonderFactoryTypes } from "./types/PonderFactoryTypes.sol";
import { PonderPair } from "../pair/PonderPair.sol";
import { PonderFactoryLib } from "./libraries/PonderFactoryLib.sol";

contract PonderFactory is IPonderFactory, PonderFactoryStorage {
    using PonderFactoryLib for address;

    constructor(
        address feeToSetter_,
        address launcher_,
        address ponder_
    ) {
        // Validate core addresses
        PonderFactoryLib.validateAddress(feeToSetter_);
        PonderFactoryLib.validateAddress(ponder_);

        _feeToSetter = feeToSetter_;
        _launcher = launcher_;
        _ponder = ponder_;
    }

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

    function pendingLauncher() external view returns (address) {
        return _pendingLauncher;
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

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        if (tokenA == tokenB) revert IPonderFactory.IdenticalAddresses();

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        PonderFactoryLib.validateAddress(token0);
        if (_getPair[token0][token1] != address(0)) revert IPonderFactory.PairExists();

        // Create and initialize new pair
        pair = address(new PonderPair{salt: keccak256(abi.encodePacked(token0, token1))}());
        _getPair[token0][token1] = pair;
        _getPair[token1][token0] = pair;
        _allPairs.push(pair);

        PonderPair(pair).initialize(token0, token1);
        emit PairCreated(token0, token1, pair, _allPairs.length);
    }

    function setFeeTo(address newFeeTo) external {
        // Access control
        PonderFactoryLib.verifyAccess(msg.sender, _feeToSetter);
        PonderFactoryLib.validateFeeTo(newFeeTo);

        address oldFeeTo = _feeTo;
        _feeTo = newFeeTo;
        emit FeeToUpdated(oldFeeTo, newFeeTo);
    }

    function setFeeToSetter(address newFeeToSetter) external {
        // Access control
        PonderFactoryLib.verifyAccess(msg.sender, _feeToSetter);
        PonderFactoryLib.validateAddress(newFeeToSetter);

        address oldFeeToSetter = _feeToSetter;
        _feeToSetter = newFeeToSetter;
        emit FeeToSetterUpdated(oldFeeToSetter, newFeeToSetter);
    }

    function setLauncher(address newLauncher) external {
        // Access control
        PonderFactoryLib.verifyAccess(msg.sender, _feeToSetter);
        PonderFactoryLib.validateLauncher(newLauncher);

        if (_launcher == address(0)) {
            _launcher = newLauncher;
            emit LauncherUpdated(address(0), newLauncher);
        } else {
            _pendingLauncher = newLauncher;
            _launcherDelay = block.timestamp + PonderFactoryTypes.LAUNCHER_TIMELOCK;
            emit LauncherUpdated(_launcher, newLauncher);
        }
    }

    function applyLauncher() external {
        // Access control
        PonderFactoryLib.verifyAccess(msg.sender, _feeToSetter);

        if (block.timestamp < _launcherDelay) revert IPonderFactory.TimeLocked();
        PonderFactoryLib.validateLauncher(_pendingLauncher);

        address oldLauncher = _launcher;
        _launcher = _pendingLauncher;
        _pendingLauncher = address(0);
        _launcherDelay = 0;

        emit LauncherUpdated(oldLauncher, _launcher);
    }
}
