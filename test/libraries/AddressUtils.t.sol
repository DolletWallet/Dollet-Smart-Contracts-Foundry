// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { AddressUtils } from "../../src/libraries/AddressUtils.sol";
import "forge-std/Test.sol";

contract AddressUtilsTest is Test {
    function test_doesntCaptureNonContractAddress() external {
        MockContract mockContract = new MockContract();
        mockContract.checkContractAddress(address(mockContract));
    }

    function test_capturesNonContractAddress() external {
        MockContract mockContract = new MockContract();

        bytes memory revertReason = abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0));
        vm.expectRevert(revertReason);
        mockContract.checkContractAddress(address(0));
    }

    function test_capturesOnlyNonZeroAddress() external {
        MockContract mockContract = new MockContract();

        vm.expectRevert(AddressUtils.ZeroAddress.selector);
        mockContract.checkNonZeroAddress(address(0));
    }

    function test_doesntCapturesOnlyNonZeroAddress() external {
        MockContract mockContract = new MockContract();

        mockContract.checkNonZeroAddress(address(1));
    }

    function test_validatesOnlyTokenAndETH() external {
        MockContract mockContract = new MockContract();

        mockContract.checkTokenAddress(address(0));
        mockContract.checkTokenAddress(address(new MockContract()));

        bytes memory revertReason = abi.encodeWithSelector(AddressUtils.NotContract.selector, address(1));
        vm.expectRevert(revertReason);
        mockContract.checkTokenAddress(address(1));
    }
}

contract MockContract {
    using AddressUtils for address;

    function checkContractAddress(address _contract) external view {
        AddressUtils.onlyContract(_contract);
    }

    function checkNonZeroAddress(address _contract) external pure {
        AddressUtils.onlyNonZeroAddress(_contract);
    }

    function checkTokenAddress(address _contract) external view {
        AddressUtils.onlyTokenContract(_contract);
    }
}
