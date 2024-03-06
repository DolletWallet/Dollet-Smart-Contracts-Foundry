// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { WETH, EETH, CURVE_WEETH_WETH_POOL } from "addresses/ETHMainnet.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OracleCurveeETH } from "src/oracles/OracleCurveeETH.sol";
import { Script, console } from "forge-std/Script.sol";

contract OETHCurveOracleScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address oracleCurveeEthImplementationAddress = address(new OracleCurveeETH());
        console.log("OracleCurveeEthImplementation deployed at:", oracleCurveeEthImplementationAddress);

        address oracleCurveeEthProxyAddress = address(
            new Proxy(
                oracleCurveeEthImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,uint256,address,address)",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
                    vm.envAddress("PLSDS_STRATEGY_HELPER"),
                    CURVE_WEETH_WETH_POOL,
                    vm.envUint("PLSDS_CURVE_WEETH_INDEX"),
                    WETH,
                    EETH
                )
            )
        );
        OracleCurveeETH oracleCurveeEth = OracleCurveeETH(oracleCurveeEthProxyAddress);
        console.log("OracleCurveeEthProxy deployed at:", address(oracleCurveeEth));

        vm.stopBroadcast();
    }
}
