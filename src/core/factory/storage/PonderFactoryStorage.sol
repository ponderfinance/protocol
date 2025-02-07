// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER FACTORY STORAGE
//////////////////////////////////////////////////////////////*/

/// @title PonderFactoryStorage
/// @author taayyohh
/// @notice Storage layout for the Ponder Factory contract
/// @dev Abstract contract defining storage layout for factory implementation
///      All state variables are internal to allow implementation flexibility
abstract contract PonderFactoryStorage {
    /*//////////////////////////////////////////////////////////////
                        FEE CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Address that receives protocol fees
    /// @dev Fees are collected from trading pairs and sent to this address
    address internal _feeTo;

    /// @notice Address authorized to update the fee recipient
    /// @dev Has permission to modify _feeTo address
    address internal _feeToSetter;

    /*//////////////////////////////////////////////////////////////
                        LAUNCHER CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Current launcher address for token deployments
    /// @dev Authorized to deploy new trading pairs
    address internal _launcher;

    /// @notice Address of the PONDER token
    /// @dev Core protocol token used for fees and governance
    address internal _ponder;

    /// @notice Pending launcher address during transfer process
    /// @dev Part of timelock mechanism for launcher updates
    address internal _pendingLauncher;

    /// @notice Timelock duration for launcher address updates
    /// @dev Minimum time required between launcher update initiation and execution
    uint256 internal _launcherDelay;

    /*//////////////////////////////////////////////////////////////
                            PAIR TRACKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping to track deployed trading pairs
    /// @dev Maps token0 => token1 => pair address
    mapping(address => mapping(address => address)) internal _getPair;

    /// @notice Array of all deployed trading pair addresses
    /// @dev Used for pair enumeration and tracking
    address[] internal _allPairs;
}
