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
import { SetupLib } from "./libraries/SetupLib.sol";
import { FundsLib } from "./libraries/FundsLib.sol";
import { LiquidityLib } from "./libraries/LiquidityLib.sol";

/// @title FiveFiveFiveLauncher
/// @author taayyohh
/// @notice Main contract for managing token launches in the Ponder ecosystem
/// @dev Handles launch creation, contributions, refunds, and liquidity management
contract FiveFiveFiveLauncher is
    IFiveFiveFiveLauncher,
    FiveFiveFiveLauncherStorage,
    ReentrancyGuard
{
    using FiveFiveFiveLauncherTypes for FiveFiveFiveLauncherTypes.LaunchInfo;
    using SetupLib for FiveFiveFiveLauncherTypes.LaunchInfo;
    using FundsLib for FiveFiveFiveLauncherTypes.LaunchInfo;
    using LiquidityLib for FiveFiveFiveLauncherTypes.LaunchInfo;

    /*//////////////////////////////////////////////////////////////
                            IMMUTABLE STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Factory contract for creating pairs
    IPonderFactory public immutable FACTORY;

    /// @notice Router contract for liquidity operations
    IPonderRouter public immutable ROUTER;

    /// @notice PONDER token contract
    PonderToken public immutable PONDER;

    /// @notice Oracle for PONDER price data
    PonderPriceOracle public immutable PRICE_ORACLE;

    /// @notice Address with administrative privileges
    address public immutable owner;

    /// @notice Address that receives protocol fees
    address public immutable feeCollector;


    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the launcher with core protocol dependencies
    /// @param _factory Address of the Ponder factory contract
    /// @param _router Address of the Ponder router contract
    /// @param _feeCollector Address that collects protocol fees
    /// @param _ponder Address of the PONDER token
    /// @param _priceOracle Address of the price oracle
    /// @dev All addresses must be non-zero
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
        ) revert IFiveFiveFiveLauncher.ZeroAddress();

        FACTORY = IPonderFactory(_factory);
        ROUTER = IPonderRouter(_router);
        PONDER = PonderToken(_ponder);
        PRICE_ORACLE = PonderPriceOracle(_priceOracle);
        feeCollector = _feeCollector;
        owner = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////
                            LAUNCH CREATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new token launch
    /// @param params Struct containing launch parameters
    /// @return launchId Unique identifier for the created launch
    /// @dev Validates parameters and initializes launch state
    function createLaunch(
        FiveFiveFiveLauncherTypes.LaunchParams calldata params
    ) external returns (uint256 launchId) {
        SetupLib.validateTokenParams(
            params.name,
            params.symbol,
            usedNames,
            usedSymbols
        );

        launchId = launchCount++;
        usedNames[params.name] = true;
        usedSymbols[params.symbol] = true;

        address token = launches[launchId].initializeLaunch(
            params,
            msg.sender,
            FACTORY,
            ROUTER,
            PONDER,
            address(this)
        );

        emit LaunchCreated(launchId, token, msg.sender, params.imageURI);
    }

    /*//////////////////////////////////////////////////////////////
                            CONTRIBUTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Contribute KUB to a launch
    /// @param launchId ID of the launch to contribute to
    /// @dev Amount is determined by msg.value
    function contributeKUB(uint256 launchId) external payable nonReentrant {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];
        SetupLib.validateLaunchState(launch);

        bool shouldFinalize = FundsLib.processKubContribution(
            launch,
            launchId,
            msg.value,
            msg.sender
        );

        if (shouldFinalize) {
            LiquidityLib.finalizeLaunch(
                launch,
                launchId,
                FACTORY,
                ROUTER,
                PONDER,
                PRICE_ORACLE
            );
        }
    }

    /// @notice Contribute PONDER tokens to a launch
    /// @param launchId ID of the launch to contribute to
    /// @param amount Amount of PONDER tokens to contribute
    /// @dev Requires prior approval of PONDER tokens
    function contributePONDER(uint256 launchId, uint256 amount) external nonReentrant {
        FiveFiveFiveLauncherTypes.LaunchInfo storage launch = launches[launchId];
        SetupLib.validateLaunchState(launch);

        FiveFiveFiveLauncherTypes.ContributionContext memory context = FiveFiveFiveLauncherTypes.ContributionContext({
                ponderAmount: amount,
                tokensToDistribute: 0,
                priceInfo: FiveFiveFiveLauncherTypes.PonderPriceInfo({
                spotPrice: 0,
                twapPrice: 0,
                kubValue: 0,
                validatedAt: 0,
                isValidated: false
            })
        });

        bool shouldFinalize = FundsLib.processPonderContribution(
            launch,
            launchId,
            context,
            msg.sender,
            PONDER,
            FACTORY,
            ROUTER,
            PRICE_ORACLE
        );

        if (shouldFinalize) {
            LiquidityLib.finalizeLaunch(
                launch,
                launchId,
                FACTORY,
                ROUTER,
                PONDER,
                PRICE_ORACLE
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        REFUNDS AND CANCELLATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim refund for a failed or cancelled launch
    /// @param launchId ID of the launch to claim refund from
    /// @dev Returns both KUB and PONDER contributions
    function claimRefund(uint256 launchId) external nonReentrant {
        FundsLib.processRefund(
            launches[launchId],
            msg.sender,
            PONDER
        );
    }

    /// @notice Cancel a launch
    /// @param launchId ID of the launch to cancel
    /// @dev Only callable by launch creator before deadline
    function cancelLaunch(uint256 launchId) external {
        FundsLib.processLaunchCancellation(
            launches[launchId],
            launchId,
            msg.sender,
            usedNames,
            usedSymbols
        );
    }

    /// @notice Withdraw LP tokens from a completed launch
    /// @param launchId ID of the launch to withdraw LP tokens from
    /// @dev Only callable by launch creator after lock period
    function withdrawLP(uint256 launchId) external {
        FundsLib.processLPWithdrawal(
            launches[launchId],
            launchId,
            msg.sender
        );
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get contributor information for a launch
    /// @param launchId ID of the launch
    /// @param contributor Address of the contributor
    /// @return kubContributed Amount of KUB contributed
    /// @return ponderContributed Amount of PONDER contributed
    /// @return ponderValue KUB value of PONDER contribution
    /// @return tokensReceived Amount of launch tokens received
    function getContributorInfo(uint256 launchId, address contributor)
    external
    view
    returns (
        uint256 kubContributed,
        uint256 ponderContributed,
        uint256 ponderValue,
        uint256 tokensReceived
    )
    {
        return LiquidityLib.getContributorInfo(launches[launchId], contributor);
    }

    /// @notice Get overall contribution information for a launch
    /// @param launchId ID of the launch
    function getContributionInfo(uint256 launchId)
    external
    view
    returns (
        uint256 kubCollected,
        uint256 ponderCollected,
        uint256 ponderValueCollected,
        uint256 totalValue
    )
    {
        return LiquidityLib.getContributionInfo(launches[launchId]);
    }

    /// @notice Get pool information for a launch
    /// @param launchId ID of the launch
    function getPoolInfo(uint256 launchId)
    external
    view
    returns (
        address memeKubPair,
        address memePonderPair,
        bool hasSecondaryPool
    )
    {
        return LiquidityLib.getPoolInfo(launches[launchId]);
    }

    /// @notice Get basic information about a launch
    /// @param launchId ID of the launch
    function getLaunchInfo(uint256 launchId)
    external
    view
    returns (
        address tokenAddress,
        string memory name,
        string memory symbol,
        string memory imageURI,
        uint256 kubRaised,
        bool launched,
        uint256 lpUnlockTime
    )
    {
        return LiquidityLib.getLaunchInfo(launches[launchId]);
    }

    /// @notice Get minimum requirements for contributions and liquidity
    function getMinimumRequirements()
    external
    pure
    returns (
        uint256 minKub,
        uint256 minPonder,
        uint256 minPoolLiquidity
    )
    {
        return LiquidityLib.getMinimumRequirements();
    }

    /// @notice Get remaining amounts that can be raised
    /// @param launchId ID of the launch
    function getRemainingToRaise(uint256 launchId)
    external
    view
    returns (
        uint256 remainingTotal,
        uint256 remainingPonderValue
    )
    {
        return LiquidityLib.getRemainingToRaise(launches[launchId]);
    }

    /// @notice Get the launch deadline timestamp
    /// @param launchId ID of the launch
    /// @return The launch deadline as uint40
    function getLaunchDeadline(uint256 launchId) external view returns (uint40) {
        return launches[launchId].base.launchDeadline;
    }

    /// @notice Accept KUB payments
    /// @dev Required to receive KUB for liquidity
    receive() external payable {}
}
