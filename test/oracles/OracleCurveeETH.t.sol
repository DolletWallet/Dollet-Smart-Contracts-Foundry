// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { OracleErrors } from "src/libraries/OracleErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { OracleCurveeETH } from "src/oracles/OracleCurveeETH.sol";
import { ICurvePool } from "src/interfaces/ICurve.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract OracleCurveeETHTest is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    StrategyHelper public strategyHelper;
    OracleCurveeETH public oracleCurveeEth;
    uint256 public index = 0;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 19_030_272);

        Proxy strategyHelperProxy =
            new Proxy(address(new StrategyHelper()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE));

        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        vm.prank(strategyHelper.adminStructure().superAdmin());

        strategyHelper.setOracle(WETH, ETH_ORACLE);

        Proxy oracleCurveeEthProxy = new Proxy(
            address(new OracleCurveeETH()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_WEETH_WETH_POOL,
                index,
                WETH,
                EETH
            )
        );

        oracleCurveeEth = OracleCurveeETH(address(oracleCurveeEthProxy));
    }

    function test_pool() external {
        assertEq(address(oracleCurveeEth.pool()), CURVE_WEETH_WETH_POOL);
    }

    function test_index() external {
        assertEq(oracleCurveeEth.index(), index);
    }

    function test_tokenA() external {
        assertEq(oracleCurveeEth.tokenA(), WEETH);
        assertEq(oracleCurveeEth.tokenA(), ICurvePool(CURVE_WEETH_WETH_POOL).coins(index));
    }

    function test_tokenB() external {
        assertEq(oracleCurveeEth.tokenB(), WETH);
    }

    function test_initialize_ShouldFailIfEethIsNotContract() external {
        OracleCurveeETH newOracleCurve = new OracleCurveeETH();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_WEETH_WETH_POOL,
                index,
                WETH,
                address(0)
            )
        );
    }

    function test_initialize() external {
        Proxy oracleCurveeEthProxy = new Proxy(
            address(new OracleCurveeETH()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_WEETH_WETH_POOL,
                index,
                WETH,
                EETH
            )
        );
        OracleCurveeETH newOracleCurve = OracleCurveeETH(address(oracleCurveeEthProxy));

        assertEq(address(newOracleCurve.adminStructure()), ADMIN_STRUCTURE);
        assertEq(address(newOracleCurve.strategyHelper()), address(strategyHelper));
        assertEq(address(newOracleCurve.pool()), CURVE_WEETH_WETH_POOL);
        assertEq(newOracleCurve.index(), index);
        assertEq(newOracleCurve.tokenA(), ICurvePool(CURVE_WEETH_WETH_POOL).coins(index));
        assertEq(newOracleCurve.tokenB(), WETH);
        assertEq(address(newOracleCurve.weth()), WETH);
        assertEq(newOracleCurve.eeth(), EETH);
    }

    function test_latestAnswer() external {
        assertEq(oracleCurveeEth.latestAnswer(), 2_526_721_183_248_959_260_597);
    }

    function test_latestRoundData() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleCurveeEth.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 2_526_721_183_248_959_260_597);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_decimals() external {
        assertEq(oracleCurveeEth.decimals(), 18);
    }
}
