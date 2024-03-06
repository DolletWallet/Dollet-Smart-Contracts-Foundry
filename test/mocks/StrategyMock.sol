// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IVault } from "../../src/interfaces/dollet/IVault.sol";
import { Signature } from "../../src/libraries/ERC20Lib.sol";

/**
 * @title Mock implementation of a Strategy
 * @author Dollet Team
 * @notice This contract it is used to simulate functions of the strategy contracts.
 * @dev This contract is used for testing purposes only, it won't be used for production.
 * @dev The contract allows to modifiy different values without access control just for ease of use.
 */
contract StrategyMock {
    IVault public vault;
    Target public target;

    enum Target {
        None,
        Deposit,
        DepositWithPermit,
        Withdraw
    }

    function setVault(address newVault) external {
        vault = IVault(newVault);
    }

    function setTarget(Target newTarget) external {
        target = newTarget;
    }

    function compound(bytes calldata) external {
        if (target != Target.Deposit) {
            vault.deposit(address(0), address(0), uint256(0), hex"");
            return;
        }

        if (target != Target.DepositWithPermit) {
            vault.depositWithPermit(address(0), address(0), uint256(0), hex"", (new Signature[](1))[0]);

            return;
        }

        if (target != Target.Withdraw) {
            vault.withdraw(address(0), address(0), uint256(0), hex"");

            return;
        }
    }
}
