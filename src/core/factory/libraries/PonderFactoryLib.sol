// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IPonderFactory } from "../IPonderFactory.sol";

library PonderFactoryLib {
    function handleAddressUpdate(
        address sender,
        address currentAdmin,
        address newValue
    ) internal pure returns (bool) {
        verifyAccess(sender, currentAdmin);
        validateAddress(newValue);
        return true;
    }


    function validateConstructorParams(
        address feeToSetter_,
        address ponder_
    ) internal pure {
        validateAddress(feeToSetter_);
        validateAddress(ponder_);
    }

    function validateAddress(address addr) internal pure {
        if (addr == address(0)) revert IPonderFactory.ZeroAddress();
    }

    function validateFeeTo(address addr) internal pure {
        if (addr == address(0)) revert IPonderFactory.InvalidFeeReceiver();
    }

    function validateLauncher(address addr) internal pure {
        if (addr == address(0)) revert IPonderFactory.InvalidLauncher();
    }

    function verifyAccess(address sender, address feeToSetter) internal pure {
        if (sender != feeToSetter) revert IPonderFactory.Forbidden();
    }
}
