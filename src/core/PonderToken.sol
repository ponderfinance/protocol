// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PonderERC20.sol";
import "forge-std/console.sol";

contract PonderToken is PonderERC20 {
    /// @notice Address with minting privileges for farming rewards
    address public minter;

    /// @notice Total cap on token supply
    uint256 public constant MAXIMUM_SUPPLY = 1_000_000_000e18; // 1 billion PONDER

    /// @notice Time after which minting is disabled forever (4 years in seconds)
    uint256 public constant MINTING_END = 4 * 365 days;

    /// @notice Timestamp when token was deployed
    uint256 public immutable deploymentTime;

    /// @notice Address that can set the minter
    address public owner;

    /// @notice Future owner in 2-step transfer
    address public pendingOwner;

    /// @notice Treasury/DAO address
    address public treasury;

    /// @notice Team/Reserve address
    address public teamReserve;

    /// @notice Marketing address
    address public marketing;

    /// @notice Vesting start timestamp for team allocation
    uint256 public teamVestingStart;

    /// @notice Amount of team tokens claimed
    uint256 public teamTokensClaimed;

    /// @notice Total amount for team vesting
    uint256 public constant TEAM_ALLOCATION = 150_000_000e18; // 15%

    /// @notice Vesting duration for team allocation (1 year)
    uint256 public constant VESTING_DURATION = 365 days;

    error Forbidden();
    error MintingDisabled();
    error SupplyExceeded();
    error ZeroAddress();
    error VestingNotStarted();
    error NoTokensAvailable();
    error VestingNotEnded();

    event MinterUpdated(address indexed previousMinter, address indexed newMinter);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TeamTokensClaimed(uint256 amount);

    modifier onlyOwner {
        if (msg.sender != owner) revert Forbidden();
        _;
    }

    modifier onlyMinter {
        if (msg.sender != minter) revert Forbidden();
        _;
    }

    constructor(
        address _treasury,
        address _teamReserve,
        address _marketing
    ) PonderERC20("Ponder", "PONDER") {
        if (_treasury == address(0) || _teamReserve == address(0) || _marketing == address(0)) revert ZeroAddress();

        owner = msg.sender;
        deploymentTime = block.timestamp;
        treasury = _treasury;
        teamReserve = _teamReserve;
        marketing = _marketing;
        teamVestingStart = block.timestamp;

        // Initial distributions
        // Treasury/DAO: 25% (250M)
        _mint(treasury, 250_000_000e18);

        // Initial Liquidity: 10% (100M)
        _mint(address(this), 100_000_000e18);

        // Marketing: 10% (100M)
        _mint(marketing, 100_000_000e18);

        // Note: Team allocation (15%, 150M) is vested
        // Farming allocation (40%, 400M) will be handled by MasterChef
    }

    function _calculateVestedAmount() internal view returns (uint256) {
        if (block.timestamp < teamVestingStart) return 0;

        uint256 timeElapsed = block.timestamp - teamVestingStart;
        if (timeElapsed > VESTING_DURATION) {
            timeElapsed = VESTING_DURATION; // Cap elapsed time
        }

        uint256 totalVested = (TEAM_ALLOCATION * timeElapsed) / VESTING_DURATION;

        console.log("Time elapsed:", timeElapsed);
        console.log("Total vested:", totalVested);
        console.log("Team tokens claimed:", teamTokensClaimed);

        uint256 claimable = totalVested > teamTokensClaimed ? totalVested - teamTokensClaimed : 0;
        console.log("Claimable amount:", claimable);

        return claimable;
    }

    function claimTeamTokens() external {
        if (msg.sender != teamReserve) revert Forbidden();
        if (block.timestamp < teamVestingStart) revert VestingNotStarted();

        uint256 vestedAmount = _calculateVestedAmount();
        if (vestedAmount == 0) revert NoTokensAvailable();

        console.log("Claiming vested amount:", vestedAmount);

        // Update before minting
        teamTokensClaimed += vestedAmount;
        _mint(teamReserve, vestedAmount);

        emit TeamTokensClaimed(vestedAmount);
    }


    /// @notice Mint new tokens for farming rewards, capped by maximum supply
    function mint(address to, uint256 amount) external onlyMinter {
        if (block.timestamp > deploymentTime + MINTING_END) revert MintingDisabled();
        if (totalSupply() + amount > MAXIMUM_SUPPLY) revert SupplyExceeded();
        _mint(to, amount);
    }

    /// @notice Update minting privileges
    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert ZeroAddress();
        address oldMinter = minter;
        minter = _minter;
        emit MinterUpdated(oldMinter, _minter);
    }

    /// @notice Begin ownership transfer process
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    /// @notice Complete ownership transfer process
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert Forbidden();
        address oldOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, owner);
    }
}
