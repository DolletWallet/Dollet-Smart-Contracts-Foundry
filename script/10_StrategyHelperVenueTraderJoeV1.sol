// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { StrategyHelperVenueTraderJoeV1 } from "src/strategies/StrategyHelper.sol";
import { TRADER_JOE_V1_ROUTER } from "addresses/AVAXMainnet.sol";
import { Script, console } from "forge-std/Script.sol";

contract StrategyHelperVenueTraderJoeV1Script is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address StrategyHelperVenueTraderJoeV1Address =
            address(new StrategyHelperVenueTraderJoeV1(TRADER_JOE_V1_ROUTER));
        console.log("StrategyHelperVenueTraderJoeV1 deployed at: ", StrategyHelperVenueTraderJoeV1Address);

        vm.stopBroadcast();
    }
}
