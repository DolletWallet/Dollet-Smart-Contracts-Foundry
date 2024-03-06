// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console } from "forge-std/Script.sol";
import { PendleLSDCalculations } from "src/calculations/pendle/PendleLSDCalculations.sol";

contract PendleLSDCalculationsScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address pendleLSDCalculationsImplementationAddress = address(new PendleLSDCalculations());
        console.log(
            "PendleLSDCalculationsImplementationAddress deployed at:", pendleLSDCalculationsImplementationAddress
        );

        address pendleLSDCalculationsProxyAddress = address(
            new Proxy(
                pendleLSDCalculationsImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address)",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE")
                )
            )
        );
        PendleLSDCalculations pendleLSDCalculations = PendleLSDCalculations(pendleLSDCalculationsProxyAddress);
        console.log("pendleLSDCalculationsProxy deployed at:", address(pendleLSDCalculations));

        vm.stopBroadcast();
    }
}
