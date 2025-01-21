// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import { LaunchToken } from "../LaunchToken.sol";
import { PonderToken } from "../../core/token/PonderToken.sol";
import { PonderPriceOracle } from "../../core/oracle/PonderPriceOracle.sol";
import { IPonderFactory } from "../../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../../periphery/router/IPonderRouter.sol";
import { FiveFiveFiveConstants } from "./FiveFiveFiveConstants.sol";
import { FiveFiveFivePoolLib } from "./FiveFiveFivePoolLib.sol";
import { FiveFiveFiveValidation } from "./FiveFiveFiveValidation.sol";
import { FiveFiveFiveLauncherTypes } from "../types/FiveFiveFiveLauncherTypes.sol";

/// @title FiveFiveFiveFinalizationLib
/// @author taayyohh
/// @notice Library for managing launch finalization
/// @dev Handles pool creation and trading enablement
library FiveFiveFiveFinalizationLib {
    using FiveFiveFiveConstants for uint256;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event PonderBurned(uint256 indexed launchId, uint256 amount);
    event PonderPoolSkipped(uint256 indexed launchId, uint256 ponderAmount, uint256 ponderValueInKub);
    event DualPoolsCreated(
        uint256 indexed launchId,
        address memeKubPair,
        address memePonderPair,
        uint256 kubLiquidity,
        uint256 ponderLiquidity
    );
    event LaunchCompleted(uint256 indexed launchId, uint256 kubRaised, uint256 ponderRaised);

    /*//////////////////////////////////////////////////////////////
                            FINALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Finalizes a launch by creating pools and enabling trading
    /// @param launch The launch info struct
    /// @param launchId The launch ID
    /// @param factory Factory contract for creating pairs
    /// @param router Router contract for adding liquidity
    /// @param ponder PONDER token contract
    /// @param priceOracle Oracle for price validation
    function finalizeLaunch(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        PonderPriceOracle priceOracle
    ) external {
        // Initial safety checks
        if (launch.base.launched) {
            revert FiveFiveFiveLauncherTypes.AlreadyLaunched();
        }
        if (launch.contributions.tokensDistributed + launch.allocation.tokensForLP >
            LaunchToken(launch.base.tokenAddress).TOTAL_SUPPLY()) {
            revert FiveFiveFiveLauncherTypes.InsufficientLPTokens();
        }

        // Mark as launched immediately to prevent reentrancy
        launch.base.launched = true;

        // Calculate pool amounts
        FiveFiveFiveLauncherTypes.PoolConfig memory pools = FiveFiveFivePoolLib.calculatePoolAmounts(launch);

        // Create and validate KUB pool
        _createKubPool(launch, pools, factory, router);

        // Handle PONDER pool if needed
        if (launch.contributions.ponderCollected > 0) {
            _handlePonderPool(
                launch,
                launchId,
                pools,
                factory,
                router,
                ponder,
                priceOracle
            );
        }

        // Enable trading and finalize
        _enableTrading(launch, launchId);
    }

    /*//////////////////////////////////////////////////////////////
                        POOL CREATION
    //////////////////////////////////////////////////////////////*/

    /// @dev Creates and initializes KUB pool
    function _createKubPool(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.PoolConfig memory pools,
        IPonderFactory factory,
        IPonderRouter router
    ) private {
        // Create KUB pair
        launch.pools.memeKubPair = FiveFiveFivePoolLib.getOrCreateKubPair(
            factory,
            launch.base.tokenAddress,
            router
        );

        // Validate pool creation
        FiveFiveFivePoolLib.validatePoolCreation(pools, launch.pools.memeKubPair);

        // Add KUB liquidity
        LaunchToken(launch.base.tokenAddress).approve(address(router), pools.tokenAmount);
        FiveFiveFivePoolLib.addKubLiquidity(
            router,
            launch.base.tokenAddress,
            pools.kubAmount,
            pools.tokenAmount,
            address(this)
        );
    }

    /// @dev Creates and initializes PONDER pool if conditions are met
    function _handlePonderPool(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId,
        FiveFiveFiveLauncherTypes.PoolConfig memory pools,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        PonderPriceOracle priceOracle
    ) private {
        // Get PONDER value
        uint256 ponderPoolValue = _getPonderValue(
            pools.ponderAmount,
            factory,
            router,
            ponder,
            priceOracle
        );

        // Create pool if enough liquidity
        if (ponderPoolValue >= FiveFiveFiveConstants.MIN_POOL_LIQUIDITY) {
            _createPonderPool(
                launch,
                pools,
                factory,
                router,
                ponder,
                launchId
            );
        } else {
            // Burn all PONDER if no pool created
            ponder.burn(launch.contributions.ponderCollected);
            emit PonderBurned(launchId, launch.contributions.ponderCollected);
            emit PonderPoolSkipped(launchId, pools.ponderAmount, ponderPoolValue);
        }
    }

    /// @dev Creates PONDER pool and adds initial liquidity
    function _createPonderPool(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        FiveFiveFiveLauncherTypes.PoolConfig memory pools,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        uint256 launchId
    ) private {
        // Create PONDER pair
        launch.pools.memePonderPair = FiveFiveFivePoolLib.getOrCreatePonderPair(
            factory,
            launch.base.tokenAddress,
            address(ponder)
        );

        // Validate pool creation
        FiveFiveFivePoolLib.validatePoolCreation(pools, launch.pools.memePonderPair);

        // Add PONDER liquidity
        ponder.approve(address(router), pools.ponderAmount);
        FiveFiveFivePoolLib.addPonderLiquidity(
            router,
            launch.base.tokenAddress,
            address(ponder),
            pools.ponderAmount,
            pools.tokenAmount,
            address(this)
        );

        // Burn percentage of PONDER
        uint256 ponderToBurn = (launch.contributions.ponderCollected *
            FiveFiveFiveConstants.PONDER_TO_BURN) / FiveFiveFiveConstants.BASIS_POINTS;
        ponder.burn(ponderToBurn);
        emit PonderBurned(launchId, ponderToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                            TRADING ENABLEMENT
    //////////////////////////////////////////////////////////////*/

    /// @dev Enables trading and finalizes launch
    function _enableTrading(
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch,
        uint256 launchId
    ) private {
        // Enable trading
        LaunchToken token = LaunchToken(launch.base.tokenAddress);
        token.setPairs(launch.pools.memeKubPair, launch.pools.memePonderPair);
        token.enableTransfers();

        // Set LP unlock time
        launch.base.lpUnlockTime = block.timestamp + FiveFiveFiveConstants.LP_LOCK_PERIOD;

        // Emit completion events
        emit DualPoolsCreated(
            launchId,
            launch.pools.memeKubPair,
            launch.pools.memePonderPair,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );

        emit LaunchCompleted(
            launchId,
            launch.contributions.kubCollected,
            launch.contributions.ponderCollected
        );
    }

    /*//////////////////////////////////////////////////////////////
                            UTILITIES
    //////////////////////////////////////////////////////////////*/

    /// @dev Gets KUB value of PONDER amount
    function _getPonderValue(
        uint256 amount,
        IPonderFactory factory,
        IPonderRouter router,
        PonderToken ponder,
        PonderPriceOracle priceOracle
    ) private view returns (uint256) {
        address ponderKubPair = factory.getPair(address(ponder), router.weth());
        return FiveFiveFiveValidation.validatePonderPrice(
            ponderKubPair,
            priceOracle,
            address(ponder),
            amount
        );
    }
}
