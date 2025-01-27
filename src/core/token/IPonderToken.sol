// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IPonderToken
 * @notice Interface for the PonderToken contract
 */
interface IPonderToken {
    /**
     * @notice Calculate and claim vested team tokens
     * @dev Only callable by teamReserve address
     * @dev Emits TeamTokensClaimed event
     */
    function claimTeamTokens() external;

    /**
     * @notice Mint new tokens to specified address
     * @dev Only callable by minter before MINTING_END
     * @param to Address to receive minted tokens
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Update minter address
     * @dev Only callable by owner
     * @param minter_ New minter address
     */
    function setMinter(address minter_) external;

    /**
     * @notice Update launcher address
     * @dev Only callable by owner
     * @param launcher_ New launcher address
     */
    function setLauncher(address launcher_) external;

    /**
     * @notice Initiate ownership transfer
     * @dev First step of two-step ownership transfer
     * @param newOwner Address of proposed new owner
     */
    function transferOwnership(address newOwner) external;

    /**
     * @notice Complete ownership transfer
     * @dev Second step of two-step ownership transfer
     */
    function acceptOwnership() external;

    /**
     * @notice Burn tokens
     * @dev Only callable by launcher or owner
     * @param amount Amount of tokens to burn
     */
    function burn(uint256 amount) external;

    /**
     * @notice Get amount of tokens reserved for team
     * @return Amount of tokens still reserved for team allocation
     */
    function getReservedForTeam() external view returns (uint256);

    /**
     * @notice View current minter address
     * @return Address of current minter
     */
    function minter() external view returns (address);

    /**
     * @notice View current owner address
     * @return Address of current owner
     */
    function owner() external view returns (address);

    /**
     * @notice View pending owner address
     * @return Address of pending owner
     */
    function pendingOwner() external view returns (address);

    /**
     * @notice View team reserve address
     * @return Address of team reserve
     */
    function teamReserve() external view returns (address);

    /**
     * @notice View marketing address
     * @return Address of marketing wallet
     */
    function marketing() external view returns (address);

    /**
     * @notice View launcher address
     * @return Address of launcher contract
     */
    function launcher() external view returns (address);

    /**
     * @notice View total burned token amount
     * @return Amount of tokens burned
     */
    function totalBurned() external view returns (uint256);

    /**
     * @notice View amount of team tokens claimed
     * @return Amount of team allocation tokens claimed
     */
    function teamTokensClaimed() external view returns (uint256);

    /**
     * @notice Get immutable deployment timestamp
     * @return Timestamp when contract was deployed
     */
    function deploymentTime() external view returns (uint256);

    /**
     * @notice View team vesting start timestamp
     * @return Timestamp when team vesting started
     */
    function teamVestingStart() external view returns (uint256);

    /**
     * @notice Get maximum total supply of tokens
     * @return Maximum supply cap
     */
    function maximumSupply() external pure returns (uint256);

    /**
     * @notice Get duration after which minting is disabled
     * @return Duration in seconds
     */
    function mintingEnd() external pure returns (uint256);

    /**
     * @notice Get total allocation for team
     * @return Team allocation amount
     */
    function teamAllocation() external pure returns (uint256);

    /**
     * @notice Get vesting duration for team allocation
     * @return Duration in seconds
     */
    function vestingDuration() external pure returns (uint256);
}
