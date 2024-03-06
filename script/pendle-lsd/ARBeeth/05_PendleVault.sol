// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { PendleeETHStrategy } from "src/strategies/pendle/PendleeETHStrategy.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ETH, WETH } from "addresses/ARBMainnet.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { FeeManager, IFeeManager } from "src/FeeManager.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { Script, console } from "forge-std/Script.sol";

contract PendleLSDVaultScript is Script {
    uint256 private constant ETH_DEPOSIT_LIMIT = 5e15; // 10 USD approximately
    uint256 private constant WETH_DEPOSIT_LIMIT = 5e15; // 10 USD approximately

    address[] private depositAllowedTokens;
    address[] private withdrawalAllowedTokens;

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address pendleStrategyAddress = payable(vm.envAddress("PLSDS_STRATEGY"));
        FeeManager feeManager = FeeManager(vm.envAddress("PLSDS_FEE_MANAGER"));

        depositAllowedTokens = [ETH, WETH];
        withdrawalAllowedTokens = [ETH, WETH];

        IVault.DepositLimit[] memory depositLimits = new IVault.DepositLimit[](2);
        depositLimits[0] = IVault.DepositLimit(ETH, ETH_DEPOSIT_LIMIT);
        depositLimits[1] = IVault.DepositLimit(WETH, WETH_DEPOSIT_LIMIT);

        address pendleVaultImplementationAddress = address(new CompoundVault());
        console.log("PendleLSDVaultImplementation deployed at: ", pendleVaultImplementationAddress);

        address pendleVaultProxyAddress = address(
            new Proxy(
                pendleVaultImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
                    pendleStrategyAddress,
                    WETH,
                    vm.envAddress("PLSDS_CALCULATIONS"),
                    depositAllowedTokens,
                    withdrawalAllowedTokens,
                    depositLimits
                )
            )
        );
        CompoundVault pendleVault = CompoundVault(pendleVaultProxyAddress);
        console.log("PendleLSDVaultProxy deployed at:", address(pendleVault));

        PendleeETHStrategy(payable(pendleStrategyAddress)).setVault(address(pendleVault));

        feeManager.setFee(
            pendleStrategyAddress,
            IFeeManager.FeeType.MANAGEMENT,
            vm.envAddress("PLSDS_MANAGEMENT_FEE_RECIPIENT"),
            uint16(vm.envUint("PLSDS_MANAGEMENT_FEE_PERCENTAGE"))
        );
        feeManager.setFee(
            pendleStrategyAddress,
            IFeeManager.FeeType.PERFORMANCE,
            vm.envAddress("PLSDS_PERFORMANCE_FEE_RECIPIENT"),
            uint16(vm.envUint("PLSDS_PERFORMANCE_FEE_PERCENTAGE"))
        );

        vm.stopBroadcast();
    }
}
