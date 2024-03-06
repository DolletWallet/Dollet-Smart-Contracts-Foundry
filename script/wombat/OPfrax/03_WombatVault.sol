// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { WombatStrategy } from "src/strategies/wombat/WombatStrategy.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { FeeManager, IFeeManager } from "src/FeeManager.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { Script, console } from "forge-std/Script.sol";
import "addresses/OPMainnet.sol";

contract WombatVaultScript is Script {
    address[] public allowedTokens = [USDC];
    uint256[] public limits = [10e6];

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyAddress = payable(vm.envAddress("WS_STRATEGY"));
        FeeManager feeManager = FeeManager(vm.envAddress("WS_FEE_MANAGER"));

        IVault.DepositLimit[] memory depositLimits = new IVault.DepositLimit[](limits.length);

        for (uint256 i; i < limits.length; ++i) {
            depositLimits[i] = IVault.DepositLimit(allowedTokens[i], limits[i]);
        }

        address wombatVaultImplementationAddress = address(new CompoundVault());
        console.log("WombatVaultImplementation deployed at: ", wombatVaultImplementationAddress);

        address wombatVaultProxyAddress = address(
            new Proxy(
                wombatVaultImplementationAddress,
                vm.envAddress("WS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                    vm.envAddress("WS_ADMIN_STRUCTURE"),
                    strategyAddress,
                    WETH,
                    vm.envAddress("WS_CALCULATIONS"),
                    allowedTokens,
                    allowedTokens,
                    depositLimits
                )
            )
        );
        CompoundVault vault = CompoundVault(wombatVaultProxyAddress);
        console.log("WombatVaultProxy deployed at:", address(vault));

        WombatStrategy(payable(strategyAddress)).setVault(address(vault));

        feeManager.setFee(
            strategyAddress,
            IFeeManager.FeeType.MANAGEMENT,
            vm.envAddress("WS_MANAGEMENT_FEE_RECIPIENT"),
            uint16(vm.envUint("WS_MANAGEMENT_FEE_PERCENTAGE"))
        );
        feeManager.setFee(
            strategyAddress,
            IFeeManager.FeeType.PERFORMANCE,
            vm.envAddress("WS_PERFORMANCE_FEE_RECIPIENT"),
            uint16(vm.envUint("WS_PERFORMANCE_FEE_PERCENTAGE"))
        );

        vm.stopBroadcast();
    }
}
