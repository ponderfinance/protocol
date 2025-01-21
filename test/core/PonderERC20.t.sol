// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import "../mocks/PonderERC20Test.sol";

contract PonderERC20Test is Test {
    TestPonderERC20 token;
    address alice = address(0x1);
    address bob = address(0x2);
    uint256 constant INITIAL_SUPPLY = 1000e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new TestPonderERC20();
    }

    function testMetadata() public {
        assertEq(token.name(), "Ponder LP Token");
        assertEq(token.symbol(), "PONDER-LP");
        assertEq(token.decimals(), 18);
    }

    function testMintAndBurn() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), alice, INITIAL_SUPPLY);
        token.mint(alice, INITIAL_SUPPLY);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY);

        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, address(0), INITIAL_SUPPLY);
        token.burn(alice, INITIAL_SUPPLY);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(alice), 0);
    }

    function testApprove() public {
        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 100);
        assertTrue(token.approve(bob, 100));
        assertEq(token.allowance(alice, bob), 100);
    }

    function testTransfer() public {
        token.mint(alice, INITIAL_SUPPLY);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 100);
        assertTrue(token.transfer(bob, 100));
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 100);
        assertEq(token.balanceOf(bob), 100);
    }

    function testTransferFrom() public {
        token.mint(alice, INITIAL_SUPPLY);

        vm.prank(alice);
        token.approve(bob, 100);

        vm.prank(bob);
        vm.expectEmit(true, true, true, true);
        emit Transfer(alice, bob, 50);
        assertTrue(token.transferFrom(alice, bob, 50));
        assertEq(token.allowance(alice, bob), 50);
        assertEq(token.balanceOf(alice), INITIAL_SUPPLY - 50);
        assertEq(token.balanceOf(bob), 50);
    }

    function testPermit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.domainSeparator(),
                    keccak256(
                        abi.encode(
                            token.PERMIT_TYPEHASH(),
                            owner,
                            bob,
                            100,
                            0,
                            block.timestamp
                        )
                    )
                )
            )
        );

        token.permit(owner, bob, 100, block.timestamp, v, r, s);
        assertEq(token.allowance(owner, bob), 100);
        assertEq(token.nonces(owner), 1);
    }

    function testFailTransferInsufficientBalance() public {
        token.mint(alice, INITIAL_SUPPLY);
        vm.prank(alice);
        token.transfer(bob, INITIAL_SUPPLY + 1);
    }

    function testFailTransferFromInsufficientAllowance() public {
        token.mint(alice, INITIAL_SUPPLY);
        vm.prank(alice);
        token.approve(bob, 50);
        vm.prank(bob);
        token.transferFrom(alice, bob, 100);
    }

    function testFailPermitExpired() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    token.domainSeparator(),
                    keccak256(
                        abi.encode(
                            token.PERMIT_TYPEHASH(),
                            owner,
                            bob,
                            100,
                            0,
                            block.timestamp - 1
                        )
                    )
                )
            )
        );

        token.permit(owner, bob, 100, block.timestamp - 1, v, r, s);
    }

    function testFailMintToZero() public {
        token.mint(address(0), 100);
    }

    function testFailBurnFromZero() public {
        token.burn(address(0), 100);
    }
}
