// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { WETH, CURVE_WEETH_WETH_POOL } from "addresses/ETHMainnet.sol";
import { OracleCurveWeETH } from "src/oracles/OracleCurveWeETH.sol";
import { Script, console } from "forge-std/Script.sol";

contract OETHCurveOracleScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address oracleCurveWeEthImplementationAddress = address(new OracleCurveWeETH());
        console.log("OracleCurveWeEthImplementation deployed at:", oracleCurveWeEthImplementationAddress);

        address oracleCurveWeEthProxyAddress = address(
            new Proxy(
                oracleCurveWeEthImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,uint256,address)",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
                    vm.envAddress("PLSDS_STRATEGY_HELPER"),
                    CURVE_WEETH_WETH_POOL,
                    vm.envUint("PLSDS_CURVE_WEETH_INDEX"),
                    WETH
                )
            )
        );
        OracleCurveWeETH oracleCurveWeEth = OracleCurveWeETH(oracleCurveWeEthProxyAddress);
        console.log("OracleCurveWeEthProxy deployed at:", address(oracleCurveWeEth));

        vm.stopBroadcast();
    }
}
