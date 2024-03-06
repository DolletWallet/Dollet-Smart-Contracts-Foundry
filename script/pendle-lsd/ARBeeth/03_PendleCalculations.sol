// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console } from "forge-std/Script.sol";
import { PendleLSDCalculationsV2 } from "src/calculations/pendle/PendleLSDCalculationsV2.sol";

contract PendleLSDCalculationsV2Script is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address pendleCalculationsImplementationAddress = address(new PendleLSDCalculationsV2());
        console.log("PendleCalculationsImplementation deployed at:", pendleCalculationsImplementationAddress);

        address pendleCalculationsProxyAddress = address(
            new Proxy(
                pendleCalculationsImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address)",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
                    vm.envAddress("PLSDS_SY_TOKEN")
                )
            )
        );
        PendleLSDCalculationsV2 pendleCalculations = PendleLSDCalculationsV2(pendleCalculationsProxyAddress);
        console.log("PendleCalculationsProxy deployed at:", address(pendleCalculations));

        vm.stopBroadcast();
    }
}
