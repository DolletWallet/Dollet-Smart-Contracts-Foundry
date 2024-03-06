// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { WETH, CURVE_OETH_ETH_POOL } from "addresses/ETHMainnet.sol";
import { OracleCurve } from "src/oracles/OracleCurve.sol";
import { Script, console } from "forge-std/Script.sol";

contract OETHCurveOracleScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address oracleCurveImplementationAddress = address(new OracleCurve());
        console.log("OracleCurveImplementationAddress deployed at:", oracleCurveImplementationAddress);

        address oracleCurveOETHProxyAddress = address(
            new Proxy(
                oracleCurveImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,uint256,address)",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
                    vm.envAddress("PLSDS_STRATEGY_HELPER"),
                    CURVE_OETH_ETH_POOL,
                    vm.envUint("PLSDS_CURVE_OETH_INDEX"),
                    WETH
                )
            )
        );
        OracleCurve oracleCurveOETH = OracleCurve(oracleCurveOETHProxyAddress);
        console.log("OracleCurveOETHProxy deployed at:", address(oracleCurveOETH));

        vm.stopBroadcast();
    }
}
