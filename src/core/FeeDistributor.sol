// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IFeeDistributor.sol";
import "../interfaces/IPonderFactory.sol";
import "../interfaces/IPonderPair.sol";
import "../interfaces/IPonderRouter.sol";
import "../interfaces/IPonderStaking.sol";
import "../interfaces/IERC20.sol";
import "../libraries/TransferHelper.sol";

/**
 * @title FeeDistributor
 * @notice Handles collection and distribution of protocol fees
 * @dev Collects fees from pairs, converts to PONDER, and distributes to stakeholders
 */
contract FeeDistributor is IFeeDistributor {
    /// @notice Factory contract reference
    IPonderFactory public immutable factory;

    /// @notice Router for token conversions
    IPonderRouter public immutable router;

    /// @notice PONDER token address
    address public immutable ponder;

    /// @notice xPONDER staking contract
    IPonderStaking public immutable staking;

    /// @notice Treasury address
    address public treasury;

    /// @notice Team address
    address public team;

    /// @notice Owner address
    address public owner;

    /// @notice Pending owner for 2-step transfer
    address public pendingOwner;

    /// @notice Distribution ratios in basis points (100 = 1%)
    uint256 public stakingRatio = 5000;  // 50%
    uint256 public treasuryRatio = 3000; // 30%
    uint256 public teamRatio = 2000;     // 20%

    /// @notice Minimum amount for conversion to prevent dust
    uint256 public constant MINIMUM_AMOUNT = 1000;

    /// @notice Basis points denominator
    uint256 public constant BASIS_POINTS = 10000;

    /// @notice Custom errors
    error InvalidRatio();
    error RatioSumIncorrect();
    error NotOwner();
    error NotPendingOwner();
    error ZeroAddress();
    error InvalidAmount();
    error SwapFailed();
    error TransferFailed();

    /**
     * @notice Contract constructor
     * @param _factory Factory contract address
     * @param _router Router contract address
     * @param _ponder PONDER token address
     * @param _staking xPONDER staking contract address
     * @param _treasury Treasury address
     * @param _team Team address
     */
    constructor(
        address _factory,
        address _router,
        address _ponder,
        address _staking,
        address _treasury,
        address _team
    ) {
        if (_factory == address(0) || _router == address(0) || _ponder == address(0) ||
        _staking == address(0) || _treasury == address(0) || _team == address(0)) {
            revert ZeroAddress();
        }

        factory = IPonderFactory(_factory);
        router = IPonderRouter(_router);
        ponder = _ponder;
        staking = IPonderStaking(_staking);
        treasury = _treasury;
        team = _team;
        owner = msg.sender;

        // Approve router for all conversions
        IERC20(_ponder).approve(_router, type(uint256).max);
    }

    /**
     * @notice Collects fees from a specific pair
     * @param pair Address of the pair to collect from
     */
    function collectFeesFromPair(address pair) public {
        // First sync to ensure reserves are up to date
        IPonderPair(pair).sync();

        // Get pair token addresses
        address token0 = IPonderPair(pair).token0();
        address token1 = IPonderPair(pair).token1();

        // Check balances before transfer
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // Collect fees (transfer from pair to this contract)
        IPonderPair(pair).skim(address(this));

        // Sync again after skim to ensure reserves are correct
        IPonderPair(pair).sync();

        // Calculate collected amounts
        uint256 collected0 = IERC20(token0).balanceOf(address(this)) - balance0;
        uint256 collected1 = IERC20(token1).balanceOf(address(this)) - balance1;

        if (collected0 > 0) {
            emit FeesCollected(token0, collected0);
        }
        if (collected1 > 0) {
            emit FeesCollected(token1, collected1);
        }
    }

    /**
     * @notice Converts collected fees of a specific token to PONDER
     * @param token Address of the token to convert
     */
    function convertFees(address token) external {
        if (token == ponder) return; // No need to convert PONDER

        uint256 amount = IERC20(token).balanceOf(address(this));
        if (amount < MINIMUM_AMOUNT) revert InvalidAmount();

        // Approve router if needed
        IERC20(token).approve(address(router), amount);

        // Setup path for swap
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = ponder;

        // Perform swap
        try router.swapExactTokensForTokens(
            amount,
            0, // Accept any amount of PONDER
            path,
            address(this),
            block.timestamp
        ) returns (uint256[] memory amounts) {
            emit FeesConverted(token, amount, amounts[1]);
        } catch {
            revert SwapFailed();
        }
    }

    /**
     * @notice Distributes converted fees to stakeholders
     * @dev All fees should be converted to PONDER before distribution
     */
    function distribute() external {
        uint256 totalAmount = IERC20(ponder).balanceOf(address(this));
        if (totalAmount < MINIMUM_AMOUNT) revert InvalidAmount();

        // Calculate distribution amounts
        uint256 stakingAmount = (totalAmount * stakingRatio) / BASIS_POINTS;
        uint256 treasuryAmount = (totalAmount * treasuryRatio) / BASIS_POINTS;
        uint256 teamAmount = (totalAmount * teamRatio) / BASIS_POINTS;

        // Transfer to staking contract first (triggers rebase)
        if (stakingAmount > 0) {
            if (!IERC20(ponder).transfer(address(staking), stakingAmount)) {
                revert TransferFailed();
            }
            staking.rebase();
        }

        // Transfer to treasury
        if (treasuryAmount > 0) {
            if (!IERC20(ponder).transfer(treasury, treasuryAmount)) {
                revert TransferFailed();
            }
        }

        // Transfer to team
        if (teamAmount > 0) {
            if (!IERC20(ponder).transfer(team, teamAmount)) {
                revert TransferFailed();
            }
        }

        emit FeesDistributed(totalAmount, stakingAmount, treasuryAmount, teamAmount);
    }

    /**
     * @notice Distributes fees from specific pairs
     * @param pairs Array of pair addresses to collect and distribute fees from
     */
    function distributePairFees(address[] calldata pairs) external {
        // First collect from all pairs
        for (uint256 i = 0; i < pairs.length; i++) {
            collectFeesFromPair(pairs[i]);
        }

        // Convert collected fees to PONDER
        address[] memory uniqueTokens = _getUniqueTokens(pairs);
        for (uint256 i = 0; i < uniqueTokens.length; i++) {
            if (IERC20(uniqueTokens[i]).balanceOf(address(this)) >= MINIMUM_AMOUNT) {
                this.convertFees(uniqueTokens[i]);
            }
        }

        // Distribute converted PONDER
        if (IERC20(ponder).balanceOf(address(this)) >= MINIMUM_AMOUNT) {
            this.distribute();
        }
    }

    /**
     * @notice Updates fee distribution ratios
     * @param _stakingRatio New staking ratio in basis points
     * @param _treasuryRatio New treasury ratio in basis points
     * @param _teamRatio New team ratio in basis points
     */
    function updateDistributionRatios(
        uint256 _stakingRatio,
        uint256 _treasuryRatio,
        uint256 _teamRatio
    ) external onlyOwner {
        if (_stakingRatio + _treasuryRatio + _teamRatio != BASIS_POINTS) {
            revert RatioSumIncorrect();
        }

        stakingRatio = _stakingRatio;
        treasuryRatio = _treasuryRatio;
        teamRatio = _teamRatio;

        emit DistributionRatiosUpdated(_stakingRatio, _treasuryRatio, _teamRatio);
    }

    /**
     * @notice Updates treasury address
     * @param _treasury New treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        if (_treasury == address(0)) revert ZeroAddress();
        treasury = _treasury;
    }

    /**
     * @notice Updates team address
     * @param _team New team address
     */
    function setTeam(address _team) external onlyOwner {
        if (_team == address(0)) revert ZeroAddress();
        team = _team;
    }

    /**
     * @notice Returns current distribution ratios
     */
    function getDistributionRatios() external view returns (
        uint256 _stakingRatio,
        uint256 _treasuryRatio,
        uint256 _teamRatio
    ) {
        return (stakingRatio, treasuryRatio, teamRatio);
    }

    /**
     * @notice Initiates ownership transfer
     * @param newOwner Address of new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;
    }

    /**
     * @notice Completes ownership transfer
     */
    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    /**
     * @notice Gets unique tokens from pairs for conversion
     * @param pairs Array of pair addresses
     * @return tokens Array of unique token addresses
     */
    function _getUniqueTokens(address[] calldata pairs) internal view returns (address[] memory tokens) {
        // This is a simplified version - in production you might want to use a more gas-efficient approach
        address[] memory tempTokens = new address[](pairs.length * 2);
        uint256 count = 0;

        for (uint256 i = 0; i < pairs.length; i++) {
            address token0 = IPonderPair(pairs[i]).token0();
            address token1 = IPonderPair(pairs[i]).token1();

            bool found0 = false;
            bool found1 = false;

            for (uint256 j = 0; j < count; j++) {
                if (tempTokens[j] == token0) found0 = true;
                if (tempTokens[j] == token1) found1 = true;
            }

            if (!found0 && token0 != ponder) {
                tempTokens[count++] = token0;
            }
            if (!found1 && token1 != ponder) {
                tempTokens[count++] = token1;
            }
        }

        tokens = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            tokens[i] = tempTokens[i];
        }
    }

    /// @notice Modifier for owner-only functions
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }
}
