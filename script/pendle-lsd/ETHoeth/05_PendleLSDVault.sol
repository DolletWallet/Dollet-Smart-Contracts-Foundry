// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { PendleLSDStrategy } from "src/strategies/pendle/PendleLSDStrategy.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ETH, WETH, USDC, USDT, WBTC } from "addresses/ETHMainnet.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { FeeManager, IFeeManager } from "src/FeeManager.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { Script, console } from "forge-std/Script.sol";

contract PendleLSDVaultScript is Script {
    uint256 constant USDC_DEPOSIT_LIMIT = 10e6;
    uint256 constant USDT_DEPOSIT_LIMIT = 10e6;
    uint256 constant WBTC_DEPOSIT_LIMIT = 0.00038e8; // 10 USD approximately
    uint256 constant ETH_DEPOSIT_LIMIT = 0.0045e18; // 10 USD approximately

    address[] private depositAllowedTokens;
    address[] private withdrawalAllowedTokens;

    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address pendleLSDStrategyAddress = payable(vm.envAddress("PLSDS_STRATEGY"));
        FeeManager feeManager = FeeManager(vm.envAddress("PLSDS_FEE_MANAGER"));

        depositAllowedTokens = [ETH, WBTC, USDC, USDT];
        withdrawalAllowedTokens = [ETH, WBTC, USDC, USDT];

        IVault.DepositLimit[] memory depositLimits = new IVault.DepositLimit[](4);
        depositLimits[0] = IVault.DepositLimit(USDC, USDC_DEPOSIT_LIMIT);
        depositLimits[1] = IVault.DepositLimit(USDT, USDT_DEPOSIT_LIMIT);
        depositLimits[2] = IVault.DepositLimit(WBTC, WBTC_DEPOSIT_LIMIT);
        depositLimits[3] = IVault.DepositLimit(ETH, ETH_DEPOSIT_LIMIT);

        address pendleLSDVaultImplementationAddress = address(new CompoundVault());
        console.log("PendleLSDVaultImplementation deployed at: ", pendleLSDVaultImplementationAddress);

        address pendleLSDVaultProxyAddress = address(
            new Proxy(
                pendleLSDVaultImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
                    pendleLSDStrategyAddress,
                    WETH,
                    vm.envAddress("PLSDS_CALCULATIONS"),
                    depositAllowedTokens,
                    withdrawalAllowedTokens,
                    depositLimits
                )
            )
        );
        CompoundVault pendleLSDVault = CompoundVault(pendleLSDVaultProxyAddress);
        console.log("PendleLSDVaultProxy deployed at:", address(pendleLSDVault));

        PendleLSDStrategy(payable(pendleLSDStrategyAddress)).setVault(address(pendleLSDVault));

        feeManager.setFee(
            pendleLSDStrategyAddress,
            IFeeManager.FeeType.MANAGEMENT,
            vm.envAddress("PLSDS_MANAGEMENT_FEE_RECIPIENT"),
            uint16(vm.envUint("PLSDS_MANAGEMENT_FEE_PERCENTAGE"))
        );
        feeManager.setFee(
            pendleLSDStrategyAddress,
            IFeeManager.FeeType.PERFORMANCE,
            vm.envAddress("PLSDS_PERFORMANCE_FEE_RECIPIENT"),
            uint16(vm.envUint("PLSDS_PERFORMANCE_FEE_PERCENTAGE"))
        );

        vm.stopBroadcast();
    }
}
