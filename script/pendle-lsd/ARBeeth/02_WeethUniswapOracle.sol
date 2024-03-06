// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ETH_ORACLE, WETH, UNISWAP_V3_WEETH_WETH_POOL } from "addresses/ARBMainnet.sol";
import { OracleUniswapV3 } from "src/oracles/OracleUniswapV3.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console } from "forge-std/Script.sol";

contract WeethUniswapOracleScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address oracleWeethUniswapImplementationAddress = address(new OracleUniswapV3());
        console.log("OracleWeethUniswapImplementation deployed at:", oracleWeethUniswapImplementationAddress);

        address oracleWeethUniswapProxyAddress = address(
            new Proxy(
                oracleWeethUniswapImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,uint32,uint32)",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
                    ETH_ORACLE,
                    UNISWAP_V3_WEETH_WETH_POOL,
                    WETH,
                    uint32(vm.envUint("PLSDS_TWAB_PERIOD")),
                    uint32(vm.envUint("PLSDS_VALIDITY_DURATION"))
                )
            )
        );
        OracleUniswapV3 oracleWeethUniswap = OracleUniswapV3(oracleWeethUniswapProxyAddress);
        console.log("oracleWeethUniswapProxy deployed at:", address(oracleWeethUniswap));

        vm.stopBroadcast();
    }
}
