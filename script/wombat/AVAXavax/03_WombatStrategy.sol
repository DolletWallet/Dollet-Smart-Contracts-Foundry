// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IWombatStrategy } from "src/strategies/wombat/interfaces/IWombatStrategy.sol";
import { WombatStrategy } from "src/strategies/wombat/WombatStrategy.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { Script, console } from "forge-std/Script.sol";
import "addresses/AVAXMainnet.sol";

contract WombatStrategyScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        StrategyHelper strategyHelper = StrategyHelper(vm.envAddress("WS_STRATEGY_HELPER"));
        address strategyHelperVenueTraderJoeV1 = vm.envAddress("WS_STRATEGY_HELPER_VENUE_TRADERJOE_V1");

        strategyHelper.setOracle(WAVAX, AVAX_ORACLE);
        strategyHelper.setOracle(WOM, vm.envAddress("WS_WOM_TRADERJOE_ORACLE"));
        strategyHelper.setOracle(QI, QI_ORACLE);

        strategyHelper.setPath(WOM, WAVAX, address(strategyHelperVenueTraderJoeV1), abi.encode(WOM, WAVAX)); // WOM/WAVAX
        strategyHelper.setPath(QI, WAVAX, address(strategyHelperVenueTraderJoeV1), abi.encode(QI, WAVAX)); // QI/WAVAX

        ICalculations calculations = ICalculations(vm.envAddress("WS_CALCULATIONS"));

        address wombatStrategyImplementationAddress = address(new WombatStrategy());
        console.log("WombatStrategyImplementation deployed at:", wombatStrategyImplementationAddress);

        IWombatStrategy.InitParams memory initParams = IWombatStrategy.InitParams({
            adminStructure: vm.envAddress("WS_ADMIN_STRUCTURE"),
            strategyHelper: address(strategyHelper),
            feeManager: vm.envAddress("WS_FEE_MANAGER"),
            weth: WAVAX,
            want: vm.envAddress("WS_WANT"),
            pool: WOMBAT_AVAX_sAVAX_POOL,
            wom: WOM,
            targetAsset: WAVAX,
            calculations: address(calculations),
            tokensToCompound: vm.envAddress("WS_COMPOUND_TOKENS", ","),
            minimumsToCompound: vm.envUint("WS_COMPOUND_AMOUNTS", ",")
        });
        address wombatStrategyProxyAddress = address(
            new Proxy(
                wombatStrategyImplementationAddress,
                vm.envAddress("WS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize((address,address,address,address,address,address,address,address,address,address[],uint256[]))",
                    initParams
                )
            )
        );

        WombatStrategy strategy = WombatStrategy(payable(wombatStrategyProxyAddress));
        console.log("WombatStrategyProxyAddress deployed at:", address(strategy));

        strategy.setSlippageTolerance(uint16(vm.envUint("WS_SLIPPAGE_TOLERANCE")));

        calculations.setStrategyValues(wombatStrategyProxyAddress);

        vm.stopBroadcast();
    }
}
