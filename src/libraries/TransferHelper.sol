// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library TransferHelper {
    error ApprovalFailed();
    error TransferFailed();
    error TransferFromFailed();
    error ETHTransferFailed();

    function safeApprove(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert ApprovalFailed();
        }
    }

    function safeTransfer(address token, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFailed();
        }
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        if (!success || (data.length != 0 && !abi.decode(data, (bool)))) {
            revert TransferFromFailed();
        }
    }

    function safeTransferETH(address to, uint256 value) internal {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = to.call{value: value}(new bytes(0));
        if (!success) {
            revert ETHTransferFailed();
        }
    }
}
