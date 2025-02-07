// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "./IPonderFactory.sol";
import { PonderFactoryStorage } from "./storage/PonderFactoryStorage.sol";
import { PonderFactoryTypes } from "./types/PonderFactoryTypes.sol";
import { PonderPair } from "../pair/PonderPair.sol";

/*//////////////////////////////////////////////////////////////
                        PONDER FACTORY
//////////////////////////////////////////////////////////////*/

/// @title PonderFactory
/// @author taayyohh
/// @notice Factory contract for deploying and managing Ponder trading pairs
/// @dev Implements pair creation logic, protocol configuration, and admin functions
contract PonderFactory is IPonderFactory, PonderFactoryStorage {
    using PonderFactoryTypes for *;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the factory with core protocol addresses
    /// @dev Sets up initial administrative configuration
    /// @param feeToSetter_ Address authorized to modify fee parameters
    /// @param launcher_ Initial pair deployment controller
    /// @param ponder_ Protocol governance token address
    constructor(
        address feeToSetter_,
        address launcher_,
        address ponder_
    ) {
        if (feeToSetter_ == address(0)) revert PonderFactoryTypes.ZeroAddress();
        if (ponder_ == address(0)) revert PonderFactoryTypes.ZeroAddress();

        _feeToSetter = feeToSetter_;
        _launcher = launcher_;
        _ponder = ponder_;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Retrieves current protocol fee recipient
    /// @dev Address where protocol fees are collected
    /// @return Current fee collection address
    function feeTo() external view returns (address) {
        return _feeTo;
    }

    /// @notice Retrieves current fee configuration admin
    /// @dev Address authorized to modify fee-related parameters
    /// @return Current fee setter address
    function feeToSetter() external view returns (address) {
        return _feeToSetter;
    }

    /// @notice Retrieves current pair deployment controller
    /// @dev Address authorized to deploy new trading pairs
    /// @return Current launcher address
    function launcher() external view returns (address) {
        return _launcher;
    }

    /// @notice Retrieves protocol governance token
    /// @dev Core token of the Ponder protocol
    /// @return PONDER token address
    function ponder() external view returns (address) {
        return _ponder;
    }

    /// @notice Retrieves pending launcher during timelock
    /// @dev Part of launcher update safety mechanism
    /// @return Address queued to become new launcher
    function pendingLauncher() external view returns (address) {
        return _pendingLauncher;
    }

    /// @notice Retrieves launcher update timelock expiry
    /// @dev Timestamp when launcher can be updated
    /// @return Unix timestamp of timelock expiration
    function launcherDelay() external view returns (uint256) {
        return _launcherDelay;
    }

    /// @notice Retrieves pair address for given tokens
    /// @dev Returns zero address if pair doesn't exist
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return Address of the trading pair
    function getPair(address tokenA, address tokenB) external view returns (address) {
        return _getPair[tokenA][tokenB];
    }

    /// @notice Retrieves pair address by index
    /// @dev For pair enumeration and iteration
    /// @param index Position in pairs array
    /// @return Address of the indexed pair
    function allPairs(uint256 index) external view returns (address) {
        return _allPairs[index];
    }

    /// @notice Retrieves total number of created pairs
    /// @dev Length of allPairs array
    /// @return Total count of deployed pairs
    function allPairsLength() external view returns (uint256) {
        return _allPairs.length;
    }

    /*//////////////////////////////////////////////////////////////
                            PAIR CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys new trading pair for provided tokens
    /// @dev Uses CREATE2 for deterministic pair addresses
    /// @param tokenA First token in the pair
    /// @param tokenB Second token in the pair
    /// @return pair Address of the newly created pair
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

    /*//////////////////////////////////////////////////////////////
                        ADMIN CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates protocol fee recipient
    /// @dev Restricted to feeToSetter
    /// @param newFeeTo New fee collection address
    function setFeeTo(address newFeeTo) external onlyFeeToSetter {
        if (newFeeTo == address(0)) revert PonderFactoryTypes.InvalidFeeReceiver();
        address oldFeeTo = _feeTo;
        _feeTo = newFeeTo;
        emit FeeToUpdated(oldFeeTo, newFeeTo);
    }

    /// @notice Updates fee configuration admin
    /// @dev Restricted to current feeToSetter
    /// @param newFeeToSetter New fee admin address
    function setFeeToSetter(address newFeeToSetter) external onlyFeeToSetter {
        if (newFeeToSetter == address(0)) revert PonderFactoryTypes.ZeroAddress();
        address oldFeeToSetter = _feeToSetter;

        _feeToSetter = newFeeToSetter;
        emit FeeToSetterUpdated(oldFeeToSetter, newFeeToSetter);
    }

    /// @notice Initiates launcher update process
    /// @dev Starts timelock period for launcher change
    /// @param newLauncher Proposed new launcher address
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

    /// @notice Completes launcher update after timelock
    /// @dev Can only execute after timelock expires
    function applyLauncher() external onlyFeeToSetter {
        // - Used for timelock functionality with long duration
        // - Timestamp manipulation window (900s) is negligible compared to typical timelock periods
        // - Only callable by privileged role (feeToSetter)
        // slither-disable-next-line block-timestamp
        if (block.timestamp < _launcherDelay) revert PonderFactoryTypes.TimelockNotFinished();
        if (_pendingLauncher == address(0)) revert PonderFactoryTypes.InvalidLauncher();

        address oldLauncher = _launcher;
        _launcher = _pendingLauncher;
        _pendingLauncher = address(0);
        _launcherDelay = 0;

        emit LauncherUpdated(oldLauncher, _launcher);
    }

    /// @notice Updates protocol token address
    /// @dev Restricted to feeToSetter
    /// @param newPonder New PONDER token address
    function setPonder(address newPonder) external onlyFeeToSetter {
        if (newPonder == address(0)) revert PonderFactoryTypes.ZeroAddress();

        address oldPonder = _ponder;
        _ponder = newPonder;
        emit LauncherUpdated(oldPonder, newPonder);
    }

    /*//////////////////////////////////////////////////////////////
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function access to fee setter
    /// @dev Reverts if caller is not the current fee setter
    modifier onlyFeeToSetter() {
        if (msg.sender != _feeToSetter) revert PonderFactoryTypes.Forbidden();
        _;
    }
}
