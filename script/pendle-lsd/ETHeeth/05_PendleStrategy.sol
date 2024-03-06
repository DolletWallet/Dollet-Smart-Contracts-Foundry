// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IPendleCalculations } from "src/calculations/pendle/interfaces/IPendleCalculations.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { PendleeETHStrategy } from "src/strategies/pendle/PendleeETHStrategy.sol";
import { StrategyHelperVenueCurve } from "src/strategies/StrategyHelper.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { IStrategy } from "src/interfaces/dollet/IStrategy.sol";
import { Script, console } from "forge-std/Script.sol";
import {
    ETH_ORACLE,
    WETH,
    EETH,
    WEETH,
    PENDLE,
    PENDLE_ROUTER,
    CURVE_WEETH_WETH_POOL,
    ETHER_FI_EETH_LIQUIDITY_POOL
} from "addresses/ETHMainnet.sol";

contract PendleLSDStrategyScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        StrategyHelper strategyHelper = StrategyHelper(vm.envAddress("PLSDS_STRATEGY_HELPER"));

        address strategyHelperVenueCurve = vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_CURVE");

        strategyHelper.setOracle(PENDLE, vm.envAddress("PLSDS_PENDLE_BALANCER_WEIGHTED_ORACLE")); // PENDLE/USD
        strategyHelper.setOracle(WETH, ETH_ORACLE); // WETH/USD = ETH/USD
        strategyHelper.setOracle(EETH, vm.envAddress("PLSDS_EETH_CURVE_ORACLE")); // EETH/USD
        strategyHelper.setOracle(WEETH, vm.envAddress("PLSDS_WEETH_CURVE_ORACLE")); // WEETH/USD

        // PENDLE/WETH
        strategyHelper.setPath(
            address(PENDLE),
            address(WETH),
            address(vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_BALANCER")),
            abi.encode(WETH, vm.envBytes32("PLSDS_BALANCER_POOL_ID"))
        );

        // WEETH/WETH
        address[] memory pools = new address[](1);
        uint256[] memory coinsIn = new uint256[](1);
        uint256[] memory coinsOut = new uint256[](1);

        pools[0] = CURVE_WEETH_WETH_POOL;

        coinsIn[0] = 0;
        coinsOut[0] = 1;
        strategyHelper.setPath(WEETH, WETH, strategyHelperVenueCurve, abi.encode(pools, coinsIn, coinsOut));

        coinsIn[0] = 1;
        coinsOut[0] = 0;
        strategyHelper.setPath(WETH, WEETH, strategyHelperVenueCurve, abi.encode(pools, coinsIn, coinsOut));

        IPendleCalculations pendleLSDCalculations = IPendleCalculations(vm.envAddress("PLSDS_CALCULATIONS"));

        address pendleeEthStrategyImplementationAddress = address(new PendleeETHStrategy());
        console.log("PendleeEthStrategyImplementation deployed at:", pendleeEthStrategyImplementationAddress);

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
                pendleeEthStrategyImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]),address,address,address)",
                    initParams,
                    ETHER_FI_EETH_LIQUIDITY_POOL,
                    WEETH,
                    PENDLE
                )
            )
        );
        PendleeETHStrategy pendleStrategy = PendleeETHStrategy(payable(pendleStrategyProxyAddress));
        console.log("PendleeEthStrategyProxy deployed at:", address(pendleStrategy));

        pendleStrategy.setSlippageTolerance(uint16(vm.envUint("PLSDS_SLIPPAGE_TOLERANCE")));

        pendleLSDCalculations.setStrategyValues(pendleStrategyProxyAddress);

        vm.stopBroadcast();
    }
}
