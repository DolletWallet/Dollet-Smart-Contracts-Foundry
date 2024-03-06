// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { OracleMock } from "src/mocks/OracleMock.sol";
import { EmptyMock } from "src/mocks/EmptyMock.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract OracleTest is Test {
    address public token;

    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    IAdminStructure public adminStructure;
    OracleMock public oracleMock;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_281_210);

        adminStructure = IAdminStructure(ADMIN_STRUCTURE);

        // EXTERNAL CONTRACTS
        ERC20Upgradeable tokenContract = new ERC20Upgradeable();
        token = address(tokenContract);

        // ORACLES
        Proxy oracleMockProxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), token)
        );
        oracleMock = OracleMock(address(oracleMockProxy));
    }

    // init

    function test_initialize_Fail_CalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        oracleMock.initialize(address(adminStructure), token);
    }

    function test_initialize_Fail_AdminStructureIsNotContract() external {
        OracleMock _oracleImpl = new OracleMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(address(_oracleImpl), abi.encodeWithSignature("initialize(address,address)", address(0), token));
    }

    function test_initialize_Fail_TokenIsNotContract() external {
        OracleMock _oracleImpl = new OracleMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_oracleImpl),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), address(0))
        );
    }

    function test_initialize_Success() public {
        Proxy oracleMockProxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), token)
        );
        OracleMock oracleMockLocal = OracleMock(address(oracleMockProxy));

        assertEq(address(oracleMockLocal.adminStructure()), address(adminStructure));
        assertEq(oracleMockLocal.token(), token);
        assertEq(oracleMockLocal.price(), 10 ** ERC20Upgradeable(token).decimals());
    }

    // setAdminStructure

    function test_setAdminStructure_Fail_NotSuperAdminUsingUser() public {
        address adminStructureBefore = address(oracleMock.adminStructure());
        address newAdminStructure = address(new EmptyMock());

        vm.startPrank(address(1));
        vm.expectRevert(bytes("NotSuperAdmin"));
        oracleMock.setAdminStructure(newAdminStructure);
        vm.stopPrank();

        address adminStructureAfter = address(oracleMock.adminStructure());
        assertEq(adminStructureBefore, adminStructureAfter);
    }

    function test_setAdminStructure_Fail_NotSuperAdminUsingAdmin() public {
        address adminStructureBefore = address(oracleMock.adminStructure());
        address newAdminStructure = address(new EmptyMock());

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(bytes("NotSuperAdmin"));
        oracleMock.setAdminStructure(newAdminStructure);
        vm.stopPrank();

        address adminStructureAfter = address(oracleMock.adminStructure());
        assertEq(adminStructureBefore, adminStructureAfter);
    }

    function test_setAdminStructure_Fail_NotAContract() public {
        address adminStructureBefore = address(oracleMock.adminStructure());
        address newAdminStructure = address(99_999);

        vm.startPrank(adminStructure.superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(99_999)));
        oracleMock.setAdminStructure(newAdminStructure);
        vm.stopPrank();

        address adminStructureAfter = address(oracleMock.adminStructure());
        assertEq(adminStructureBefore, adminStructureAfter);
    }

    function test_setAdminStructure_Success() public {
        address adminStructureBefore = address(oracleMock.adminStructure());
        address newAdminStructure = address(new EmptyMock());

        vm.startPrank(adminStructure.superAdmin());
        oracleMock.setAdminStructure(newAdminStructure);
        vm.stopPrank();

        address adminStructureAfter = address(oracleMock.adminStructure());
        assertFalse(adminStructureBefore == adminStructureAfter);
        assertTrue(adminStructureAfter == newAdminStructure);
    }

    // setPrice

    function test_setPrice_Success() external {
        uint256 priceBefore = uint256(oracleMock.price());
        uint256 newPrice = 2e17;

        oracleMock.setPrice(newPrice);

        uint256 priceAfter = uint256(oracleMock.price());
        assertFalse(priceBefore == priceAfter);
        assertTrue(priceAfter == newPrice);
    }

    // latestAnswer

    function test_latestAnswer_Success() external {
        assertEq(oracleMock.latestAnswer(), int256(oracleMock.price()));
    }

    // latestRoundData

    function test_latestRoundData_Success() external {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            oracleMock.latestRoundData();

        assertEq(roundId, 0);
        assertEq(answer, int256(oracleMock.price()));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);
    }

    // decimals

    function test_decimals_Success() external {
        assertEq(oracleMock.decimals(), 18);
    }
}
