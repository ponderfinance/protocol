// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface ILaunchToken {
    function initialize(string memory _name, string memory _symbol, uint256 totalSupply, address _launcher) external;
    function setupVesting(address _creator, uint256 _amount) external;
    function enableTransfers() external;
    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);

    function creator() external view returns (address);
    function launcher() external view returns (address);
    function isLaunchToken() external view returns (bool);

}
