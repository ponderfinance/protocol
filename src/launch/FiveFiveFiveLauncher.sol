// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../core/PonderFactory.sol";
import "../interfaces/IPonderFactory.sol";
import "../libraries/PonderLaunchGuard.sol";
import "./LaunchToken.sol";
import "../core/PonderToken.sol";
import "../core/PonderPriceOracle.sol";

contract FiveFiveFiveLauncher {
    // Base launch information
    struct LaunchBaseInfo {
        address tokenAddress;
        string name;
        string symbol;
        string imageURI;
        bool launched;
        address creator;
        uint256 lpUnlockTime;
        uint256 launchDeadline;
        bool cancelled;
    }

    // Track all contribution amounts
    struct ContributionState {
        uint256 kubCollected;
        uint256 ponderCollected;
        uint256 ponderValueCollected;
        uint256 tokensDistributed;
    }

    // Token distribution tracking
    struct TokenAllocation {
        uint256 tokensForContributors;
        uint256 tokensForLP;
    }

    // Pool addresses and state
    struct PoolInfo {
        address memeKubPair;
        address memePonderPair;
    }

    // Main launch info struct with minimized nesting
    struct LaunchInfo {
        LaunchBaseInfo base;
        ContributionState contributions;
        TokenAllocation allocation;
        PoolInfo pools;
        mapping(address => ContributorInfo) contributors;
    }

    // Individual contributor tracking
    struct ContributorInfo {
        uint256 kubContributed;
        uint256 ponderContributed;
        uint256 ponderValue;
        uint256 tokensReceived;
    }

    // Input parameters for launch creation
    struct LaunchParams {
        string name;
        string symbol;
        string imageURI;
    }

    // Internal state for handling contributions
    struct ContributionResult {
        uint256 contribution;
        uint256 tokensToDistribute;
        uint256 refund;
    }

    // Configuration for pool creation
    struct PoolConfig {
        uint256 kubAmount;
        uint256 tokenAmount;
        uint256 ponderAmount;
    }

    // State for handling launch finalization
    struct FinalizationState {
        address tokenAddress;
        uint256 kubAmount;
        uint256 ponderAmount;
        uint256 tokenAmount;
    }

    /// @notice Custom errors
    error LaunchNotFound();
    error AlreadyLaunched();
    error InvalidPayment();
    error InvalidAmount();
    error ImageRequired();
    error InvalidTokenParams();
    error Unauthorized();
    error LPStillLocked();
    error StalePrice();
    error ExcessiveContribution();
    error InsufficientLPTokens();
    error ExcessivePonderContribution();
    error LaunchExpired();
    error LaunchCancelled();
    error NoContributionToRefund();
    error RefundFailed();

    // Constants
    uint256 public constant LAUNCH_DURATION = 7 days;
    uint256 public constant TARGET_RAISE = 5555 ether;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant LP_LOCK_PERIOD = 180 days;
    uint256 public constant MAX_PONDER_PERCENT = 2000; // 20% max PONDER contribution

    // Distribution constants
    uint256 public constant KUB_TO_MEME_KUB_LP = 6000;
    uint256 public constant KUB_TO_PONDER_KUB_LP = 2000;
    uint256 public constant KUB_TO_MEME_PONDER_LP = 2000;
    uint256 public constant PONDER_TO_MEME_PONDER = 8000;
    uint256 public constant PONDER_TO_BURN = 2000;
    uint256 public constant PRICE_STALENESS_THRESHOLD = 2 hours;

    // Token distribution percentages
    uint256 public constant CREATOR_PERCENT = 1000; // 10%
    uint256 public constant LP_PERCENT = 2000;      // 20%
    uint256 public constant CONTRIBUTOR_PERCENT = 7000; // 70%

    // Core protocol references
    IPonderFactory public immutable factory;
    IPonderRouter public immutable router;
    PonderToken public immutable ponder;
    PonderPriceOracle public immutable priceOracle;

    // State variables
    address public owner;
    address public feeCollector;
    uint256 public launchCount;
    mapping(uint256 => LaunchInfo) public launches;

    // Events
    event LaunchCreated(uint256 indexed launchId, address indexed token, address creator, string imageURI);
    event KUBContributed(uint256 indexed launchId, address contributor, uint256 amount);
    event PonderContributed(uint256 indexed launchId, address contributor, uint256 amount, uint256 kubValue);
    event TokensDistributed(uint256 indexed launchId, address indexed recipient, uint256 amount);
    event LaunchCompleted(uint256 indexed launchId, uint256 kubRaised, uint256 ponderRaised);
    event LPTokensWithdrawn(uint256 indexed launchId, address indexed creator, uint256 amount);
    event PonderBurned(uint256 indexed launchId, uint256 amount);
    event DualPoolsCreated(uint256 indexed launchId, address memeKubPair, address memePonderPair, uint256 kubLiquidity, uint256 ponderLiquidity);

    constructor(
        address _factory,
        address payable _router,
        address _feeCollector,
        address _ponder,
        address _priceOracle
    ) {
        factory = IPonderFactory(_factory);
        router = IPonderRouter(_router);
        ponder = PonderToken(_ponder);
        priceOracle = PonderPriceOracle(_priceOracle);
        feeCollector = _feeCollector;
        owner = msg.sender;
    }

    function createLaunch(
        LaunchParams calldata params
    ) external returns (uint256 launchId) {
        if(bytes(params.imageURI).length == 0) revert ImageRequired();
        _validateTokenParams(params.name, params.symbol);

        launchId = launchCount++;
        LaunchToken token = _deployToken(params);
        _initializeLaunch(launchId, address(token), params, msg.sender);

        emit LaunchCreated(launchId, address(token), msg.sender, params.imageURI);
    }

    function _deployToken(LaunchParams calldata params) internal returns (LaunchToken) {
        return new LaunchToken(
            params.name,
            params.symbol,
            address(this),
            address(factory),
            payable(address(router)),
            address(ponder)
        );
    }

    function _initializeLaunch(
        uint256 launchId,
        address tokenAddress,
        LaunchParams calldata params,
        address creator
    ) internal {
        LaunchInfo storage launch = launches[launchId];

        // Initialize base info
        launch.base.tokenAddress = tokenAddress;
        launch.base.name = params.name;
        launch.base.symbol = params.symbol;
        launch.base.imageURI = params.imageURI;
        launch.base.creator = creator;

        // Calculate token allocations
        uint256 totalSupply = LaunchToken(tokenAddress).TOTAL_SUPPLY();
        launch.allocation.tokensForContributors = (totalSupply * CONTRIBUTOR_PERCENT) / BASIS_POINTS;
        launch.allocation.tokensForLP = (totalSupply * LP_PERCENT) / BASIS_POINTS;

        // Setup creator vesting
        uint256 creatorTokens = (totalSupply * CREATOR_PERCENT) / BASIS_POINTS;
        LaunchToken(tokenAddress).setupVesting(creator, creatorTokens);

        // Add deadline
        launch.base.launchDeadline = block.timestamp + LAUNCH_DURATION;
    }

    function contributeKUB(uint256 launchId) external payable {
        LaunchInfo storage launch = launches[launchId];
        _validateLaunchState(launch);
        if(msg.value == 0) revert InvalidAmount();

        ContributionResult memory result = _calculateKubContribution(launch, msg.value);
        _processKubContribution(launchId, launch, result, msg.sender);

        if (result.refund > 0) {
            payable(msg.sender).transfer(result.refund);
        }

        _checkAndFinalizeLaunch(launchId, launch);
    }

    function _validateLaunchState(LaunchInfo storage launch) internal view {
        if (launch.base.tokenAddress == address(0)) revert LaunchNotFound();
        if (launch.base.launched) revert AlreadyLaunched();
        if (launch.base.cancelled) revert LaunchCancelled();
        if (block.timestamp > launch.base.launchDeadline) revert LaunchExpired();
    }

    function _calculateKubContribution(
        LaunchInfo storage launch,
        uint256 amount
    ) internal view returns (ContributionResult memory result) {
        uint256 remaining = TARGET_RAISE - (launch.contributions.kubCollected + launch.contributions.ponderValueCollected);
        result.contribution = amount > remaining ? remaining : amount;

        result.tokensToDistribute = (result.contribution * launch.allocation.tokensForContributors) / TARGET_RAISE;

        result.refund = amount > remaining ? amount - remaining : 0;
        return result;
    }

    function _processKubContribution(
        uint256 launchId,
        LaunchInfo storage launch,
        ContributionResult memory result,
        address contributor
    ) internal {
        // Update contribution state
        launch.contributions.kubCollected += result.contribution;
        launch.contributions.tokensDistributed += result.tokensToDistribute;

        // Update contributor info
        ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.kubContributed += result.contribution;
        contributorInfo.tokensReceived += result.tokensToDistribute;

        // Transfer tokens
        LaunchToken(launch.base.tokenAddress).transfer(contributor, result.tokensToDistribute);

        // Emit events
        emit TokensDistributed(launchId, contributor, result.tokensToDistribute);
        emit KUBContributed(launchId, contributor, result.contribution);
    }

    function contributePONDER(uint256 launchId, uint256 amount) external {
        LaunchInfo storage launch = launches[launchId];
        _validateLaunchState(launch);
        if(amount == 0) revert InvalidAmount();

        uint256 kubValue = _getPonderValue(amount);
        ContributionResult memory result = _calculatePonderContribution(launch, amount, kubValue);

        _processPonderContribution(launchId, launch, result, kubValue, amount, msg.sender);
        _checkAndFinalizeLaunch(launchId, launch);
    }

    function _calculatePonderContribution(
        LaunchInfo storage launch,
        uint256 amount,
        uint256 kubValue
    ) internal view returns (ContributionResult memory result) {
        // Calculate what total PONDER value would be after this contribution
        uint256 totalPonderValue = launch.contributions.ponderValueCollected + kubValue;

        // Check if it would exceed 20% PONDER limit
        uint256 maxPonderValue = (TARGET_RAISE * MAX_PONDER_PERCENT) / BASIS_POINTS;
        if (totalPonderValue > maxPonderValue) {
            revert ExcessivePonderContribution();
        }

        // Calculate remaining raise needed
        uint256 remaining = TARGET_RAISE - (launch.contributions.kubCollected + launch.contributions.ponderValueCollected);

        // If kubValue exceeds remaining, calculate partial amount
        if (kubValue > remaining) {
            // Calculate what portion of the PONDER contribution we'll accept
            result.contribution = remaining;
            result.tokensToDistribute = (remaining * launch.allocation.tokensForContributors) / TARGET_RAISE;

            // Calculate refund in PONDER terms
            uint256 ponderToAccept = (amount * remaining) / kubValue;
            result.refund = amount - ponderToAccept;
        } else {
            // Accept full contribution
            result.contribution = kubValue;
            result.tokensToDistribute = (kubValue * launch.allocation.tokensForContributors) / TARGET_RAISE;
            result.refund = 0;
        }

        return result;
    }

    function _processPonderContribution(
        uint256 launchId,
        LaunchInfo storage launch,
        ContributionResult memory result,
        uint256 kubValue,
        uint256 amount,
        address contributor
    ) internal {
        // Calculate actual PONDER amount to accept (total - refund)
        uint256 ponderToAccept = amount - result.refund;

        // Update contribution state
        launch.contributions.ponderCollected += ponderToAccept;
        launch.contributions.ponderValueCollected += result.contribution;  // Using adjusted kubValue
        launch.contributions.tokensDistributed += result.tokensToDistribute;

        // Update contributor info
        ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.ponderContributed += ponderToAccept;
        contributorInfo.ponderValue += result.contribution;  // Using adjusted kubValue
        contributorInfo.tokensReceived += result.tokensToDistribute;

        // Transfer accepted amount of PONDER
        ponder.transferFrom(contributor, address(this), ponderToAccept);

        // If there's a refund, don't transfer it - just leave it in contributor's wallet

        // Transfer launch tokens
        LaunchToken(launch.base.tokenAddress).transfer(contributor, result.tokensToDistribute);

        // Emit events
        emit TokensDistributed(launchId, contributor, result.tokensToDistribute);
        emit PonderContributed(launchId, contributor, ponderToAccept, result.contribution);
    }

    function claimRefund(uint256 launchId) external {
        LaunchInfo storage launch = launches[launchId];

        // Check if refund is possible
        require(
            block.timestamp > launch.base.launchDeadline || launch.base.cancelled,
            "Launch still active"
        );
        require(
            !launch.base.launched &&
            launch.contributions.kubCollected + launch.contributions.ponderValueCollected < TARGET_RAISE,
            "Launch succeeded"
        );

        ContributorInfo storage contributor = launch.contributors[msg.sender];
        if (contributor.kubContributed == 0 && contributor.ponderContributed == 0) {
            revert NoContributionToRefund();
        }

        // Process KUB refund
        uint256 kubToRefund = contributor.kubContributed;
        if (kubToRefund > 0) {
            contributor.kubContributed = 0;
            (bool success, ) = msg.sender.call{value: kubToRefund}("");
            if (!success) revert RefundFailed();
        }

        // Process PONDER refund
        uint256 ponderToRefund = contributor.ponderContributed;
        if (ponderToRefund > 0) {
            contributor.ponderContributed = 0;
            ponder.transfer(msg.sender, ponderToRefund);
        }

        // Process token return
        if (contributor.tokensReceived > 0) {
            LaunchToken token = LaunchToken(launch.base.tokenAddress);
            // First get approval
            require(
                token.allowance(msg.sender, address(this)) >= contributor.tokensReceived,
                "Token approval required for refund"
            );
            // Then transfer tokens back
            token.transferFrom(msg.sender, address(this), contributor.tokensReceived);
            contributor.tokensReceived = 0;
        }
    }

    // Add ability for creator to cancel launch
    function cancelLaunch(uint256 launchId) external {
        LaunchInfo storage launch = launches[launchId];
        if (msg.sender != launch.base.creator) revert Unauthorized();
        if (launch.base.launched) revert AlreadyLaunched();

        launch.base.cancelled = true;
    }

    function _checkAndFinalizeLaunch(uint256 launchId, LaunchInfo storage launch) internal {
        if (launch.contributions.kubCollected + launch.contributions.ponderValueCollected >= TARGET_RAISE) {
            _finalizeLaunch(launchId);
        }
    }

    function _finalizeLaunch(uint256 launchId) internal {
        LaunchInfo storage launch = launches[launchId];
        if (launch.contributions.tokensDistributed + launch.allocation.tokensForLP > LaunchToken(launch.base.tokenAddress).TOTAL_SUPPLY())
            revert InsufficientLPTokens();

        launch.base.launched = true;
        PoolConfig memory pools = _calculatePoolAmounts(launch);
        _createPools(launchId, launch, pools);
        _enableTrading(launch);

        emit LaunchCompleted(
            launchId,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    function _calculatePoolAmounts(LaunchInfo storage launch) internal view returns (PoolConfig memory pools) {
        pools.kubAmount = (launch.contributions.kubCollected * KUB_TO_MEME_KUB_LP) / BASIS_POINTS;
        pools.ponderAmount = (launch.contributions.ponderCollected * PONDER_TO_MEME_PONDER) / BASIS_POINTS;
        pools.tokenAmount = launch.allocation.tokensForLP / 2; // Split LP tokens between pairs
        return pools;
    }

    function _createPools(
        uint256 launchId,
        LaunchInfo storage launch,
        PoolConfig memory pools
    ) internal {
        // Create KUB pool
        launch.pools.memeKubPair = _createKubPool(
            launch.base.tokenAddress,
            pools.kubAmount,
            pools.tokenAmount
        );

        // Create PONDER pool if needed
        if (launch.contributions.ponderCollected > 0) {
            launch.pools.memePonderPair = _createPonderPool(
                launch.base.tokenAddress,
                pools.ponderAmount,
                pools.tokenAmount
            );
            _burnPonderTokens(launchId, launch);
        }

        emit DualPoolsCreated(
            launchId,
            launch.pools.memeKubPair,
            launch.pools.memePonderPair,
            pools.kubAmount,
            pools.ponderAmount
        );
    }

    function _burnPonderTokens(uint256 launchId, LaunchInfo storage launch) internal {
        uint256 ponderToBurn = (launch.contributions.ponderCollected * PONDER_TO_BURN) / BASIS_POINTS;
        ponder.burn(ponderToBurn);
        emit PonderBurned(launchId, ponderToBurn);
    }

    function _enableTrading(LaunchInfo storage launch) internal {
        LaunchToken token = LaunchToken(launch.base.tokenAddress);
        token.setPairs(launch.pools.memeKubPair, launch.pools.memePonderPair);
        token.enableTransfers();
        launch.base.lpUnlockTime = block.timestamp + LP_LOCK_PERIOD;
    }

    function _createKubPool(
        address tokenAddress,
        uint256 kubAmount,
        uint256 tokenAmount
    ) internal returns (address) {
        // Check if pair exists first
        address pair = factory.getPair(tokenAddress, router.WETH());
        if (pair == address(0)) {
            pair = factory.createPair(tokenAddress, router.WETH());
        }

        LaunchToken(tokenAddress).approve(address(router), tokenAmount);

        router.addLiquidityETH{value: kubAmount}(
            tokenAddress,
            tokenAmount,
            tokenAmount * 99 / 100,
            kubAmount * 99 / 100,
            address(this),
            block.timestamp + 1 hours
        );

        return pair;
    }

    function _createPonderPool(
        address tokenAddress,
        uint256 ponderAmount,
        uint256 tokenAmount
    ) internal returns (address) {
        // Check if pair exists first
        address pair = factory.getPair(tokenAddress, address(ponder));
        if (pair == address(0)) {
            pair = factory.createPair(tokenAddress, address(ponder));
        }

        LaunchToken(tokenAddress).approve(address(router), tokenAmount);
        ponder.approve(address(router), ponderAmount);

        router.addLiquidity(
            tokenAddress,
            address(ponder),
            tokenAmount,
            ponderAmount,
            tokenAmount * 99 / 100,
            ponderAmount * 99 / 100,
            address(this),
            block.timestamp + 1 hours
        );

        return pair;
    }

    function withdrawLP(uint256 launchId) external {
        LaunchInfo storage launch = launches[launchId];
        if(msg.sender != launch.base.creator) revert Unauthorized();
        if(block.timestamp < launch.base.lpUnlockTime) revert LPStillLocked();

        _withdrawPairLP(launch.pools.memeKubPair, launch.base.creator);
        _withdrawPairLP(launch.pools.memePonderPair, launch.base.creator);

        emit LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);
    }

    function _withdrawPairLP(address pair, address recipient) internal {
        if (pair == address(0)) return;
        uint256 balance = PonderERC20(pair).balanceOf(address(this));
        if (balance > 0) {
            PonderERC20(pair).transfer(recipient, balance);
        }
    }

    function _getPonderValue(uint256 amount) internal view returns (uint256) {
        address ponderKubPair = factory.getPair(address(ponder), router.WETH());
        (, , uint32 lastUpdateTime) = PonderPair(ponderKubPair).getReserves();

        if (block.timestamp - lastUpdateTime > PRICE_STALENESS_THRESHOLD) {
            revert StalePrice();
        }

        return priceOracle.getCurrentPrice(ponderKubPair, address(ponder), amount);
    }

    function _validateTokenParams(string memory name, string memory symbol) internal pure {
        bytes memory nameBytes = bytes(name);
        bytes memory symbolBytes = bytes(symbol);
        if(nameBytes.length == 0 || nameBytes.length > 32) revert InvalidTokenParams();
        if(symbolBytes.length == 0 || symbolBytes.length > 8) revert InvalidTokenParams();
    }

    // View functions with minimal stack usage
    function getContributorInfo(uint256 launchId, address contributor) external view returns (
        uint256 kubContributed,
        uint256 ponderContributed,
        uint256 ponderValue,
        uint256 tokensReceived
    ) {
        ContributorInfo storage info = launches[launchId].contributors[contributor];
        return (
            info.kubContributed,
            info.ponderContributed,
            info.ponderValue,
            info.tokensReceived
        );
    }

    function getContributionInfo(uint256 launchId) external view returns (
        uint256 kubCollected,
        uint256 ponderCollected,
        uint256 ponderValueCollected,
        uint256 totalValue
    ) {
        ContributionState storage contributions = launches[launchId].contributions;
        return (
            contributions.kubCollected,
            contributions.ponderCollected,
            contributions.ponderValueCollected,
            contributions.kubCollected + contributions.ponderValueCollected
        );
    }

    function getPoolInfo(uint256 launchId) external view returns (
        address memeKubPair,
        address memePonderPair,
        bool hasSecondaryPool
    ) {
        PoolInfo storage pools = launches[launchId].pools;
        return (
            pools.memeKubPair,
            pools.memePonderPair,
            pools.memePonderPair != address(0)
        );
    }

    function getLaunchInfo(uint256 launchId) external view returns (
        address tokenAddress,
        string memory name,
        string memory symbol,
        string memory imageURI,
        uint256 kubRaised,
        bool launched,
        uint256 lpUnlockTime
    ) {
        LaunchBaseInfo storage base = launches[launchId].base;
        ContributionState storage contributions = launches[launchId].contributions;

        return (
            base.tokenAddress,
            base.name,
            base.symbol,
            base.imageURI,
            contributions.kubCollected,
            base.launched,
            base.lpUnlockTime
        );
    }

    receive() external payable {}
}
