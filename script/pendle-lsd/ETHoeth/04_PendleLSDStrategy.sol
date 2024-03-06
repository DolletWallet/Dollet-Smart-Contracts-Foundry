// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IPendleCalculations } from "src/calculations/pendle/interfaces/IPendleCalculations.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { PendleLSDStrategy } from "src/strategies/pendle/PendleLSDStrategy.sol";
import { StrategyHelperVenueCurve } from "src/strategies/StrategyHelper.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { IStrategy } from "src/interfaces/dollet/IStrategy.sol";
import { Script, console } from "forge-std/Script.sol";
import {
    ETH_ORACLE,
    USDC_ORACLE,
    USDT_ORACLE,
    WBTC_ORACLE,
    WETH,
    USDC,
    USDT,
    WBTC,
    OETH,
    PENDLE,
    PENDLE_ROUTER,
    CURVE_OETH_ETH_POOL
} from "addresses/ETHMainnet.sol";

contract PendleLSDStrategyScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        StrategyHelper strategyHelper = StrategyHelper(vm.envAddress("PLSDS_STRATEGY_HELPER"));

        address strategyHelperUniswapV3Venue = vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_UNISWAP_V3");
        address strategyHelperVenueCurve = vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_CURVE");

        strategyHelper.setOracle(PENDLE, vm.envAddress("PLSDS_PENDLE_BALANCER_WEIGHTED_ORACLE")); // PENDLE/USD
        strategyHelper.setOracle(OETH, vm.envAddress("PLSDS_OETH_CURVE_ORACLE")); // OETH/USD
        strategyHelper.setOracle(WETH, ETH_ORACLE); // WETH/USD = ETH/USD
        strategyHelper.setOracle(USDC, USDC_ORACLE); // USDC/USD
        strategyHelper.setOracle(USDT, USDT_ORACLE); // USDT/USD
        strategyHelper.setOracle(WBTC, WBTC_ORACLE); // WBTC/USD = BTC/USD

        // PENDLE/WETH
        strategyHelper.setPath(
            address(PENDLE),
            address(WETH),
            address(vm.envAddress("PLSDS_STRATEGY_HELPER_VENUE_BALANCER")),
            abi.encode(WETH, vm.envBytes32("PLSDS_BALANCER_POOL_ID"))
        );

        // USDC/WETH
        strategyHelper.setPath(USDC, WETH, strategyHelperUniswapV3Venue, abi.encodePacked(USDC, uint24(500), WETH));
        strategyHelper.setPath(WETH, USDC, strategyHelperUniswapV3Venue, abi.encodePacked(WETH, uint24(500), USDC));

        // USDT/WETH
        strategyHelper.setPath(USDT, WETH, strategyHelperUniswapV3Venue, abi.encodePacked(USDT, uint24(500), WETH));
        strategyHelper.setPath(WETH, USDT, strategyHelperUniswapV3Venue, abi.encodePacked(WETH, uint24(500), USDT));

        // WBTC/WETH
        strategyHelper.setPath(WBTC, WETH, strategyHelperUniswapV3Venue, abi.encodePacked(WBTC, uint24(500), WETH));
        strategyHelper.setPath(WETH, WBTC, strategyHelperUniswapV3Venue, abi.encodePacked(WETH, uint24(500), WBTC));

        // WETH/OETH
        address[] memory pools = new address[](1);
        uint256[] memory coinsIn = new uint256[](1);
        uint256[] memory coinsOut = new uint256[](1);

        pools[0] = CURVE_OETH_ETH_POOL;

        coinsIn[0] = 0;
        coinsOut[0] = 1;
        strategyHelper.setPath(WETH, OETH, strategyHelperVenueCurve, abi.encode(pools, coinsIn, coinsOut));

        coinsIn[0] = 1;
        coinsOut[0] = 0;
        strategyHelper.setPath(OETH, WETH, strategyHelperVenueCurve, abi.encode(pools, coinsIn, coinsOut));

        IPendleCalculations pendleLSDCalculations = IPendleCalculations(vm.envAddress("PLSDS_CALCULATIONS"));

        address pendleLSDStrategyImplementationAddress = address(new PendleLSDStrategy());
        console.log("PendleLSDStrategyImplementation deployed at:", pendleLSDStrategyImplementationAddress);

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
                pendleLSDStrategyImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                    initParams
                )
            )
        );

        PendleLSDStrategy pendleStrategy = PendleLSDStrategy(payable(pendleStrategyProxyAddress));
        console.log("PendleLSDStrategyProxy deployed at:", address(pendleStrategy));

        pendleStrategy.setSlippageTolerance(uint16(vm.envUint("PLSDS_SLIPPAGE_TOLERANCE")));

        pendleLSDCalculations.setStrategyValues(pendleStrategyProxyAddress);

        vm.stopBroadcast();
    }
}
