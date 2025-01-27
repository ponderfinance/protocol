// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IPonderFactory } from "../core/factory/IPonderFactory.sol";
import { IPonderRouter } from "../periphery/router/IPonderRouter.sol";
import { PonderToken } from "../core/token/PonderToken.sol";
import { PonderPriceOracle } from "../core/oracle/PonderPriceOracle.sol";
import { IFiveFiveFiveLauncher } from "./IFiveFiveFiveLauncher.sol";
import { FiveFiveFiveLauncherStorage } from "./storage/FiveFiveFiveStorage.sol";
import { FiveFiveFiveLauncherTypes } from "./types/FiveFiveFiveLauncherTypes.sol";
import { FiveFiveFiveInitLib } from "./libraries/FiveFiveFiveInitLib.sol";
import { FiveFiveFiveValidation } from "./libraries/FiveFiveFiveValidation.sol";
import { FiveFiveFivePoolLib } from "./libraries/FiveFiveFivePoolLib.sol";
import { FiveFiveFiveRefundLib } from "./libraries/FiveFiveFiveRefundLib.sol";
import { FiveFiveFiveViewLib } from "./libraries/FiveFiveFiveViewLib.sol";
import { FiveFiveFiveContributionLib } from "./libraries/FiveFiveFiveContributionLib.sol";
import { FiveFiveFiveFinalizationLib } from "./libraries/FiveFiveFiveFinalizationLib.sol";

/**
 * @title FiveFiveFiveLauncher
 * @notice This contract enables the creation, contribution, and management of token launches in the Ponder ecosystem.
 */
contract FiveFiveFiveLauncher is
    IFiveFiveFiveLauncher,
    FiveFiveFiveLauncherStorage,
    ReentrancyGuard
{
    using FiveFiveFiveLauncherTypes for *;
    using FiveFiveFiveInitLib for FiveFiveFiveLauncherTypes.LaunchInfo;
    using FiveFiveFiveValidation for FiveFiveFiveLauncherTypes.LaunchInfo;
    using FiveFiveFivePoolLib for FiveFiveFiveLauncherTypes.LaunchInfo;
    using FiveFiveFiveRefundLib for FiveFiveFiveLauncherTypes.LaunchInfo;
    using FiveFiveFiveViewLib for FiveFiveFiveLauncherTypes.LaunchInfo;
    using FiveFiveFiveFinalizationLib for FiveFiveFiveLauncherTypes.LaunchInfo;

    /// @notice Core protocol contracts
    IPonderFactory public immutable FACTORY;
    IPonderRouter public immutable ROUTER;
    PonderToken public immutable PONDER;
    PonderPriceOracle public immutable PRICE_ORACLE;

    /**
     * @notice Constructor to initialize the launcher with core protocol dependencies.
     * @param _factory Address of the Ponder factory contract.
     * @param _router Address of the Ponder router contract.
     * @param _feeCollector Address to collect protocol fees.
     * @param _ponder Address of the Ponder token contract.
     * @param _priceOracle Address of the Ponder price oracle.
     */
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

    /**
     * @notice Creates a new token launch.
     * @param params Launch parameters defined in FiveFiveFiveLauncherTypes.
     * @return launchId Unique identifier for the created launch.
     */
    function createLaunch(
        FiveFiveFiveLauncherTypes.LaunchParams calldata params
    ) external returns (uint256 launchId) {
        FiveFiveFiveValidation.validateTokenParams(
            params.name,
            params.symbol,
            usedNames,
            usedSymbols
        );

        launchId = launchCount++;
        usedNames[params.name] = true;
        usedSymbols[params.symbol] = true;

        address token = FiveFiveFiveInitLib.initializeLaunch(
            launches[launchId],
            params,
            msg.sender,
            FACTORY,
            ROUTER,
            PONDER,
            address(this)
        );

        emit LaunchCreated(launchId, token, msg.sender, params.imageURI);
    }

    /**
     * @notice Contribute KUB to a token launch.
     * @param launchId Identifier of the launch.
     */
    function contributeKUB(uint256 launchId) external payable nonReentrant {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];
        FiveFiveFiveValidation.validateLaunchState(launch);

        bool shouldFinalize = FiveFiveFiveContributionLib.processKubContribution(
            launch,
            launchId,
            msg.value,
            msg.sender
        );

        if (shouldFinalize) {
            FiveFiveFiveFinalizationLib.finalizeLaunch(
                launch,
                launchId,
                FACTORY,
                ROUTER,
                PONDER,
                PRICE_ORACLE
            );
        }
    }

    /**
     * @notice Contribute PONDER tokens to a token launch.
     * @param launchId Identifier of the launch.
     * @param amount Amount of PONDER tokens to contribute.
     */
    function contributePONDER(uint256 launchId, uint256 amount) external {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];

        bool shouldFinalize = FiveFiveFiveContributionLib.processPonderContribution(
            launch,
            launchId,
            amount,
            _getPonderValue(amount),
            msg.sender,
            PONDER
        );

        if (shouldFinalize) {
            FiveFiveFiveFinalizationLib.finalizeLaunch(
                launch,
                launchId,
                FACTORY,
                ROUTER,
                PONDER,
                PRICE_ORACLE
            );
        }
    }

    /**
     * @notice Claim a refund for a token launch.
     * @param launchId Identifier of the launch.
     */
    function claimRefund(uint256 launchId) external nonReentrant {
        FiveFiveFiveRefundLib.processRefund(
            launches[launchId],
            msg.sender,
            PONDER
        );
    }

    /**
     * @notice Cancel a token launch.
     * @param launchId Identifier of the launch.
     */
    function cancelLaunch(uint256 launchId) external {
        FiveFiveFiveRefundLib.processLaunchCancellation(
            launches[launchId],
            launchId,
            msg.sender,
            usedNames,
            usedSymbols
        );
    }

    /**
     * @notice Withdraw liquidity pool tokens from a token launch.
     * @param launchId Identifier of the launch.
     */
    function withdrawLP(uint256 launchId) external {
        FiveFiveFiveRefundLib.processLPWithdrawal(
            launches[launchId],
            launchId,
            msg.sender
        );
    }

    /**
     * @notice Retrieve contributor-specific information for a launch.
     * @param launchId Identifier of the launch.
     * @param contributor Address of the contributor.
     * @return Contribution details (amounts, timestamps, etc.).
     * @custom:slither-disable-next-line ignore-return
     */
    function getContributorInfo(uint256 launchId, address contributor)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        (
            uint256 kubContributed,
            uint256 ponderContributed,
            uint256 ponderValue,
            uint256 tokensReceived
        ) = FiveFiveFiveViewLib.getContributorInfo(launches[launchId], contributor);

        return (kubContributed, ponderContributed, ponderValue, tokensReceived);
    }

    /**
     * @notice Retrieve overall contribution information for a launch.
     * @param launchId Identifier of the launch.
     * @return Contribution summary details.
     * @custom:slither-disable-next-line ignore-return
     */
    function getContributionInfo(uint256 launchId)
        external
        view
        returns (uint256, uint256, uint256, uint256)
    {
        (
            uint256 kubCollected,
            uint256 ponderCollected,
            uint256 ponderValueCollected,
            uint256 totalValue
        ) = FiveFiveFiveViewLib.getContributionInfo(launches[launchId]);

        return (kubCollected, ponderCollected, ponderValueCollected, totalValue);
    }

    /**
     * @notice Retrieve pool-specific information for a launch.
     * @param launchId Identifier of the launch.
     * @return Pool details (addresses, states, etc.).
     * @custom:slither-disable-next-line ignore-return
     */
    function getPoolInfo(uint256 launchId)
    external
    view
    returns (address, address, bool)
    {
        (
            address memeKubPair,
            address memePonderPair,
            bool hasSecondaryPool
        ) = FiveFiveFiveViewLib.getPoolInfo(launches[launchId]);

        return (memeKubPair, memePonderPair, hasSecondaryPool);
    }

    /**
     * @notice Retrieve launch-specific information.
     * @param launchId Identifier of the launch.
     * @return Launch details (name, symbol, etc.).
     * @custom:slither-disable-next-line ignore-return
     */
    function getLaunchInfo(uint256 launchId)
    external
    view
    returns (address, string memory, string memory, string memory, uint256, bool, uint256)
    {
        return FiveFiveFiveViewLib.getLaunchInfo(launches[launchId]);
    }

    /**
     * @notice Retrieve minimum requirements for a launch.
     * @return Minimum contribution thresholds.
     * @custom:slither-disable-next-line ignore-return
     */
    function getMinimumRequirements()
    external
    pure
    returns (uint256, uint256, uint256)
    {
        return FiveFiveFiveViewLib.getMinimumRequirements();
    }

    /**
     * @notice Retrieve remaining contribution requirements for a launch.
     * @param launchId Identifier of the launch.
     * @return Remaining amounts to be raised.
     * @custom:slither-disable-next-line ignore-return
     */
    function getRemainingToRaise(uint256 launchId)
    external
    view
    returns (uint256, uint256)
    {
        return FiveFiveFiveViewLib.getRemainingToRaise(launches[launchId]);
    }

    /**
     * @dev Internal helper for calculating the PONDER token value in KUB.
     * @param amount Amount of PONDER tokens.
     * @return Value in KUB.
     */
    function _getPonderValue(uint256 amount) internal view returns (uint256) {
        address ponderKubPair = FACTORY.getPair(address(PONDER), ROUTER.weth());
        return FiveFiveFiveValidation.validatePonderPrice(
            ponderKubPair,
            PRICE_ORACLE,
            address(PONDER),
            amount
        );
    }

    /// @notice Fallback function to accept KUB contributions.
    receive() external payable {}
}
