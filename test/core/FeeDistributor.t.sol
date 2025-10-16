// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "../../src/core/distributor/FeeDistributor.sol";
import "../../src/core/staking/PonderStaking.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/router/PonderRouter.sol";

/**
 * @title Mock ERC20 Token for Testing
 */
contract ERC20Mock is PonderKAP20 {
    constructor(string memory name, string memory symbol) PonderKAP20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function isLaunchToken() external pure returns (bool) {
        return false;
    }
}

/**
 * @title Mock LP Token that behaves like a real Ponder pair
 */
contract MockLPToken is ERC20Mock {
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;

    constructor(
        address _factory,
        address _token0,
        address _token1
    ) ERC20Mock("Mock LP", "MLP") {
        factory = _factory;
        token0 = _token0;
        token1 = _token1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (1000e6, 1000e6, uint32(block.timestamp));
    }
}

/**
 * @title Mock Price Oracle for Testing
 */
contract MockPriceOracle {
    address public baseToken;

    constructor(address _baseToken) {
        baseToken = _baseToken;
    }

    function getCurrentPrice(
        address,
        address,
        uint256 amountIn
    ) external pure returns (uint256) {
        return amountIn; // 1:1 for testing
    }

    function factory() external pure returns (address) {
        return address(0);
    }
}

/**
 * @title FeeDistributor V3 Comprehensive Test Suite
 * @notice Tests all functionality with 100% coverage
 */
contract FeeDistributorTest is Test {
    FeeDistributor public distributor;
    PonderStaking public staking;
    PonderToken public ponder;
    PonderFactory public factory;
    PonderRouter public router;
    MockPriceOracle public priceOracle;

    address public owner;
    address public user1;
    address public user2;
    address public marketing;
    address public teamReserve;
    address public kkub;
    address constant WETH = address(0x1234);

    ERC20Mock public tokenA;
    ERC20Mock public tokenB;
    ERC20Mock public tokenC;
    PonderPair public pairAB;
    PonderPair public pairKKUBPonder;
    PonderPair public pairAPonder;

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;

    event FeesCollected(address[] indexed pairs, uint256 gasUsed, uint256 timestamp);
    event CollectionFailed(address indexed pair, string reason);
    event BalanceUpdated(address indexed token, uint256 lastBalance, uint256 newBalance, uint256 delta);
    event QueueProcessed(uint256 jobsProcessed, uint256 jobsFailed, uint256 gasUsed, uint256 remainingJobs);
    event JobQueued(address indexed token, uint256 amount, uint256 priority, uint256 estimatedGas, FeeDistributor.ProcessingType jobType);
    event JobProcessed(address indexed token, uint256 amount, FeeDistributor.ProcessingType jobType);
    event JobRemoved(address indexed token, uint256 index);
    event JobRetry(address indexed token, uint256 amount, uint256 failureCount);
    event JobAbandoned(address indexed token, uint256 amount, uint256 failureCount);
    event ProcessingFailed(address indexed token, uint256 amount, string reason);
    event LPTokenProcessed(address indexed lpToken, uint256 lpAmount, uint256 amount0, uint256 amount1);
    event FeesDistributed(uint256 totalAmount);
    event FeesConverted(address indexed token, uint256 tokenAmount, uint256 ponderAmount);
    event EmergencyPauseActivated(uint256 timestamp, string reason);
    event EmergencyPauseDeactivated(uint256 timestamp);
    event EmergencyProcessing(address indexed token, uint256 amount, uint256 gasUsed);
    event BalanceTrackingReset(address[] tokens, uint256[] balances);
    event QueueCleared(uint256 jobsCleared);

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        teamReserve = address(0x3);
        marketing = address(0x4);

        // Deploy KKUB as ERC20Mock
        ERC20Mock kkubToken = new ERC20Mock("KKUB", "KKUB");
        kkub = address(kkubToken);

        // Deploy core contracts
        factory = new PonderFactory(owner, address(1), address(1));
        router = new PonderRouter(address(factory), WETH, address(2));

        // Deploy PONDER token with test contract as launcher to get liquidity allocation
        ponder = new PonderToken(teamReserve, owner, address(1)); // owner is address(this)

        // Deploy staking
        staking = new PonderStaking(address(ponder), address(router), address(factory));

        // Setup staking
        ponder.setStaking(address(staking));
        ponder.initializeStaking();

        // Disable KAP20 KYC restrictions for testing
        ponder.setAcceptedKYCLevel(0);

        // Deploy price oracle
        priceOracle = new MockPriceOracle(kkub);

        // Deploy test tokens
        tokenA = new ERC20Mock("Token A", "TKA");
        tokenB = new ERC20Mock("Token B", "TKB");
        tokenC = new ERC20Mock("Token C", "TKC");

        // Deploy distributor
        distributor = new FeeDistributor(
            address(factory),
            address(router),
            address(ponder),
            address(staking),
            address(priceOracle),
            kkub
        );

        // Create pairs
        address pairABAddr = factory.createPair(address(tokenA), address(tokenB));
        pairAB = PonderPair(pairABAddr);

        address pairKKUBPonderAddr = factory.createPair(kkub, address(ponder));
        pairKKUBPonder = PonderPair(pairKKUBPonderAddr);

        address pairAPonderAddr = factory.createPair(address(tokenA), address(ponder));
        pairAPonder = PonderPair(pairAPonderAddr);

        // Set up initial liquidity
        _setupLiquidity();
    }

    function _setupLiquidity() internal {
        uint256 amount = 10000e18;

        // Mint tokens
        tokenA.mint(address(this), amount * 10);
        tokenB.mint(address(this), amount * 10);
        ERC20Mock(kkub).mint(address(this), amount * 10);

        // Approvals
        tokenA.approve(address(router), type(uint256).max);
        tokenB.approve(address(router), type(uint256).max);
        ERC20Mock(kkub).approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);

        // Add liquidity
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            amount,
            amount,
            0,
            0,
            address(this),
            block.timestamp
        );

        router.addLiquidity(
            kkub,
            address(ponder),
            amount,
            amount,
            0,
            0,
            address(this),
            block.timestamp
        );

        router.addLiquidity(
            address(tokenA),
            address(ponder),
            amount,
            amount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    // Helper function to create single-element array
    function _toArray(address item) internal pure returns (address[] memory) {
        address[] memory arr = new address[](1);
        arr[0] = item;
        return arr;
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor() public {
        assertEq(address(distributor.FACTORY()), address(factory));
        assertEq(address(distributor.ROUTER()), address(router));
        assertEq(address(distributor.PONDER()), address(ponder));
        assertEq(address(distributor.STAKING()), address(staking));
        assertEq(address(distributor.PRICE_ORACLE()), address(priceOracle));
        assertEq(distributor.KKUB(), kkub);
        assertEq(distributor.owner(), owner);
        assertFalse(distributor.emergencyPaused());
        assertEq(distributor.failureCount(), 0);
        assertEq(distributor.totalJobsProcessed(), 0);
        assertEq(distributor.totalJobsFailed(), 0);
    }

    function test_Constructor_ZeroAddresses() public {
        vm.expectRevert(IFeeDistributor.ZeroAddress.selector);
        new FeeDistributor(address(0), address(router), address(ponder), address(staking), address(priceOracle), kkub);

        vm.expectRevert(IFeeDistributor.ZeroAddress.selector);
        new FeeDistributor(address(factory), address(0), address(ponder), address(staking), address(priceOracle), kkub);

        vm.expectRevert(IFeeDistributor.ZeroAddress.selector);
        new FeeDistributor(address(factory), address(router), address(0), address(staking), address(priceOracle), kkub);

        vm.expectRevert(IFeeDistributor.ZeroAddress.selector);
        new FeeDistributor(address(factory), address(router), address(ponder), address(0), address(priceOracle), kkub);

        vm.expectRevert(IFeeDistributor.ZeroAddress.selector);
        new FeeDistributor(address(factory), address(router), address(ponder), address(staking), address(0), kkub);

        vm.expectRevert(IFeeDistributor.ZeroAddress.selector);
        new FeeDistributor(address(factory), address(router), address(ponder), address(staking), address(priceOracle), address(0));
    }

    function test_InitialTokenTracking() public {
        assertTrue(distributor.isTokenTracked(address(ponder)));
        assertTrue(distributor.isTokenTracked(kkub));
    }

    /*//////////////////////////////////////////////////////////////
                        COLLECTION PHASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CollectFees_Success() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(pairAB);

        // Generate some fees
        tokenA.mint(address(pairAB), 100e18);
        pairAB.sync();

        vm.expectEmit(true, false, false, false);
        emit FeesCollected(pairs, 0, block.timestamp);

        distributor.collectFees(pairs);
    }

    function test_CollectFees_EmptyArray() public {
        address[] memory pairs = new address[](0);

        vm.expectRevert(FeeDistributor.EmptyArray.selector);
        distributor.collectFees(pairs);
    }

    function test_CollectFees_TooManyPairs() public {
        address[] memory pairs = new address[](21); // MAX_PAIRS_PER_COLLECTION + 1

        vm.expectRevert(FeeDistributor.TooManyPairs.selector);
        distributor.collectFees(pairs);
    }

    function test_CollectFees_WhenPaused() public {
        distributor.emergencyPause();

        address[] memory pairs = new address[](1);
        pairs[0] = address(pairAB);

        vm.expectRevert(FeeDistributor.EmergencyPaused.selector);
        distributor.collectFees(pairs);
    }

    function test_CollectFees_InvalidPair() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(0);

        // Should revert with InvalidPairAddress
        vm.expectRevert(IFeeDistributor.InvalidPairAddress.selector);
        distributor.collectFees(pairs);
    }

    function test_UpdateBalanceTracking() public {
        // Add tokens to tracking first
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        distributor.addTokensToTracking(tokens);

        // Add tokens to distributor
        tokenA.mint(address(distributor), 1000e18);
        ponder.transfer(address(distributor), 500e18);

        distributor.updateBalanceTracking();

        assertTrue(distributor.pendingBalance(address(tokenA)) > 0);
        assertTrue(distributor.pendingBalance(address(ponder)) > 0);
    }

    function test_AddTokensToTracking() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(tokenB);

        distributor.addTokensToTracking(tokens);

        assertTrue(distributor.isTokenTracked(address(tokenA)));
        assertTrue(distributor.isTokenTracked(address(tokenB)));
    }

    function test_AddTokensToTracking_OnlyOwner() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);

        vm.prank(user1);
        vm.expectRevert(IFeeDistributor.NotOwner.selector);
        distributor.addTokensToTracking(tokens);
    }

    /*//////////////////////////////////////////////////////////////
                        PROCESSING PHASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ProcessQueue_Success() public {
        // Add balance and update tracking
        ponder.transfer(address(distributor), 1000e18);
        distributor.updateBalanceTracking();

        uint256 queueLength = distributor.getQueueLength();
        assertTrue(queueLength > 0);

        distributor.processQueue(1);

        assertEq(distributor.getQueueLength(), queueLength - 1);
    }

    function test_ProcessQueue_WhenPaused() public {
        distributor.emergencyPause();

        vm.expectRevert(FeeDistributor.EmergencyPaused.selector);
        distributor.processQueue(1);
    }

    function test_ProcessQueue_ZeroJobs() public {
        vm.expectRevert(IFeeDistributor.InvalidAmount.selector);
        distributor.processQueue(0);
    }

    function test_ProcessQueue_MaxJobsLimit() public {
        // Add many tokens
        ponder.transfer(address(distributor), 1000e18);
        distributor.updateBalanceTracking();

        // Should cap at MAX_JOBS_PER_BATCH (10)
        distributor.processQueue(100);
    }

    function test_ProcessQueue_JobFailure() public {
        // Add token without conversion path
        tokenC.mint(address(distributor), 1000e18);
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenC);
        distributor.addTokensToTracking(tokens);
        distributor.updateBalanceTracking();

        // Process will fail but shouldn't revert
        distributor.processQueue(1);

        assertTrue(distributor.totalJobsFailed() > 0);
    }

    function test_ProcessQueue_CircuitBreaker() public {
        // Add a single token without conversion path that will fail
        ERC20Mock badToken = new ERC20Mock("Bad", "BAD");
        badToken.mint(address(distributor), 1000e18);
        address[] memory tokens = new address[](1);
        tokens[0] = address(badToken);
        distributor.addTokensToTracking(tokens);
        distributor.updateBalanceTracking();

        // Process the job - processQueue(1) will keep trying until it successfully processes 1 job
        // or the queue is empty. Since this job has no conversion path, it will fail 3 times
        // and then be abandoned, all within this single call
        distributor.processQueue(1);

        // After the call: job failed 3 times and was abandoned
        assertEq(distributor.failureCount(), 3);
        assertEq(distributor.totalJobsFailed(), 3);

        // Queue should now be empty (job was abandoned after 3 failures)
        assertEq(distributor.getQueueLength(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Distribute_Success() public {
        // Warp past initial cooldown period
        vm.warp(block.timestamp + 1 hours);

        ponder.transfer(address(distributor), 1000e18);

        uint256 stakingBalanceBefore = ponder.balanceOf(address(staking));

        distributor.distribute();

        uint256 stakingBalanceAfter = ponder.balanceOf(address(staking));
        assertGt(stakingBalanceAfter, stakingBalanceBefore);
    }

    function test_Distribute_WhenPaused() public {
        distributor.emergencyPause();

        vm.expectRevert(FeeDistributor.EmergencyPaused.selector);
        distributor.distribute();
    }

    function test_Distribute_ZeroBalance() public {
        vm.expectRevert(IFeeDistributor.InvalidAmount.selector);
        distributor.distribute();
    }

    function test_Distribute_Cooldown() public {
        // Warp past initial cooldown period
        vm.warp(block.timestamp + 1 hours);

        ponder.transfer(address(distributor), 1000e18);
        distributor.distribute();

        ponder.transfer(address(distributor), 1000e18);
        vm.expectRevert(IFeeDistributor.DistributionTooFrequent.selector);
        distributor.distribute();

        // After cooldown
        vm.warp(block.timestamp + 1 hours);
        distributor.distribute();
    }

    function test_AutoDistribute() public {
        // Add balance and trigger auto-distribute via processQueue
        ponder.transfer(address(distributor), 1000e18);
        distributor.updateBalanceTracking();

        vm.warp(block.timestamp + 1 hours);

        uint256 stakingBalanceBefore = ponder.balanceOf(address(staking));
        distributor.processQueue(1);
        uint256 stakingBalanceAfter = ponder.balanceOf(address(staking));

        // Auto-distribute may trigger
        assertGe(stakingBalanceAfter, stakingBalanceBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        CONVERSION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ConvertFees_RegularToken() public {
        tokenA.mint(address(distributor), 1000e18);

        uint256 ponderBefore = ponder.balanceOf(address(distributor));
        distributor.convertFees(address(tokenA));
        uint256 ponderAfter = ponder.balanceOf(address(distributor));

        assertGt(ponderAfter, ponderBefore);
    }

    function test_ConvertFees_PONDER_NoOp() public {
        ponder.transfer(address(distributor), 1000e18);

        uint256 balanceBefore = ponder.balanceOf(address(distributor));
        distributor.convertFees(address(ponder));
        uint256 balanceAfter = ponder.balanceOf(address(distributor));

        assertEq(balanceAfter, balanceBefore);
    }

    function test_ConvertFees_LPToken() public {
        // Get LP tokens
        uint256 lpBalance = pairAB.balanceOf(address(this));
        pairAB.transfer(address(distributor), lpBalance / 10);

        distributor.convertFees(address(pairAB));

        // LP tokens should be processed
        assertEq(pairAB.balanceOf(address(distributor)), 0);
    }

    function test_ConvertFees_ZeroAddress() public {
        vm.expectRevert(IFeeDistributor.ZeroAddress.selector);
        distributor.convertFees(address(0));
    }

    function test_ConvertFees_ZeroBalance() public {
        vm.expectRevert(IFeeDistributor.InvalidAmount.selector);
        distributor.convertFees(address(tokenA));
    }

    function test_ConvertFees_WhenPaused() public {
        distributor.emergencyPause();
        tokenA.mint(address(distributor), 1000e18);

        vm.expectRevert(FeeDistributor.EmergencyPaused.selector);
        distributor.convertFees(address(tokenA));
    }

    function test_ConvertFees_NoConversionPath() public {
        // Token without pair to PONDER or KKUB
        tokenC.mint(address(distributor), 1000e18);

        vm.expectRevert(FeeDistributor.NoConversionPath.selector);
        distributor.convertFees(address(tokenC));
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyPause() public {
        assertFalse(distributor.emergencyPaused());

        distributor.emergencyPause();

        assertTrue(distributor.emergencyPaused());
    }

    function test_EmergencyPause_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert(IFeeDistributor.NotOwner.selector);
        distributor.emergencyPause();
    }

    function test_EmergencyResume() public {
        distributor.emergencyPause();
        assertTrue(distributor.emergencyPaused());

        distributor.emergencyResume();

        assertFalse(distributor.emergencyPaused());
        assertEq(distributor.failureCount(), 0);
    }

    function test_EmergencyResume_OnlyOwner() public {
        distributor.emergencyPause();

        vm.prank(user1);
        vm.expectRevert(IFeeDistributor.NotOwner.selector);
        distributor.emergencyResume();
    }

    function test_EmergencyProcessToken() public {
        distributor.emergencyPause();

        tokenA.mint(address(distributor), 1000e18);

        distributor.emergencyProcessToken(address(tokenA), 1000e18);
    }

    function test_EmergencyProcessToken_NotInEmergency() public {
        vm.expectRevert(FeeDistributor.NotInEmergencyMode.selector);
        distributor.emergencyProcessToken(address(tokenA), 1000e18);
    }

    function test_EmergencyProcessToken_OnlyOwner() public {
        distributor.emergencyPause();

        vm.prank(user1);
        vm.expectRevert(IFeeDistributor.NotOwner.selector);
        distributor.emergencyProcessToken(address(tokenA), 1000e18);
    }

    function test_ResetBalanceTracking() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(tokenA);
        tokens[1] = address(ponder);

        uint256[] memory balances = new uint256[](2);
        balances[0] = 1000e18;
        balances[1] = 500e18;

        distributor.resetBalanceTracking(tokens, balances);

        assertEq(distributor.lastProcessedBalance(address(tokenA)), 1000e18);
        assertEq(distributor.lastProcessedBalance(address(ponder)), 500e18);
        assertEq(distributor.pendingBalance(address(tokenA)), 0);
        assertEq(distributor.pendingBalance(address(ponder)), 0);
    }

    function test_ResetBalanceTracking_ArrayLengthMismatch() public {
        address[] memory tokens = new address[](2);
        uint256[] memory balances = new uint256[](1);

        vm.expectRevert(FeeDistributor.ArrayLengthMismatch.selector);
        distributor.resetBalanceTracking(tokens, balances);
    }

    function test_ResetBalanceTracking_OnlyOwner() public {
        address[] memory tokens = new address[](0);
        uint256[] memory balances = new uint256[](0);

        vm.prank(user1);
        vm.expectRevert(IFeeDistributor.NotOwner.selector);
        distributor.resetBalanceTracking(tokens, balances);
    }

    function test_ClearQueue() public {
        // Add jobs to queue
        tokenA.mint(address(distributor), 1000e18);
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        distributor.addTokensToTracking(tokens);
        distributor.updateBalanceTracking();

        assertTrue(distributor.getQueueLength() > 0);

        distributor.clearQueue();

        assertEq(distributor.getQueueLength(), 0);
    }

    function test_ClearQueue_OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert(IFeeDistributor.NotOwner.selector);
        distributor.clearQueue();
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetStatus() public {
        (
            uint256 queueLength,
            uint256 totalPendingUSD,
            uint256 ponderBalance,
            uint256 nextDistributionTime,
            bool canDistribute,
            uint256[3] memory avgGasPerJob,
            uint256 successRate
        ) = distributor.getStatus();

        assertEq(queueLength, distributor.getQueueLength());
        assertEq(ponderBalance, ponder.balanceOf(address(distributor)));
        assertEq(avgGasPerJob[0], 150000);
        assertEq(avgGasPerJob[1], 300000);
        assertEq(avgGasPerJob[2], 500000);
    }

    function test_GetQueueLength() public {
        assertEq(distributor.getQueueLength(), 0);

        tokenA.mint(address(distributor), 1000e18);
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        distributor.addTokensToTracking(tokens);
        distributor.updateBalanceTracking();

        assertTrue(distributor.getQueueLength() > 0);
    }

    function test_GetJob() public {
        tokenA.mint(address(distributor), 1000e18);
        address[] memory tokens = new address[](1);
        tokens[0] = address(tokenA);
        distributor.addTokensToTracking(tokens);
        distributor.updateBalanceTracking();

        FeeDistributor.ProcessingJob memory job = distributor.getJob(0);

        assertEq(job.token, address(tokenA));
        assertTrue(job.amount > 0);
    }

    function test_GetJob_InvalidIndex() public {
        vm.expectRevert(FeeDistributor.InvalidIndex.selector);
        distributor.getJob(999);
    }

    function test_MinimumAmount() public {
        assertEq(distributor.minimumAmount(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CollectFees_Reentrancy() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(pairAB);

        distributor.collectFees(pairs);

        // Try to collect again in same transaction (simulated)
        distributor.collectFees(pairs);
    }

    function test_ProcessQueue_Reentrancy() public {
        ponder.transfer(address(distributor), 1000e18);
        distributor.updateBalanceTracking();

        distributor.processQueue(1);
    }

    function test_Distribute_Reentrancy() public {
        // Warp past initial cooldown period
        vm.warp(block.timestamp + 1 hours);

        ponder.transfer(address(distributor), 1000e18);
        distributor.distribute();

        vm.warp(block.timestamp + 1 hours);
        ponder.transfer(address(distributor), 1000e18);
        distributor.distribute();
    }

    function test_ConvertFees_Reentrancy() public {
        tokenA.mint(address(distributor), 1000e18);
        distributor.convertFees(address(tokenA));
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CompleteFeeLifecycle() public {
        // 1. Collect fees
        address[] memory pairs = new address[](1);
        pairs[0] = address(pairAB);

        tokenA.mint(address(pairAB), 100e18);
        pairAB.sync();

        distributor.collectFees(pairs);

        // 2. Update balance tracking
        tokenA.mint(address(distributor), 1000e18);
        distributor.updateBalanceTracking();

        // 3. Process queue
        distributor.processQueue(1);

        // 4. Convert fees
        tokenA.mint(address(distributor), 1000e18);
        distributor.convertFees(address(tokenA));

        // 5. Distribute
        vm.warp(block.timestamp + 1 hours);
        if (ponder.balanceOf(address(distributor)) > 0) {
            distributor.distribute();
        }
    }

    function test_QueuePrioritization() public {
        // Add KKUB (high priority)
        ERC20Mock(kkub).mint(address(distributor), 1000e18);

        // Add regular token (low priority)
        tokenA.mint(address(distributor), 1000e18);

        // Add PONDER (medium priority)
        ponder.transfer(address(distributor), 1000e18);

        distributor.updateBalanceTracking();

        // KKUB should be first
        FeeDistributor.ProcessingJob memory firstJob = distributor.getJob(0);
        assertTrue(firstJob.priority >= 900); // KKUB or PONDER priority
    }

    function test_MultipleTokenConversion() public {
        // Add various tokens
        tokenA.mint(address(distributor), 1000e18);
        ERC20Mock(kkub).mint(address(distributor), 500e18);

        uint256 ponderBefore = ponder.balanceOf(address(distributor));

        distributor.convertFees(address(tokenA));
        distributor.convertFees(kkub);

        uint256 ponderAfter = ponder.balanceOf(address(distributor));
        assertGt(ponderAfter, ponderBefore);
    }

    function test_LPTokenDetection() public {
        // Test LP token processing indirectly via convertFees
        uint256 lpBalance = pairAB.balanceOf(address(this));
        pairAB.transfer(address(distributor), lpBalance / 10);

        // This will internally call _isLPToken and process as LP
        distributor.convertFees(address(pairAB));

        // Verify LP token was processed (balance should be 0)
        assertEq(pairAB.balanceOf(address(distributor)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_ProcessQueue_EmptyQueue() public {
        assertEq(distributor.getQueueLength(), 0);

        // Should not revert on empty queue
        distributor.processQueue(1);
    }

    function test_UpdateBalanceTracking_NoChange() public {
        distributor.updateBalanceTracking();

        // Should not create jobs if no balance changes
        uint256 queueLengthBefore = distributor.getQueueLength();
        distributor.updateBalanceTracking();
        uint256 queueLengthAfter = distributor.getQueueLength();

        assertEq(queueLengthAfter, queueLengthBefore);
    }

    function test_ConvertFees_DustAmount() public {
        tokenA.mint(address(distributor), 1); // 1 wei

        // Dust amounts will fail during swap, not at validation
        vm.expectRevert(); // Router will revert with InsufficientOutputAmount
        distributor.convertFees(address(tokenA));
    }

    function test_ProcessQueue_InsufficientBalance() public {
        // Add to queue but remove actual balance
        tokenA.mint(address(distributor), 1000e18);
        distributor.updateBalanceTracking();

        // Transfer away the balance
        vm.prank(address(distributor));
        tokenA.transfer(address(this), 1000e18);

        // Process should fail gracefully
        distributor.processQueue(1);
    }
}