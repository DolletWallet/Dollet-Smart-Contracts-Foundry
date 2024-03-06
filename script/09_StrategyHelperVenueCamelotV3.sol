// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { StrategyHelperVenueCamelotV3 } from "src/strategies/StrategyHelper.sol";
import { CAMELOT_V3_ROUTER } from "addresses/ARBMainnet.sol";
import { Script, console } from "forge-std/Script.sol";

contract StrategyHelperVenueCamelotV3Script is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyHelperVenueCamelotV3Address = address(new StrategyHelperVenueCamelotV3(CAMELOT_V3_ROUTER));
        console.log("StrategyHelperVenueCamelotV3 deployed at: ", strategyHelperVenueCamelotV3Address);

        vm.stopBroadcast();
    }
}
