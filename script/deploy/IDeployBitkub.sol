// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/masterchef/PonderMasterChef.sol";
import "../../src/core/oracle/PonderPriceOracle.sol";
import "../../src/core/token/PonderToken.sol";
import "../../src/core/staking/PonderStaking.sol";
import "../../src/core/distributor/FeeDistributor.sol";
import "../../src/launch/FiveFiveFiveLauncher.sol";
import "../../src/periphery/unwrapper/KKUBUnwrapper.sol";
import "../../src/periphery/router/PonderRouter.sol";

interface IDeployBitkubScript {
    struct DeployConfig {
        uint256 ponderPerSecond;
        uint256 initialKubAmount;
        uint256 liquidityAllocation;
        uint256 deploymentDeadline;
        uint256 liquidityDeadline;
    }

    struct DeploymentState {
        address deployer;
        address teamReserve;
        address marketing;
        PonderToken ponder;
        PonderFactory factory;
        KKUBUnwrapper kkubUnwrapper;
        PonderRouter router;
        PonderPriceOracle oracle;
        address ponderKubPair;
        PonderMasterChef masterChef;
        FiveFiveFiveLauncher launcher;
        PonderStaking staking;
        FeeDistributor feeDistributor;
    }

    function deployCore(
        address deployer,
        address teamReserve,
        address marketing,
        DeployConfig memory config
    ) external returns (DeploymentState memory);

    function setupInitialPrices(
        DeploymentState memory state,
        DeployConfig memory config
    ) external;

    function finalizeConfiguration(
        DeploymentState memory state,
        address deployer,
        DeployConfig memory config
    ) external;

    function validateAddresses(
        address teamReserve,
        address marketing,
        address deployer
    ) external pure;

    function verifyContract(string memory name, address contractAddress) external view;
}
