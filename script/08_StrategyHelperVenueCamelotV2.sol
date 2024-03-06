// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { StrategyHelperVenueCamelotV2 } from "src/strategies/StrategyHelper.sol";
import { CAMELOT_V2_ROUTER } from "addresses/ARBMainnet.sol";
import { Script, console } from "forge-std/Script.sol";

contract StrategyHelperVenueCamelotV2Script is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyHelperVenueCamelotV2Address = address(new StrategyHelperVenueCamelotV2(CAMELOT_V2_ROUTER));
        console.log("StrategyHelperVenueCamelotV2 deployed at: ", strategyHelperVenueCamelotV2Address);

        vm.stopBroadcast();
    }
}
