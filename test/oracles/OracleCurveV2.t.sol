// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { OracleErrors } from "src/libraries/OracleErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { OracleCurveV2 } from "src/oracles/OracleCurveV2.sol";
import { ICurvePool } from "src/interfaces/ICurve.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";

import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract OracleCurveV2Mock is OracleCurveV2 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _adminStructure,
        address _strategyHelper,
        address _pool,
        uint256 _index,
        address _weth
    )
        external
        initializer
    {
        _oracleCurveInitUnchained(_adminStructure, _strategyHelper, _pool, _index, _weth);
    }

    function _getAmountTokenA(address _tokenA) internal view override returns (uint256) {
        return 10 ** IERC20(_tokenA).decimals();
    }
}

contract OracleCurveV2Test is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    address curveOracle;

    StrategyHelper public strategyHelper;
    OracleCurveV2Mock public oracleCurve;
    uint256 public index = 0;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 19_030_272);

        Proxy strategyHelperProxy =
            new Proxy(address(new StrategyHelper()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE));

        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        vm.prank(strategyHelper.adminStructure().superAdmin());

        strategyHelper.setOracle(WETH, ETH_ORACLE);

        // TODO make it generic
        // deploy curve oracle mock
        // get token address from it

        curveOracle = 0xc5424B857f758E906013F3555Dad202e4bdB4567;

        Proxy oracleCurveProxy = new Proxy(
            address(new OracleCurveV2Mock()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                curveOracle,
                index,
                WETH
            )
        );

        oracleCurve = OracleCurveV2Mock(address(oracleCurveProxy));
    }

    function test_adminStructure() external {
        assertEq(address(oracleCurve.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_strategyHelper() external {
        assertEq(address(oracleCurve.strategyHelper()), address(strategyHelper));
    }

    function test_pool() external {
        assertEq(address(oracleCurve.pool()), curveOracle);
    }

    function test_index() external {
        assertEq(oracleCurve.index(), index);
    }

    function test_tokenA() external {
        assertEq(oracleCurve.tokenA(), ETH);
    }

    function test_tokenB() external {
        assertEq(oracleCurve.tokenB(), 0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb);
    }

    function test_weth() external {
        assertEq(address(oracleCurve.weth()), WETH);
    }

    function test_initialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        oracleCurve.initialize(ADMIN_STRUCTURE, address(strategyHelper), curveOracle, index, WETH);
    }

    function test_initialize_ShouldFailIfAdminStructureIsNotContract() external {
        OracleCurveV2Mock newOracleCurve = new OracleCurveV2Mock();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                address(0),
                address(strategyHelper),
                curveOracle,
                index,
                WETH
            )
        );
    }

    function test_initialize_ShouldFailIfStrategyHelperIsNotContract() external {
        OracleCurveV2Mock newOracleCurve = new OracleCurveV2Mock();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(0),
                curveOracle,
                index,
                WETH
            )
        );
    }

    function test_initialize_ShouldFailIfPoolIsNotContract() external {
        OracleCurveV2Mock newOracleCurve = new OracleCurveV2Mock();

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
        OracleCurveV2Mock newOracleCurve = new OracleCurveV2Mock();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                curveOracle,
                index,
                address(0)
            )
        );
    }

    function test_initialize_ShouldFailIfIndexIsGT1() external {
        OracleCurveV2Mock newOracleCurve = new OracleCurveV2Mock();

        vm.expectRevert(abi.encodeWithSelector(OracleErrors.WrongCurvePoolTokenIndex.selector));

        new Proxy(
            address(newOracleCurve),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                curveOracle,
                2,
                WETH
            )
        );
    }

    function test_initialize() external {
        Proxy oracleCurveProxy = new Proxy(
            address(new OracleCurveV2Mock()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                ADMIN_STRUCTURE,
                address(strategyHelper),
                curveOracle,
                index,
                WETH
            )
        );
        OracleCurveV2Mock newOracleCurve = OracleCurveV2Mock(address(oracleCurveProxy));

        assertEq(address(newOracleCurve.adminStructure()), ADMIN_STRUCTURE);
        assertEq(address(newOracleCurve.strategyHelper()), address(strategyHelper));
        assertEq(address(newOracleCurve.pool()), curveOracle);
        assertEq(newOracleCurve.index(), index);
        assertEq(newOracleCurve.tokenA(), 0x0000000000000000000000000000000000000000);
        assertEq(newOracleCurve.tokenB(), 0x5e74C9036fb86BD7eCdcb084a0673EFc32eA31cb);
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
}
