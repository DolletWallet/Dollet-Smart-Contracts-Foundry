// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { OracleCamelotV2Usd } from "src/oracles/OracleCamelotV2Usd.sol";
import { ICamelotV3Pool } from "src/interfaces/ICamelotV3.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import "../../addresses/ARBMainnet.sol";
import "forge-std/Test.sol";

contract OracleCamelotV2UsdTest is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    address public USDC_USDT = 0x1C31fB3359357f6436565cCb3E982Bc6Bf4189ae;
    address public pair = CAMELOT_V2_WOM_USDT_POOL;
    address public USD = USDT;

    OracleCamelotV2Usd public oracleCamelotV2Usd;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ARB_MAINNET"), 180_321_801);

        Proxy oracleCamelotV2UsdProxy = new Proxy(
            address(new OracleCamelotV2Usd()),
            abi.encodeWithSignature("initialize(address,address,address)", ADMIN_STRUCTURE, pair, USD)
        );

        oracleCamelotV2Usd = OracleCamelotV2Usd(address(oracleCamelotV2UsdProxy));
    }

    function test_adminStructure() external {
        assertEq(address(oracleCamelotV2Usd.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_pair() external {
        assertEq(address(oracleCamelotV2Usd.pair()), pair);
    }

    function test_usd() external {
        assertEq(address(oracleCamelotV2Usd.usd()), USD);
    }

    function test_initialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        oracleCamelotV2Usd.initialize(ADMIN_STRUCTURE, pair, USD);
    }

    function test_initialize_ShouldFailIfAdminStructureIsNotContract() external {
        OracleCamelotV2Usd newOracleCamelotV2Usd = new OracleCamelotV2Usd();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCamelotV2Usd),
            abi.encodeWithSignature("initialize(address,address,address)", address(0), pair, USD)
        );
    }

    function test_initialize_ShouldFailIfPairIsNotContract() external {
        OracleCamelotV2Usd newOracleCamelotV2Usd = new OracleCamelotV2Usd();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCamelotV2Usd),
            abi.encodeWithSignature("initialize(address,address,address)", ADMIN_STRUCTURE, address(0), USD)
        );
    }

    function test_initialize_ShouldFailIfUSDIsNotContract() external {
        OracleCamelotV2Usd newOracleCamelotV2Usd = new OracleCamelotV2Usd();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCamelotV2Usd),
            abi.encodeWithSignature("initialize(address,address,address)", ADMIN_STRUCTURE, pair, address(0))
        );
    }

    function test_initialize() external {
        Proxy oracleCamelotV2UsdProxy = new Proxy(
            address(new OracleCamelotV2Usd()),
            abi.encodeWithSignature("initialize(address,address,address)", ADMIN_STRUCTURE, pair, USD)
        );
        OracleCamelotV2Usd newOracleCamelotV2Usd = OracleCamelotV2Usd(address(oracleCamelotV2UsdProxy));

        assertEq(address(newOracleCamelotV2Usd.adminStructure()), ADMIN_STRUCTURE);
        assertEq(address(newOracleCamelotV2Usd.pair()), pair);
        assertEq(address(newOracleCamelotV2Usd.usd()), USD);
    }

    function test_setAdminStructure_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleCamelotV2Usd.setAdminStructure(address(0));
    }

    function test_setAdminStructure() external {
        address newAdminStructure = address(this);
        address adminStructureBefore = address(oracleCamelotV2Usd.adminStructure());

        vm.prank(oracleCamelotV2Usd.adminStructure().superAdmin());

        oracleCamelotV2Usd.setAdminStructure(newAdminStructure);

        address adminStructureAfter = address(oracleCamelotV2Usd.adminStructure());

        assertTrue(adminStructureAfter == newAdminStructure);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_latestAnswer() external {
        // 1 WOM = 0,0293045258 USDT
        assertEq(oracleCamelotV2Usd.latestAnswer(), 29_304_525_796_607_306);
    }

    function test_latestRoundData() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleCamelotV2Usd.latestRoundData();

        assertEq(roundId, 0);
        // 1 WOM = 0,0293045258 USDT
        assertEq(answer, 29_304_525_796_607_306);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_decimals() external {
        assertEq(oracleCamelotV2Usd.decimals(), 18);
    }
}
