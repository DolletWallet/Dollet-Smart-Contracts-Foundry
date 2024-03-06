// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { StrategyHelperVenueCamelotV2 } from "src/strategies/StrategyHelper.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import "../../addresses/ARBMainnet.sol";

import "forge-std/Test.sol";

contract StrategyHelperVenueCamelotV2Test is Test {
    using SafeERC20Upgradeable for IERC20;

    address public alice = makeAddr("Alice");

    StrategyHelperVenueCamelotV2 public strategyHelperVenueCamelotV2;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ARB_MAINNET"), 178_318_000);

        strategyHelperVenueCamelotV2 = new StrategyHelperVenueCamelotV2(CAMELOT_V2_ROUTER);

        deal(WOM, address(this), 1000e18);
    }

    function test_router() external {
        assertEq(address(strategyHelperVenueCamelotV2.router()), CAMELOT_V2_ROUTER);
    }

    function test_constructor_ShouldFailIfRouterIsNotContract() external {
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new StrategyHelperVenueCamelotV2(address(0));
    }

    function test_constructor() external {
        StrategyHelperVenueCamelotV2 newStrategyHelperVenueCamelotV2 = new StrategyHelperVenueCamelotV2(
            CAMELOT_V2_ROUTER
        );

        assertEq(address(newStrategyHelperVenueCamelotV2.router()), CAMELOT_V2_ROUTER);
    }

    function test_swap_ShouldFailWithExpiredDeadline() external {
        address asset = WOM;
        bytes memory path = abi.encodePacked(asset, USDT);
        uint256 amount = 100e18;
        uint256 minAmountOut = 0;
        address recipient = alice;
        uint256 deadline = block.timestamp - 1;

        IERC20(asset).safeTransfer(address(strategyHelperVenueCamelotV2), amount);

        vm.expectRevert("CamelotRouter: EXPIRED");

        strategyHelperVenueCamelotV2.swap(asset, path, amount, minAmountOut, recipient, deadline);
    }

    function test_swap() external {
        address asset = WOM;
        bytes memory path = abi.encodePacked(asset, USDT);
        uint256 amount = 100e18;
        uint256 minAmountOut = 0;
        address recipient = alice;

        uint256 prevAssetAmount = IERC20(asset).balanceOf(address(this));
        uint256 prevUSDTRecipientAmount = IERC20(USDT).balanceOf(recipient);

        IERC20(asset).safeTransfer(address(strategyHelperVenueCamelotV2), amount);
        strategyHelperVenueCamelotV2.swap(asset, path, amount, minAmountOut, recipient, type(uint256).max);

        uint256 currAssetAmount = IERC20(asset).balanceOf(address(this));
        uint256 currUSDTRecipientAmount = IERC20(USDT).balanceOf(recipient);

        assertEq(currAssetAmount, prevAssetAmount - amount);
        assertTrue(currUSDTRecipientAmount > prevUSDTRecipientAmount);
    }
}
