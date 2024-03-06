// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { StrategyHelperVenueUniswapV3 } from "src/strategies/StrategyHelper.sol";
import { UNISWAP_V3_ROUTER } from "addresses/ETHMainnet.sol";
import { Script, console } from "forge-std/Script.sol";

contract StrategyHelperVenueUniswapV3Script is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address strategyHelperVenueUniswapV3Address = address(new StrategyHelperVenueUniswapV3(UNISWAP_V3_ROUTER));
        console.log("StrategyHelperVenueUniswapV3 deployed at: ", strategyHelperVenueUniswapV3Address);

        vm.stopBroadcast();
    }
}
