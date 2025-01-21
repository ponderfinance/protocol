// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract MockKYC {
    mapping(address => uint256) public kycLevels;

    /// @notice Sets the KYC level for an address
    function setKYCLevel(address _addr, uint256 _level) external {
        kycLevels[_addr] = _level;
    }

    /// @notice Returns the KYC level for a given address
    function kycsLevel(address _addr) external view returns (uint256) {
        return kycLevels[_addr];
    }
}
