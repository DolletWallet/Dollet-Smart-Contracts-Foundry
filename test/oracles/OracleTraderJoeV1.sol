// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { TemporaryAdminStructure } from "src/admin/TemporaryAdminStructure.sol";
import { OracleTraderJoeV1 } from "src/oracles/OracleTraderJoeV1.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import "../../addresses/AVAXMainnet.sol";
import "forge-std/Test.sol";

contract OracleTraderJoeV1Test is Test {
    TemporaryAdminStructure public adminStructure;
    StrategyHelper public strategyHelper;
    OracleTraderJoeV1 public oracleTraderJoeV1;

    address public alice;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_AVAX_MAINNET"), 42_300_708);

        (alice,) = makeAddrAndKey("Alice");

        Proxy adminStructureProxy =
            new Proxy(address(new TemporaryAdminStructure()), abi.encodeWithSignature("initialize()"));
        adminStructure = TemporaryAdminStructure(address(adminStructureProxy));

        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()), abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        vm.prank(strategyHelper.adminStructure().superAdmin());

        strategyHelper.setOracle(WAVAX, AVAX_ORACLE);

        Proxy oracleProxy = new Proxy(
            address(new OracleTraderJoeV1()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(adminStructure),
                address(strategyHelper),
                TRADER_JOE_V1_ROUTER,
                WOM,
                WAVAX,
                WAVAX
            )
        );
        oracleTraderJoeV1 = OracleTraderJoeV1(address(oracleProxy));
    }

    function test_initialize_Fail_MethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        oracleTraderJoeV1.initialize(
            address(adminStructure), address(strategyHelper), TRADER_JOE_V1_ROUTER, WOM, WAVAX, WAVAX
        );
    }

    function test_initialize_Fail_AdminStructureIsNotContract() external {
        OracleTraderJoeV1 newOracle = new OracleTraderJoeV1();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracle),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(0),
                address(strategyHelper),
                TRADER_JOE_V1_ROUTER,
                WOM,
                WAVAX,
                WAVAX
            )
        );
    }

    function test_initialize_Fail_StrategyHelperIsNotContract() external {
        OracleTraderJoeV1 newOracle = new OracleTraderJoeV1();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracle),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(adminStructure),
                address(0),
                TRADER_JOE_V1_ROUTER,
                WOM,
                WAVAX,
                WAVAX
            )
        );
    }

    function test_initialize_Fail_RouterIsNotContract() external {
        OracleTraderJoeV1 newOracle = new OracleTraderJoeV1();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracle),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(adminStructure),
                address(strategyHelper),
                address(0),
                WOM,
                WAVAX,
                WAVAX
            )
        );
    }

    function test_initialize_Fail_TokenAIsNotContract() external {
        OracleTraderJoeV1 newOracle = new OracleTraderJoeV1();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracle),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(adminStructure),
                address(strategyHelper),
                TRADER_JOE_V1_ROUTER,
                address(0),
                WAVAX,
                WAVAX
            )
        );
    }

    function test_initialize_Fail_TokenBIsNotContract() external {
        OracleTraderJoeV1 newOracle = new OracleTraderJoeV1();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracle),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(adminStructure),
                address(strategyHelper),
                TRADER_JOE_V1_ROUTER,
                WOM,
                address(0),
                WAVAX
            )
        );
    }

    function test_initialize_Fail_WethIsNotContract() external {
        OracleTraderJoeV1 newOracle = new OracleTraderJoeV1();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracle),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(adminStructure),
                address(strategyHelper),
                TRADER_JOE_V1_ROUTER,
                WOM,
                WAVAX,
                address(0)
            )
        );
    }

    function test_initialize_Success() external {
        Proxy oracleProxy = new Proxy(
            address(new OracleTraderJoeV1()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(adminStructure),
                address(strategyHelper),
                TRADER_JOE_V1_ROUTER,
                WOM,
                WAVAX,
                WAVAX
            )
        );
        OracleTraderJoeV1 newOracle = OracleTraderJoeV1(address(oracleProxy));

        assertEq(address(newOracle.adminStructure()), address(adminStructure));
        assertEq(address(newOracle.strategyHelper()), address(strategyHelper));
        assertEq(address(newOracle.router()), TRADER_JOE_V1_ROUTER);
        assertEq(newOracle.tokenA(), WOM);
        assertEq(newOracle.tokenB(), WAVAX);
        assertEq(address(newOracle.weth()), WAVAX);
    }

    function test_setAdminStructure_Fail_IfNotSuperAdminIsCalling() external {
        vm.startPrank(alice);
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleTraderJoeV1.setAdminStructure(WOM);
    }

    function test_setAdminStructure_Fail_IfAdminStructureIsNotContract() external {
        vm.prank(oracleTraderJoeV1.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        oracleTraderJoeV1.setAdminStructure(address(0));
    }

    function test_setAdminStructure_Success() external {
        address newAdminStructure = address(this);
        address adminStructureBefore = address(oracleTraderJoeV1.adminStructure());

        vm.prank(oracleTraderJoeV1.adminStructure().superAdmin());

        oracleTraderJoeV1.setAdminStructure(newAdminStructure);

        address adminStructureAfter = address(oracleTraderJoeV1.adminStructure());

        assertTrue(adminStructureAfter == newAdminStructure);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_latestAnswer() external {
        assertEq(oracleTraderJoeV1.latestAnswer(), 37_033_676_911_276_818);
    }

    function test_latestRoundData() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleTraderJoeV1.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 37_033_676_911_276_818);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_decimals() external {
        assertEq(oracleTraderJoeV1.decimals(), 18);
    }
}
