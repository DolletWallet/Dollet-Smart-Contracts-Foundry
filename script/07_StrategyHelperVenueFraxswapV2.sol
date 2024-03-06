// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { StrategyHelperVenueFraxswapV2 } from "src/strategies/StrategyHelper.sol";
import { FRAXSWAP_V2_ROUTER } from "addresses/OPMainnet.sol";
import { Script, console } from "forge-std/Script.sol";

contract StrategyHelperVenueFraxswapV2Script is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyHelperVenueFraxswapV2Address = address(new StrategyHelperVenueFraxswapV2(FRAXSWAP_V2_ROUTER));
        console.log("StrategyHelperVenueFraxswapV2 deployed at: ", strategyHelperVenueFraxswapV2Address);

        vm.stopBroadcast();
    }
}
