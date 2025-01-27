// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../src/core/factory/PonderFactory.sol";
import "../../src/core/pair/PonderPair.sol";
import "../../src/periphery/router/PonderRouter.sol";
import "../mocks/ERC20Mint.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "../mocks/WETH9.sol";
import "forge-std/Test.sol";

contract PonderSecurityTest is Test {
    PonderFactory factory;
    PonderRouter router;
    PonderPair pair;
    ERC20Mint tokenA;
    ERC20Mint tokenB;
    WETH9 weth;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant INITIAL_LIQUIDITY = 100_000e18;

    function setUp() public {
        // Deploy core contracts
        weth = new WETH9();
        factory = new PonderFactory(address(this), address(1), address(2));
        MockKKUBUnwrapper unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(address(factory), address(weth), address(unwrapper));

        // Deploy tokens
        tokenA = new ERC20Mint("Token A", "TKNA");
        tokenB = new ERC20Mint("Token B", "TKNB");

        // Create pair
        address pairAddress = factory.createPair(address(tokenA), address(tokenB));
        pair = PonderPair(pairAddress);

        // Setup initial state
        vm.startPrank(alice);
        vm.deal(alice, 100 ether);
        vm.stopPrank();
    }

    function testInvalidTokenTransferProtection() public {
        vm.startPrank(alice);

        // Deploy malicious token
        MaliciousToken malToken = new MaliciousToken();

        // Try to add liquidity with malicious token
        vm.expectRevert(abi.encodeWithSignature("SafeERC20FailedOperation(address)", address(malToken)));
        router.addLiquidity(
            address(malToken),
            address(tokenB),
            1e18,
            1e18,
            0,
            0,
            alice,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testSlippageProtection() public {
        vm.startPrank(alice);

        _setupInitialLiquidity();

        uint256 swapAmount = 10e18;
        tokenA.mint(alice, swapAmount);
        tokenA.approve(address(router), swapAmount);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(tokenB);

        bytes4 selector = bytes4(keccak256("InsufficientOutputAmount()"));
        vm.expectRevert(selector);
        router.swapExactTokensForTokens(
            swapAmount,
            type(uint256).max, // Impossible to meet
            path,
            alice,
            block.timestamp
        );

        vm.stopPrank();
    }

    function testReentrancyProtection() public {
        vm.startPrank(alice);

        // Setup initial liquidity
        _setupInitialLiquidity();

        // Deploy attacker
        ReentrantAttacker attacker = new ReentrantAttacker(address(pair));

        // Fund attacker
        tokenA.mint(address(attacker), 10e18);
        tokenB.mint(address(attacker), 10e18);

        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSignature("ReentrancyGuardReentrantCall()"));
        attacker.executeAttack();
    }

    function testOwnershipProtection() public {
        // Try to set fee recipient without being owner
        vm.startPrank(alice);

        bytes4 selector = bytes4(keccak256("Forbidden()"));
        vm.expectRevert(selector);
        factory.setFeeTo(alice);

        // Try to change fee setter
        vm.expectRevert(selector);
        factory.setFeeToSetter(alice);

        vm.stopPrank();
    }
    // Helper function
    function _setupInitialLiquidity() internal {
        tokenA.mint(alice, INITIAL_LIQUIDITY);
        tokenB.mint(alice, INITIAL_LIQUIDITY);
        tokenA.approve(address(router), INITIAL_LIQUIDITY);
        tokenB.approve(address(router), INITIAL_LIQUIDITY);
        router.addLiquidity(
            address(tokenA),
            address(tokenB),
            INITIAL_LIQUIDITY,
            INITIAL_LIQUIDITY,
            0,
            0,
            alice,
            block.timestamp
        );
    }
}

contract ReentrantAttacker is IPonderCallee {
    PonderPair immutable pair;
    bool public attacking;

    constructor(address _pair) {
        pair = PonderPair(_pair);
    }

    function executeAttack() external {
        // Start with a swap that will trigger our callback
        attacking = true;
        pair.swap(1e18, 0, address(this), "trigger reentrancy");
    }

    // This callback will be invoked during the swap
    function ponderCall(
        address sender,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        // Try to call a function with the lock modifier while we're already in a locked state
        if (attacking) {
            // Call sync which has the lock modifier
            pair.sync();
        }
    }

    // Add these functions to handle token operations
    function transfer(address to, uint256 amount) external returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return true;
    }

    receive() external payable {}
}

contract MaliciousToken {
    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}
