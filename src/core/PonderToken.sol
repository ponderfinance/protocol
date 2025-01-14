// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./PonderERC20.sol";

contract PonderToken is PonderERC20 {
    ///  @notice  555 Launcher address
    address public launcher;

    /// @notice Track total burned PONDER
    uint256 public totalBurned;

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

    /// @notice Team/Reserve address
    address public teamReserve;

    uint256 private immutable teamVestingEnd;

    // Track unvested team allocation
    uint256 private reservedForTeam;


    /// @notice Marketing address
    address public marketing;

    /// @notice Vesting start timestamp for team allocation
    uint256 public teamVestingStart;

    /// @notice Amount of team tokens claimed
    uint256 public teamTokensClaimed;

    /// @notice Total amount for team vesting
    uint256 public constant TEAM_ALLOCATION = 250_000_000e18; // 25%

    /// @notice Vesting duration for team allocation (1 year)
    uint256 public constant VESTING_DURATION = 365 days;

    error Forbidden();
    error MintingDisabled();
    error SupplyExceeded();
    error ZeroAddress();
    error VestingNotStarted();
    error NoTokensAvailable();
    error VestingNotEnded();
    error OnlyLauncherOrOwner();

    event MinterUpdated(address indexed previousMinter, address indexed newMinter);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TeamTokensClaimed(uint256 amount);
    event LauncherUpdated(address indexed oldLauncher, address indexed newLauncher);
    // @notice burn function that only launcher can call
    event TokensBurned(address indexed burner, uint256 amount);


    modifier onlyOwner {
        if (msg.sender != owner) revert Forbidden();
        _;
    }

    modifier onlyMinter {
        if (msg.sender != minter) revert Forbidden();
        _;
    }

    constructor(
        address _teamReserve,
        address _marketing,
        address _launcher
    ) PonderERC20("Koi", "KOI") {
        if (_teamReserve == address(0) || _marketing == address(0)) revert ZeroAddress();

        launcher = _launcher;
        owner = msg.sender;
        deploymentTime = block.timestamp;
        teamReserve = _teamReserve;
        marketing = _marketing;
        teamVestingStart = block.timestamp;
        teamVestingEnd = block.timestamp + VESTING_DURATION;

        // Initialize reserved amount for team
        reservedForTeam = TEAM_ALLOCATION;

        // Initial distributions
        _mint(owner, 200_000_000e18);
        _mint(marketing, 150_000_000e18);
    }

    function _calculateVestedAmount() internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - teamVestingStart;
        if (timeElapsed > VESTING_DURATION) {
            timeElapsed = VESTING_DURATION;
        }

        uint256 totalVested = (TEAM_ALLOCATION * timeElapsed) / VESTING_DURATION;
        return totalVested > teamTokensClaimed ? totalVested - teamTokensClaimed : 0;
    }

    function claimTeamTokens() external {
        if (msg.sender != teamReserve) revert Forbidden();

        // First check vesting start
        if (block.timestamp < teamVestingStart) revert VestingNotStarted();

        // Then calculate amount
        uint256 vestedAmount = _calculateVestedAmount();

        // Check for zero amount last
        if (vestedAmount == 0) revert NoTokensAvailable();

        // Update state
        reservedForTeam -= vestedAmount;
        teamTokensClaimed += vestedAmount;

        _mint(teamReserve, vestedAmount);

        emit TeamTokensClaimed(vestedAmount);
    }



    /// @notice Mint new tokens for farming rewards, capped by maximum supply
    function mint(address to, uint256 amount) external onlyMinter {
        if (block.timestamp > deploymentTime + MINTING_END) revert MintingDisabled();

        // Check max supply including reserved but unclaimed team tokens
        if (totalSupply() + amount + reservedForTeam > MAXIMUM_SUPPLY) revert SupplyExceeded();

        _mint(to, amount);
    }

    /// @notice Update minting privileges
    function setMinter(address _minter) external onlyOwner {
        if (_minter == address(0)) revert ZeroAddress();
        address oldMinter = minter;
        minter = _minter;
        emit MinterUpdated(oldMinter, _minter);
    }

    /// @notice Update launcher address - can only be called by owner
    /// @param _launcher New launcher address
    function setLauncher(address _launcher) external onlyOwner {
        if (_launcher == address(0)) revert ZeroAddress();
        address oldLauncher = launcher;
        launcher = _launcher;
        emit LauncherUpdated(oldLauncher, _launcher);
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

    function burn(uint256 amount) external {
        // Check caller is either launcher or owner
        if (msg.sender != launcher && msg.sender != owner) revert Forbidden();

        // Check minimum burn amount to prevent dust attacks
        if (amount < 1000) revert("Amount too small");

        // Check maximum burn per transaction (e.g. 1% of total supply)
        if (amount > totalSupply() / 100) revert("Exceeds max burn amount");

        // Balance check (already in _burn but good to be explicit)
        require(balanceOf(msg.sender) >= amount, "ERC20: burn amount exceeds balance");

        // Perform burn
        _burn(msg.sender, amount);

        // Update total burned tracking
        totalBurned += amount;

        // Emit burn event
        emit TokensBurned(msg.sender, amount);
    }

    function getReservedForTeam() external view returns (uint256) {
        return reservedForTeam;
    }
}
