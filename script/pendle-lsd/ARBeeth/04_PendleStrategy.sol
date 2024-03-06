// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IPendleCalculations } from "src/calculations/pendle/interfaces/IPendleCalculations.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { PendleweETHStrategy } from "src/strategies/pendle/PendleweETHStrategy.sol";
import { StrategyHelperVenueCurve } from "src/strategies/StrategyHelper.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { IStrategy } from "src/interfaces/dollet/IStrategy.sol";
import { Script, console } from "forge-std/Script.sol";
import {
    ETH_ORACLE,
    WETH,
    WEETH,
    PENDLE,
    PENDLE_ROUTER,
    UNISWAP_V3_PENDLE_WETH_POOL,
    UNISWAP_V3_WEETH_WETH_POOL
} from "addresses/ARBMainnet.sol";

contract PendleLSDStrategyScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        StrategyHelper strategyHelper = StrategyHelper(vm.envAddress("PLSDS_STRATEGY_HELPER"));

        strategyHelper.setOracle(PENDLE, vm.envAddress("PLSDS_PENDLE_UNISWAP_ORACLE")); // PENDLE/USD
        strategyHelper.setOracle(WETH, ETH_ORACLE); // WETH/USD = ETH/USD
        strategyHelper.setOracle(WEETH, vm.envAddress("PLSDS_WEETH_UNISWAP_ORACLE")); // WEETH/USD

        strategyHelper.setPath(
            PENDLE,
            WETH,
            address(vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_UNISWAP_V3")),
            abi.encodePacked(PENDLE, uint24(3000), WETH)
        );
        strategyHelper.setPath(
            WEETH,
            WETH,
            address(vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_UNISWAP_V3")),
            abi.encodePacked(WEETH, uint24(3000), WETH)
        );
        strategyHelper.setPath(
            WETH,
            WEETH,
            address(vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_UNISWAP_V3")),
            abi.encodePacked(WETH, uint24(3000), WEETH)
        );

        IPendleCalculations pendleLSDCalculations = IPendleCalculations(vm.envAddress("PLSDS_CALCULATIONS"));

        address pendleweEthStrategyImplementationAddress = address(new PendleweETHStrategy());
        console.log("PendleweEthStrategyImplementation deployed at:", pendleweEthStrategyImplementationAddress);

        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
            strategyHelper: address(strategyHelper),
            feeManager: vm.envAddress("PLSDS_FEE_MANAGER"),
            weth: WETH,
            want: vm.envAddress("PLSDS_WANT"),
            calculations: address(pendleLSDCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: vm.envAddress("PLSDS_PENDLE_MARKET"),
            twapPeriod: uint32(vm.envUint("PLSDS_TWAB_PERIOD")),
            tokensToCompound: vm.envAddress("PLSDS_COMPOUND_TOKENS", ","),
            minimumsToCompound: vm.envUint("PLSDS_COMPOUND_AMOUNTS", ",")
        });
        address pendleStrategyProxyAddress = address(
            new Proxy(
                pendleweEthStrategyImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]),address,address)",
                    initParams,
                    WEETH,
                    PENDLE
                )
            )
        );
        PendleweETHStrategy pendleStrategy = PendleweETHStrategy(payable(pendleStrategyProxyAddress));
        console.log("PendleweEthStrategyProxy deployed at:", address(pendleStrategy));

        pendleStrategy.setSlippageTolerance(uint16(vm.envUint("PLSDS_SLIPPAGE_TOLERANCE")));

        pendleLSDCalculations.setStrategyValues(pendleStrategyProxyAddress);

        pendleStrategy.setTargetAsset(WEETH);

        vm.stopBroadcast();
    }
}
