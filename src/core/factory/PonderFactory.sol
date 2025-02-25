// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "./IPonderFactory.sol";
import { PonderFactoryStorage } from "./storage/PonderFactoryStorage.sol";
import { PonderFactoryTypes } from "./types/PonderFactoryTypes.sol";
import { PonderPair } from "../pair/PonderPair.sol";
import { PonderFactoryLib } from "./libraries/PonderFactoryLib.sol";

/// @title PonderFactory
/// @author taayyohh
/// @notice Factory contract for creating and managing Ponder trading pairs
/// @dev Implements core functionality for pair creation and protocol configuration
contract PonderFactory is IPonderFactory, PonderFactoryStorage {
    using PonderFactoryLib for address;

    /// @notice Initializes the factory with essential protocol addresses
    /// @param feeToSetter_ Address authorized to update fee recipient
    /// @param launcher_ Address authorized for specialized deployments
    /// @param ponder_ Address of the PONDER token
    constructor(
        address feeToSetter_,
        address launcher_,
        address ponder_
    ) {
        PonderFactoryLib.validateAddress(feeToSetter_);
        PonderFactoryLib.validateAddress(ponder_);

        _feeToSetter = feeToSetter_;
        _launcher = launcher_;
        _ponder = ponder_;
    }

    /// @notice Returns current protocol fee recipient
    /// @return Address receiving protocol fees
    function feeTo() external view returns (address) {
        return _feeTo;
    }

    /// @notice Returns current fee management admin
    /// @return Address with fee configuration permissions
    function feeToSetter() external view returns (address) {
        return _feeToSetter;
    }

    /// @notice Returns current protocol launcher
    /// @return Address of the launcher contract
    function launcher() external view returns (address) {
        return _launcher;
    }

    /// @notice Returns protocol governance token
    /// @return Address of the PONDER token contract
    function ponder() external view returns (address) {
        return _ponder;
    }

    /// @notice Returns pending launcher update if in process
    /// @return Address of the pending launcher
    function pendingLauncher() external view returns (address) {
        return _pendingLauncher;
    }

    /// @notice Retrieves pair address for given tokens
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return Address of the pair contract
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return _getPair[tokenA][tokenB];
    }

    /// @notice Gets pair address by index
    /// @param index Position in the allPairs array
    /// @return Address of the indexed pair
    function allPairs(uint256 index) external view returns (address) {
        return _allPairs[index];
    }

    /// @notice Returns total number of created pairs
    /// @return Total count of deployed pairs
    function allPairsLength() external view returns (uint256) {
        return _allPairs.length;
    }

    /// @notice Creates new trading pair for provided tokens
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Address of the created pair contract
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

    /// @notice Updates protocol fee recipient
    /// @param newFeeTo New fee collection address
    function setFeeTo(address newFeeTo) external {
        // Access control
        PonderFactoryLib.verifyAccess(msg.sender, _feeToSetter);
        PonderFactoryLib.validateFeeTo(newFeeTo);

        address oldFeeTo = _feeTo;
        _feeTo = newFeeTo;
        emit FeeToUpdated(oldFeeTo, newFeeTo);
    }

    /// @notice Updates fee management admin
    /// @param newFeeToSetter New fee admin address
    function setFeeToSetter(address newFeeToSetter) external {
        // Access control
        PonderFactoryLib.verifyAccess(msg.sender, _feeToSetter);
        PonderFactoryLib.validateAddress(newFeeToSetter);

        address oldFeeToSetter = _feeToSetter;
        _feeToSetter = newFeeToSetter;
        emit FeeToSetterUpdated(oldFeeToSetter, newFeeToSetter);
    }

    /// @notice Initiates launcher update process
    /// @param newLauncher Proposed new launcher address
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

    /// @notice Completes launcher update after timelock
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
