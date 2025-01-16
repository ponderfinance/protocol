// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../core/PonderFactory.sol";
import "../interfaces/IPonderFactory.sol";
import "../libraries/PonderLaunchGuard.sol";
import "./LaunchToken.sol";
import "../core/PonderToken.sol";
import "../core/PonderPriceOracle.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract FiveFiveFiveLauncher is ReentrancyGuard  {

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
        bool isFinalizingLaunch;
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
    error LaunchNotCancellable();
    error NoContributionToRefund();
    error RefundFailed();
    error ContributionTooSmall();
    error InsufficientPoolLiquidity();
    error TokenNameExists();
    error TokenSymbolExists();
    error ContributionFailed();
    error LaunchBeingFinalized();
    error EthTransferFailed();
    error ExcessivePriceDeviation();
    error InsufficientPriceHistory();
    error PriceOutOfBounds();
    error PoolCreationFailed();
    error InsufficientLiquidity();
    error LaunchDoesNotExist();
    error LaunchDeadlinePassed();

    mapping(string => bool) public usedNames;
    mapping(string => bool) public usedSymbols;

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
    uint256 public constant MIN_POOL_LIQUIDITY = 50 ether;       // Minimum 1 KUB worth for pool creation


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
    event RefundProcessed(address indexed user, uint256 kubAmount, uint256 ponderAmount, uint256 tokenAmount);
    event LaunchCancelled(
        uint256 indexed launchId,
        address indexed creator,
        uint256 kubCollected,
        uint256 ponderCollected
    );

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

        // Mark name and symbol as used
        usedNames[params.name] = true;
        usedSymbols[params.symbol] = true;

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

    function contributeKUB(uint256 launchId) external payable nonReentrant {
        LaunchInfo storage launch = launches[launchId];

        // 1. Initial validations
        if (launch.base.launched) revert AlreadyLaunched();
        if (launch.base.cancelled) revert LaunchNotCancellable();
        if (block.timestamp > launch.base.launchDeadline) revert LaunchExpired();
        if (launch.base.isFinalizingLaunch) revert LaunchBeingFinalized();

        // 2. Calculate contribution impact BEFORE ANY STATE CHANGES
        uint256 currentTotal = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        uint256 newTotal = currentTotal + msg.value;

        // 3. Validate contribution amount
        if(msg.value < MIN_KUB_CONTRIBUTION) revert ContributionTooSmall();
        if(msg.value > TARGET_RAISE - currentTotal) revert ExcessiveContribution();

        // 4. Set finalization flag if this contribution will complete the raise
        // This MUST happen before any external calls or state changes
        if (newTotal == TARGET_RAISE) {
            launch.base.isFinalizingLaunch = true;
        } else if (newTotal > TARGET_RAISE) {
            revert ExcessiveContribution();
        }

        // 5. Calculate token distribution
        uint256 tokensToDistribute = (msg.value * launch.allocation.tokensForContributors) / TARGET_RAISE;

        // 6. Update all state BEFORE external calls
        launch.contributions.kubCollected += msg.value;
        launch.contributions.tokensDistributed += tokensToDistribute;
        launch.contributors[msg.sender].kubContributed += msg.value;
        launch.contributors[msg.sender].tokensReceived += tokensToDistribute;

        // 7. External calls AFTER all state changes
        LaunchToken(launch.base.tokenAddress).transfer(msg.sender, tokensToDistribute);

        // 8. Emit events
        emit TokensDistributed(launchId, msg.sender, tokensToDistribute);
        emit KUBContributed(launchId, msg.sender, msg.value);

        // 9. Finalize if needed (this should be last)
        if (launch.base.isFinalizingLaunch) {
            _finalizeLaunch(launchId);
        }
    }

    function _completeLaunch(uint256 launchId) private {
        LaunchInfo storage launch = launches[launchId];

        // Safety check - don't allow reentry into completion
        if (launch.base.launched) revert AlreadyLaunched();

        // Pool setup and liquidity checks
        PoolConfig memory pools = _calculatePoolAmounts(launch);
        if (pools.kubAmount < MIN_POOL_LIQUIDITY) {
            revert InsufficientPoolLiquidity();
        }

        // Get or create pairs (no external calls yet)
        address memeKubPair = _getOrCreateKubPair(launch.base.tokenAddress);
        launch.pools.memeKubPair = memeKubPair;

        // Handle PONDER pool creation if needed
        address memePonderPair = address(0);
        bool createPonderPool = false;
        if (launch.contributions.ponderCollected > 0) {
            uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount);
            if (ponderPoolValue >= MIN_POOL_LIQUIDITY) {
                memePonderPair = _getOrCreatePonderPair(launch.base.tokenAddress);
                launch.pools.memePonderPair = memePonderPair;
                createPonderPool = true;
            }
        }

        // Add liquidity (external calls happen here)
        _addKubLiquidity(launch.base.tokenAddress, pools.kubAmount, pools.tokenAmount);

        if (createPonderPool) {
            _addPonderLiquidity(launch.base.tokenAddress, pools.ponderAmount, pools.tokenAmount);
            _burnPonderTokens(launchId, launch, false);
        } else if (launch.contributions.ponderCollected > 0) {
            emit PonderPoolSkipped(launchId, pools.ponderAmount, _getPonderValue(pools.ponderAmount));
            _burnPonderTokens(launchId, launch, true);
        }

        // Enable trading
        LaunchToken(launch.base.tokenAddress).setPairs(memeKubPair, memePonderPair);
        LaunchToken(launch.base.tokenAddress).enableTransfers();

        // Update final state
        launch.base.lpUnlockTime = block.timestamp + LP_LOCK_PERIOD;
        launch.base.launched = true;
        launch.base.isFinalizingLaunch = false;

        // Final events
        emit DualPoolsCreated(
            launchId,
            memeKubPair,
            memePonderPair,
            pools.kubAmount,
            pools.ponderAmount
        );

        emit LaunchCompleted(
            launchId,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    function _validateLaunchState(LaunchInfo storage launch) internal view {
        if (launch.base.tokenAddress == address(0)) revert LaunchNotFound();
        if (launch.base.launched) revert AlreadyLaunched();
        if (launch.base.cancelled) revert LaunchNotCancellable();
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
        // Update state first
        launch.contributions.kubCollected += amount;
        uint256 tokensToDistribute = (amount * launch.allocation.tokensForContributors) / TARGET_RAISE;
        launch.contributions.tokensDistributed += tokensToDistribute;

        // Update contributor info
        ContributorInfo storage contributorInfo = launch.contributors[contributor];
        contributorInfo.kubContributed += amount;
        contributorInfo.tokensReceived += tokensToDistribute;

        // External interactions last
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

    function claimRefund(uint256 launchId) external nonReentrant {
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

        // Cache refund amounts
        uint256 kubToRefund = contributor.kubContributed;
        uint256 ponderToRefund = contributor.ponderContributed;
        uint256 tokensToReturn = contributor.tokensReceived;

        // Clear state BEFORE transfers (CEI pattern)
        contributor.kubContributed = 0;
        contributor.ponderContributed = 0;
        contributor.tokensReceived = 0;
        contributor.ponderValue = 0;

        // Get token approvals before any transfers
        if (tokensToReturn > 0) {
            LaunchToken token = LaunchToken(launch.base.tokenAddress);
            require(
                token.allowance(msg.sender, address(this)) >= tokensToReturn,
                "Token approval required for refund"
            );
            // Transfer tokens back first
            token.transferFrom(msg.sender, address(this), tokensToReturn);
        }

        // Process PONDER refund
        if (ponderToRefund > 0) {
            ponder.transfer(msg.sender, ponderToRefund);
        }

        // Process KUB refund last
        if (kubToRefund > 0) {
            (bool success, ) = msg.sender.call{value: kubToRefund}("");
            if (!success) revert RefundFailed();
        }

        // Emit refund event
        emit RefundProcessed(msg.sender, kubToRefund, ponderToRefund, tokensToReturn);
    }

    // Add ability for creator to cancel launch
    function cancelLaunch(uint256 launchId) external {
        LaunchInfo storage launch = launches[launchId];

        // Validate launch exists
        if (launch.base.tokenAddress == address(0)) revert LaunchNotCancellable();

        // Core validation checks
        if (msg.sender != launch.base.creator) revert Unauthorized();
        if (launch.base.launched) revert AlreadyLaunched();
        if (launch.base.isFinalizingLaunch) revert LaunchBeingFinalized();
        if (block.timestamp > launch.base.launchDeadline) revert LaunchDeadlinePassed();

        // Free up name and symbol for reuse
        usedNames[launch.base.name] = false;
        usedSymbols[launch.base.symbol] = false;

        // Mark as cancelled
        launch.base.cancelled = true;

        // Emit cancel event
        emit LaunchCancelled(
            launchId,
            msg.sender,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    function _checkAndFinalizeLaunch(uint256 launchId, LaunchInfo storage launch) internal {
        uint256 totalValue = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        if (totalValue == TARGET_RAISE) {
            // Set flag before proceeding with finalization
            launch.base.isFinalizingLaunch = true;
            _finalizeLaunch(launchId);
        }
    }

    function _finalizeLaunch(uint256 launchId) internal {
        LaunchInfo storage launch = launches[launchId];

        // Safety checks
        if (launch.base.launched) revert AlreadyLaunched();
        if (launch.contributions.tokensDistributed + launch.allocation.tokensForLP >
            LaunchToken(launch.base.tokenAddress).TOTAL_SUPPLY()) {
            revert InsufficientLPTokens();
        }

        // Mark as launched immediately
        launch.base.launched = true;

        // Calculate pools
        PoolConfig memory pools = _calculatePoolAmounts(launch);
        if (pools.kubAmount < MIN_POOL_LIQUIDITY) {
            revert InsufficientPoolLiquidity();
        }

        // Create pools and enable trading
        _createPools(launchId, launch, pools);
        _enableTrading(launch);

        emit LaunchCompleted(
            launchId,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );

        // Clear finalization flag at the end
        launch.base.isFinalizingLaunch = false;
    }

    function _calculatePoolAmounts(LaunchInfo storage launch) internal view returns (PoolConfig memory pools) {
        pools.kubAmount = (launch.contributions.kubCollected * KUB_TO_MEME_KUB_LP) / BASIS_POINTS;
        pools.ponderAmount = (launch.contributions.ponderCollected * PONDER_TO_MEME_PONDER) / BASIS_POINTS;
        pools.tokenAmount = launch.allocation.tokensForLP / 2; // Split LP tokens between pairs
        return pools;
    }

    function _createPools(uint256 launchId, LaunchInfo storage launch, PoolConfig memory pools) private {
        // 1. Early checks
        if (pools.kubAmount < MIN_POOL_LIQUIDITY) {
            revert InsufficientPoolLiquidity();
        }

        // 2. Get the KUB pair
        address memeKubPair = _getOrCreatePair(launch.base.tokenAddress, router.WETH());

        // 3. Check reserves BEFORE doing any transfers
        // This will catch any pre-existing liquidity that could manipulate price
        (uint112 kubR0, uint112 kubR1,) = PonderPair(memeKubPair).getReserves();
        if (kubR0 != 0 || kubR1 != 0) {
            revert PriceOutOfBounds();
        }
        launch.pools.memeKubPair = memeKubPair;

        // 4. Now check PONDER pair reserves if needed
        if (launch.contributions.ponderCollected > 0) {
            uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount);
            if (ponderPoolValue >= MIN_POOL_LIQUIDITY) {
                address memePonderPair = _getOrCreatePair(launch.base.tokenAddress, address(ponder));
                (uint112 ponderR0, uint112 ponderR1,) = PonderPair(memePonderPair).getReserves();
                if (ponderR0 != 0 || ponderR1 != 0) {
                    revert PriceOutOfBounds();
                }
                launch.pools.memePonderPair = memePonderPair;
            }
        }

        // 5. Add KUB liquidity only after all reserve checks pass
        _addKubLiquidity(
            launch.base.tokenAddress,
            pools.kubAmount,
            pools.tokenAmount
        );

        // 6. Add PONDER liquidity if needed
        if (launch.contributions.ponderCollected > 0) {
            uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount);
            if (ponderPoolValue >= MIN_POOL_LIQUIDITY) {
                _addPonderLiquidity(
                    launch.base.tokenAddress,
                    pools.ponderAmount,
                    pools.tokenAmount
                );
                _burnPonderTokens(launchId, launch, false);
            } else {
                // Burn all PONDER if no pool created
                ponder.burn(launch.contributions.ponderCollected);
                emit PonderBurned(launchId, launch.contributions.ponderCollected);
                emit PonderPoolSkipped(launchId, pools.ponderAmount, ponderPoolValue);
            }
        }

        emit DualPoolsCreated(
            launchId,
            memeKubPair,
            launch.pools.memePonderPair,
            pools.kubAmount,
            pools.ponderAmount
        );
    }

    function _getOrCreatePair(address tokenA, address tokenB) private returns (address) {
        address pair = factory.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = factory.createPair(tokenA, tokenB);
        }
        return pair;
    }

    function _getOrCreateKubPair(address tokenAddress) private returns (address) {
        address weth = router.WETH();
        address pair = factory.getPair(tokenAddress, weth);
        if (pair == address(0)) {
            pair = factory.createPair(tokenAddress, weth);
        }
        return pair;
    }

    function _getOrCreatePonderPair(address tokenAddress) private returns (address) {
        address pair = factory.getPair(tokenAddress, address(ponder));
        if (pair == address(0)) {
            pair = factory.createPair(tokenAddress, address(ponder));
        }
        return pair;
    }

    // Helper function to add KUB liquidity
    function _addKubLiquidity(
        address tokenAddress,
        uint256 kubAmount,
        uint256 tokenAmount
    ) private {
        LaunchToken(tokenAddress).approve(address(router), tokenAmount);

        router.addLiquidityETH{value: kubAmount}(
            tokenAddress,
            tokenAmount,
            tokenAmount * 995 / 1000,  // 0.5% slippage
            kubAmount * 995 / 1000,    // 0.5% slippage
            address(this),
            block.timestamp + 3 minutes // Shorter deadline
        );
    }

    function _addPonderLiquidity(
        address tokenAddress,
        uint256 ponderAmount,
        uint256 tokenAmount
    ) private {
        LaunchToken(tokenAddress).approve(address(router), tokenAmount);
        ponder.approve(address(router), ponderAmount);

        router.addLiquidity(
            tokenAddress,
            address(ponder),
            tokenAmount,
            ponderAmount,
            tokenAmount * 995 / 1000,  // 0.5% slippage
            ponderAmount * 995 / 1000, // 0.5% slippage
            address(this),
            block.timestamp + 3 minutes // Shorter deadline
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

    function _createKubPool(uint256 launchId) private {
        LaunchInfo storage launch = launches[launchId];

        // Calculate pools
        PoolConfig memory pools = _calculatePoolAmounts(launch);

        // Check minimum liquidity first
        uint256 expectedPoolLiquidity = (pools.kubAmount * KUB_TO_MEME_KUB_LP) / BASIS_POINTS;
        if (expectedPoolLiquidity < MIN_POOL_LIQUIDITY) {
            revert InsufficientPoolLiquidity();
        }

        // Get or create pair and verify no existing manipulated state
        address memeKubPair = factory.getPair(launch.base.tokenAddress, router.WETH());
        if (memeKubPair == address(0)) {
            memeKubPair = factory.createPair(launch.base.tokenAddress, router.WETH());
        }
        launch.pools.memeKubPair = memeKubPair;

        // Check existing reserves
        (uint112 r0, uint112 r1,) = PonderPair(memeKubPair).getReserves();
        if (r0 != 0 || r1 != 0) {
            revert PriceOutOfBounds();
        }

        // Approve exact amount
        LaunchToken(launch.base.tokenAddress).approve(address(router), pools.tokenAmount);

        // Add liquidity
        router.addLiquidityETH{value: pools.kubAmount}(
            launch.base.tokenAddress,
            pools.tokenAmount,
            pools.tokenAmount * 995 / 1000,  // 0.5% max slippage
            pools.kubAmount * 995 / 1000,    // 0.5% max slippage
            address(this),
            block.timestamp + 3 minutes
        );

        // Final validation
        (uint112 reserve0, uint112 reserve1,) = PonderPair(memeKubPair).getReserves();
        uint256 actualLiquidity = PonderERC20(memeKubPair).totalSupply();

        // Verify minimum liquidity
        if (actualLiquidity < MIN_POOL_LIQUIDITY) {
            revert InsufficientLiquidity();
        }

        // Verify price bounds
        uint256 expectedPrice = (pools.kubAmount * 1e18) / pools.tokenAmount;
        uint256 actualPrice = uint256(reserve1) * 1e18 / uint256(reserve0);

        uint256 minPrice = (expectedPrice * 995) / 1000;
        uint256 maxPrice = (expectedPrice * 1005) / 1000;

        if (actualPrice < minPrice || actualPrice > maxPrice) {
            revert PriceOutOfBounds();
        }
    }

    function _setupLaunch(uint256 launchId) private {
        LaunchInfo storage launch = launches[launchId];

        LaunchToken(launch.base.tokenAddress).setPairs(
            launch.pools.memeKubPair,
            launch.pools.memePonderPair
        );
        LaunchToken(launch.base.tokenAddress).enableTransfers();

        emit DualPoolsCreated(
            launchId,
            launch.pools.memeKubPair,
            launch.pools.memePonderPair,
            (launch.contributions.kubCollected * KUB_TO_MEME_KUB_LP) / BASIS_POINTS,
            0  // No PONDER liquidity in this case
        );
    }

    function _clearLaunchFlags(uint256 launchId) private {
        LaunchInfo storage launch = launches[launchId];
        launch.base.lpUnlockTime = block.timestamp + LP_LOCK_PERIOD;
        launch.base.launched = true;  // Set launched only after everything is done
        launch.base.isFinalizingLaunch = false;  // Clear finalization flag last

        emit LaunchCompleted(
            launchId,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    function _createPonderPool(
        address tokenAddress,
        uint256 ponderAmount,
        uint256 tokenAmount
    ) internal returns (address) {
        // Check minimum liquidity value first
        uint256 ponderValue = _getPonderValue(ponderAmount);
        if (ponderValue < MIN_POOL_LIQUIDITY) {
            revert InsufficientPoolLiquidity();
        }

        // Get or create pair
        address pair = factory.getPair(tokenAddress, address(ponder));
        if (pair == address(0)) {
            pair = factory.createPair(tokenAddress, address(ponder));
        }

        // Check existing reserves
        (uint112 r0, uint112 r1,) = PonderPair(pair).getReserves();
        if (r0 != 0 || r1 != 0) {
            revert PriceOutOfBounds();
        }

        // Approve tokens with exact amounts
        LaunchToken(tokenAddress).approve(address(router), tokenAmount);
        ponder.approve(address(router), ponderAmount);

        // Add liquidity with reasonable slippage
        router.addLiquidity(
            tokenAddress,
            address(ponder),
            tokenAmount,
            ponderAmount,
            tokenAmount * 995 / 1000,  // 0.5% slippage
            ponderAmount * 995 / 1000, // 0.5% slippage
            address(this),
            block.timestamp + 3 minutes
        );

        // Verify minimum liquidity was created
        uint256 liquidity = PonderERC20(pair).totalSupply();
        if (liquidity < MIN_POOL_LIQUIDITY) {
            revert InsufficientLiquidity();
        }

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

        // First check if price is stale
        if (block.timestamp - lastUpdateTime > PRICE_STALENESS_THRESHOLD) {
            revert StalePrice();
        }

        // Get spot price for contribution value
        uint256 spotPrice = priceOracle.getCurrentPrice(
            ponderKubPair,
            address(ponder),
            amount
        );

        // Get TWAP price for manipulation check
        uint256 twapPrice = priceOracle.consult(
            ponderKubPair,
            address(ponder),
            amount,
            1 hours // 1 hour TWAP period
        );

        // If TWAP is 0 or very low, we don't have enough price history
        if (twapPrice == 0) {
            revert InsufficientPriceHistory();
        }

        // Check for excessive deviation between TWAP and spot price
        uint256 maxDeviation = (twapPrice * 110) / 100; // 10% max deviation
        uint256 minDeviation = (twapPrice * 90) / 100;  // 10% min deviation

        if (spotPrice > maxDeviation || spotPrice < minDeviation) {
            revert ExcessivePriceDeviation();
        }

        // Return spot price for actual contribution calculation
        return spotPrice;
    }

    function _validateTokenParams(string memory name, string memory symbol) internal view {
        bytes memory nameBytes = bytes(name);
        bytes memory symbolBytes = bytes(symbol);

        // Existing checks
        if(nameBytes.length == 0 || nameBytes.length > 32) revert InvalidTokenParams();
        if(symbolBytes.length == 0 || symbolBytes.length > 8) revert InvalidTokenParams();

        // New checks
        if(usedNames[name]) revert TokenNameExists();
        if(usedSymbols[symbol]) revert TokenSymbolExists();

        // Validate characters (basic sanitization)
        for(uint i = 0; i < nameBytes.length; i++) {
            // Only allow alphanumeric and basic punctuation
            bytes1 char = nameBytes[i];
            if(!(
                (char >= 0x30 && char <= 0x39) || // 0-9
                (char >= 0x41 && char <= 0x5A) || // A-Z
                (char >= 0x61 && char <= 0x7A) || // a-z
                char == 0x20 || // space
                char == 0x2D || // -
                char == 0x5F    // _
            )) revert InvalidTokenParams();
        }

        // Similar validation for symbol
        for(uint i = 0; i < symbolBytes.length; i++) {
            bytes1 char = symbolBytes[i];
            if(!(
                (char >= 0x30 && char <= 0x39) ||
                (char >= 0x41 && char <= 0x5A) ||
                (char >= 0x61 && char <= 0x7A)
            )) revert InvalidTokenParams();
        }
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

    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        if (!success) revert EthTransferFailed();
    }

    receive() external payable {}
}
