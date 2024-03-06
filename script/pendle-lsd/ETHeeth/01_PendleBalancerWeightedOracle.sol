// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ETH_ORACLE, WETH, BALANCER_PENDLE_WETH_POOL, BALANCER_VAULT } from "addresses/ETHMainnet.sol";
import { OracleBalancerWeighted } from "src/oracles/OracleBalancerWeighted.sol";
import { TransparentUpgradeableProxy as Proxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { Script, console } from "forge-std/Script.sol";

contract PendleBalancerWeightedOracleScript is Script {
    function run() external {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        address oracleBalancerWeightedImplementationAddress = address(new OracleBalancerWeighted());
        console.log("OracleBalancerWeightedImplementation deployed at:", oracleBalancerWeightedImplementationAddress);

        address oracleBalancerWeightedPendleProxyAddress = address(
            new Proxy(
                oracleBalancerWeightedImplementationAddress,
                vm.envAddress("PLSDS_PROXY_ADMIN"),
                abi.encodeWithSignature(
                    "initialize(address,address,address,address,address,uint32)",
                    vm.envAddress("PLSDS_ADMIN_STRUCTURE"),
                    BALANCER_VAULT,
                    BALANCER_PENDLE_WETH_POOL,
                    ETH_ORACLE,
                    WETH,
                    uint32(vm.envUint("PLSDS_VALIDITY_DURATION"))
                )
            )
        );
        OracleBalancerWeighted oracleBalancerWeightedPendle =
            OracleBalancerWeighted(oracleBalancerWeightedPendleProxyAddress);
        console.log("OracleBalancerWeightedPendleProxy deployed at:", address(oracleBalancerWeightedPendle));

        vm.stopBroadcast();
    }
}
