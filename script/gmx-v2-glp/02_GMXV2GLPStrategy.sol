// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IGMXV2GLPStrategy } from "../../src/strategies/gmx-v2/interfaces/IGMXV2GLPStrategy.sol";
import { GMXV2GLPStrategy } from "../../src/strategies/gmx-v2/GMXV2GLPStrategy.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ICalculations } from "../../src/interfaces/dollet/ICalculations.sol";
import { StrategyHelper } from "../../src/strategies/StrategyHelper.sol";
import { Script, console } from "forge-std/Script.sol";
import "../../addresses/AVAXMainnet.sol";

contract GMXV2GLPStrategyScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        StrategyHelper strategyHelper = StrategyHelper(vm.envAddress("GMXV2GLPS_STRATEGY_HELPER"));

        strategyHelper.setOracle(WAVAX, AVAX_ORACLE);
        strategyHelper.setOracle(WETHe, ETH_ORACLE);
        strategyHelper.setOracle(BTCb, WBTC_ORACLE);
        strategyHelper.setOracle(WBTCe, WBTC_ORACLE);
        strategyHelper.setOracle(USDC, USDC_ORACLE);
        strategyHelper.setOracle(USDCe, USDC_ORACLE);

        ICalculations calculations = ICalculations(vm.envAddress("GMXV2GLPS_CALCULATIONS"));

        address GMXV2GLPStrategyImplementationAddress = address(new GMXV2GLPStrategy());
        console.log("GMXV2GLPStrategyImplementation deployed at:", GMXV2GLPStrategyImplementationAddress);

        IGMXV2GLPStrategy.InitParams memory initParams = IGMXV2GLPStrategy.InitParams({
            adminStructure: vm.envAddress("GMXV2GLPS_ADMIN_STRUCTURE"),
            strategyHelper: address(strategyHelper),
            feeManager: vm.envAddress("GMXV2GLPS_FEE_MANAGER"),
            weth: WAVAX,
            want: sGLP,
            calculations: address(calculations),
            gmxGlpHandler: GMX_GLP_HANDLER,
            gmxRewardsHandler: GMX_REWARDS_HANDLER,
            tokensToCompound: vm.envAddress("GMXV2GLPS_COMPOUND_TOKENS", ","),
            minimumsToCompound: vm.envUint("GMXV2GLPS_COMPOUND_AMOUNTS", ",")
        });
        address GMXV2GLPStrategyProxyAddress = address(
            new Proxy(
                GMXV2GLPStrategyImplementationAddress,
                vm.envAddress("GMXV2GLPS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize((address,address,address,address,address,address,address,address,address[],uint256[]))",
                    initParams
                )
            )
        );

        GMXV2GLPStrategy strategy = GMXV2GLPStrategy(payable(GMXV2GLPStrategyProxyAddress));
        console.log("GMXV2GLPStrategyProxyAddress deployed at:", address(strategy));

        strategy.setSlippageTolerance(uint16(vm.envUint("GMXV2GLPS_SLIPPAGE_TOLERANCE")));

        calculations.setStrategyValues(GMXV2GLPStrategyProxyAddress);

        vm.stopBroadcast();
    }
}
