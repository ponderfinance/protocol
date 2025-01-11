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
    error ContributionTooSmall();
    error InsufficientPoolLiquidity();


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

    uint256 public constant MIN_KUB_CONTRIBUTION = 0.01 ether;  // Minimum 0.01 KUB
    uint256 public constant MIN_PONDER_CONTRIBUTION = 0.1 ether; // Minimum 0.1 PONDER
    uint256 public constant MIN_POOL_LIQUIDITY = 1 ether;       // Minimum 1 KUB worth for pool creation


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
    event PonderPoolSkipped(uint256 indexed launchId, uint256 ponderAmount, uint256 ponderValueInKub);

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

        uint256 remaining = TARGET_RAISE - (launch.contributions.kubCollected + launch.contributions.ponderValueCollected);
        if(msg.value > remaining) revert ExcessiveContribution();
        if(msg.value < MIN_KUB_CONTRIBUTION) revert ContributionTooSmall();

        _processKubContribution(launchId, launch, msg.value, msg.sender);
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

        // Only check minimum contribution, not pool liquidity
        if (result.contribution < MIN_KUB_CONTRIBUTION) {
            revert ContributionTooSmall();
        }

        result.tokensToDistribute = (result.contribution * launch.allocation.tokensForContributors) / TARGET_RAISE;
        result.refund = amount > remaining ? amount - remaining : 0;
        return result;
    }

    function _processKubContribution(
        uint256 launchId,
        LaunchInfo storage launch,
        uint256 amount,
        address contributor
    ) internal {
        // Update contribution state
        launch.contributions.kubCollected += amount;
        uint256 tokensToDistribute = (amount * launch.allocation.tokensForContributors) / TARGET_RAISE;
        launch.contributions.tokensDistributed += tokensToDistribute;

        // Update contributor info
        ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.kubContributed += amount;
        contributorInfo.tokensReceived += tokensToDistribute;

        // Transfer tokens
        LaunchToken(launch.base.tokenAddress).transfer(contributor, tokensToDistribute);

        // Emit events
        emit TokensDistributed(launchId, contributor, tokensToDistribute);
        emit KUBContributed(launchId, contributor, amount);
    }

    function contributePONDER(uint256 launchId, uint256 amount) external {
        LaunchInfo storage launch = launches[launchId];
        _validateLaunchState(launch);
        if(amount < MIN_PONDER_CONTRIBUTION) revert ContributionTooSmall();

        uint256 kubValue = _getPonderValue(amount);

        // Check against 20% PONDER cap
        uint256 totalPonderValue = launch.contributions.ponderValueCollected + kubValue;
        if (totalPonderValue > (TARGET_RAISE * MAX_PONDER_PERCENT) / BASIS_POINTS) {
            revert ExcessivePonderContribution();
        }

        // Check against remaining needed
        uint256 remaining = TARGET_RAISE - (launch.contributions.kubCollected + launch.contributions.ponderValueCollected);
        if (kubValue > remaining) revert ExcessiveContribution();

        uint256 tokensToDistribute = (kubValue * launch.allocation.tokensForContributors) / TARGET_RAISE;

        // Transfer exact amount needed
        ponder.transferFrom(msg.sender, address(this), amount);

        // Update state
        launch.contributions.ponderCollected += amount;
        launch.contributions.ponderValueCollected += kubValue;
        launch.contributions.tokensDistributed += tokensToDistribute;

        // Update contributor info
        ContributorInfo storage contributorInfo = launch.contributors[msg.sender];
        contributorInfo.ponderContributed += amount;
        contributorInfo.ponderValue += kubValue;
        contributorInfo.tokensReceived += tokensToDistribute;

        // Transfer tokens and emit events
        LaunchToken(launch.base.tokenAddress).transfer(msg.sender, tokensToDistribute);
        emit TokensDistributed(launchId, msg.sender, tokensToDistribute);
        emit PonderContributed(launchId, msg.sender, amount, kubValue);

        _checkAndFinalizeLaunch(launchId, launch);
    }

    function _calculatePonderContribution(
        LaunchInfo storage launch,
        uint256 amount,
        uint256 kubValue
    ) internal view returns (ContributionResult memory result) {
        // First check if this would exceed the 20% PONDER limit
        uint256 totalPonderValue = launch.contributions.ponderValueCollected + kubValue;
        uint256 maxPonderValue = (TARGET_RAISE * MAX_PONDER_PERCENT) / BASIS_POINTS;
        if (totalPonderValue > maxPonderValue) {
            revert ExcessivePonderContribution();
        }

        // Calculate remaining raise needed in KUB terms
        uint256 remaining = TARGET_RAISE - (launch.contributions.kubCollected + launch.contributions.ponderValueCollected);

        // If kubValue exceeds remaining, calculate partial amount
        if (kubValue > remaining) {
            // Calculate in KUB terms first
            result.contribution = remaining;
            result.tokensToDistribute = (remaining * launch.allocation.tokensForContributors) / TARGET_RAISE;

            // Convert remaining from KUB to PONDER amount
            result.refund = amount - (amount * remaining / kubValue);
        } else {
            result.contribution = kubValue;
            result.tokensToDistribute = (kubValue * launch.allocation.tokensForContributors) / TARGET_RAISE;
            result.refund = 0;
        }

        // Verify minimum contribution
        if (amount - result.refund < MIN_PONDER_CONTRIBUTION) {
            revert ContributionTooSmall();
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
        uint256 ponderToAccept = amount - result.refund;

        // Transfer exact amount needed first
        ponder.transferFrom(contributor, address(this), ponderToAccept);

        // Update state after transfer
        launch.contributions.ponderCollected += ponderToAccept;
        launch.contributions.ponderValueCollected += result.contribution;
        launch.contributions.tokensDistributed += result.tokensToDistribute;

        // Update contributor info
        ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.ponderContributed += ponderToAccept;
        contributorInfo.ponderValue += result.contribution;
        contributorInfo.tokensReceived += result.tokensToDistribute;

        // Distribute tokens and emit events
        LaunchToken(launch.base.tokenAddress).transfer(contributor, result.tokensToDistribute);
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
        uint256 totalValue = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        if (totalValue >= TARGET_RAISE) {
            _finalizeLaunch(launchId);
        }
    }

    function _finalizeLaunch(uint256 launchId) internal {
        LaunchInfo storage launch = launches[launchId];
        if (launch.contributions.tokensDistributed + launch.allocation.tokensForLP > LaunchToken(launch.base.tokenAddress).TOTAL_SUPPLY())
            revert InsufficientLPTokens();

        launch.base.launched = true;
        PoolConfig memory pools = _calculatePoolAmounts(launch);

        // First check KUB pool amount meets minimum
        if (pools.kubAmount < MIN_POOL_LIQUIDITY) {
            revert InsufficientPoolLiquidity();
        }

        // Create KUB pool first
        launch.pools.memeKubPair = _createKubPool(
            launch.base.tokenAddress,
            pools.kubAmount,
            pools.tokenAmount
        );

        // Handle PONDER if any was contributed
        if (launch.contributions.ponderCollected > 0) {
            uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount);

            if (ponderPoolValue >= MIN_POOL_LIQUIDITY) {
                // If enough value, create pool and burn standard percentage
                launch.pools.memePonderPair = _createPonderPool(
                    launch.base.tokenAddress,
                    pools.ponderAmount,
                    pools.tokenAmount
                );
                _burnPonderTokens(launchId, launch, false);
            } else {
                // If insufficient value, burn all PONDER and skip pool creation
                emit PonderPoolSkipped(launchId, pools.ponderAmount, ponderPoolValue);
                _burnPonderTokens(launchId, launch, true);
            }
        }

        _enableTrading(launch);

        emit LaunchCompleted(
            launchId,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );

        emit DualPoolsCreated(
            launchId,
            launch.pools.memeKubPair,
            launch.pools.memePonderPair,
            pools.kubAmount,
            pools.ponderAmount
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
        // First check KUB pool amount meets minimum
        if (pools.kubAmount < MIN_POOL_LIQUIDITY) {
            revert InsufficientPoolLiquidity();
        }

        // Create KUB pool
        launch.pools.memeKubPair = _createKubPool(
            launch.base.tokenAddress,
            pools.kubAmount,
            pools.tokenAmount
        );

        // Handle PONDER if any was contributed
        if (launch.contributions.ponderCollected > 0) {
            // Calculate PONDER pool value in KUB terms
            uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount);

            if (ponderPoolValue >= MIN_POOL_LIQUIDITY) {
                // If enough value, create pool
                launch.pools.memePonderPair = _createPonderPool(
                    launch.base.tokenAddress,
                    pools.ponderAmount,
                    pools.tokenAmount
                );
                // Burn standard percentage
                _burnPonderTokens(launchId, launch, false);
            } else {
                // If insufficient value, burn all PONDER and skip pool
                emit PonderPoolSkipped(launchId, pools.ponderAmount, ponderPoolValue);
                _burnPonderTokens(launchId, launch, true);
            }
        }

        emit DualPoolsCreated(
            launchId,
            launch.pools.memeKubPair,
            launch.pools.memePonderPair,
            pools.kubAmount,
            pools.ponderAmount
        );
    }

    function _burnPonderTokens(uint256 launchId, LaunchInfo storage launch, bool burnAll) internal {
        uint256 ponderToBurn;
        if (burnAll) {
            // Burn all PONDER that was collected
            ponderToBurn = launch.contributions.ponderCollected;
        } else {
            // Burn standard percentage for pool creation
            ponderToBurn = (launch.contributions.ponderCollected * PONDER_TO_BURN) / BASIS_POINTS;
        }

        if (ponderToBurn > 0) {
            ponder.burn(ponderToBurn);
            emit PonderBurned(launchId, ponderToBurn);
        }
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

        // At this point, we only have the exact KUB amount we need in the contract
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

    function getMinimumRequirements() external pure returns (
        uint256 minKub,
        uint256 minPonder,
        uint256 minPoolLiquidity
    ) {
        return (MIN_KUB_CONTRIBUTION, MIN_PONDER_CONTRIBUTION, MIN_POOL_LIQUIDITY);
    }

    function getRemainingToRaise(uint256 launchId) external view returns (
        uint256 remainingTotal,
        uint256 remainingPonderValue
    ) {
        LaunchInfo storage launch = launches[launchId];
        uint256 total = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        uint256 remaining = total >= TARGET_RAISE ? 0 : TARGET_RAISE - total;

        uint256 maxPonderValue = (TARGET_RAISE * MAX_PONDER_PERCENT) / BASIS_POINTS;
        uint256 currentPonderValue = launch.contributions.ponderValueCollected;
        uint256 remainingPonder = currentPonderValue >= maxPonderValue ?
            0 : maxPonderValue - currentPonderValue;

        // Return minimum of overall remaining and remaining PONDER capacity
        return (remaining, remainingPonder < remaining ? remainingPonder : remaining);
    }

    receive() external payable {}
}
