// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TemporaryAdminStructure } from "src/admin/TemporaryAdminStructure.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console } from "forge-std/Script.sol";

contract TemporaryAdminStructureScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address proxyAdminAddress = address(new ProxyAdmin());
        console.log("ProxyAdmin deployed at:", proxyAdminAddress);

        address adminStructureImplementationAddress = address(new TemporaryAdminStructure());
        console.log("TemporaryAdminStructureImplementation deployed at:", adminStructureImplementationAddress);

        address adminStructureProxyAddress = address(
            new Proxy(
                adminStructureImplementationAddress,
                proxyAdminAddress,
                abi.encodeWithSignature("initialize()")
            )
        );
        TemporaryAdminStructure temporaryAdminStructure = TemporaryAdminStructure(adminStructureProxyAddress);
        console.log("TemporaryAdminStructureProxy deployed at:", address(temporaryAdminStructure));

        vm.stopBroadcast();
    }
}
