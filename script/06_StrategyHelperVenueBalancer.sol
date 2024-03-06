// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { StrategyHelperVenueBalancer } from "src/strategies/StrategyHelper.sol";
import { BALANCER_VAULT } from "addresses/ETHMainnet.sol";
import { Script, console } from "forge-std/Script.sol";

contract StrategyHelperVenueBalancerScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyHelperVenueBalancerAddress = address(new StrategyHelperVenueBalancer(BALANCER_VAULT));
        console.log("StrategyHelperVenueBalancer deployed at: ", strategyHelperVenueBalancerAddress);

        vm.stopBroadcast();
    }
}
