// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console } from "forge-std/Script.sol";
import { FeeManager } from "src/FeeManager.sol";

contract FeeManagerScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address feeManagerImplementationAddress = address(new FeeManager());
        console.log("FeeManagerImplementation deployed at:", feeManagerImplementationAddress);

        address feeManagerProxyAddress = address(
            new Proxy(
                feeManagerImplementationAddress,
                vm.envAddress("FM_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address)",
                    vm.envAddress("FM_ADMIN_STRUCTURE")
                )
            )
        );
        FeeManager feeManager = FeeManager(feeManagerProxyAddress);
        console.log("FeeManagerProxy deployed at:", address(feeManager));

        vm.stopBroadcast();
    }
}
