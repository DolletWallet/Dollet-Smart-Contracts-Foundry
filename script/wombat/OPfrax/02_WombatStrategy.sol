// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IWombatStrategy } from "src/strategies/wombat/interfaces/IWombatStrategy.sol";
import { WombatStrategy } from "src/strategies/wombat/WombatStrategy.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { Script, console } from "forge-std/Script.sol";
import "addresses/OPMainnet.sol";

contract WombatStrategyScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        StrategyHelper strategyHelper = StrategyHelper(vm.envAddress("WS_STRATEGY_HELPER"));
        address strategyHelperVenueUniswapV3 = vm.envAddress("WS_STRATEGY_HELPER_VENUE_UNISWAP_V3");
        address strategyHelperVenueFraxswapV2 = vm.envAddress("WS_STRATEGY_HELPER_VENUE_FRAXSWAP_V2");

        strategyHelper.setOracle(WETH, ETH_ORACLE);
        strategyHelper.setOracle(USDC, USDC_ORACLE);
        strategyHelper.setOracle(OP, OP_ORACLE);
        strategyHelper.setOracle(FXS, FXS_ORACLE);

        // OP/WETH
        strategyHelper.setPath(OP, WETH, strategyHelperVenueUniswapV3, abi.encodePacked(OP, uint24(3000), WETH));

        // FXS/WETH
        strategyHelper.setPath(FXS, WETH, strategyHelperVenueFraxswapV2, abi.encodePacked(FXS, FRAX, WETH));

        // WETH/USDC
        strategyHelper.setPath(WETH, USDC, strategyHelperVenueUniswapV3, abi.encodePacked(WETH, uint24(500), USDC));

        ICalculations calculations = ICalculations(vm.envAddress("WS_CALCULATIONS"));

        address wombatStrategyImplementationAddress = address(new WombatStrategy());
        console.log("WombatStrategyImplementation deployed at:", wombatStrategyImplementationAddress);

        IWombatStrategy.InitParams memory initParams = IWombatStrategy.InitParams({
            adminStructure: vm.envAddress("WS_ADMIN_STRUCTURE"),
            strategyHelper: address(strategyHelper),
            feeManager: vm.envAddress("WS_FEE_MANAGER"),
            weth: WETH,
            want: vm.envAddress("WS_WANT"),
            pool: WOMBAT_FRAX_USDC_POOL,
            wom: WOM,
            targetAsset: USDC,
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
