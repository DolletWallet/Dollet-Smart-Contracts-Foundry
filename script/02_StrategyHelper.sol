// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { Script, console } from "forge-std/Script.sol";

contract StrategyHelperScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyHelperImplementationAddress = address(new StrategyHelper());
        console.log("StrategyHelperImplementation deployed at:", strategyHelperImplementationAddress);

        address strategyHelperProxyAddress = address(
            new Proxy(
                strategyHelperImplementationAddress,
                vm.envAddress("SH_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address)",
                    vm.envAddress("SH_ADMIN_STRUCTURE")
                )
            )
        );
        StrategyHelper strategyHelper = StrategyHelper(strategyHelperProxyAddress);
        console.log("StrategyHelperProxy deployed at:", address(strategyHelper));

        vm.stopBroadcast();
    }
}
