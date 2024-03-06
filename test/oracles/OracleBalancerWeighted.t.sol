// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { OracleBalancerWeighted } from "src/oracles/OracleBalancerWeighted.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { OracleErrors } from "src/libraries/OracleErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract OracleBalancerWeightedTest is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;
    address public constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address public constant POOL = 0xFD1Cf6FD41F229Ca86ada0584c63C49C3d66BbC9;
    address public constant WRONG_POOL = 0x42ED016F826165C2e5976fe5bC3df540C5aD0Af7;

    OracleBalancerWeighted public oracleBalancerWeighted;

    uint32 public validityDuration;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_742_359);

        validityDuration = 12 hours;

        Proxy oracleBalancerWeightedProxy = new Proxy(
            address(new OracleBalancerWeighted()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                VAULT,
                POOL,
                ETH_ORACLE,
                WETH,
                validityDuration
            )
        );

        oracleBalancerWeighted = OracleBalancerWeighted(address(oracleBalancerWeightedProxy));
    }

    function test_adminStructure() external {
        assertEq(address(oracleBalancerWeighted.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_vault() external {
        assertEq(address(oracleBalancerWeighted.vault()), VAULT);
    }

    function test_pool() external {
        assertEq(address(oracleBalancerWeighted.pool()), POOL);
    }

    function test_ethOracle() external {
        assertEq(address(oracleBalancerWeighted.ethOracle()), ETH_ORACLE);
    }

    function test_tokenIndex() external {
        assertEq(oracleBalancerWeighted.tokenIndex(), 0);
    }

    function test_wethIndex() external {
        assertEq(oracleBalancerWeighted.wethIndex(), 1);
    }

    function test_validityDuration() external {
        assertEq(oracleBalancerWeighted.validityDuration(), validityDuration);
    }

    function test_initialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        oracleBalancerWeighted.initialize(ADMIN_STRUCTURE, VAULT, POOL, ETH_ORACLE, WETH, validityDuration);
    }

    function test_initialize_ShouldFailIfAdminStructureIsNotContract() external {
        OracleBalancerWeighted newOracleBalancerWeighted = new OracleBalancerWeighted();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleBalancerWeighted),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                address(0),
                VAULT,
                POOL,
                ETH_ORACLE,
                WETH,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfVaultIsNotContract() external {
        OracleBalancerWeighted newOracleBalancerWeighted = new OracleBalancerWeighted();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleBalancerWeighted),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                address(0),
                POOL,
                ETH_ORACLE,
                WETH,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfPoolIsNotContract() external {
        OracleBalancerWeighted newOracleBalancerWeighted = new OracleBalancerWeighted();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleBalancerWeighted),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                VAULT,
                address(0),
                ETH_ORACLE,
                WETH,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfEthOracleIsNotContract() external {
        OracleBalancerWeighted newOracleBalancerWeighted = new OracleBalancerWeighted();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleBalancerWeighted),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                VAULT,
                POOL,
                address(0),
                WETH,
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfWethIsNotContract() external {
        OracleBalancerWeighted newOracleBalancerWeighted = new OracleBalancerWeighted();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newOracleBalancerWeighted),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                VAULT,
                POOL,
                ETH_ORACLE,
                address(0),
                validityDuration
            )
        );
    }

    function test_initialize_ShouldFailIfValidityDurationIsTooShort() external {
        OracleBalancerWeighted newOracleBalancerWeighted = new OracleBalancerWeighted();

        vm.expectRevert(abi.encodeWithSelector(OracleErrors.WrongValidityDuration.selector));

        new Proxy(
            address(newOracleBalancerWeighted),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                VAULT,
                POOL,
                ETH_ORACLE,
                WETH,
                0
            )
        );
    }

    function test_initialize_ShouldFailIfValidityDurationIsTooLong() external {
        OracleBalancerWeighted newOracleBalancerWeighted = new OracleBalancerWeighted();

        vm.expectRevert(abi.encodeWithSelector(OracleErrors.WrongValidityDuration.selector));

        new Proxy(
            address(newOracleBalancerWeighted),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                VAULT,
                POOL,
                ETH_ORACLE,
                WETH,
                2 days + 1
            )
        );
    }

    function test_initialize_ShouldFailIfWrongBalancerPoolTokensNumber() external {
        OracleBalancerWeighted newOracleBalancerWeighted = new OracleBalancerWeighted();

        vm.expectRevert(abi.encodeWithSelector(OracleErrors.WrongBalancerPoolTokensNumber.selector));

        new Proxy(
            address(newOracleBalancerWeighted),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                VAULT,
                WRONG_POOL,
                ETH_ORACLE,
                WETH,
                validityDuration
            )
        );
    }

    function test_initialize() external {
        Proxy oracleBalancerWeightedProxy = new Proxy(
            address(new OracleBalancerWeighted()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                ADMIN_STRUCTURE,
                VAULT,
                POOL,
                ETH_ORACLE,
                WETH,
                validityDuration
            )
        );
        OracleBalancerWeighted newOracleBalancerWeighted = OracleBalancerWeighted(address(oracleBalancerWeightedProxy));

        assertEq(address(newOracleBalancerWeighted.adminStructure()), ADMIN_STRUCTURE);
        assertEq(address(newOracleBalancerWeighted.vault()), VAULT);
        assertEq(address(newOracleBalancerWeighted.pool()), POOL);
        assertEq(address(newOracleBalancerWeighted.ethOracle()), ETH_ORACLE);
        assertEq(newOracleBalancerWeighted.tokenIndex(), 0);
        assertEq(newOracleBalancerWeighted.wethIndex(), 1);
        assertEq(newOracleBalancerWeighted.validityDuration(), validityDuration);
    }

    function test_setAdminStructure_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleBalancerWeighted.setAdminStructure(address(0));
    }

    function test_setAdminStructure_ShouldFailIfAdminStructureIsNotContract() external {
        vm.prank(oracleBalancerWeighted.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        oracleBalancerWeighted.setAdminStructure(address(0));
    }

    function test_setAdminStructure() external {
        address newAdminStructure = address(this);
        address adminStructureBefore = address(oracleBalancerWeighted.adminStructure());

        vm.prank(oracleBalancerWeighted.adminStructure().superAdmin());

        oracleBalancerWeighted.setAdminStructure(newAdminStructure);

        address adminStructureAfter = address(oracleBalancerWeighted.adminStructure());

        assertTrue(adminStructureAfter == newAdminStructure);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_setValidityDuration_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        oracleBalancerWeighted.setValidityDuration(0);
    }

    function test_setValidityDuration_ShouldFailIfValidityDurationIsTooShort() external {
        vm.prank(oracleBalancerWeighted.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(OracleErrors.WrongValidityDuration.selector));

        oracleBalancerWeighted.setValidityDuration(0);
    }

    function test_setValidityDuration_ShouldFailIfValidityDurationIsTooLong() external {
        uint32 maxValidityDuration = oracleBalancerWeighted.MAX_VALIDITY_DURATION();

        vm.prank(oracleBalancerWeighted.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(OracleErrors.WrongValidityDuration.selector));

        oracleBalancerWeighted.setValidityDuration(maxValidityDuration + 1);
    }

    function test_setValidityDuration() external {
        uint32 newValidityDuration = 24 hours;

        vm.prank(oracleBalancerWeighted.adminStructure().superAdmin());

        oracleBalancerWeighted.setValidityDuration(newValidityDuration);

        assertEq(oracleBalancerWeighted.validityDuration(), newValidityDuration);
    }

    function test_latestAnswer_ShouldFailIfPriceIsStale() external {
        vm.warp(block.timestamp + validityDuration);
        vm.expectRevert(OracleErrors.StalePrice.selector);

        oracleBalancerWeighted.latestAnswer();
    }

    function test_latestAnswer() external {
        assertEq(oracleBalancerWeighted.latestAnswer(), 1_270_436_258_957_789_942);
    }

    function test_latestRoundData_ShouldFailIfPriceIsStale() external {
        vm.warp(block.timestamp + validityDuration);
        vm.expectRevert(OracleErrors.StalePrice.selector);

        oracleBalancerWeighted.latestRoundData();
    }

    function test_latestRoundData() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleBalancerWeighted.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, 1_270_436_258_957_789_942);
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    function test_decimals() external {
        assertEq(oracleBalancerWeighted.decimals(), 18);
    }
}
