// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { FeeManagerErrors } from "src/libraries/FeeManagerErrors.sol";
import { IFeeManager } from "src/interfaces/dollet/IFeeManager.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { FeeManager } from "src/FeeManager.sol";
import "forge-std/Test.sol";

contract FeeManagerTest is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    FeeManager public feeManager;

    event FeeSet(address indexed strategy, IFeeManager.FeeType indexed feeType, IFeeManager.Fee fee);

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_412_791);

        Proxy feeManagerProxy = new Proxy(
            address(new FeeManager()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );

        feeManager = FeeManager(address(feeManagerProxy));

        vm.startPrank(IAdminStructure(ADMIN_STRUCTURE).getAllAdmins()[0]);
    }

    function test_fees() external {
        (address recipient, uint16 fee) = feeManager.fees(address(0), IFeeManager.FeeType.MANAGEMENT);

        assertEq(recipient, address(0));
        assertEq(fee, 0);
    }

    function test_adminStructure() external {
        assertEq(address(feeManager.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_MAX_FEE() external {
        assertEq(feeManager.MAX_FEE(), 4000);
    }

    function test_initialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        feeManager.initialize(ADMIN_STRUCTURE);
    }

    function test_initialize_ShouldFailIfAdminStructureIsNotContract() external {
        FeeManager newFeeManager = new FeeManager();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newFeeManager),
            abi.encodeWithSignature("initialize(address)", address(0))
        );
    }

    function test_initialize() external {
        Proxy feeManagerProxy = new Proxy(
            address(new FeeManager()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        FeeManager newFeeManager = FeeManager(address(feeManagerProxy));

        assertEq(address(newFeeManager.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_setAdminStructure_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        feeManager.setAdminStructure(address(0));
    }

    function test_setAdminStructure_ShouldFailIfAdminStructureIsNotContract() external {
        vm.stopPrank();
        vm.prank(feeManager.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        feeManager.setAdminStructure(address(0));
    }

    function test_setAdminStructure() external {
        address newAdminStructure = address(this);
        address adminStructureBefore = address(feeManager.adminStructure());

        vm.stopPrank();
        vm.prank(feeManager.adminStructure().superAdmin());

        feeManager.setAdminStructure(newAdminStructure);

        address adminStructureAfter = address(feeManager.adminStructure());

        assertTrue(adminStructureAfter == newAdminStructure);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_setFee_ShouldFailIfNotAdminIsCalling() external {
        vm.stopPrank();
        vm.prank(address(this));
        vm.expectRevert(bytes("NotUserAdmin"));

        feeManager.setFee(address(0), IFeeManager.FeeType.MANAGEMENT, address(0), 0);
    }

    function test_setFee_ShouldFailIfStrategyIsNotContract() external {
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        feeManager.setFee(address(0), IFeeManager.FeeType.MANAGEMENT, address(0), 0);
    }

    function test_setFee_ShouldFailIfRecipientIsZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(FeeManagerErrors.WrongFeeRecipient.selector, address(0)));

        feeManager.setFee(address(this), IFeeManager.FeeType.MANAGEMENT, address(0), 0);
    }

    function test_setFee_ShouldFailIfFeeIsGreaterThanMaxPossibleFee() external {
        uint16 newFee = feeManager.MAX_FEE() + 1;

        vm.expectRevert(abi.encodeWithSelector(FeeManagerErrors.WrongFee.selector, newFee));

        feeManager.setFee(address(this), IFeeManager.FeeType.MANAGEMENT, address(this), newFee);
    }

    function test_setFee_Management() external {
        address strategy = address(this);
        IFeeManager.FeeType feeType = IFeeManager.FeeType.MANAGEMENT;
        address recipient = address(this);
        uint16 newFee = 1000; // 10.00%

        vm.expectEmit(true, true, true, true, address(feeManager));

        emit FeeSet(strategy, feeType, IFeeManager.Fee({ recipient: recipient, fee: newFee }));

        feeManager.setFee(strategy, feeType, recipient, newFee);

        (address feeRecipient, uint16 fee) = feeManager.fees(strategy, feeType);

        assertEq(feeRecipient, recipient);
        assertEq(fee, newFee);
    }

    function test_setFee_Performance() external {
        address strategy = ADMIN_STRUCTURE;
        IFeeManager.FeeType feeType = IFeeManager.FeeType.PERFORMANCE;
        address recipient = ADMIN_STRUCTURE;
        uint16 newFee = 555; // 5.55%

        vm.expectEmit(true, true, true, true, address(feeManager));

        emit FeeSet(strategy, feeType, IFeeManager.Fee({ recipient: recipient, fee: newFee }));

        feeManager.setFee(strategy, feeType, recipient, newFee);

        (address feeRecipient, uint16 fee) = feeManager.fees(strategy, feeType);

        assertEq(feeRecipient, recipient);
        assertEq(fee, newFee);
    }

    function test_setFee_Zero() external {
        address strategy = address(this);
        IFeeManager.FeeType feeType = IFeeManager.FeeType.MANAGEMENT;
        address recipient = address(this);
        uint16 newFee = 0; // 0%

        vm.expectEmit(true, true, true, true, address(feeManager));

        emit FeeSet(strategy, feeType, IFeeManager.Fee({ recipient: recipient, fee: newFee }));

        feeManager.setFee(strategy, feeType, recipient, newFee);

        (address feeRecipient, uint16 fee) = feeManager.fees(strategy, feeType);

        assertEq(feeRecipient, recipient);
        assertEq(fee, newFee);
    }
}
