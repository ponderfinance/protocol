// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPonderFactory} from "../core/factory/IPonderFactory.sol";
import {IPonderRouter} from "../periphery/router/IPonderRouter.sol";
import {LaunchToken} from "./LaunchToken.sol";
import {PonderToken} from "../core/token/PonderToken.sol";
import {PonderPriceOracle} from "../core/oracle/PonderPriceOracle.sol";
import {IFiveFiveFiveLauncher} from "./IFiveFiveFiveLauncher.sol";
import {FiveFiveFiveLauncherStorage} from "./storage/FiveFiveFiveStorage.sol";
import {PonderPair} from "../core/pair/PonderPair.sol";
import {PonderERC20} from "../core/token/PonderERC20.sol";

/// @title FiveFiveFiveLauncher
/// @author taayyohh
/// @notice Implementation of the 555 token launch platform
/// @dev Handles token launches with dual liquidity pools (KUB and PONDER)
contract FiveFiveFiveLauncher is IFiveFiveFiveLauncher, FiveFiveFiveLauncherStorage, ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                         IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Core protocol contracts
    IPonderFactory public immutable FACTORY;
    IPonderRouter public immutable ROUTER;
    PonderToken public immutable PONDER;
    PonderPriceOracle public immutable PRICE_ORACLE;

    /// @notice Sets up the launcher with required protocol contracts
    /// @param _factory Address of the PonderFactory contract
    /// @param _router Address of the PonderRouter contract
    /// @param _feeCollector Address to collect fees
    /// @param _ponder Address of the PONDER token
    /// @param _priceOracle Address of the price oracle
    constructor(
        address _factory,
        address payable _router,
        address _feeCollector,
        address _ponder,
        address _priceOracle
    ) {
        if (_factory == address(0) || _router == address(0) ||
        _feeCollector == address(0) || _ponder == address(0) ||
            _priceOracle == address(0)) revert ZeroAddress();

        FACTORY = IPonderFactory(_factory);
        ROUTER = IPonderRouter(_router);
        PONDER = PonderToken(_ponder);
        PRICE_ORACLE = PonderPriceOracle(_priceOracle);
        feeCollector = _feeCollector;
        owner = msg.sender;
    }

    /// @notice Creates a new token launch
    /// @param params Launch parameters including name, symbol, and imageURI
    /// @return launchId Unique identifier for the launch
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

    /// @dev Deploys a new token contract for the launch
    /// @param params Launch parameters
    /// @return token The deployed token contract
    function _deployToken(LaunchParams calldata params) internal returns (LaunchToken) {
        return new LaunchToken(
            params.name,
            params.symbol,
            address(this),
            address(FACTORY),
            payable(address(ROUTER)),
            address(PONDER)
        );
    }

    /// @dev Initializes a new launch with the deployed token
    /// @param launchId ID of the launch
    /// @param tokenAddress Address of the deployed token
    /// @param params Launch parameters
    /// @param creator Address of the launch creator
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


    /// @notice Allows users to contribute KUB to a launch
    /// @param launchId The ID of the launch to contribute to
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

    /// @dev Validates that a launch is in an active state
    /// @param launch The launch to validate
    function _validateLaunchState(LaunchInfo storage launch) internal view {
        if (launch.base.tokenAddress == address(0)) revert LaunchNotFound();
        if (launch.base.launched) revert AlreadyLaunched();
        if (launch.base.cancelled) revert LaunchNotCancellable();
        if (block.timestamp > launch.base.launchDeadline) revert LaunchExpired();
    }

    /// @dev Calculates contribution result for KUB
    /// @param launch The launch info
    /// @param amount The amount being contributed
    /// @return result Contribution calculation results
    function _calculateKubContribution(
        LaunchInfo storage launch,
        uint256 amount
    ) internal view returns (ContributionResult memory result) {
        uint256 remaining = TARGET_RAISE - (
            launch.contributions.kubCollected +
            launch.contributions.ponderValueCollected
        );
        result.contribution = amount > remaining ? remaining : amount;


        if (result.contribution < MIN_KUB_CONTRIBUTION) {
            revert ContributionTooSmall();
        }

        result.tokensToDistribute = (result.contribution * launch.allocation.tokensForContributors) / TARGET_RAISE;
        result.refund = amount > remaining ? amount - remaining : 0;
        return result;
    }

    /// @dev Processes a KUB contribution
    /// @param launchId The ID of the launch
    /// @param launch The launch info
    /// @param amount The amount being contributed
    /// @param contributor The address of the contributor
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


    /// @notice Allows users to contribute PONDER to a launch
    /// @param launchId The ID of the launch to contribute to
    /// @param amount Amount of PONDER to contribute
    function contributePONDER(uint256 launchId, uint256 amount) external {
        LaunchInfo storage launch = launches[launchId];
        _validateLaunchState(launch);
        if(amount < MIN_PONDER_CONTRIBUTION) revert ContributionTooSmall();

        uint256 kubValue = _getPonderValue(amount);

        // Check against 20% PONDER cap
        uint256 totalPonderValue = launch.contributions.ponderValueCollected + kubValue;
        uint256 maxPonderAllowed = (TARGET_RAISE * MAX_PONDER_PERCENT) / BASIS_POINTS;
        if (totalPonderValue > maxPonderAllowed) {
            revert ExcessivePonderContribution();
        }

        // Check against remaining needed
        uint256 totalCollected =
            launch.contributions.kubCollected +
            launch.contributions.ponderValueCollected;

        uint256 remaining = TARGET_RAISE - totalCollected;
        if (kubValue > remaining) revert ExcessiveContribution();

        uint256 tokensToDistribute = (kubValue * launch.allocation.tokensForContributors) / TARGET_RAISE;

        // Transfer exact amount needed
        PONDER.transferFrom(msg.sender, address(this), amount);

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

    /// @dev Calculates contribution result for PONDER
    /// @param launch The launch info
    /// @param amount The PONDER amount
    /// @param kubValue The KUB value of the PONDER amount
    /// @return result Contribution calculation results
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

        uint256 totalContributed = launch.contributions.kubCollected +
                            launch.contributions.ponderValueCollected;
        uint256 remaining = TARGET_RAISE - totalContributed;

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

    /// @dev Processes a PONDER contribution
    /// @param launchId The ID of the launch
    /// @param launch The launch info
    /// @param result The contribution calculation results
    /// @param amount The PONDER amount
    /// @param contributor The address of the contributor
    function _processPonderContribution(
        uint256 launchId,
        LaunchInfo storage launch,
        ContributionResult memory result,
        uint256 amount,
        address contributor
    ) internal {
        uint256 ponderToAccept = amount - result.refund;

        // Transfer exact amount needed first
        PONDER.transferFrom(contributor, address(this), ponderToAccept);

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

    /// @notice Allows contributors to claim refunds for failed or cancelled launches
    /// @param launchId The ID of the launch to claim refund from
    function claimRefund(uint256 launchId) external nonReentrant {
        LaunchInfo storage launch = launches[launchId];

        // Check if refund is possible
        if (!(block.timestamp > launch.base.launchDeadline || launch.base.cancelled)) {
            revert LaunchStillActive();
        }
        if (launch.base.launched ||
            launch.contributions.kubCollected + launch.contributions.ponderValueCollected >= TARGET_RAISE) {
            revert LaunchSucceeded();
        }

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
            if (token.allowance(msg.sender, address(this)) < tokensToReturn) {
                revert TokenApprovalRequired();
            }
            // Transfer tokens back first
            token.transferFrom(msg.sender, address(this), tokensToReturn);
        }

        // Process PONDER refund
        if (ponderToRefund > 0) {
            PONDER.transfer(msg.sender, ponderToRefund);
        }

        // Process KUB refund last
        if (kubToRefund > 0) {
            _safeTransferETH(msg.sender, kubToRefund);
        }

        // Emit refund event
        emit RefundProcessed(msg.sender, kubToRefund, ponderToRefund, tokensToReturn);
    }

    /// @notice Allows creator to cancel their launch
    /// @param launchId The ID of the launch to cancel
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

    /// @dev Checks if a launch should be finalized and initiates finalization if needed
    /// @param launchId The ID of the launch
    /// @param launch The launch info
    function _checkAndFinalizeLaunch(uint256 launchId, LaunchInfo storage launch) internal {
        uint256 totalValue = launch.contributions.kubCollected + launch.contributions.ponderValueCollected;
        if (totalValue == TARGET_RAISE) {
            // Set flag before proceeding with finalization
            launch.base.isFinalizingLaunch = true;
            _finalizeLaunch(launchId);
        }
    }

    /// @notice Finalizes a launch by creating liquidity pools and enabling trading
    /// @param launchId The ID of the launch to finalize
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

    /// @dev Calculates amounts for pool creation based on collected contributions
    /// @param launch The launch info
    /// @return pools Pool configuration with token amounts
    function _calculatePoolAmounts(LaunchInfo storage launch) internal view returns (PoolConfig memory pools) {
        pools.kubAmount = (launch.contributions.kubCollected * KUB_TO_MEME_KUB_LP) / BASIS_POINTS;
        pools.ponderAmount = (launch.contributions.ponderCollected * PONDER_TO_MEME_PONDER) / BASIS_POINTS;
        pools.tokenAmount = launch.allocation.tokensForLP / 2; // Split LP tokens between pairs
        return pools;
    }

    /// @dev Creates liquidity pools for the token
    /// @param launchId The ID of the launch
    /// @param launch The launch info
    /// @param pools Pool configuration
    function _createPools(uint256 launchId, LaunchInfo storage launch, PoolConfig memory pools) private {
        // 1. Early checks
        if (pools.kubAmount < MIN_POOL_LIQUIDITY) {
            revert InsufficientPoolLiquidity();
        }

        // 2. Get the KUB pair
        address memeKubPair = _getOrCreatePair(launch.base.tokenAddress, ROUTER.WETH());

        // 3. Check reserves BEFORE doing any transfers
        (uint112 kubR0, uint112 kubR1,) = PonderPair(memeKubPair).getReserves();
        if (kubR0 != 0 || kubR1 != 0) {
            revert PriceOutOfBounds();
        }
        launch.pools.memeKubPair = memeKubPair;

        // 4. Now check PONDER pair reserves if needed
        if (launch.contributions.ponderCollected > 0) {
            uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount);
            if (ponderPoolValue >= MIN_POOL_LIQUIDITY) {
                address memePonderPair = _getOrCreatePair(launch.base.tokenAddress, address(PONDER));
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
                PONDER.burn(launch.contributions.ponderCollected);
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


    /// @dev Gets or creates a trading pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return Address of the pair
    function _getOrCreatePair(address tokenA, address tokenB) private returns (address) {
        address pair = FACTORY.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = FACTORY.createPair(tokenA, tokenB);
        }
        return pair;
    }

    function _getOrCreateKubPair(address tokenAddress) private returns (address) {
        address weth = ROUTER.WETH();
        address pair = FACTORY.getPair(tokenAddress, weth);
        if (pair == address(0)) {
            pair = FACTORY.createPair(tokenAddress, weth);
        }
        return pair;
    }

    function _getOrCreatePonderPair(address tokenAddress) private returns (address) {
        address pair = FACTORY.getPair(tokenAddress, address(PONDER));
        if (pair == address(0)) {
            pair = FACTORY.createPair(tokenAddress, address(PONDER));
        }
        return pair;
    }

    /// @dev Adds KUB liquidity to a pool
    /// @param tokenAddress Token address
    /// @param kubAmount Amount of KUB
    /// @param tokenAmount Amount of tokens
    function _addKubLiquidity(
        address tokenAddress,
        uint256 kubAmount,
        uint256 tokenAmount
    ) private {
        LaunchToken(tokenAddress).approve(address(ROUTER), tokenAmount);

        ROUTER.addLiquidityETH{value: kubAmount}(
            tokenAddress,
            tokenAmount,
            tokenAmount * 995 / 1000,  // 0.5% slippage
            kubAmount * 995 / 1000,    // 0.5% slippage
            address(this),
            block.timestamp + 3 minutes // Shorter deadline
        );
    }

    /// @dev Adds PONDER liquidity to a pool
    /// @param tokenAddress Token address
    /// @param ponderAmount Amount of PONDER
    /// @param tokenAmount Amount of tokens
    function _addPonderLiquidity(
        address tokenAddress,
        uint256 ponderAmount,
        uint256 tokenAmount
    ) private {
        LaunchToken(tokenAddress).approve(address(ROUTER), tokenAmount);
        PONDER.approve(address(ROUTER), ponderAmount);

        ROUTER.addLiquidity(
            tokenAddress,
            address(PONDER),
            tokenAmount,
            ponderAmount,
            tokenAmount * 995 / 1000,  // 0.5% slippage
            ponderAmount * 995 / 1000, // 0.5% slippage
            address(this),
            block.timestamp + 3 minutes // Shorter deadline
        );
    }

    /// @dev Burns PONDER tokens based on pool creation outcome
    /// @param launchId The ID of the launch
    /// @param launch The launch info
    /// @param burnAll Whether to burn all PONDER tokens
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
            PONDER.burn(ponderToBurn);
            emit PonderBurned(launchId, ponderToBurn);
        }
    }

    /// @dev Enables trading for the launched token
    /// @param launch The launch info
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
        address memeKubPair = FACTORY.getPair(launch.base.tokenAddress, ROUTER.WETH());
        if (memeKubPair == address(0)) {
            memeKubPair = FACTORY.createPair(launch.base.tokenAddress, ROUTER.WETH());
        }
        launch.pools.memeKubPair = memeKubPair;

        // Check existing reserves
        (uint112 r0, uint112 r1,) = PonderPair(memeKubPair).getReserves();
        if (r0 != 0 || r1 != 0) {
            revert PriceOutOfBounds();
        }

        // Approve exact amount
        LaunchToken(launch.base.tokenAddress).approve(address(ROUTER), pools.tokenAmount);

        // Add liquidity
        ROUTER.addLiquidityETH{value: pools.kubAmount}(
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
        address pair = FACTORY.getPair(tokenAddress, address(PONDER));
        if (pair == address(0)) {
            pair = FACTORY.createPair(tokenAddress, address(PONDER));
        }

        // Check existing reserves
        (uint112 r0, uint112 r1,) = PonderPair(pair).getReserves();
        if (r0 != 0 || r1 != 0) {
            revert PriceOutOfBounds();
        }

        // Approve tokens with exact amounts
        LaunchToken(tokenAddress).approve(address(ROUTER), tokenAmount);
        PONDER.approve(address(ROUTER), ponderAmount);

        // Add liquidity with reasonable slippage
        ROUTER.addLiquidity(
            tokenAddress,
            address(PONDER),
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

    /// @notice Allows creator to withdraw LP tokens after lock period
    /// @param launchId The ID of the launch to withdraw from
    function withdrawLP(uint256 launchId) external {
        LaunchInfo storage launch = launches[launchId];
        if(msg.sender != launch.base.creator) revert Unauthorized();
        if(block.timestamp < launch.base.lpUnlockTime) revert LPStillLocked();

        _withdrawPairLP(launch.pools.memeKubPair, launch.base.creator);
        _withdrawPairLP(launch.pools.memePonderPair, launch.base.creator);

        emit LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);
    }

    /// @dev Withdraws LP tokens from a specific pair
    /// @param pair The pair address
    /// @param recipient The address to receive the LP tokens
    function _withdrawPairLP(address pair, address recipient) internal {
        if (pair == address(0)) return;
        uint256 balance = PonderERC20(pair).balanceOf(address(this));
        if (balance > 0) {
            PonderERC20(pair).transfer(recipient, balance);
        }
    }

/// @dev Gets the KUB value of PONDER tokens using the price oracle
    /// @param amount Amount of PONDER to value
    /// @return KUB value of the PONDER amount
    function _getPonderValue(uint256 amount) internal view returns (uint256) {
        address ponderKubPair = FACTORY.getPair(address(PONDER), ROUTER.WETH());
        (, , uint32 lastUpdateTime) = PonderPair(ponderKubPair).getReserves();

        // First check if price is stale
        if (block.timestamp - lastUpdateTime > PRICE_STALENESS_THRESHOLD) {
            revert StalePrice();
        }

        // Get spot price for contribution value
        uint256 spotPrice = PRICE_ORACLE.getCurrentPrice(
            ponderKubPair,
            address(PONDER),
            amount
        );

        // Get TWAP price for manipulation check
        uint256 twapPrice = PRICE_ORACLE.consult(
            ponderKubPair,
            address(PONDER),
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

    /// @dev Validates token name and symbol parameters
    /// @param name Token name to validate
    /// @param symbol Token symbol to validate
    function _validateTokenParams(string memory name, string memory symbol) internal view {
        bytes memory nameBytes = bytes(name);
        bytes memory symbolBytes = bytes(symbol);

        // Length checks
        if(nameBytes.length == 0 || nameBytes.length > 32) revert InvalidTokenParams();
        if(symbolBytes.length == 0 || symbolBytes.length > 8) revert InvalidTokenParams();

        // Uniqueness checks
        if(usedNames[name]) revert TokenNameExists();
        if(usedSymbols[symbol]) revert TokenSymbolExists();

        // Validate name characters
        for(uint256 i = 0; i < nameBytes.length; i++) {
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

        // Validate symbol characters
        for(uint256 i = 0; i < symbolBytes.length; i++) {
            bytes1 char = symbolBytes[i];
            if(!(
                (char >= 0x30 && char <= 0x39) ||
                (char >= 0x41 && char <= 0x5A) ||
                (char >= 0x61 && char <= 0x7A)
            )) revert InvalidTokenParams();
        }
    }

    /// @notice View functions with minimal stack usage
    /// @inheritdoc IFiveFiveFiveLauncher
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

    /// @inheritdoc IFiveFiveFiveLauncher
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

    /// @inheritdoc IFiveFiveFiveLauncher
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

    /// @inheritdoc IFiveFiveFiveLauncher
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

    /// @inheritdoc IFiveFiveFiveLauncher
    function getMinimumRequirements() external pure returns (
        uint256 minKub,
        uint256 minPonder,
        uint256 minPoolLiquidity
    ) {
        return (MIN_KUB_CONTRIBUTION, MIN_PONDER_CONTRIBUTION, MIN_POOL_LIQUIDITY);
    }

    /// @inheritdoc IFiveFiveFiveLauncher
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


    /// @dev Safely transfers ETH
    /// @param to Address to transfer to
    /// @param value Amount to transfer
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        if (!success) revert EthTransferFailed();
    }

    receive() external payable {}
}
