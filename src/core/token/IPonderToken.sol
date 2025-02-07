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

    /// @notice Claims vested team tokens
    /// @dev Only callable by teamReserve address
    /// @dev Linear vesting over VESTING_DURATION
    /// @dev Amount determined by vesting schedule
    function claimTeamTokens() external;

    /// @notice Mints new tokens to specified recipient
    /// @dev Restricted to minter role before MINTING_END
    /// @dev Cannot exceed MAXIMUM_SUPPLY
    /// @param to Recipient of minted tokens
    /// @param amount Quantity of tokens to mint
    function mint(address to, uint256 amount) external;

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

    /// @notice Retrieves remaining team allocation
    /// @dev Decreases as team tokens are claimed
    /// @return Amount of tokens reserved for team
    function getReservedForTeam() external view returns (uint256);

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

    /// @notice Marketing allocation recipient
    /// @return Address for marketing operations
    function marketing() external view returns (address);

    /// @notice Protocol launcher address
    /// @return Address with launcher privileges
    function launcher() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS - ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Total tokens removed from circulation
    /// @return Cumulative amount of burned tokens
    function totalBurned() external view returns (uint256);

    /// @notice Vested team tokens distributed
    /// @return Amount of claimed team allocation
    function teamTokensClaimed() external view returns (uint256);

    /// @notice Contract deployment timestamp
    /// @return Block timestamp of deployment
    function deploymentTime() external view returns (uint256);

    /// @notice Team vesting schedule start
    /// @return Timestamp when vesting began
    function teamVestingStart() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS - CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum token supply cap
    /// @return Total supply limit (1B tokens)
    function maximumSupply() external pure returns (uint256);

    /// @notice Minting period duration
    /// @return Time until minting disabled (4 years)
    function mintingEnd() external pure returns (uint256);

    /// @notice Total team token allocation
    /// @return Team allocation amount (250M tokens)
    function teamAllocation() external pure returns (uint256);

    /// @notice Team vesting schedule length
    /// @return Vesting duration (1 year)
    function vestingDuration() external pure returns (uint256);
}
