// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ETH_ORACLE, WETH, ARB, PENDLE, PENDLE_ROUTER, ARB_ORACLE } from "addresses/ARBMainnet.sol";
import { IPendleCalculations } from "src/calculations/pendle/interfaces/IPendleCalculations.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { PendlesETHStrategy } from "src/strategies/pendle/PendlesETHStrategy.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { Script, console } from "forge-std/Script.sol";

contract PendleLSDStrategyScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        StrategyHelper strategyHelper = StrategyHelper(vm.envAddress("PLSDS_STRATEGY_HELPER"));

        strategyHelper.setOracle(PENDLE, vm.envAddress("PLSDS_PENDLE_UNISWAP_ORACLE")); // PENDLE/USD
        strategyHelper.setOracle(WETH, ETH_ORACLE); // WETH/USD = ETH/USD
        strategyHelper.setOracle(ARB, ARB_ORACLE); // ARB/USD

        // strategyHelper.setPath(
        //     PENDLE,
        //     WETH,
        //     address(vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_UNISWAP_V3")),
        //     abi.encodePacked(PENDLE, uint24(3000), WETH)
        // );
        strategyHelper.setPath(
            ARB,
            WETH,
            address(vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_UNISWAP_V3")),
            abi.encodePacked(ARB, uint24(500), WETH)
        );

        IPendleCalculations pendleLSDCalculations = IPendleCalculations(vm.envAddress("PLSDS_CALCULATIONS"));

        address pendlesEthStrategyImplementationAddress = address(new PendlesETHStrategy());
        console.log("PendlesEthStrategyImplementation deployed at:", pendlesEthStrategyImplementationAddress);

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
                pendlesEthStrategyImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                    initParams
                )
            )
        );
        PendlesETHStrategy pendleStrategy = PendlesETHStrategy(payable(pendleStrategyProxyAddress));
        console.log("PendlesEthStrategyProxy deployed at:", address(pendleStrategy));

        pendleStrategy.setSlippageTolerance(uint16(vm.envUint("PLSDS_SLIPPAGE_TOLERANCE")));

        pendleLSDCalculations.setStrategyValues(pendleStrategyProxyAddress);

        vm.stopBroadcast();
    }
}
