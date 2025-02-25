// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                PONDER FACTORY STORAGE
//////////////////////////////////////////////////////////////*/

/// @title PonderFactoryStorage
/// @author taayyohh
/// @notice Optimized storage layout for the Ponder Factory contract
/// @dev Reorganized for optimal packing and gas efficiency
abstract contract PonderFactoryStorage {
    /*//////////////////////////////////////////////////////////////
                         CORE ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice Address that receives protocol fees
    address internal _feeTo;

    /// @notice Address authorized to update the fee recipient
    address internal _feeToSetter;

    /// @notice Current launcher address for token deployments
    address internal _launcher;

    /// @notice Address of the PONDER token
    address internal _ponder;

    /// @notice Pending launcher address during transfer process
    address internal _pendingLauncher;

    /*//////////////////////////////////////////////////////////////
                          TIMELOCK STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Timelock duration for launcher address updates
    uint256 internal _launcherDelay;

    /*//////////////////////////////////////////////////////////////
                          PAIR TRACKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping to track deployed trading pairs
    mapping(address => mapping(address => address)) internal _getPair;

    /// @notice Array of all deployed trading pair addresses
    address[] internal _allPairs;
}
