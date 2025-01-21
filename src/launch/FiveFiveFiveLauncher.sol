// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IPonderFactory } from "../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../periphery/router/IPonderRouter.sol";
import { LaunchToken } from "./LaunchToken.sol";
import { PonderToken } from "../core/token/PonderToken.sol";
import { PonderPriceOracle } from "../core/oracle/PonderPriceOracle.sol";
import { PonderPair } from "../core/pair/PonderPair.sol";
import { PonderERC20 } from "../core/token/PonderERC20.sol";
import { IFiveFiveFiveLauncher } from "./IFiveFiveFiveLauncher.sol";
import { FiveFiveFiveLauncherStorage } from "./storage/FiveFiveFiveStorage.sol";
import { FiveFiveFiveLauncherTypes } from "./types/FiveFiveFiveLauncherTypes.sol";

/// @title FiveFiveFiveLauncher
/// @author taayyohh
/// @notice Implementation of the 555 token launch platform
/// @dev Handles token launches with dual liquidity pools (KUB and PONDER)
contract FiveFiveFiveLauncher is
    IFiveFiveFiveLauncher,
    FiveFiveFiveLauncherStorage,
    ReentrancyGuard
{
    using FiveFiveFiveLauncherTypes for *;

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
        if (
            _factory == address(0) ||
            _router == address(0) ||
            _feeCollector == address(0) ||
            _ponder == address(0) ||
            _priceOracle == address(0)
        ) revert FiveFiveFiveLauncherTypes.ZeroAddress();

        FACTORY = IPonderFactory(_factory);
        ROUTER = IPonderRouter(_router);
        PONDER = PonderToken(_ponder);
        PRICE_ORACLE = PonderPriceOracle(_priceOracle);
        feeCollector = _feeCollector;
        owner = msg.sender;
    }

    /// @notice Creates a new token launch
    /// @param params LaunchParams containing name, symbol and imageURI
    /// @return launchId Unique identifier for the new launch
    function createLaunch(
        FiveFiveFiveLauncherTypes.LaunchParams calldata params
    ) external returns (uint256 launchId) {
        if(bytes(params.imageURI).length == 0) revert FiveFiveFiveLauncherTypes.ImageRequired();
        _validateTokenParams(params.name, params.symbol);

        launchId = launchCount++;

        usedNames[params.name] = true;
        usedSymbols[params.symbol] = true;

        LaunchToken token = _deployToken(params);
        _initializeLaunch(launchId, address(token), params, msg.sender);

        emit LaunchCreated(launchId, address(token), msg.sender, params.imageURI);
    }

    /// @dev Deploys a new token contract with given parameters
    /// @param params Launch parameters for token creation
    /// @return Newly deployed token contract
    function _deployToken(
        FiveFiveFiveLauncherTypes.LaunchParams calldata params
    ) internal returns (LaunchToken) {
        return new LaunchToken(
            params.name,
            params.symbol,
            address(this),
            address(FACTORY),
            payable(address(ROUTER)),
            address(PONDER)
        );
    }

    /// @dev Sets up initial state for a new launch
    /// @param launchId ID of the launch to initialize
    /// @param tokenAddress Address of the deployed token
    /// @param params Launch parameters
    /// @param creator Address of launch creator
    function _initializeLaunch(
        uint256 launchId,
        address tokenAddress,
        FiveFiveFiveLauncherTypes.LaunchParams calldata params,
        address creator
    ) internal {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];

        launch.base.tokenAddress = tokenAddress;
        launch.base.name = params.name;
        launch.base.symbol = params.symbol;
        launch.base.imageURI = params.imageURI;
        launch.base.creator = creator;

        uint256 totalSupply = LaunchToken(tokenAddress).TOTAL_SUPPLY();
        uint256 forContributors = (totalSupply * FiveFiveFiveLauncherTypes.CONTRIBUTOR_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;
        uint256 forLP = (totalSupply * FiveFiveFiveLauncherTypes.LP_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;
        uint256 forCreator = (totalSupply * FiveFiveFiveLauncherTypes.CREATOR_PERCENT) /
                        FiveFiveFiveLauncherTypes.BASIS_POINTS;

        launch.allocation.tokensForContributors = forContributors;
        launch.allocation.tokensForLP = forLP;

        LaunchToken(tokenAddress).setupVesting(creator, forCreator);

        launch.base.launchDeadline = block.timestamp + FiveFiveFiveLauncherTypes.LAUNCH_DURATION;
    }

    /// @notice Allows users to contribute KUB to a launch
    /// @param launchId The ID of the launch to contribute to
    function contributeKUB(uint256 launchId) external payable nonReentrant {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];

        if (launch.base.launched) revert FiveFiveFiveLauncherTypes.AlreadyLaunched();
        if (launch.base.cancelled) revert FiveFiveFiveLauncherTypes.LaunchNotCancellable();
        if (block.timestamp > launch.base.launchDeadline) {
            revert FiveFiveFiveLauncherTypes.LaunchExpired();
        }
        if (launch.base.isFinalizingLaunch) {
            revert FiveFiveFiveLauncherTypes.LaunchBeingFinalized();
        }

        uint256 currentTotal = launch.contributions.kubCollected +
                            launch.contributions.ponderValueCollected;
        uint256 newTotal = currentTotal + msg.value;

        if(msg.value < FiveFiveFiveLauncherTypes.MIN_KUB_CONTRIBUTION) {
            revert FiveFiveFiveLauncherTypes.ContributionTooSmall();
        }
        if(msg.value > FiveFiveFiveLauncherTypes.TARGET_RAISE - currentTotal) {
            revert FiveFiveFiveLauncherTypes.ExcessiveContribution();
        }

        if (newTotal == FiveFiveFiveLauncherTypes.TARGET_RAISE) {
            launch.base.isFinalizingLaunch = true;
        } else if (newTotal > FiveFiveFiveLauncherTypes.TARGET_RAISE) {
            revert FiveFiveFiveLauncherTypes.ExcessiveContribution();
        }

        uint256 tokensToDistribute = (msg.value * launch.allocation.tokensForContributors) /
                        FiveFiveFiveLauncherTypes.TARGET_RAISE;

        launch.contributions.kubCollected += msg.value;
        launch.contributions.tokensDistributed += tokensToDistribute;
        launch.contributors[msg.sender].kubContributed += msg.value;
        launch.contributors[msg.sender].tokensReceived += tokensToDistribute;

        LaunchToken(launch.base.tokenAddress).transfer(msg.sender, tokensToDistribute);

        emit TokensDistributed(launchId, msg.sender, tokensToDistribute);
        emit KUBContributed(launchId, msg.sender, msg.value);

        if (launch.base.isFinalizingLaunch) {
            _finalizeLaunch(launchId);
        }
    }

    /// @notice Allows users to contribute PONDER to a launch
    /// @param launchId The ID of the launch to contribute to
    /// @param amount The amount of PONDER to contribute
    function contributePONDER(uint256 launchId, uint256 amount) external {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];
        _validateLaunchState(launch);
        if(amount < FiveFiveFiveLauncherTypes.MIN_PONDER_CONTRIBUTION) {
            revert FiveFiveFiveLauncherTypes.ContributionTooSmall();
        }

        uint256 kubValue = _getPonderValue(amount);

        uint256 totalPonderValue = launch.contributions.ponderValueCollected + kubValue;
        uint256 maxPonderAllowed = (FiveFiveFiveLauncherTypes.TARGET_RAISE *
            FiveFiveFiveLauncherTypes.MAX_PONDER_PERCENT) / FiveFiveFiveLauncherTypes.BASIS_POINTS;

        if (totalPonderValue > maxPonderAllowed) {
            revert FiveFiveFiveLauncherTypes.ExcessivePonderContribution();
        }

        uint256 totalCollected = launch.contributions.kubCollected +
                            launch.contributions.ponderValueCollected;
        uint256 remaining = FiveFiveFiveLauncherTypes.TARGET_RAISE - totalCollected;
        if (kubValue > remaining) revert FiveFiveFiveLauncherTypes.ExcessiveContribution();

        uint256 tokensToDistribute = (kubValue * launch.allocation.tokensForContributors) /
                        FiveFiveFiveLauncherTypes.TARGET_RAISE;

        PONDER.transferFrom(msg.sender, address(this), amount);

        launch.contributions.ponderCollected += amount;
        launch.contributions.ponderValueCollected += kubValue;
        launch.contributions.tokensDistributed += tokensToDistribute;

        FiveFiveFiveLauncherTypes.ContributorInfo storage contributorInfo =
                            launch.contributors[msg.sender];
        contributorInfo.ponderContributed += amount;
        contributorInfo.ponderValue += kubValue;
        contributorInfo.tokensReceived += tokensToDistribute;

        LaunchToken(launch.base.tokenAddress).transfer(msg.sender, tokensToDistribute);
        emit TokensDistributed(launchId, msg.sender, tokensToDistribute);
        emit PonderContributed(launchId, msg.sender, amount, kubValue);

        _checkAndFinalizeLaunch(launchId, launch);
    }

    /// @notice Allows contributors to claim refunds for failed or cancelled launches
    /// @param launchId The ID of the launch to claim refund from
    function claimRefund(uint256 launchId) external nonReentrant {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];

        bool canRefund = block.timestamp > launch.base.launchDeadline || launch.base.cancelled;
        if (!canRefund) {
            revert FiveFiveFiveLauncherTypes.LaunchStillActive();
        }

        uint256 totalValue = launch.contributions.kubCollected +
                            launch.contributions.ponderValueCollected;
        if (launch.base.launched || totalValue >= FiveFiveFiveLauncherTypes.TARGET_RAISE) {
            revert FiveFiveFiveLauncherTypes.LaunchSucceeded();
        }

        FiveFiveFiveLauncherTypes.ContributorInfo storage contributor =
                            launch.contributors[msg.sender];
        if (contributor.kubContributed == 0 && contributor.ponderContributed == 0) {
            revert FiveFiveFiveLauncherTypes.NoContributionToRefund();
        }

        uint256 kubToRefund = contributor.kubContributed;
        uint256 ponderToRefund = contributor.ponderContributed;
        uint256 tokensToReturn = contributor.tokensReceived;

        contributor.kubContributed = 0;
        contributor.ponderContributed = 0;
        contributor.tokensReceived = 0;
        contributor.ponderValue = 0;

        if (tokensToReturn > 0) {
            LaunchToken token = LaunchToken(launch.base.tokenAddress);
            if (token.allowance(msg.sender, address(this)) < tokensToReturn) {
                revert FiveFiveFiveLauncherTypes.TokenApprovalRequired();
            }
            token.transferFrom(msg.sender, address(this), tokensToReturn);
        }

        if (ponderToRefund > 0) {
            PONDER.transfer(msg.sender, ponderToRefund);
        }

        if (kubToRefund > 0) {
            _safeTransferETH(msg.sender, kubToRefund);
        }

        emit RefundProcessed(msg.sender, kubToRefund, ponderToRefund, tokensToReturn);
    }

    /// @notice Allows creator to cancel their launch
    /// @param launchId The ID of the launch to cancel
    function cancelLaunch(uint256 launchId) external {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];

        if (launch.base.tokenAddress == address(0)) {
            revert FiveFiveFiveLauncherTypes.LaunchNotCancellable();
        }
        if (msg.sender != launch.base.creator) revert FiveFiveFiveLauncherTypes.Unauthorized();
        if (launch.base.launched) revert FiveFiveFiveLauncherTypes.AlreadyLaunched();
        if (launch.base.isFinalizingLaunch) {
            revert FiveFiveFiveLauncherTypes.LaunchBeingFinalized();
        }
        if (block.timestamp > launch.base.launchDeadline) {
            revert FiveFiveFiveLauncherTypes.LaunchDeadlinePassed();
        }

        usedNames[launch.base.name] = false;
        usedSymbols[launch.base.symbol] = false;
        launch.base.cancelled = true;

        emit LaunchCancelled(
            launchId,
            msg.sender,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    /// @notice Allows creator to withdraw LP tokens after lock period
    /// @param launchId The ID of the launch to withdraw from
    function withdrawLP(uint256 launchId) external {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];
        if(msg.sender != launch.base.creator) revert FiveFiveFiveLauncherTypes.Unauthorized();
        if(block.timestamp < launch.base.lpUnlockTime) {
            revert FiveFiveFiveLauncherTypes.LPStillLocked();
        }

        _withdrawPairLP(launch.pools.memeKubPair, launch.base.creator);
        _withdrawPairLP(launch.pools.memePonderPair, launch.base.creator);

        emit LPTokensWithdrawn(launchId, launch.base.creator, block.timestamp);
    }

    /// @dev Finalizes a launch by setting up liquidity pools and enabling trading
    /// @param launchId The ID of the launch to finalize
    function _finalizeLaunch(uint256 launchId) internal {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];

        if (launch.base.launched) revert FiveFiveFiveLauncherTypes.AlreadyLaunched();

        uint256 totalTokens = launch.contributions.tokensDistributed + launch.allocation.tokensForLP;
        uint256 totalSupply = LaunchToken(launch.base.tokenAddress).TOTAL_SUPPLY();
        if (totalTokens > totalSupply) {
            revert FiveFiveFiveLauncherTypes.InsufficientLPTokens();
        }

        launch.base.launched = true;

        FiveFiveFiveLauncherTypes.PoolConfig memory pools = _calculatePoolAmounts(launch);
        if (pools.kubAmount < FiveFiveFiveLauncherTypes.MIN_POOL_LIQUIDITY) {
            revert FiveFiveFiveLauncherTypes.InsufficientPoolLiquidity();
        }

        _createPools(launchId, launch, pools);
        _enableTrading(launch);

        emit LaunchCompleted(
            launchId,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );

        launch.base.isFinalizingLaunch = false;
    }

    /// @dev Calculates amounts for pool creation based on collected contributions
    /// @param launch The launch info
    /// @return pools Pool configuration with token amounts
    function _calculatePoolAmounts(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) internal view returns (FiveFiveFiveLauncherTypes.PoolConfig memory pools) {
        pools.kubAmount = (launch.contributions.kubCollected *
            FiveFiveFiveLauncherTypes.KUB_TO_MEME_KUB_LP) / FiveFiveFiveLauncherTypes.BASIS_POINTS;

        pools.ponderAmount = (launch.contributions.ponderCollected *
            FiveFiveFiveLauncherTypes.PONDER_TO_MEME_PONDER) / FiveFiveFiveLauncherTypes.BASIS_POINTS;

        pools.tokenAmount = launch.allocation.tokensForLP / 2;
        return pools;
    }

    /// @dev Creates liquidity pools for the token
    /// @param launchId The ID of the launch
    /// @param launch The launch info
    /// @param pools Pool configuration
    function _createPools(
        uint256 launchId,
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.PoolConfig memory pools
    ) private {
        if (pools.kubAmount < FiveFiveFiveLauncherTypes.MIN_POOL_LIQUIDITY) {
            revert FiveFiveFiveLauncherTypes.InsufficientPoolLiquidity();
        }

        address memeKubPair = _getOrCreatePair(launch.base.tokenAddress, ROUTER.weth());
        (uint112 kubR0, uint112 kubR1,) = PonderPair(memeKubPair).getReserves();
        if (kubR0 != 0 || kubR1 != 0) {
            revert FiveFiveFiveLauncherTypes.PriceOutOfBounds();
        }
        launch.pools.memeKubPair = memeKubPair;

        if (launch.contributions.ponderCollected > 0) {
            uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount);
            if (ponderPoolValue >= FiveFiveFiveLauncherTypes.MIN_POOL_LIQUIDITY) {
                address memePonderPair = _getOrCreatePair(
                    launch.base.tokenAddress,
                    address(PONDER)
                );
                (uint112 ponderR0, uint112 ponderR1,) = PonderPair(memePonderPair).getReserves();
                if (ponderR0 != 0 || ponderR1 != 0) {
                    revert FiveFiveFiveLauncherTypes.PriceOutOfBounds();
                }
                launch.pools.memePonderPair = memePonderPair;
            }
        }

        _addKubLiquidity(
            launch.base.tokenAddress,
            pools.kubAmount,
            pools.tokenAmount
        );

        if (launch.contributions.ponderCollected > 0) {
            uint256 ponderPoolValue = _getPonderValue(pools.ponderAmount);
            if (ponderPoolValue >= FiveFiveFiveLauncherTypes.MIN_POOL_LIQUIDITY) {
                _addPonderLiquidity(
                    launch.base.tokenAddress,
                    pools.ponderAmount,
                    pools.tokenAmount
                );
                _burnPonderTokens(launchId, launch, false);
            } else {
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

    /// @dev Validates that a launch is in an active state
    /// @param launch The launch to validate
    function _validateLaunchState(FiveFiveFiveLauncherTypes.LaunchInfo storage launch) internal view {
        if (launch.base.tokenAddress == address(0)) {
            revert FiveFiveFiveLauncherTypes.LaunchNotFound();
        }
        if (launch.base.launched) revert FiveFiveFiveLauncherTypes.AlreadyLaunched();
        if (launch.base.cancelled) revert FiveFiveFiveLauncherTypes.LaunchNotCancellable();
        if (block.timestamp > launch.base.launchDeadline) {
            revert FiveFiveFiveLauncherTypes.LaunchExpired();
        }
    }


/// @dev Validates token name and symbol parameters
    /// @param name Token name to validate
    /// @param symbol Token symbol to validate
    function _validateTokenParams(string memory name, string memory symbol) internal view {
        bytes memory nameBytes = bytes(name);
        bytes memory symbolBytes = bytes(symbol);

        if(nameBytes.length == 0 || nameBytes.length > 32) {
            revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }
        if(symbolBytes.length == 0 || symbolBytes.length > 8) {
            revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }

        if(usedNames[name]) revert FiveFiveFiveLauncherTypes.TokenNameExists();
        if(usedSymbols[symbol]) revert FiveFiveFiveLauncherTypes.TokenSymbolExists();

        for(uint256 i = 0; i < nameBytes.length; i++) {
            bytes1 char = nameBytes[i];
            if(!(
                (char >= 0x30 && char <= 0x39) ||  // 0-9
                (char >= 0x41 && char <= 0x5A) ||  // A-Z
                (char >= 0x61 && char <= 0x7A) ||  // a-z
                char == 0x20 ||  // space
                char == 0x2D ||  // -
                char == 0x5F     // _
            )) revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }

        // Continue validating symbol characters
        for(uint256 i = 0; i < symbolBytes.length; i++) {
            bytes1 char = symbolBytes[i];
            if(!(
                (char >= 0x30 && char <= 0x39) ||  // 0-9
                (char >= 0x41 && char <= 0x5A) ||  // A-Z
                (char >= 0x61 && char <= 0x7A)     // a-z
            )) revert FiveFiveFiveLauncherTypes.InvalidTokenParams();
        }
    }


    /// @dev Checks if a launch should be finalized and initiates finalization if needed
    /// @param launchId The ID of the launch
    /// @param launch The launch info
    function _checkAndFinalizeLaunch(
        uint256 launchId,
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch
    ) internal {
        uint256 totalValue = launch.contributions.kubCollected +
                            launch.contributions.ponderValueCollected;
        if (totalValue == FiveFiveFiveLauncherTypes.TARGET_RAISE) {
            launch.base.isFinalizingLaunch = true;
            _finalizeLaunch(launchId);
        }
    }

    /// @dev Gets or creates a trading pair
    /// @param tokenA First token address
    /// @param tokenB Second token address
    /// @return pair Address of the trading pair
    function _getOrCreatePair(address tokenA, address tokenB) private returns (address pair) {
        pair = FACTORY.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            pair = FACTORY.createPair(tokenA, tokenB);
        }
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
            block.timestamp + 3 minutes
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
            block.timestamp + 3 minutes
        );
    }

    /// @dev Burns PONDER tokens based on pool creation outcome
    /// @param launchId The ID of the launch
    /// @param launch The launch info
    /// @param burnAll Whether to burn all PONDER tokens
    function _burnPonderTokens(
        uint256 launchId,
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        bool burnAll
    ) internal {
        uint256 ponderToBurn;
        if (burnAll) {
            ponderToBurn = launch.contributions.ponderCollected;
        } else {
            ponderToBurn = (launch.contributions.ponderCollected *
                FiveFiveFiveLauncherTypes.PONDER_TO_BURN) / FiveFiveFiveLauncherTypes.BASIS_POINTS;
        }

        if (ponderToBurn > 0) {
            PONDER.burn(ponderToBurn);
            emit PonderBurned(launchId, ponderToBurn);
        }
    }

    /// @dev Enables trading for the launched token
    /// @param launch The launch info
    function _enableTrading(FiveFiveFiveLauncherTypes.LaunchInfo storage launch) internal {
        LaunchToken token = LaunchToken(launch.base.tokenAddress);
        token.setPairs(launch.pools.memeKubPair, launch.pools.memePonderPair);
        token.enableTransfers();
        launch.base.lpUnlockTime = block.timestamp + FiveFiveFiveLauncherTypes.LP_LOCK_PERIOD;
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

    /// @dev Gets the KUB value of PONDER tokens using price oracle
    /// @param amount Amount of PONDER to value
    /// @return The KUB value of the PONDER amount
    function _getPonderValue(uint256 amount) internal view returns (uint256) {
        address ponderKubPair = FACTORY.getPair(address(PONDER), ROUTER.weth());
        (, , uint32 lastUpdateTime) = PonderPair(ponderKubPair).getReserves();

        if (block.timestamp - lastUpdateTime > FiveFiveFiveLauncherTypes.PRICE_STALENESS_THRESHOLD) {
            revert FiveFiveFiveLauncherTypes.StalePrice();
        }

        uint256 spotPrice = PRICE_ORACLE.getCurrentPrice(
            ponderKubPair,
            address(PONDER),
            amount
        );

        uint256 twapPrice = PRICE_ORACLE.consult(
            ponderKubPair,
            address(PONDER),
            amount,
            1 hours
        );

        if (twapPrice == 0) {
            revert FiveFiveFiveLauncherTypes.InsufficientPriceHistory();
        }

        uint256 maxDeviation = (twapPrice * 110) / 100;  // 10% max deviation
        uint256 minDeviation = (twapPrice * 90) / 100;   // 10% min deviation

        if (spotPrice > maxDeviation || spotPrice < minDeviation) {
            revert FiveFiveFiveLauncherTypes.ExcessivePriceDeviation();
        }

        return spotPrice;
    }

    /// @dev Safely transfers ETH to an address
    /// @param to Address to transfer to
    /// @param value Amount to transfer
    function _safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}("");
        if (!success) revert FiveFiveFiveLauncherTypes.EthTransferFailed();
    }

    /// @inheritdoc IFiveFiveFiveLauncher
    function getContributorInfo(
        uint256 launchId,
        address contributor
    ) external view returns (
        uint256 kubContributed,
        uint256 ponderContributed,
        uint256 ponderValue,
        uint256 tokensReceived
    ) {
        FiveFiveFiveLauncherTypes.ContributorInfo storage info =
                                launches[launchId].contributors[contributor];
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
        FiveFiveFiveLauncherTypes.ContributionState storage contributions =
                            launches[launchId].contributions;
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
        FiveFiveFiveLauncherTypes.PoolInfo storage pools = launches[launchId].pools;
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
        FiveFiveFiveLauncherTypes.LaunchBaseInfo storage base = launches[launchId].base;
        FiveFiveFiveLauncherTypes.ContributionState storage contributions =
                            launches[launchId].contributions;

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
        return (
            FiveFiveFiveLauncherTypes.MIN_KUB_CONTRIBUTION,
            FiveFiveFiveLauncherTypes.MIN_PONDER_CONTRIBUTION,
            FiveFiveFiveLauncherTypes.MIN_POOL_LIQUIDITY
        );
    }

    /// @inheritdoc IFiveFiveFiveLauncher
    function getRemainingToRaise(uint256 launchId) external view returns (
        uint256 remainingTotal,
        uint256 remainingPonderValue
    ) {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];
        uint256 total = launch.contributions.kubCollected +
                            launch.contributions.ponderValueCollected;
        uint256 remaining = total >= FiveFiveFiveLauncherTypes.TARGET_RAISE ?
            0 : FiveFiveFiveLauncherTypes.TARGET_RAISE - total;

        uint256 maxPonderValue = (FiveFiveFiveLauncherTypes.TARGET_RAISE *
            FiveFiveFiveLauncherTypes.MAX_PONDER_PERCENT) / FiveFiveFiveLauncherTypes.BASIS_POINTS;
        uint256 currentPonderValue = launch.contributions.ponderValueCollected;
        uint256 remainingPonder = currentPonderValue >= maxPonderValue ?
            0 : maxPonderValue - currentPonderValue;

        return (remaining, remainingPonder < remaining ? remainingPonder : remaining);
    }

    receive() external payable {}
}


