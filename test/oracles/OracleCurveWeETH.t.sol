// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { OracleErrors } from "src/libraries/OracleErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { OracleCurveWeETH } from "src/oracles/OracleCurveWeETH.sol";
import { ICurvePool } from "src/interfaces/ICurve.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract OracleCurveWeETHTest is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    StrategyHelper public strategyHelper;
    OracleCurveWeETH public oracleCurveWeEth;
    uint256 public index = 0;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 19_051_787);

        Proxy strategyHelperProxy =
            new Proxy(address(new StrategyHelper()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE));

        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        vm.prank(strategyHelper.adminStructure().superAdmin());

        strategyHelper.setOracle(WETH, ETH_ORACLE);

        Proxy oracleCurveWeEthProxy = new Proxy(
            address(new OracleCurveWeETH()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_WEETH_WETH_POOL,
                index,
                WETH
            )
        );

        oracleCurveWeEth = OracleCurveWeETH(address(oracleCurveWeEthProxy));
    }

    function test_pool() external {
        assertEq(address(oracleCurveWeEth.pool()), CURVE_WEETH_WETH_POOL);
    }

    function test_index() external {
        assertEq(oracleCurveWeEth.index(), index);
    }

    function test_tokenA() external {
        assertEq(oracleCurveWeEth.tokenA(), WEETH);
        assertEq(oracleCurveWeEth.tokenA(), ICurvePool(CURVE_WEETH_WETH_POOL).coins(index));
    }

    function test_tokenB() external {
        assertEq(oracleCurveWeEth.tokenB(), WETH);
    }

    function test_weth() external {
        assertEq(address(oracleCurveWeEth.weth()), WETH);
    }

    function test_initialize() external {
        Proxy oracleCurveWeEthProxy = new Proxy(
            address(new OracleCurveWeETH()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_WEETH_WETH_POOL,
                index,
                WETH
            )
        );
        OracleCurveWeETH newOracleCurve = OracleCurveWeETH(address(oracleCurveWeEthProxy));

        assertEq(address(newOracleCurve.adminStructure()), ADMIN_STRUCTURE);
        assertEq(address(newOracleCurve.strategyHelper()), address(strategyHelper));
        assertEq(address(newOracleCurve.pool()), CURVE_WEETH_WETH_POOL);
        assertEq(newOracleCurve.index(), index);
        assertEq(newOracleCurve.tokenA(), ICurvePool(CURVE_WEETH_WETH_POOL).coins(index));
        assertEq(newOracleCurve.tokenB(), WETH);
        assertEq(address(newOracleCurve.weth()), WETH);
    }

    function test_latestAnswer() external {
        assertEq(oracleCurveWeEth.latestAnswer(), 2_539_091_440_284_557_790_998);
    }

    function test_latestRoundData() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleCurveWeEth.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 2_539_091_440_284_557_790_998);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_decimals() external {
        assertEq(oracleCurveWeEth.decimals(), 18);
    }
}
