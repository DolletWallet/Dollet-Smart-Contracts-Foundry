// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { OracleErrors } from "src/libraries/OracleErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { OracleCurve } from "src/oracles/OracleCurve.sol";
import { ICurvePool } from "src/interfaces/ICurve.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract OracleCurveTest is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    StrategyHelper public strategyHelper;
    OracleCurve public oracleCurve;
    uint256 public index = 1;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_412_791);

        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()),
            abi.encodeWithSignature(
                "initialize(address)",
                ADMIN_STRUCTURE
            )
        );

        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        vm.prank(strategyHelper.adminStructure().superAdmin());

        strategyHelper.setOracle(WETH, ETH_ORACLE);

        Proxy oracleCurveProxy = new Proxy(
            address(new OracleCurve()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_OETH_ETH_POOL,
                index,
                WETH
            )
        );

        oracleCurve = OracleCurve(address(oracleCurveProxy));
    }

    function test_adminStructure() external {
        assertEq(address(oracleCurve.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_strategyHelper() external {
        assertEq(address(oracleCurve.strategyHelper()), address(strategyHelper));
    }

    function test_pool() external {
        assertEq(address(oracleCurve.pool()), CURVE_OETH_ETH_POOL);
    }

    function test_index() external {
        assertEq(oracleCurve.index(), index);
    }

    function test_tokenA() external {
        assertEq(oracleCurve.tokenA(), ICurvePool(CURVE_OETH_ETH_POOL).coins(index));
    }

    function test_tokenB() external {
        assertEq(oracleCurve.tokenB(), WETH);
    }

    function test_weth() external {
        assertEq(address(oracleCurve.weth()), WETH);
    }

    function test_initialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        oracleCurve.initialize(ADMIN_STRUCTURE, address(strategyHelper), CURVE_OETH_ETH_POOL, index, WETH);
    }

    function test_initialize_ShouldFailIfAdminStructureIsNotContract() external {
        OracleCurve newOracleCurve = new OracleCurve();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                address(0),
                address(strategyHelper),
                CURVE_OETH_ETH_POOL,
                index,
                WETH
            )
        );
    }

    function test_initialize_ShouldFailIfStrategyHelperIsNotContract() external {
        OracleCurve newOracleCurve = new OracleCurve();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(0),
                CURVE_OETH_ETH_POOL,
                index,
                WETH
            )
        );
    }

    function test_initialize_ShouldFailIfPoolIsNotContract() external {
        OracleCurve newOracleCurve = new OracleCurve();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                address(0),
                WETH,
                index,
                WETH
            )
        );
    }

    function test_initialize_ShouldFailIfWethIsNotContract() external {
        OracleCurve newOracleCurve = new OracleCurve();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_OETH_ETH_POOL,
                index,
                address(0)
            )
        );
    }

    function test_initialize_ShouldFailIfIndexIsGT1() external {
        OracleCurve newOracleCurve = new OracleCurve();

        vm.expectRevert(abi.encodeWithSelector(OracleErrors.WrongCurvePoolTokenIndex.selector));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_OETH_ETH_POOL,
                2,
                WETH
            )
        );
    }

    function test_initialize() external {
        Proxy oracleCurveProxy = new Proxy(
            address(new OracleCurve()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                CURVE_OETH_ETH_POOL,
                index,
                WETH
            )
        );
        OracleCurve newOracleCurve = OracleCurve(address(oracleCurveProxy));

        assertEq(address(newOracleCurve.adminStructure()), ADMIN_STRUCTURE);
        assertEq(address(newOracleCurve.strategyHelper()), address(strategyHelper));
        assertEq(address(newOracleCurve.pool()), CURVE_OETH_ETH_POOL);
        assertEq(newOracleCurve.index(), index);
        assertEq(newOracleCurve.tokenA(), ICurvePool(CURVE_OETH_ETH_POOL).coins(index));
        assertEq(newOracleCurve.tokenB(), WETH);
        assertEq(address(newOracleCurve.weth()), WETH);
    }

    function test_setAdminStructure_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleCurve.setAdminStructure(address(0));
    }

    function test_setAdminStructure_ShouldFailIfAdminStructureIsNotContract() external {
        vm.prank(oracleCurve.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        oracleCurve.setAdminStructure(address(0));
    }

    function test_setAdminStructure() external {
        address newAdminStructure = address(this);
        address adminStructureBefore = address(oracleCurve.adminStructure());

        vm.prank(oracleCurve.adminStructure().superAdmin());

        oracleCurve.setAdminStructure(newAdminStructure);

        address adminStructureAfter = address(oracleCurve.adminStructure());

        assertTrue(adminStructureAfter == newAdminStructure);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_latestAnswer() external {
        assertEq(oracleCurve.latestAnswer(), 1_673_365_756_314_405_165_709);
    }

    function test_latestRoundData() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleCurve.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 1_673_365_756_314_405_165_709);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_decimals() external {
        assertEq(oracleCurve.decimals(), 18);
    }
}
