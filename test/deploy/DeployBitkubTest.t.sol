//// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;
//
//import "forge-std/Test.sol";
//import "../../script/deploy/DeployBitkub.sol";
//import "../../src/core/pair/IPonderPair.sol";
//import "../../src/core/factory/IPonderFactory.sol";
//import "../../src/core/token/PonderToken.sol";
//
//contract DeployBitkubTest is Test {
//    DeployBitkubScript public deployerScript;
//    address public constant MOCK_TEAM = address(0x1);
//    address public constant MOCK_MARKETING = address(0x2);
//    address public constant MOCK_KKUB = 0xBa71efd94be63bD47B78eF458DE982fE29f552f7;
//    address public constant MOCK_USDT = 0x7d984C24d2499D840eB3b7016077164e15E5faA6;
//
//    // Events to test
//    event DeploymentStarted(address indexed deployer, uint256 deadline);
//    event ContractDeployed(string indexed name, address indexed addr);
//    event LibraryDeployed(string indexed name, address indexed addr);
//    event LiquidityAdded(uint256 kubAmount, uint256 ponderAmount);
//    event ConfigurationFinalized(
//        address indexed factory,
//        address indexed masterChef,
//        address indexed feeDistributor
//    );
//
//    function setUp() public {
//        // Deploy the script contract
//        deployerScript = new DeployBitkubScript();
//
//        // Setup environment variables
//        vm.etch(MOCK_KKUB, "some code");
//        vm.etch(MOCK_USDT, "some code");
//
//        vm.mockCall(
//            address(vm),
//            abi.encodeWithSignature("envUint(string)", "PRIVATE_KEY"),
//            abi.encode(uint256(1))
//        );
//        vm.mockCall(
//            address(vm),
//            abi.encodeWithSignature("envAddress(string)", "TEAM_RESERVE_ADDRESS"),
//            abi.encode(MOCK_TEAM)
//        );
//        vm.mockCall(
//            address(vm),
//            abi.encodeWithSignature("envAddress(string)", "MARKETING_ADDRESS"),
//            abi.encode(MOCK_MARKETING)
//        );
//
//        // Fund test contract
//        vm.deal(address(this), 1000 ether);
//    }
//
//    // Test successful deployment sequence
//    function testSuccessfulDeployment() public {
//        address deployerAddress = address(this);
//
//        vm.expectEmit(true, true, false, false);
//        emit DeploymentStarted(deployerAddress, block.timestamp + 1 hours);
//
//        // Execute full deployment
//        DeployBitkubScript.DeploymentState memory state = deployerScript.executeDeploy(
//            deployerAddress,
//            MOCK_TEAM,
//            MOCK_MARKETING
//        );
//
//        // Verify core contract deployments
//        assertTrue(state.factory != address(0), "Factory not deployed");
//        assertTrue(state.ponder != address(0), "Ponder not deployed");
//        assertTrue(state.router != address(0), "Router not deployed");
//        assertTrue(state.ponderKubPair != address(0), "Pair not created");
//
//        // Verify that the deployer is set as feeToSetter
//        assertEq(IPonderFactory(state.factory).feeToSetter(), deployerAddress, "Deployer should be feeToSetter");
//    }
//
//    // Test front-running protection
//    function testFrontRunningProtection() public {
//        address attacker = address(0xBad);
//        vm.startPrank(attacker);
//        vm.deal(attacker, 1000 ether);
//
//        // Expect revert when attacker tries to deploy
//        vm.expectRevert("Invalid addresses");
//        deployerScript.executeDeploy(
//            attacker,
//            MOCK_TEAM,
//            MOCK_MARKETING
//        );
//
//        vm.stopPrank();
//    }
//
//    // Test initial liquidity setup
//    function testInitialLiquiditySetup() public {
//        address deployerAddress = address(this);
//        DeployBitkubScript.DeploymentState memory state = deployerScript.executeDeploy(
//            deployerAddress,
//            MOCK_TEAM,
//            MOCK_MARKETING
//        );
//
//        // Verify liquidity was added
//        IPonderPair pair = IPonderPair(state.ponderKubPair);
//        (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
//        assertTrue(reserve0 > 0 && reserve1 > 0, "Liquidity not added");
//    }
//
//    // Test configuration completion
//    function testConfigurationCompletion() public {
//        address deployerAddress = address(this);
//        DeployBitkubScript.DeploymentState memory state = deployerScript.executeDeploy(
//            deployerAddress,
//            MOCK_TEAM,
//            MOCK_MARKETING
//        );
//
//        // Verify permissions are set correctly
//        assertEq(PonderToken(state.ponder).minter(), state.masterChef, "MasterChef not set as minter");
//        assertEq(IPonderFactory(state.factory).feeTo(), state.feeDistributor, "FeeDistributor not set");
//        assertEq(IPonderFactory(state.factory).launcher(), state.launcher, "Launcher not set");
//    }
//
//    // Test invalid address protection
//    function testInvalidAddresses() public {
//        vm.expectRevert("Invalid addresses");
//        deployerScript.executeDeploy(
//            address(0),
//            MOCK_TEAM,
//            MOCK_MARKETING
//        );
//
//        vm.expectRevert("Invalid addresses");
//        deployerScript.executeDeploy(
//            address(this),
//            address(0),
//            MOCK_MARKETING
//        );
//
//        vm.expectRevert("Invalid addresses");
//        deployerScript.executeDeploy(
//            address(this),
//            MOCK_TEAM,
//            address(0)
//        );
//    }
//
//    // Test library deployment and linking
//    function testLibraryDeployment() public {
//        address deployerAddress = address(this);
//
//        vm.expectEmit(true, true, false, false);
//        emit LibraryDeployed("ContributionLib", address(0)); // address will be dynamic
//
//        DeployBitkubScript.DeploymentState memory state = deployerScript.executeDeploy(
//            deployerAddress,
//            MOCK_TEAM,
//            MOCK_MARKETING
//        );
//
//        assertTrue(state.launcher != address(0), "Launcher not deployed with libraries");
//    }
//
//    receive() external payable {}
//}
