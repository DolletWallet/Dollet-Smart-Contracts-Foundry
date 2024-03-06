// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { GMXV2GLPCalculations } from "../../src/calculations/gmx-v2/GMXV2GLPCalculations.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console } from "forge-std/Script.sol";
import "../../addresses/AVAXMainnet.sol";

contract GMXV2GLPCalculationsScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address GMXV2GLPCalculationsImplementationAddress = address(new GMXV2GLPCalculations());
        console.log("GMXV2GLPCalculationsImplementation deployed at:", GMXV2GLPCalculationsImplementationAddress);

        address GMXV2GLPCalculationsProxyAddress = address(
            new Proxy(
                GMXV2GLPCalculationsImplementationAddress,
                vm.envAddress("GMXV2GLPS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address)",
                    vm.envAddress("GMXV2GLPS_ADMIN_STRUCTURE"),
                    USDC
                )
            )
        );
        GMXV2GLPCalculations calculations = GMXV2GLPCalculations(GMXV2GLPCalculationsProxyAddress);
        console.log("GMXV2GLPCalculationsProxy deployed at:", address(calculations));

        vm.stopBroadcast();
    }
}
