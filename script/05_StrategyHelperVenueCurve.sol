// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { StrategyHelperVenueCurve } from "src/strategies/StrategyHelper.sol";
import { Script, console } from "forge-std/Script.sol";
import { WETH } from "addresses/ETHMainnet.sol";

contract StrategyHelperVenueCurveScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyHelperVenueCurveAddress = address(new StrategyHelperVenueCurve(WETH));
        console.log("StrategyHelperVenueCurve deployed at: ", strategyHelperVenueCurveAddress);

        vm.stopBroadcast();
    }
}
