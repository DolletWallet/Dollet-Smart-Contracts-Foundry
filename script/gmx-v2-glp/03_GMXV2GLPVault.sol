// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { GMXV2GLPStrategy } from "../../src/strategies/gmx-v2/GMXV2GLPStrategy.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { CompoundVault } from "../../src/vaults/CompoundVault.sol";
import { FeeManager, IFeeManager } from "../../src/FeeManager.sol";
import { IVault } from "../../src/interfaces/dollet/IVault.sol";
import { Script, console } from "forge-std/Script.sol";
import "../../addresses/AVAXMainnet.sol";

contract GMXV2GLPVaultScript is Script {
    address[] public allowedTokens = [AVAX, WAVAX, WETHe, BTCb, WBTCe, USDC, USDCe];
    uint256[] public limits = [2.7e17, 2.7e17, 638e13, 38e3, 38e3, 10e6, 10e6];

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyAddress = payable(vm.envAddress("GMXV2GLPS_STRATEGY"));
        FeeManager feeManager = FeeManager(vm.envAddress("GMXV2GLPS_FEE_MANAGER"));

        IVault.DepositLimit[] memory depositLimits = new IVault.DepositLimit[](limits.length);

        for (uint256 i; i < limits.length; ++i) {
            depositLimits[i] = IVault.DepositLimit(allowedTokens[i], limits[i]);
        }

        address GMXV2GLPVaultImplementationAddress = address(new CompoundVault());
        console.log("GMXV2GLPVaultImplementation deployed at: ", GMXV2GLPVaultImplementationAddress);

        address GMXV2GLPVaultProxyAddress = address(
            new Proxy(
                GMXV2GLPVaultImplementationAddress,
                vm.envAddress("GMXV2GLPS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                    vm.envAddress("GMXV2GLPS_ADMIN_STRUCTURE"),
                    strategyAddress,
                    WAVAX,
                    vm.envAddress("GMXV2GLPS_CALCULATIONS"),
                    allowedTokens,
                    allowedTokens,
                    depositLimits
                )
            )
        );
        CompoundVault vault = CompoundVault(GMXV2GLPVaultProxyAddress);
        console.log("GMXV2GLPVaultProxy deployed at:", address(vault));

        GMXV2GLPStrategy(payable(strategyAddress)).setVault(address(vault));

        feeManager.setFee(
            strategyAddress,
            IFeeManager.FeeType.MANAGEMENT,
            vm.envAddress("GMXV2GLPS_MANAGEMENT_FEE_RECIPIENT"),
            uint16(vm.envUint("GMXV2GLPS_MANAGEMENT_FEE_PERCENTAGE"))
        );
        feeManager.setFee(
            strategyAddress,
            IFeeManager.FeeType.PERFORMANCE,
            vm.envAddress("GMXV2GLPS_PERFORMANCE_FEE_RECIPIENT"),
            uint16(vm.envUint("GMXV2GLPS_PERFORMANCE_FEE_PERCENTAGE"))
        );

        vm.stopBroadcast();
    }
}
