// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { OracleCamelotV3 } from "src/oracles/OracleCamelotV3.sol";
import { ICamelotV3Pool } from "src/interfaces/ICamelotV3.sol";
import { OracleErrors } from "src/libraries/OracleErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import "../../addresses/ARBMainnet.sol";
import "forge-std/Test.sol";

contract OracleCamelotV3Test is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    OracleCamelotV3 public oracleCamelotV3;

    uint32 public twapPeriod;
    uint32 public validityDuration;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ARB_MAINNET"), 161_911_790);

        twapPeriod = 2 minutes;
        validityDuration = 12 hours;

        Proxy oracleCamelotV3Proxy = new Proxy(
            address(new OracleCamelotV3()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                CAMELOT_V3_PNP_WETH_POOL,
                WETH,
                twapPeriod,
                validityDuration
            )
        );

        oracleCamelotV3 = OracleCamelotV3(address(oracleCamelotV3Proxy));
    }

    function test_MAX_VALIDITY_DURATION() external {
        assertEq(oracleCamelotV3.MAX_VALIDITY_DURATION(), 2 days);
    }

    function test_MIN_TWAB_PERIOD() external {
        assertEq(oracleCamelotV3.MIN_TWAB_PERIOD(), 2 minutes);
    }

    function test_adminStructure() external {
        assertEq(address(oracleCamelotV3.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_ethOracle() external {
        assertEq(address(oracleCamelotV3.ethOracle()), ETH_ORACLE);
    }

    function test_pool() external {
        assertEq(address(oracleCamelotV3.pool()), CAMELOT_V3_PNP_WETH_POOL);
    }

    function test_weth() external {
        assertEq(oracleCamelotV3.weth(), WETH);
    }

    function test_twapPeriod() external {
        assertEq(oracleCamelotV3.twapPeriod(), twapPeriod);
    }

    function test_validityDuration() external {
        assertEq(oracleCamelotV3.validityDuration(), validityDuration);
    }

    function test_initialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        oracleCamelotV3.initialize(
            ADMIN_STRUCTURE, ETH_ORACLE, CAMELOT_V3_PNP_WETH_POOL, WETH, twapPeriod, validityDuration
        );
    }

    function test_initialize_ShouldFailIfAdminStructureIsNotContract() external {
        OracleCamelotV3 newOracleCamelotV3 = new OracleCamelotV3();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCamelotV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                address(0),
                ETH_ORACLE,
                CAMELOT_V3_PNP_WETH_POOL,
                WETH,
                twapPeriod,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfEthOracleIsNotContract() external {
        OracleCamelotV3 newOracleCamelotV3 = new OracleCamelotV3();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCamelotV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                address(0),
                CAMELOT_V3_PNP_WETH_POOL,
                WETH,
                twapPeriod,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfPoolIsNotContract() external {
        OracleCamelotV3 newOracleCamelotV3 = new OracleCamelotV3();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCamelotV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                address(0),
                WETH,
                twapPeriod,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfWethIsNotContract() external {
        OracleCamelotV3 newOracleCamelotV3 = new OracleCamelotV3();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleCamelotV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                CAMELOT_V3_PNP_WETH_POOL,
                address(0),
                twapPeriod,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfTwabPeriodIsTooShort() external {
        OracleCamelotV3 newOracleCamelotV3 = new OracleCamelotV3();

        vm.expectRevert(OracleErrors.WrongTwabPeriod.selector);

        new Proxy(
            address(newOracleCamelotV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                CAMELOT_V3_PNP_WETH_POOL,
                WETH,
                2 minutes - 1 seconds,
                2 days
            )
        );
    }

    function test_initialize_ShouldFailIfValidityDurationIsTooShort() external {
        OracleCamelotV3 newOracleCamelotV3 = new OracleCamelotV3();

        vm.expectRevert(OracleErrors.WrongValidityDuration.selector);

        new Proxy(
            address(newOracleCamelotV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                CAMELOT_V3_PNP_WETH_POOL,
                WETH,
                twapPeriod,
                0
            )
        );
    }

    function test_initialize_ShouldFailIfValidityDurationIsTooLong() external {
        OracleCamelotV3 newOracleCamelotV3 = new OracleCamelotV3();

        vm.expectRevert(OracleErrors.WrongValidityDuration.selector);

        new Proxy(
            address(newOracleCamelotV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                CAMELOT_V3_PNP_WETH_POOL,
                WETH,
                twapPeriod,
                2 days + 1 seconds
            )
        );
    }

    function test_initialize() external {
        Proxy oracleCamelotV3Proxy = new Proxy(
            address(new OracleCamelotV3()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                CAMELOT_V3_PNP_WETH_POOL,
                WETH,
                twapPeriod,
                validityDuration
            )
        );
        OracleCamelotV3 newOracleCamelotV3 = OracleCamelotV3(address(oracleCamelotV3Proxy));

        assertEq(address(newOracleCamelotV3.adminStructure()), ADMIN_STRUCTURE);
        assertEq(address(newOracleCamelotV3.ethOracle()), ETH_ORACLE);
        assertEq(address(newOracleCamelotV3.pool()), CAMELOT_V3_PNP_WETH_POOL);
        assertEq(newOracleCamelotV3.weth(), WETH);
        assertEq(newOracleCamelotV3.twapPeriod(), twapPeriod);
        assertEq(newOracleCamelotV3.validityDuration(), validityDuration);
    }

    function test_setAdminStructure_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleCamelotV3.setAdminStructure(address(0));
    }

    function test_setAdminStructure_ShouldFailIfAdminStructureIsNotContract() external {
        vm.prank(oracleCamelotV3.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        oracleCamelotV3.setAdminStructure(address(0));
    }

    function test_setAdminStructure() external {
        address newAdminStructure = address(this);
        address adminStructureBefore = address(oracleCamelotV3.adminStructure());

        vm.prank(oracleCamelotV3.adminStructure().superAdmin());

        oracleCamelotV3.setAdminStructure(newAdminStructure);

        address adminStructureAfter = address(oracleCamelotV3.adminStructure());

        assertTrue(adminStructureAfter == newAdminStructure);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_setTwapPeriod_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleCamelotV3.setTwapPeriod(0);
    }

    function test_setTwapPeriod_ShouldFailIfTwabPeriodIsTooShort() external {
        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());
        vm.expectRevert(OracleErrors.WrongTwabPeriod.selector);

        oracleCamelotV3.setTwapPeriod(2 minutes - 1 seconds);
    }

    function test_setTwapPeriod() external {
        uint32 newTwapPeriod = 3 minutes;

        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());

        oracleCamelotV3.setTwapPeriod(newTwapPeriod);

        assertEq(oracleCamelotV3.twapPeriod(), newTwapPeriod);
    }

    function test_setValidityDuration_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleCamelotV3.setValidityDuration(0);
    }

    function test_setValidityDuration_ShouldFailIfValidityDurationIsTooShort() external {
        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());
        vm.expectRevert(OracleErrors.WrongValidityDuration.selector);

        oracleCamelotV3.setValidityDuration(0);
    }

    function test_setValidityDuration_ShouldFailIfValidityDurationIsTooLong() external {
        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());
        vm.expectRevert(OracleErrors.WrongValidityDuration.selector);

        oracleCamelotV3.setValidityDuration(2 days + 1 seconds);
    }

    function test_setValidityDuration() external {
        uint32 newValidityDuration = 6 hours;

        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());

        oracleCamelotV3.setValidityDuration(newValidityDuration);

        assertEq(oracleCamelotV3.validityDuration(), newValidityDuration);
    }

    function test_latestAnswer_ShouldFailIfPriceIsStale() external {
        vm.warp(block.timestamp + validityDuration);
        vm.expectRevert(OracleErrors.StalePrice.selector);

        oracleCamelotV3.latestAnswer();
    }

    function test_latestAnswer() external {
        assertEq(oracleCamelotV3.latestAnswer(), 2_491_265_992_205_489_602);
    }

    function test_latestAnswer_MatchesPeriod() external {
        vm.prank(oracleCamelotV3.adminStructure().superAdmin());

        oracleCamelotV3.setTwapPeriod(9_213_361);

        int56[] memory _tickCumulatives = new int56[](2);

        _tickCumulatives[0] = -53_909_406_369_491;
        _tickCumulatives[1] = -53_909_415_582_851;

        uint160[] memory _secondsPerLiquidityCumulatives;
        uint112[] memory _volatilityCumulatives;
        uint256[] memory _volumePerAvgLiquiditys;

        vm.mockCall(
            CAMELOT_V3_PNP_WETH_POOL,
            abi.encodeWithSelector(ICamelotV3Pool.getTimepoints.selector),
            abi.encode(
                _tickCumulatives, _secondsPerLiquidityCumulatives, _volatilityCumulatives, _volumePerAvgLiquiditys
            )
        );

        assertEq(oracleCamelotV3.latestAnswer(), 2_210_892_589_231_076_890_121);
    }

    function test_latestAnswer_InvalidDelta() external {
        vm.prank(oracleCamelotV3.adminStructure().superAdmin());

        oracleCamelotV3.setTwapPeriod(9_213_361);

        int56[] memory _tickCumulatives = new int56[](2);

        _tickCumulatives[0] = -53_909_406_369_491;
        _tickCumulatives[1] = -53_909_406_369_490;

        uint160[] memory _secondsPerLiquidityCumulatives;
        uint112[] memory _volatilityCumulatives;
        uint256[] memory _volumePerAvgLiquiditys;

        vm.mockCall(
            CAMELOT_V3_PNP_WETH_POOL,
            abi.encodeWithSelector(ICamelotV3Pool.getTimepoints.selector),
            abi.encode(
                _tickCumulatives, _secondsPerLiquidityCumulatives, _volatilityCumulatives, _volumePerAvgLiquiditys
            )
        );

        oracleCamelotV3.latestAnswer();
    }

    function test_latestRoundData_ShouldFailIfPriceIsStale() external {
        vm.warp(block.timestamp + validityDuration);
        vm.expectRevert(OracleErrors.StalePrice.selector);

        oracleCamelotV3.latestRoundData();
    }

    function test_latestRoundData() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleCamelotV3.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 2_491_265_992_205_489_602);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_decimals() external {
        assertEq(oracleCamelotV3.decimals(), 18);
    }
}
