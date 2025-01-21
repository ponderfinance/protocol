// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IDeployBitkub {
    // Structs for deployment configuration and state
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
        address ponder;
        address factory;
        address kkubUnwrapper;
        address router;
        address oracle;
        address staking;
        address feeDistributor;
        address launcher;
        address masterChef;
        address ponderKubPair;
        uint256 deploymentStartTime;
        bool initialized;
    }

    // Functions that need to be exposed for testing
    function deployCore(
        address deployer,
        address teamReserve,
        address marketing,
        DeployConfig calldata config
    ) external returns (DeploymentState memory);

    function setupInitialPrices(
        DeploymentState memory state,
        DeployConfig calldata config
    ) external;

    function finalizeConfiguration(
        DeploymentState memory state,
        address deployer,
        DeployConfig calldata config
    ) external;

    function validateAddresses(
        address teamReserve,
        address marketing,
        address deployer
    ) external pure;

    function verifyContract(
        string memory name,
        address contractAddress
    ) external view;
}
