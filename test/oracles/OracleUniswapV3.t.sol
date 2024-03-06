// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IUniswapV3PoolDerivedState } from "@uniswap/v3-core/contracts/interfaces/pool/IUniswapV3PoolDerivedState.sol";
import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { OracleUniswapV3 } from "src/oracles/OracleUniswapV3.sol";
import { OracleErrors } from "src/libraries/OracleErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract OracleUniswapV3Test is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    OracleUniswapV3 public oracleUniswapV3;

    uint32 public twapPeriod;
    uint32 public validityDuration;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_412_791);

        twapPeriod = 2 minutes;
        validityDuration = 12 hours;

        Proxy oracleUniswapV3Proxy = new Proxy(
            address(new OracleUniswapV3()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_PENDLE_WETH_POOL,
                WETH,
                twapPeriod,
                validityDuration
            )
        );

        oracleUniswapV3 = OracleUniswapV3(address(oracleUniswapV3Proxy));
    }

    function test_adminStructure() external {
        assertEq(address(oracleUniswapV3.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_ethOracle() external {
        assertEq(address(oracleUniswapV3.ethOracle()), ETH_ORACLE);
    }

    function test_pool() external {
        assertEq(address(oracleUniswapV3.pool()), UNISWAP_PENDLE_WETH_POOL);
    }

    function test_weth() external {
        assertEq(address(oracleUniswapV3.weth()), WETH);
    }

    function test_twapPeriod() external {
        assertEq(oracleUniswapV3.twapPeriod(), twapPeriod);
    }

    function test_validityDuration() external {
        assertEq(oracleUniswapV3.validityDuration(), validityDuration);
    }

    function test_initialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        oracleUniswapV3.initialize(
            ADMIN_STRUCTURE, ETH_ORACLE, UNISWAP_PENDLE_WETH_POOL, WETH, twapPeriod, validityDuration
        );
    }

    function test_initialize_ShouldFailIfAdminStructureIsNotContract() external {
        OracleUniswapV3 newOracleUniswapV3 = new OracleUniswapV3();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleUniswapV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                address(0),
                ETH_ORACLE,
                UNISWAP_PENDLE_WETH_POOL,
                WETH,
                twapPeriod,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfEthOracleIsNotContract() external {
        OracleUniswapV3 newOracleUniswapV3 = new OracleUniswapV3();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleUniswapV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                address(0),
                UNISWAP_PENDLE_WETH_POOL,
                WETH,
                twapPeriod,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfPoolIsNotContract() external {
        OracleUniswapV3 newOracleUniswapV3 = new OracleUniswapV3();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleUniswapV3),
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
        OracleUniswapV3 newOracleUniswapV3 = new OracleUniswapV3();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleUniswapV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_PENDLE_WETH_POOL,
                address(0),
                twapPeriod,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfTwabPeriodIsTooShort() external {
        OracleUniswapV3 newOracleUniswapV3 = new OracleUniswapV3();

        vm.expectRevert(OracleErrors.WrongTwabPeriod.selector);

        new Proxy(
            address(newOracleUniswapV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_PENDLE_WETH_POOL,
                WETH,
                2 minutes - 1 seconds,
                2 days
            )
        );
    }

    function test_initialize_ShouldFailIfValidityDurationIsTooShort() external {
        OracleUniswapV3 newOracleUniswapV3 = new OracleUniswapV3();

        vm.expectRevert(OracleErrors.WrongValidityDuration.selector);

        new Proxy(
            address(newOracleUniswapV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_PENDLE_WETH_POOL,
                WETH,
                twapPeriod,
                0
            )
        );
    }

    function test_initialize_ShouldFailIfValidityDurationIsTooLong() external {
        OracleUniswapV3 newOracleUniswapV3 = new OracleUniswapV3();

        vm.expectRevert(OracleErrors.WrongValidityDuration.selector);

        new Proxy(
            address(newOracleUniswapV3),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_PENDLE_WETH_POOL,
                WETH,
                twapPeriod,
                2 days + 1 seconds
            )
        );
    }

    function test_initialize() external {
        Proxy oracleUniswapV3Proxy = new Proxy(
            address(new OracleUniswapV3()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_PENDLE_WETH_POOL,
                WETH,
                twapPeriod,
                validityDuration
            )
        );
        OracleUniswapV3 newOracleUniswapV3 = OracleUniswapV3(address(oracleUniswapV3Proxy));

        assertEq(address(newOracleUniswapV3.adminStructure()), ADMIN_STRUCTURE);
        assertEq(address(newOracleUniswapV3.ethOracle()), ETH_ORACLE);
        assertEq(address(newOracleUniswapV3.pool()), UNISWAP_PENDLE_WETH_POOL);
        assertEq(address(newOracleUniswapV3.weth()), WETH);
        assertEq(newOracleUniswapV3.twapPeriod(), twapPeriod);
        assertEq(newOracleUniswapV3.validityDuration(), validityDuration);
    }

    function test_setAdminStructure_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleUniswapV3.setAdminStructure(address(0));
    }

    function test_setAdminStructure_ShouldFailIfAdminStructureIsNotContract() external {
        vm.prank(oracleUniswapV3.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        oracleUniswapV3.setAdminStructure(address(0));
    }

    function test_setAdminStructure() external {
        address newAdminStructure = address(this);
        address adminStructureBefore = address(oracleUniswapV3.adminStructure());

        vm.prank(oracleUniswapV3.adminStructure().superAdmin());

        oracleUniswapV3.setAdminStructure(newAdminStructure);

        address adminStructureAfter = address(oracleUniswapV3.adminStructure());

        assertTrue(adminStructureAfter == newAdminStructure);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_setTwapPeriod_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleUniswapV3.setTwapPeriod(0);
    }

    function test_setTwapPeriod_ShouldFailIfTwabPeriodIsTooShort() external {
        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());
        vm.expectRevert(OracleErrors.WrongTwabPeriod.selector);

        oracleUniswapV3.setTwapPeriod(2 minutes - 1 seconds);
    }

    function test_setTwapPeriod() external {
        uint32 newTwapPeriod = 3 minutes;

        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());

        oracleUniswapV3.setTwapPeriod(newTwapPeriod);

        assertEq(oracleUniswapV3.twapPeriod(), newTwapPeriod);
    }

    function test_setValidityDuration_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleUniswapV3.setValidityDuration(0);
    }

    function test_setValidityDuration_ShouldFailIfValidityDurationIsTooShort() external {
        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());
        vm.expectRevert(OracleErrors.WrongValidityDuration.selector);

        oracleUniswapV3.setValidityDuration(0);
    }

    function test_setValidityDuration_ShouldFailIfValidityDurationIsTooLong() external {
        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());
        vm.expectRevert(OracleErrors.WrongValidityDuration.selector);

        oracleUniswapV3.setValidityDuration(2 days + 1 seconds);
    }

    function test_setValidityDuration() external {
        uint32 newValidityDuration = 6 hours;

        vm.prank(IAdminStructure(ADMIN_STRUCTURE).superAdmin());

        oracleUniswapV3.setValidityDuration(newValidityDuration);

        assertEq(oracleUniswapV3.validityDuration(), newValidityDuration);
    }

    function test_latestAnswer_ShouldFailIfPriceIsStale() external {
        vm.warp(block.timestamp + validityDuration);
        vm.expectRevert(OracleErrors.StalePrice.selector);

        oracleUniswapV3.latestAnswer();
    }

    function test_latestAnswer() external {
        assertEq(oracleUniswapV3.latestAnswer(), 775_452_508_719_086_118);
    }

    function test_latestAnswer_MatchesPeriod() external {
        vm.prank(oracleUniswapV3.adminStructure().superAdmin());

        oracleUniswapV3.setTwapPeriod(9_213_361);

        int56[] memory _tickCumulatives = new int56[](2);

        _tickCumulatives[0] = -53_909_406_369_491;
        _tickCumulatives[1] = -53_909_415_582_851;

        uint160[] memory _secondsPerLiquidityCumulativeX128s;

        vm.mockCall(
            UNISWAP_PENDLE_WETH_POOL,
            abi.encodeWithSelector(IUniswapV3PoolDerivedState.observe.selector),
            abi.encode(_tickCumulatives, _secondsPerLiquidityCumulativeX128s)
        );

        assertEq(oracleUniswapV3.latestAnswer(), 1_674_060_853_914_608_537_488);
    }

    function test_latestAnswer_InvalidDelta() external {
        vm.prank(oracleUniswapV3.adminStructure().superAdmin());

        oracleUniswapV3.setTwapPeriod(9_213_361);

        int56[] memory _tickCumulatives = new int56[](2);

        _tickCumulatives[0] = -53_909_406_369_491;
        _tickCumulatives[1] = -53_909_406_369_490;

        uint160[] memory _secondsPerLiquidityCumulativeX128s;

        vm.mockCall(
            UNISWAP_PENDLE_WETH_POOL,
            abi.encodeWithSelector(IUniswapV3PoolDerivedState.observe.selector),
            abi.encode(_tickCumulatives, _secondsPerLiquidityCumulativeX128s)
        );

        oracleUniswapV3.latestAnswer();
    }

    function test_latestRoundData_ShouldFailIfPriceIsStale() external {
        vm.warp(block.timestamp + validityDuration);
        vm.expectRevert(OracleErrors.StalePrice.selector);

        oracleUniswapV3.latestRoundData();
    }

    function test_latestRoundData() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleUniswapV3.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 775_452_508_719_086_118);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_decimals() external {
        assertEq(oracleUniswapV3.decimals(), 18);
    }
}
