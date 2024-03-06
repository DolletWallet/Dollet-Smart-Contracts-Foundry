// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { TemporaryAdminStructure } from "../../src/admin/TemporaryAdminStructure.sol";
import { IAdminStructure } from "../../src/interfaces/dollet/IAdminStructure.sol";
import "forge-std/Test.sol";

contract TemporaryAdminStructureTest is Test {
    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    TemporaryAdminStructure public adminStructure;

    function setUp() external {
        vm.startPrank(alice); // Super admin

        Proxy adminStructureProxy = new Proxy(
            address(new TemporaryAdminStructure()),
            abi.encodeWithSignature("initialize()")
        );

        adminStructure = TemporaryAdminStructure(address(adminStructureProxy));

        vm.stopPrank();
    }

    function test_superAdmin() external {
        assertEq(adminStructure.superAdmin(), alice);
    }

    function test_potentialSuperAdmin() external {
        assertEq(adminStructure.potentialSuperAdmin(), address(0));
    }

    function test_initialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        adminStructure.initialize();
    }

    function test_initialize() external {
        Proxy adminStructureProxy = new Proxy(
            address(new TemporaryAdminStructure()),
            abi.encodeWithSignature("initialize()")
        );
        TemporaryAdminStructure newAdminStructure = TemporaryAdminStructure(address(adminStructureProxy));

        assertEq(newAdminStructure.superAdmin(), address(this));
    }

    function test_transferSuperAdmin_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        adminStructure.transferSuperAdmin(bob);
    }

    function test_transferSuperAdmin() external {
        assertEq(adminStructure.potentialSuperAdmin(), address(0));

        vm.prank(alice);

        adminStructure.transferSuperAdmin(bob);

        assertEq(adminStructure.potentialSuperAdmin(), bob);
    }

    function test_acceptSuperAdmin_ShouldFailIfNotPotentialSuperAdminIsCalling() external {
        vm.prank(alice);

        adminStructure.transferSuperAdmin(bob);

        vm.expectRevert(bytes("NotPotentialSuperAdmin"));

        adminStructure.acceptSuperAdmin();
    }

    function test_acceptSuperAdmin() external {
        assertEq(adminStructure.superAdmin(), alice);
        assertEq(adminStructure.potentialSuperAdmin(), address(0));

        vm.prank(alice);

        adminStructure.transferSuperAdmin(bob);

        assertEq(adminStructure.superAdmin(), alice);
        assertEq(adminStructure.potentialSuperAdmin(), bob);

        vm.prank(bob);

        adminStructure.acceptSuperAdmin();

        assertEq(adminStructure.superAdmin(), bob);
        assertEq(adminStructure.potentialSuperAdmin(), address(0));
    }

    function test_isValidAdmin_ShouldFailIfNotSuperAdmin() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        adminStructure.isValidAdmin(bob);
    }

    function test_isValidAdmin() external view {
        adminStructure.isValidAdmin(alice);
    }

    function test_isValidSuperAdmin_ShouldFailIfNotSuperAdmin() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        adminStructure.isValidSuperAdmin(bob);
    }

    function test_isValidSuperAdmin() external view {
        adminStructure.isValidAdmin(alice);
    }

    function test_getAllAdmins() external {
        address[] memory admins = adminStructure.getAllAdmins();

        assertEq(admins.length, 1);
        assertEq(admins[0], adminStructure.superAdmin());
    }
}
