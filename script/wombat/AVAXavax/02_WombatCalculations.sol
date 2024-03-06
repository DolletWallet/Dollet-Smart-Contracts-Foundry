// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { WombatCalculations } from "src/calculations/wombat/WombatCalculations.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console } from "forge-std/Script.sol";

contract WombatCalculationsScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address wombatCalculationsImplementationAddress = address(new WombatCalculations());
        console.log("WombatCalculationsImplementation deployed at:", wombatCalculationsImplementationAddress);

        address wombatCalculationsProxyAddress = address(
            new Proxy(
                wombatCalculationsImplementationAddress,
                vm.envAddress("WS_PROXY_ADMIN"),
                abi.encodeWithSignature("initialize(address)", vm.envAddress("WS_ADMIN_STRUCTURE"))
            )
        );
        WombatCalculations calculations = WombatCalculations(wombatCalculationsProxyAddress);
        console.log("WombatCalculationsProxy deployed at:", address(calculations));

        vm.stopBroadcast();
    }
}
