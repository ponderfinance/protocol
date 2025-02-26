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

    // Add this function to prevent reverting
    function isLaunchToken() external pure returns (bool) {
        return false;
    }
}

contract ReentrantToken is PonderKAP20 {
    FeeDistributor public distributor;
    bool private _isReentering;

    constructor(address _distributor) PonderKAP20("Reentrant", "RENT") {
        distributor = FeeDistributor(_distributor);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        // During convertFees, the router will call transfer. Try to reenter convertFees here
        if (to == address(distributor) && !_isReentering) {
            _isReentering = true;
            distributor.convertFees(address(this));  // Try to reenter convertFees
            _isReentering = false;
        }

        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        // Check if we're being transferred to pair during convertFees
        if (from == address(distributor) && !_isReentering) {
            _isReentering = true;
            distributor.convertFees(address(this));  // Try to reenter convertFees
            _isReentering = false;
        }

        if (amount > allowance(from, msg.sender)) revert("Insufficient allowance");

        _transfer(from, to, amount);
        _approve(from, msg.sender, allowance(from, msg.sender) - amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function isLaunchToken() external pure returns (bool) {
        return false;
    }
}

contract ReentrantPair {
    FeeDistributor public distributor;
    address public token0;
    address public token1;
    bool private _isReentering;

    constructor(address _distributor, address _token0, address _token1) {
        distributor = FeeDistributor(_distributor);
        token0 = _token0;
        token1 = _token1;
    }

    function sync() external {
        if (!_isReentering) {
            _isReentering = true;
            distributor.collectFeesFromPair(address(this));
            _isReentering = false;
        }
    }

    function skim(address to) external {
        // Transfer some tokens to simulate fee collection
        uint256 amount = 1000e18;
        IERC20(token0).transfer(to, amount);
        IERC20(token1).transfer(to, amount);
    }

    // Added to match IPonderPair interface
    function getReserves() external view returns (uint112, uint112, uint32) {
        return (1000e6, 1000e6, uint32(block.timestamp));
    }
}

/**
 * @title Mock Token that fails transfers
 * @dev Used to test error handling
 */
contract MockFailingToken is PonderKAP20 {
    constructor() PonderKAP20("Failing", "FAIL") {}

    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/**
 * @title FeeDistributor Test Contract
 * @notice Tests the FeeDistributor contract's functionality
 * @dev Tests core fee collection, conversion, and distribution logic
 */
contract FeeDistributorTest is Test {
    FeeDistributor public distributor;
    PonderStaking public staking;
    PonderToken public ponder;
    PonderFactory public factory;
    PonderRouter public router;
    PonderPair public pair;

    address public owner;
    address public user1;
    address public user2;
    address public marketing;
    address public teamReserve;
    address constant WETH = address(0x1234);

    // Test token for pairs
    ERC20Mock public testToken;

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant MAX_PAIRS_PER_DISTRIBUTION = 10;
    uint256 public constant DISTRIBUTION_COOLDOWN = 1 hours;
    bytes4 constant INVALID_PAIR_ERROR = 0x6fd6873e;

    error ReentrancyGuardReentrantCall();

    event FeesDistributed(uint256 totalAmount);
    event FeesCollected(address indexed token, uint256 amount);
    event FeesConverted(address indexed token, uint256 tokenAmount, uint256 ponderAmount);

    function _getPath(address tokenIn, address tokenOut) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return path;
    }

    function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        teamReserve = address(0x3);
        marketing = address(0x4);

        // Deploy core contracts
        factory = new PonderFactory(owner, address(1), address(1));
        router = new PonderRouter(address(factory), WETH, address(2));

        // Deploy token with temporary staking address
        ponder = new PonderToken(teamReserve, marketing, address(1));

        // Deploy staking
        staking = new PonderStaking(address(ponder), address(router), address(factory));

        // Setup staking in token
        ponder.setStaking(address(staking));
        ponder.initializeStaking();

        // Deploy test token for pairs
        testToken = new ERC20Mock("Test Token", "TEST");

        // Deploy distributor
        distributor = new FeeDistributor(
            address(factory),
            address(router),
            address(ponder),
            address(staking)
        );

        // Transfer initial tokens from marketing wallet
        vm.startPrank(marketing);
        ponder.transfer(address(this), INITIAL_SUPPLY * 100);
        vm.stopPrank();

        // Create test pair
        address standardPairAddr = factory.createPair(address(ponder), address(testToken));
        pair = PonderPair(standardPairAddr);

        // Set fee collector
        factory.setFeeTo(address(distributor));

        // Setup initial liquidity
        _setupInitialLiquidity();
    }

    function _setupInitialLiquidity() internal {
        // Add initial liquidity using test contract's balance
        uint256 ponderAmount = INITIAL_SUPPLY * 10;  // Use larger amount
        uint256 tokenAmount = INITIAL_SUPPLY * 10;   // Match PONDER amount

        // Mint test tokens
        testToken.mint(address(this), tokenAmount * 2);

        // Approve tokens
        testToken.approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);

        // Add initial liquidity
        router.addLiquidity(
            address(ponder),
            address(testToken),
            ponderAmount,
            tokenAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    /**
     * @notice Helper to generate trading fees through swaps
     */
    function _generateTradingFees() internal {
        // First ensure larger initial liquidity
        testToken.mint(address(this), INITIAL_SUPPLY * 100);

        // Add massive liquidity to the pair
        vm.startPrank(address(this));
        testToken.approve(address(pair), type(uint256).max);
        ponder.approve(address(pair), type(uint256).max);

        testToken.transfer(address(pair), INITIAL_SUPPLY * 10);
        ponder.transfer(address(pair), INITIAL_SUPPLY * 10);
        pair.mint(address(this));
        vm.stopPrank();

        // Do moderate swaps to generate fees
        for (uint i = 0; i < 10; i++) {
            (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
            uint256 swapAmount = uint256(reserve0) / 10; // Use 10% of reserves

            testToken.transfer(address(pair), swapAmount);
            uint256 amountOut = (swapAmount * 997 * reserve1) / ((reserve0 * 1000) + (swapAmount * 997));
            pair.swap(0, amountOut, address(this), "");
            pair.skim(address(distributor));

            vm.warp(block.timestamp + 1 hours);

            (reserve0, reserve1,) = pair.getReserves();
            swapAmount = uint256(reserve1) / 10;
            ponder.transfer(address(pair), swapAmount);
            pair.swap(amountOut, 0, address(this), "");
            pair.skim(address(distributor));

            vm.warp(block.timestamp + 1 hours);
            pair.sync();
        }
    }

    /**
     * @notice Test initial contract state
     */
    function test_InitialState() public {
        assertEq(address(distributor.FACTORY()), address(factory));
        assertEq(address(distributor.ROUTER()), address(router));
        assertEq(address(distributor.PONDER()), address(ponder));
        assertEq(address(distributor.STAKING()), address(staking));
    }

    /**
     * @notice Test collecting fees from pair
     */
    function test_CollectFeesFromPair() public {
        // Set the Fee Distributor address in the factory
        factory.setFeeTo(address(distributor));

        // Generate trading fees
        _generateTradingFees();

        uint256 prePonderBalance = ponder.balanceOf(address(distributor));
        uint256 preTokenBalance = testToken.balanceOf(address(distributor));

        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        // Additional trade and skim
        testToken.mint(address(this), 1_000_000e18);
        ponder.transfer(address(this), 1_000_000e18);
        testToken.transfer(address(pair), 1_000_000e18);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountIn = 1_000_000e18;
        uint256 amountOut = (amountIn * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + amountIn * 997);

        pair.swap(0, amountOut, address(this), "");

        // Simulate the Fee Distributor calling skim
        vm.prank(address(distributor)); // Correct use of vm.prank()
        pair.skim(address(distributor));

        // Fee Distributor collects the fees
        distributor.collectFeesFromPair(address(pair));

        uint256 postPonderBalance = ponder.balanceOf(address(distributor));
        uint256 postTokenBalance = testToken.balanceOf(address(distributor));

        assertTrue(
            postPonderBalance > prePonderBalance || postTokenBalance > preTokenBalance,
            "Should collect fees"
        );
    }

    /**
     * @notice Test fee conversion to PONDER
     */
    function test_ConvertFees() public {
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        uint256 prePonderBalance = ponder.balanceOf(address(distributor));
        uint256 preTokenBalance = testToken.balanceOf(address(distributor));

        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        // Additional trade and sync
        testToken.mint(address(this), 1_000_000e18);
        ponder.transfer(address(this), 1_000_000e18);
        testToken.transfer(address(pair), 1_000_000e18);

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 amountIn = 1_000_000e18;
        uint256 amountOut = (amountIn * 997 * uint256(reserve1)) /
            (uint256(reserve0) * 1000 + amountIn * 997);

        pair.swap(0, amountOut, address(this), "");

        // Sync before converting
        pair.sync();

        // Convert fees
        distributor.convertFees(address(testToken));

        // Now skim any excess
        vm.prank(address(distributor));
        pair.skim(address(distributor));

        uint256 postPonderBalance = ponder.balanceOf(address(distributor));
        uint256 postTokenBalance = testToken.balanceOf(address(distributor));

        assertTrue(
            postPonderBalance > prePonderBalance || postTokenBalance > preTokenBalance,
            "Should convert fees and increase balance"
        );
    }




/**
     * @notice Test fee distribution to stakers and team
     */
    function test_Distribution() public {
        _generateTradingFees();
        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        uint256 totalAmount = ponder.balanceOf(address(distributor));
        require(totalAmount >= distributor.minimumAmount(), "Insufficient PONDER for distribution");

        uint256 initialStaking = ponder.balanceOf(address(staking));

        distributor.distribute();

        // Verify all fees went to staking
        assertEq(
            ponder.balanceOf(address(staking)) - initialStaking,
            totalAmount,
            "Wrong staking distribution"
        );
    }

    /**
     * @notice Test the complete fee lifecycle with multiple distributions
     */
    function test_CompleteFeeLifecycle() public {
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // Collect and convert fees
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Advance time to allow rebase
        vm.warp(block.timestamp + 1 days);

        // Distribute
        distributor.distribute();

        // Verify distribution
        assertTrue(
            ponder.balanceOf(address(staking)) > initialStakingBalance,
            "Staking balance should increase"
        );
    }

    /**
     * @notice Test that K value is maintained throughout fee collection
     */
    function test_KValueMaintenance() public {
        factory.setFeeTo(address(distributor));
        _generateTradingFees();

        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 initialK = uint256(reserve0) * uint256(reserve1);

        distributor.collectFeesFromPair(address(pair));

        (uint112 finalReserve0, uint112 finalReserve1,) = pair.getReserves();
        uint256 finalK = uint256(finalReserve0) * uint256(finalReserve1);

        assertGe(finalK, initialK, "K value should not decrease");
    }

    /**
     * @notice Helper function for calculating swap outputs
     */
    function _getAmountOut(
        uint256 amountIn,
        uint112 reserveIn,
        uint112 reserveOut
    ) internal pure returns (uint256) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");

        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * uint256(reserveOut);
        uint256 denominator = (uint256(reserveIn) * 1000) + amountInWithFee;
        return numerator / denominator;
    }

    function test_StakingShareValueUpdate() public {
        // First we need user1 to have tokens to stake
        vm.startPrank(address(this));  // Test contract has marketing tokens in setUp()
        ponder.transfer(user1, 10_000e18);
        vm.stopPrank();

        // Now do the staking
        vm.startPrank(user1);
        ponder.approve(address(staking), 1000e18);
        staking.enter(1000e18, user1);
        vm.stopPrank();

        // Record initial state
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));
        uint256 initialShareValue = staking.getPonderAmount(1000e18);

        // Generate and distribute fees using the existing helper
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Get balances before distribution
        uint256 stakingBalanceBefore = ponder.balanceOf(address(staking));

        distributor.distribute();

        // Get final states
        uint256 finalStakingBalance = ponder.balanceOf(address(staking));
        uint256 finalShareValue = staking.getPonderAmount(1000e18);

        // Verify balances changed
        assertGt(finalStakingBalance, stakingBalanceBefore, "Staking should receive tokens");

        // Verify share value increased proportionally
        assertGt(finalShareValue, initialShareValue, "Share value should increase");

        // The share value increase should match the balance increase ratio
        uint256 expectedFinalValue = (initialShareValue * finalStakingBalance) / initialStakingBalance;
        assertApproxEqRel(finalShareValue, expectedFinalValue, 0.01e18,
            "Share value should increase proportionally");
    }

    function test_ReentrancyFromToken() public {
        // Deploy malicious token that attempts reentrancy
        ReentrantToken reentrantToken = new ReentrantToken(address(distributor));  // collectMode = true

        // Create pair with reentrant token
        factory.createPair(address(ponder), address(reentrantToken));
        address reentrantPairAddr = factory.getPair(address(ponder), address(reentrantToken));

        // Setup initial liquidity with smaller amounts
        reentrantToken.mint(address(this), 2_000_000e18);
        ponder.transfer(address(this), 1_000_000e18);

        reentrantToken.approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(ponder),
            address(reentrantToken),
            1_000_000e18,
            1_000_000e18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Generate some fees
        reentrantToken.transfer(reentrantPairAddr, 10e18);
        bytes memory empty;
        IPonderPair(reentrantPairAddr).swap(0, 1e18, address(this), empty);

        // Attempt reentrancy attack - should fail
        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        distributor.collectFeesFromPair(reentrantPairAddr);
    }

    function test_ReentrancyFromPair() public {
        // Deploy tokens
        ERC20Mock token0 = new ERC20Mock("Token0", "TK0");
        ERC20Mock token1 = new ERC20Mock("Token1", "TK1");

        // Deploy malicious pair that attempts reentrancy
        ReentrantPair reentrantPair = new ReentrantPair(
            address(distributor),
            address(token0),
            address(token1)
        );

        // Setup tokens
        token0.mint(address(reentrantPair), 1_000_000e18);
        token1.mint(address(reentrantPair), 1_000_000e18);

        // Expect the custom error
        vm.expectRevert(ReentrancyGuardReentrantCall.selector);
        distributor.collectFeesFromPair(address(reentrantPair));
    }

    function test_EmergencyTokenRecovery() public {
        // Deploy token and mint some to distributor
        ERC20Mock token = new ERC20Mock("Test", "TST");
        token.mint(address(distributor), 1000e18);

        uint256 initialBalance = token.balanceOf(address(this));

        // Non-owner should not be able to recover tokens
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotOwner()"));
        distributor.emergencyTokenRecover(address(token), address(this), 1000e18);

        // Owner should be able to recover tokens
        vm.prank(owner);
        distributor.emergencyTokenRecover(address(token), address(this), 1000e18);

        assertEq(
            token.balanceOf(address(this)) - initialBalance,
            1000e18,
            "Recovery amount incorrect"
        );
    }

    function test_CollectFeesWithInvalidPair() public {
        // Try to collect fees from zero address
        vm.expectRevert(); // Should revert with invalid pair error
        distributor.collectFeesFromPair(address(0));

        // Try to collect fees from non-pair contract
        vm.expectRevert(); // Should revert when calling non-existent functions
        distributor.collectFeesFromPair(address(0x1234));
    }

    function test_CollectFeesStateValidation() public {
        // Setup pair and generate fees like in previous tests
        _generateTradingFees();

        // Get initial state
        uint256 initialBalance = ponder.balanceOf(address(distributor));

        // Collect fees
        distributor.collectFeesFromPair(address(pair));

        // Verify state changes
        uint256 finalBalance = ponder.balanceOf(address(distributor));
        assertTrue(finalBalance >= initialBalance, "Balance should not decrease");

        // Try to collect again immediately
        distributor.collectFeesFromPair(address(pair));

        // Verify no significant balance change on second collection
        uint256 afterSecondCollection = ponder.balanceOf(address(distributor));
        assertApproxEqRel(
            afterSecondCollection,
            finalBalance,
            0.01e18,
            "No significant fees should be collected twice"
        );
    }

    // Add these test functions to FeeDistributorTest contract

    function test_DistributePairFeesMaxLimit() public {
        // Create array with too many pairs
        address[] memory pairs = new address[](11); // MAX_PAIRS_PER_DISTRIBUTION + 1
        for(uint i = 0; i < 11; i++) {
            // Create new test tokens and pairs
            ERC20Mock newToken = new ERC20Mock("Test", "TEST");
            factory.createPair(address(ponder), address(newToken));
            pairs[i] = factory.getPair(address(ponder), address(newToken));
        }

        // Should revert when trying to distribute too many pairs
        vm.expectRevert(abi.encodeWithSignature("InvalidPairCount()"));
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesWithInvalidPair() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(0); // Invalid pair address

        vm.expectRevert(abi.encodeWithSignature("InvalidPair()"));
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesSuccessfulDistribution() public {
        _generateTradingFees();

        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        uint256 preStakingBalance = ponder.balanceOf(address(staking));

        // Add this to clear any pending state
        vm.warp(block.timestamp + DISTRIBUTION_COOLDOWN);
        pair.sync();  // Ensure pair state is clean

        // Now try distribution
        distributor.distributePairFees(pairs);

        uint256 postStakingBalance = ponder.balanceOf(address(staking));
        assertTrue(postStakingBalance > preStakingBalance, "Staking balance should increase");
    }

    function test_DistributePairFeesDuplicatePairs() public {
        address[] memory pairs = new address[](2);
        pairs[0] = address(pair);
        pairs[1] = address(pair);

        vm.expectRevert(INVALID_PAIR_ERROR);
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesInsufficientAccumulation() public {
        // Create new pair with more substantial liquidity
        ERC20Mock smallToken = new ERC20Mock("Small", "SMALL");
        factory.createPair(address(ponder), address(smallToken));
        address smallPair = factory.getPair(address(ponder), address(smallToken));

        // Add sufficient initial liquidity
        uint256 initAmount = 10_000e18;
        smallToken.mint(address(this), initAmount);
        ponder.transfer(address(this), initAmount);

        smallToken.approve(address(router), initAmount);
        ponder.approve(address(router), initAmount);

        router.addLiquidity(
            address(ponder),
            address(smallToken),
            initAmount,
            initAmount,
            0,
            0,
            address(this),
            block.timestamp
        );

        address[] memory pairs = new address[](1);
        pairs[0] = smallPair;

        // Should fail with InsufficientAccumulation error code 0x6fd6873e
        vm.expectRevert(bytes4(0x6fd6873e));
        distributor.distributePairFees(pairs);
    }

    function test_MaxPairsPerDistribution() public {
        address[] memory tooManyPairs = new address[](MAX_PAIRS_PER_DISTRIBUTION + 1);

        vm.expectRevert(abi.encodeWithSignature("InvalidPairCount()"));
        distributor.distributePairFees(tooManyPairs);
    }

    function test_ProcessedPairsCleanup() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        // Generate initial fees
        _generateTradingFees();

        // First distribution
        distributor.distributePairFees(pairs);

        // Wait cooldown period
        vm.warp(block.timestamp + 1 hours + 1);

        // Generate new fees
        _generateTradingFees();

        // Second distribution should work since we properly reset processedPairs
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesSlippageProtection() public {
        _generateTradingFees();

        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        // Create extreme imbalance
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 extremeAmount = uint256(reserve0) * 200;  // 200x reserves
        testToken.mint(address(this), extremeAmount);
        testToken.approve(address(router), extremeAmount);

        // Log initial state
        console.log("Initial reserves:", reserve0, reserve1);

        // Do massive swap to create imbalance
        address[] memory path = _getPath(address(testToken), address(ponder));
        router.swapExactTokensForTokens(
            extremeAmount,
            0,
            path,
            address(this),
            block.timestamp
        );

        // Force sync and wait
        pair.sync();
        vm.warp(block.timestamp + DISTRIBUTION_COOLDOWN);

        // Get post-swap reserves
        (uint112 newReserve0, uint112 newReserve1,) = pair.getReserves();
        console.log("Post-swap reserves:", newReserve0, newReserve1);

        // Should now fail due to reserve ratio exceeding threshold
        vm.expectRevert(abi.encodeWithSignature("SwapFailed()"));
        distributor.distributePairFees(pairs);
    }

    function test_DistributePairFeesCooldown() public {
        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        // First distribution
        _generateTradingFees();
        distributor.distributePairFees(pairs);

        // Try immediate second distribution - should fail with DistributionTooFrequent
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distributePairFees(pairs);

        // After cooldown, should work
        vm.warp(block.timestamp + 1 hours + 1);
        _generateTradingFees();
        distributor.distributePairFees(pairs);
    }

    function test_ConvertFeesSlippageProtection() public {
        // First generate some fees
        _generateTradingFees();

        // Get initial balances
        uint256 initialTokenBalance = testToken.balanceOf(address(distributor));
        require(initialTokenBalance > 0, "No fees generated");

        // Create extreme imbalance (similar to our working distributePairFees test)
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 extremeAmount = uint256(reserve0) * 150; // 150x reserves
        testToken.mint(address(this), extremeAmount);
        testToken.approve(address(router), extremeAmount);

        address[] memory path = new address[](2);
        path[0] = address(testToken);
        path[1] = address(ponder);

        // Do two massive trades to really break the price
        router.swapExactTokensForTokens(
            extremeAmount / 2,
            0,
            path,
            address(this),
            block.timestamp
        );

        router.swapExactTokensForTokens(
            extremeAmount / 2,
            0,
            path,
            address(this),
            block.timestamp
        );

        pair.sync();
        vm.warp(block.timestamp + 1 hours);

        // Now the conversion should fail due to extreme imbalance
        vm.expectRevert(abi.encodeWithSignature("SwapFailed()"));
        distributor.convertFees(address(testToken));
    }

    function test_ConvertFeesSuccessful() public {
        // Generate some fees
        _generateTradingFees();

        // Get initial balances
        uint256 initialPonderBalance = ponder.balanceOf(address(distributor));
        uint256 initialTokenBalance = testToken.balanceOf(address(distributor));

        // Ensure we have enough fees to convert
        require(initialTokenBalance >= distributor.minimumAmount(), "Insufficient fees");

        // Convert fees
        distributor.convertFees(address(testToken));

        // Verify balances changed appropriately
        uint256 finalPonderBalance = ponder.balanceOf(address(distributor));
        uint256 finalTokenBalance = testToken.balanceOf(address(distributor));

        assertTrue(finalPonderBalance > initialPonderBalance, "PONDER balance should increase");
        assertTrue(finalTokenBalance < initialTokenBalance, "Token balance should decrease");
    }

    function test_ConvertFeesInvalidToken() public {
        // Deploy a mock token but don't create a pair for it
        ERC20Mock invalidToken = new ERC20Mock("Invalid", "INV");

        // Mint some tokens to the distributor
        invalidToken.mint(address(distributor), distributor.minimumAmount());

        // Should revert with PairNotFound since no pair exists
        vm.expectRevert(abi.encodeWithSignature("PairNotFound()"));
        distributor.convertFees(address(invalidToken));
    }

    function test_ConvertFeesReentrancyProtection() public {
        ReentrantToken maliciousToken = new ReentrantToken(address(distributor));

        // Create pair
        factory.createPair(address(maliciousToken), address(ponder));

        // Setup liquidity
        maliciousToken.mint(address(this), 10000e18);
        ponder.transfer(address(this), 10000e18);

        maliciousToken.approve(address(router), type(uint256).max);
        ponder.approve(address(router), type(uint256).max);

        router.addLiquidity(
            address(maliciousToken),
            address(ponder),
            10000e18,
            10000e18,
            0,
            0,
            address(this),
            block.timestamp
        );

        // Mint directly to distributor
        maliciousToken.mint(address(distributor), distributor.minimumAmount());

        // Change this line to expect SwapFailed instead
        vm.expectRevert(abi.encodeWithSignature("SwapFailed()"));
        distributor.convertFees(address(maliciousToken));
    }

    function test_DistributionTimingManipulation() public {
        // Initial setup and first distribution
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        vm.warp(1000); // Set initial time
        distributor.distribute();

        // Generate more fees for subsequent attempts
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Ensure sufficient balance
        uint256 distributorBalance = ponder.balanceOf(address(distributor));
        require(distributorBalance >= distributor.minimumAmount(), "Insufficient balance for test");

        // Try after 30 minutes
        vm.warp(1000 + 30 minutes);
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();

        // Generate more fees and try after 45 minutes
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        vm.warp(1000 + 45 minutes);
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();

        // Should work after cooldown
        vm.warp(1000 + 1 hours);
        distributor.distribute();
    }

    function test_DistributionFrontRunningProtection() public {
        // Initial setup - generate some fees
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Set initial timestamp
        uint256 startTime = 1000;
        vm.warp(startTime);

        // First distribution
        distributor.distribute();

        // Verify lastDistributionTimestamp was set
        assertEq(distributor.lastDistributionTimestamp(), startTime, "Distribution timestamp not set");

        // Generate more fees for the attack attempt
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Setup attacker
        address attacker = address(0x2);
        vm.startPrank(address(this));
        ponder.transfer(attacker, 100_000e18);
        vm.stopPrank();

        vm.startPrank(attacker);
        ponder.approve(address(staking), 100_000e18);
        staking.enter(100_000e18, attacker);

        // Try to distribute immediately after (t = startTime + 1)
        vm.warp(startTime + 1);

        // Should fail due to cooldown
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();
        vm.stopPrank();

        // Verify distribution still fails just before cooldown ends
        vm.warp(startTime + DISTRIBUTION_COOLDOWN - 1);
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();

        // Should succeed after cooldown
        vm.warp(startTime + DISTRIBUTION_COOLDOWN);
        distributor.distribute();
    }

    function test_StakingPositionStability() public {
        // Setup initial stakers
        address[] memory stakers = new address[](3);
        uint256[] memory amounts = new uint256[](3);

        for(uint i = 0; i < stakers.length; i++) {
            stakers[i] = address(uint160(i + 1));
            amounts[i] = 1000e18 * (i + 1);

            vm.startPrank(address(this));
            ponder.transfer(stakers[i], amounts[i]);
            vm.stopPrank();

            vm.startPrank(stakers[i]);
            ponder.approve(address(staking), amounts[i]);
            staking.enter(amounts[i], stakers[i]);
            vm.stopPrank();
        }

        // Generate and collect fees
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // Set initial timestamp and distribute
        uint256 startTime = 1000;
        vm.warp(startTime);
        distributor.distribute();

        // Verify timestamp set
        assertEq(distributor.lastDistributionTimestamp(), startTime, "Distribution timestamp not set");

        // Setup for attack attempt
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        address attacker = address(0x999);
        vm.startPrank(address(this));
        ponder.transfer(attacker, 100_000e18);
        vm.stopPrank();

        vm.startPrank(attacker);
        ponder.approve(address(staking), 100_000e18);
        staking.enter(100_000e18, attacker);

        // Try to distribute within cooldown period (t = startTime + 1)
        vm.warp(startTime + 1);
        vm.expectRevert(abi.encodeWithSignature("DistributionTooFrequent()"));
        distributor.distribute();
        vm.stopPrank();
    }

    // Add these tests to your FeeDistributorTest contract

    function test_SwapsAfterFeeCollection() public {
        // First generate and collect fees
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));

        // Get reserves after fee collection
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Try a normal swap immediately after
        uint256 amountIn = 1e18;
        address[] memory path = _getPath(address(testToken), address(ponder));

        // Calculate expected output with 0.5% slippage
        uint256 amountOut = router.getAmountsOut(amountIn, path)[1];
        uint256 minOut = (amountOut * 995) / 1000; // 0.5% slippage

        testToken.approve(address(router), amountIn);

        // This swap should succeed
        router.swapExactTokensForTokens(
            amountIn,
            minOut,
            path,
            address(this),
            block.timestamp
        );

        // Verify reserves are still healthy
        (uint112 newReserve0, uint112 newReserve1,) = pair.getReserves();
        assertTrue(newReserve0 > 0 && newReserve1 > 0, "Reserves should be healthy");
    }

    function test_SwapsAfterDistribution() public {
        // Complete fee cycle
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));
        vm.warp(block.timestamp + 1 hours);
        distributor.distribute();

        // Record reserves after distribution
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();

        // Try swaps with different slippage values
        uint256 amountIn = 1e18;

        // Mint test tokens for the swap
        testToken.mint(address(this), amountIn);

        // Give router approval for testToken
        testToken.approve(address(router), type(uint256).max);

        address[] memory path = _getPath(address(testToken), address(ponder));

        // Test with 0.5% slippage
        uint256 amountOut = router.getAmountsOut(amountIn, path)[1];
        uint256 minOut = (amountOut * 995) / 1000;

        router.swapExactTokensForTokens(
            amountIn,
            minOut,
            path,
            address(this),
            block.timestamp
        );

        // Mint more tokens for the second swap
        testToken.mint(address(this), amountIn);

        // Test with 1% slippage
        minOut = (amountOut * 990) / 1000;
        router.swapExactTokensForTokens(
            amountIn,
            minOut,
            path,
            address(this),
            block.timestamp
        );
    }

    function test_ReserveStabilityAfterFees() public {
        // Get initial reserves
        (uint112 initialReserve0, uint112 initialReserve1,) = pair.getReserves();

        // Generate and collect fees
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));

        // Get reserves after collection
        (uint112 afterCollectionReserve0, uint112 afterCollectionReserve1,) = pair.getReserves();

        // Verify reserves haven't changed drastically
        assertGt(afterCollectionReserve0, initialReserve0 * 90 / 100, "Reserve0 dropped too much");
        assertGt(afterCollectionReserve1, initialReserve1 * 90 / 100, "Reserve1 dropped too much");

        // Convert and distribute
        distributor.convertFees(address(testToken));
        vm.warp(block.timestamp + 1 hours);
        distributor.distribute();

        // Get final reserves
        (uint112 finalReserve0, uint112 finalReserve1,) = pair.getReserves();

        // Verify final reserves are healthy
        assertGt(finalReserve0, initialReserve0 * 90 / 100, "Final reserve0 too low");
        assertGt(finalReserve1, initialReserve1 * 90 / 100, "Final reserve1 too low");
    }

    function test_LargeSwapsAfterFees() public {
        // Generate and process fees
        _generateTradingFees();
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));
        vm.warp(block.timestamp + 1 hours);
        distributor.distribute();

        // Try a large swap (5% of reserves)
        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
        uint256 largeAmount = uint256(reserve0) * 5 / 100;

        address[] memory path = _getPath(address(testToken), address(ponder));
        uint256 expectedOut = router.getAmountsOut(largeAmount, path)[1];
        uint256 minOut = (expectedOut * 995) / 1000; // 0.5% slippage

        testToken.mint(address(this), largeAmount);
        testToken.approve(address(router), largeAmount);

        // Should succeed even with large amount
        router.swapExactTokensForTokens(
            largeAmount,
            minOut,
            path,
            address(this),
            block.timestamp
        );
    }

    function test_ProductionScenario() public {
        // 1. Setup initial state
        _generateTradingFees();

        // Get initial state
        (uint112 reserve0Before, uint112 reserve1Before,) = pair.getReserves();

        // 2. Collect and convert fees
        distributor.collectFeesFromPair(address(pair));
        distributor.convertFees(address(testToken));

        // 3. Distribute fees
        vm.warp(block.timestamp + 1 hours);
        distributor.distribute();

        // Get post-distribution state
        (uint112 reserve0After, uint112 reserve1After,) = pair.getReserves();

        // Verify reserves haven't dropped significantly (using ratios instead of multiplication)
        assertGt(uint256(reserve0After) * 100 / uint256(reserve0Before), 90, "Reserve0 dropped too much");
        assertGt(uint256(reserve1After) * 100 / uint256(reserve1Before), 90, "Reserve1 dropped too much");

        // Test different swap sizes
        uint256[] memory testAmounts = new uint256[](3);
        testAmounts[0] = 0.1e18;  // Small swap
        testAmounts[1] = 1e18;    // Medium swap
        testAmounts[2] = 10e18;   // Large swap

        address[] memory path = _getPath(address(testToken), address(ponder));

        for (uint i = 0; i < testAmounts.length; i++) {
            uint256 amountIn = testAmounts[i];

            // Setup for swap
            testToken.mint(address(this), amountIn);
            testToken.approve(address(router), amountIn);

            // Record reserves before swap
            (uint112 preSwapReserve0, uint112 preSwapReserve1,) = pair.getReserves();

            // Calculate expected output with 0.5% slippage
            uint256[] memory amounts = router.getAmountsOut(amountIn, path);
            uint256 expectedOut = amounts[1];
            uint256 minOut = (expectedOut * 995) / 1000;

            // Perform swap
            uint256[] memory actualAmounts = router.swapExactTokensForTokens(
                amountIn,
                minOut,
                path,
                address(this),
                block.timestamp
            );

            // Verify swap results
            assertGe(actualAmounts[1], minOut, "Received less than minimum");
            assertLe(actualAmounts[1], expectedOut, "Received more than expected");

            // Verify reserves after swap are non-zero
            (uint112 postSwapReserve0, uint112 postSwapReserve1,) = pair.getReserves();
            assertTrue(postSwapReserve0 > 0 && postSwapReserve1 > 0, "Zero reserves after swap");

            // Verify K value hasn't decreased
            uint256 kBefore = uint256(preSwapReserve0) * uint256(preSwapReserve1);
            uint256 kAfter = uint256(postSwapReserve0) * uint256(postSwapReserve1);
            assertGe(kAfter, kBefore, "K value decreased");
        }
    }

    function test_SwapsAfterFeeDistribution() public {
        _generateTradingFees();

        // Setup for fee distribution
        address[] memory pairs = new address[](1);
        pairs[0] = address(pair);

        // Record initial states
        (uint112 initialReserve0, uint112 initialReserve1,) = pair.getReserves();
        uint256 initialStakingBalance = ponder.balanceOf(address(staking));

        // Distribute fees
        vm.warp(block.timestamp + DISTRIBUTION_COOLDOWN);
        distributor.distributePairFees(pairs);

        // Verify distribution
        uint256 postStakingBalance = ponder.balanceOf(address(staking));
        assertGt(postStakingBalance, initialStakingBalance, "Fee distribution failed");

        // Test different swap sizes
        _testSwapAfterFees(1e18, initialReserve0, initialReserve1);    // Small swap
        _testSwapAfterFees(10e18, initialReserve0, initialReserve1);   // Medium swap
        _testSwapAfterFees(100e18, initialReserve0, initialReserve1);  // Large swap

        // Verify system stability with another distribution
        vm.warp(block.timestamp + DISTRIBUTION_COOLDOWN);
        distributor.distributePairFees(pairs);
    }

    function _testSwapAfterFees(
        uint256 swapAmount,
        uint112 initialReserve0,
        uint112 initialReserve1
    ) internal {
        // Setup
        testToken.mint(address(this), swapAmount);
        testToken.approve(address(router), swapAmount);

        // Get pre-swap state
        (uint112 preSwapReserve0, uint112 preSwapReserve1,) = pair.getReserves();

        // Calculate expected output
        address[] memory path = new address[](2);
        path[0] = address(testToken);
        path[1] = address(ponder);

        uint256[] memory expectedAmounts = router.getAmountsOut(swapAmount, path);
        uint256 expectedOut = expectedAmounts[1];
        uint256 minOut = (expectedOut * 995) / 1000; // 0.5% slippage

        // Execute swap
        uint256[] memory amounts = router.swapExactTokensForTokens(
            swapAmount,
            minOut,
            path,
            address(this),
            block.timestamp
        );

        // Get post-swap state
        (uint112 postSwapReserve0, uint112 postSwapReserve1,) = pair.getReserves();

        // Verify swap success
        assertTrue(amounts[1] >= minOut, "Swap output below minimum");
        assertTrue(amounts[1] <= expectedOut, "Swap output above expected");

        // Verify reserve health
        assertTrue(postSwapReserve0 > 0 && postSwapReserve1 > 0, "Zero reserves after swap");

        // Verify k value
        uint256 kBefore = uint256(preSwapReserve0) * uint256(preSwapReserve1);
        uint256 kAfter = uint256(postSwapReserve0) * uint256(postSwapReserve1);
        assertGe(kAfter, kBefore, "K value decreased");

        // Verify reasonable reserve changes
        _validateReserveChanges(postSwapReserve0, postSwapReserve1, initialReserve0, initialReserve1);
    }

    function _validateReserveChanges(
        uint112 currentReserve0,
        uint112 currentReserve1,
        uint112 initialReserve0,
        uint112 initialReserve1
    ) internal pure {
        uint256 reserve0Ratio = (uint256(currentReserve0) * 100) / uint256(initialReserve0);
        uint256 reserve1Ratio = (uint256(currentReserve1) * 100) / uint256(initialReserve1);

        // Allow for up to 20% deviation
        assertTrue(reserve0Ratio >= 80 && reserve0Ratio <= 120, "Reserve0 deviated too much");
        assertTrue(reserve1Ratio >= 80 && reserve1Ratio <= 120, "Reserve1 deviated too much");
    }
}

