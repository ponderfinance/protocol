// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../script/deploy/DeployBitkub.sol";
import "../../script/deploy/IDeployBitkub.sol";
import "../../src/core/pair/IPonderPair.sol";
import "../../src/core/factory/IPonderFactory.sol";

contract DeployBitkubTest is Test {
    DeployBitkubScript public deployerScript;
    address public constant MOCK_TEAM = address(0x1);
    address public constant MOCK_MARKETING = address(0x2);
    address public constant MOCK_ROUTER = address(0x3);
    address public constant MOCK_KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
    address public constant MOCK_USDT = 0x7d984C24d2499D840eB3b7016077164e15E5faA6;

    // Events to test
    event DeploymentStarted(address indexed deployer, uint256 deadline);
    event ContractDeployed(string indexed name, address indexed addr);
    event LiquidityAdded(uint256 kubAmount, uint256 ponderAmount);
    event ConfigurationFinalized(
        address indexed ponder,
        address indexed masterChef,
        address indexed feeDistributor
    );

    function setUp() public {
        // Deploy the script contract
        deployerScript = new DeployBitkubScript();

        // Setup environment variables
        vm.etch(MOCK_KKUB, "some code");
        vm.etch(MOCK_USDT, "some code");

        vm.mockCall(
            address(vm),
            abi.encodeWithSignature("envUint(string)", "PRIVATE_KEY"),
            abi.encode(uint256(1))
        );
        vm.mockCall(
            address(vm),
            abi.encodeWithSignature("envAddress(string)", "TEAM_RESERVE_ADDRESS"),
            abi.encode(MOCK_TEAM)
        );
        vm.mockCall(
            address(vm),
            abi.encodeWithSignature("envAddress(string)", "MARKETING_ADDRESS"),
            abi.encode(MOCK_MARKETING)
        );

        // Fund test contract
        vm.deal(address(this), 1000 ether);
    }

    // Test successful deployment sequence
    function testSuccessfulDeployment() public {
        address deployerAddress = address(this);
        IDeployBitkub.DeployConfig memory config = IDeployBitkub.DeployConfig({
            ponderPerSecond: 3168000000000000000,
            initialKubAmount: 1000 ether,
            liquidityAllocation: 200_000_000 ether,
            deploymentDeadline: block.timestamp + 5 minutes,
            liquidityDeadline: block.timestamp + 2 minutes
        });

        // Deploy core contracts
        IDeployBitkub.DeploymentState memory state = deployerScript.deployCore(
            deployerAddress,
            MOCK_TEAM,
            MOCK_MARKETING,
            config
        );

        // Verify core contract deployments
        assertTrue(address(state.factory) != address(0), "Factory not deployed");
        assertTrue(address(state.ponder) != address(0), "Ponder not deployed");
        assertTrue(address(state.router) != address(0), "Router not deployed");
        assertTrue(state.ponderKubPair != address(0), "Pair not created");

        // Verify that the deployer is set as feeToSetter
        assertEq(IPonderFactory(state.factory).feeToSetter(), deployerAddress, "Deployer should be feeToSetter");
    }

    // Test front-running protection
    function testFrontRunningProtection() public {
        address attacker = address(0xBad);
        vm.startPrank(attacker);
        vm.deal(attacker, 1000 ether);

        IDeployBitkub.DeployConfig memory config = IDeployBitkub.DeployConfig({
            ponderPerSecond: 3168000000000000000,
            initialKubAmount: 1000 ether,
            liquidityAllocation: 200_000_000 ether,
            deploymentDeadline: block.timestamp + 5 minutes,
            liquidityDeadline: block.timestamp + 2 minutes
        });

        // Deploy core first with legitimate deployer
        IDeployBitkub.DeploymentState memory state = deployerScript.deployCore(
            address(this),
            MOCK_TEAM,
            MOCK_MARKETING,
            config
        );

        // Attacker tries to call finalizeConfiguration
        vm.expectRevert(abi.encodeWithSignature("Forbidden()"));
        deployerScript.finalizeConfiguration(state, attacker, config);

        vm.stopPrank();
    }

    // Test deadline protection
    function testDeploymentDeadline() public {
        IDeployBitkub.DeployConfig memory config = IDeployBitkub.DeployConfig({
            ponderPerSecond: 3168000000000000000,
            initialKubAmount: 1000 ether,
            liquidityAllocation: 200_000_000 ether,
            deploymentDeadline: block.timestamp + 5 minutes,
            liquidityDeadline: block.timestamp + 2 minutes
        });

        // Warp time beyond deadline
        vm.warp(block.timestamp + 6 minutes);

        // Expect revert on deployment
        vm.expectRevert("DeploymentDeadlineExceeded()");
        deployerScript.deployCore(
            address(this),
            MOCK_TEAM,
            MOCK_MARKETING,
            config
        );
    }

    // Test liquidity addition protection
    function testLiquidityAdditionProtection() public {
        IDeployBitkub.DeployConfig memory config = IDeployBitkub.DeployConfig({
            ponderPerSecond: 3168000000000000000,
            initialKubAmount: 1000 ether,
            liquidityAllocation: 200_000_000 ether,
            deploymentDeadline: block.timestamp + 5 minutes,
            liquidityDeadline: block.timestamp + 2 minutes
        });

        // Deploy core contracts
        IDeployBitkub.DeploymentState memory state = deployerScript.deployCore(
            address(this),
            MOCK_TEAM,
            MOCK_MARKETING,
            config
        );

        // Warp time beyond liquidity deadline
        vm.warp(block.timestamp + 3 minutes);

        // Expect revert on liquidity addition
        vm.expectRevert("LiquidityDeadlineExceeded()");
        deployerScript.setupInitialPrices(state, config);
    }

    // Test configuration failures
    function testConfigurationFailures() public {
        address deployerAddress = address(this);
        IDeployBitkub.DeployConfig memory config = IDeployBitkub.DeployConfig({
            ponderPerSecond: 3168000000000000000,
            initialKubAmount: 1000 ether,
            liquidityAllocation: 200_000_000 ether,
            deploymentDeadline: block.timestamp + 5 minutes,
            liquidityDeadline: block.timestamp + 2 minutes
        });

        // Deploy core contracts
        IDeployBitkub.DeploymentState memory state = deployerScript.deployCore(
            deployerAddress,
            MOCK_TEAM,
            MOCK_MARKETING,
            config
        );

        // Mock calls to revert
        vm.mockCall(
            state.ponder,
            abi.encodeWithSelector(PonderToken.setMinter.selector),
            "SetMinterFailed"
        );

        // Expect the revert to bubble up
        vm.expectRevert(abi.encodeWithSignature("Forbidden()"));
        deployerScript.finalizeConfiguration(state, deployerAddress, config);
    }

    // Test invalid address protection
    function testInvalidAddressProtection() public {
        vm.expectRevert("InvalidAddress()");
        deployerScript.validateAddresses(address(0), MOCK_MARKETING, address(this));

        vm.expectRevert("InvalidAddress()");
        deployerScript.validateAddresses(MOCK_TEAM, address(0), address(this));

        vm.expectRevert("InvalidAddress()");
        deployerScript.validateAddresses(MOCK_TEAM, MOCK_MARKETING, address(0));
    }

    // Test contract verification
    function testContractVerification() public {
        address mockContract = address(0x123);

        // Expect revert when contract has no code
        vm.expectRevert("DeploymentFailed()");
        deployerScript.verifyContract("MockContract", mockContract);

        // Add code to the mock contract
        vm.etch(mockContract, "some code");

        // Should not revert when contract has code
        deployerScript.verifyContract("MockContract", mockContract);
    }
}
