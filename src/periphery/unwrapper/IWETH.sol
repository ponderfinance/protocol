// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}
