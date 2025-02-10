// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/*//////////////////////////////////////////////////////////////
                    PONDER TOKEN INTERFACE
//////////////////////////////////////////////////////////////*/

/// @title IPonderToken
/// @author taayyohh
/// @notice Interface for Ponder protocol's token functionality
/// @dev Defines core token operations, events, and view functions
///      Implemented by the main token contract
interface IPonderToken {
    /*//////////////////////////////////////////////////////////////
                        CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Burns tokens from caller's balance
    /// @dev Restricted to launcher or owner
    /// @dev Permanently removes tokens from circulation
    /// @param amount Quantity of tokens to burn
    function burn(uint256 amount) external;


    /*//////////////////////////////////////////////////////////////
                        ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Updates address with minting privileges
    /// @dev Restricted to owner
    /// @param minter_ New address to receive minting rights
    function setMinter(address minter_) external;

    /// @notice Updates launcher address
    /// @dev Restricted to owner
    /// @param launcher_ New launcher address
    function setLauncher(address launcher_) external;

    /// @notice Initiates ownership transfer process
    /// @dev First step of two-step ownership transfer
    /// @param newOwner Proposed new owner address
    function transferOwnership(address newOwner) external;

    /// @notice Completes ownership transfer
    /// @dev Second step of two-step ownership transfer
    /// @dev Only callable by pending owner
    function acceptOwnership() external;

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS - STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current token minter address
    /// @return Address with minting privileges
    function minter() external view returns (address);

    /// @notice Current contract owner address
    /// @return Address with admin privileges
    function owner() external view returns (address);

    /// @notice Address in ownership transfer
    /// @return Pending owner awaiting acceptance
    function pendingOwner() external view returns (address);

    /// @notice Team allocation recipient
    /// @return Address receiving vested team tokens
    function teamReserve() external view returns (address);

    /// @notice Protocol launcher address
    /// @return Address with launcher privileges
    function launcher() external view returns (address);

    /// @notice Gets the staking contract address
    /// @return Address of protocol's staking contract
    function staking() external view returns (address);


    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS - ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Total tokens removed from circulation
    /// @return Cumulative amount of burned tokens
    function totalBurned() external view returns (uint256);

    /// @notice Contract deployment timestamp
    /// @return Block timestamp of deployment
    function deploymentTime() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS - CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum token supply cap
    /// @return Total supply limit (1B tokens)
    function maximumSupply() external pure returns (uint256);

    /// @notice Total team token allocation
    /// @return Team allocation amount (250M tokens)
    function teamAllocation() external pure returns (uint256);
}
