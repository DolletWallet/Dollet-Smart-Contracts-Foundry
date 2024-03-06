// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { WOM, WAVAX, TRADER_JOE_V1_ROUTER } from "addresses/AVAXMainnet.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { OracleTraderJoeV1 } from "src/oracles/OracleTraderJoeV1.sol";
import { Script, console } from "forge-std/Script.sol";

contract WomTraderJoeOracleScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address womTraderJoeOracleImplementationAddress = address(new OracleTraderJoeV1());
        console.log("OracleTraderJoeV1Implementation deployed at:", womTraderJoeOracleImplementationAddress);

        address womTraderJoeOracleProxyAddress = address(
            new Proxy(
                womTraderJoeOracleImplementationAddress,
                vm.envAddress("WS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address,address)",
                    vm.envAddress("WS_ADMIN_STRUCTURE"),
                    vm.envAddress("WS_STRATEGY_HELPER"),
                    TRADER_JOE_V1_ROUTER,
                    WOM,
                    WAVAX,
                    WAVAX
                )
            )
        );
        OracleTraderJoeV1 oracleTraderJoeV1 = OracleTraderJoeV1(womTraderJoeOracleProxyAddress);
        console.log("OracleTraderJoeV1Proxy deployed at:", address(oracleTraderJoeV1));

        vm.stopBroadcast();
    }
}
