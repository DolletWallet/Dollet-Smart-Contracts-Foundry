// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { StrategyHelperVenueFraxswapV2 } from "src/strategies/StrategyHelper.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import "../../addresses/OPMainnet.sol";

import "forge-std/Test.sol";

contract StrategyHelperVenueFraxswapV2Test is Test {
    using SafeERC20Upgradeable for IERC20;

    address public alice = makeAddr("Alice");

    StrategyHelperVenueFraxswapV2 public strategyHelperVenueFraxswapV2;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_OP_MAINNET"), 115_591_962);

        strategyHelperVenueFraxswapV2 = new StrategyHelperVenueFraxswapV2(FRAXSWAP_V2_ROUTER);

        deal(WETH, address(this), 1000e18);
    }

    function test_router() external {
        assertEq(address(strategyHelperVenueFraxswapV2.router()), FRAXSWAP_V2_ROUTER);
    }

    function test_constructor_ShouldFailIfRouterIsNotContract() external {
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new StrategyHelperVenueFraxswapV2(address(0));
    }

    function test_constructor() external {
        StrategyHelperVenueFraxswapV2 newStrategyHelperVenueFraxswapV2 = new StrategyHelperVenueFraxswapV2(
            FRAXSWAP_V2_ROUTER
        );

        assertEq(address(newStrategyHelperVenueFraxswapV2.router()), FRAXSWAP_V2_ROUTER);
    }

    function test_swap_ShouldFailWithExpiredDeadline() external {
        address asset = WETH;
        bytes memory path = abi.encodePacked(WETH, FRAX);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;
        uint256 deadline = block.timestamp - 1;

        IERC20(WETH).safeTransfer(address(strategyHelperVenueFraxswapV2), amount);

        vm.expectRevert("FraxswapV1Router: EXPIRED");

        strategyHelperVenueFraxswapV2.swap(asset, path, amount, minAmountOut, recipient, deadline);
    }

    function test_swap() external {
        address asset = WETH;
        bytes memory path = abi.encodePacked(WETH, FRAX);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;

        uint256 prevWETHAmount = IERC20(WETH).balanceOf(address(this));
        uint256 prevFRAXRecipientAmount = IERC20(FRAX).balanceOf(recipient);

        IERC20(WETH).safeTransfer(address(strategyHelperVenueFraxswapV2), amount);
        strategyHelperVenueFraxswapV2.swap(asset, path, amount, minAmountOut, recipient, type(uint256).max);

        uint256 currWETHAmount = IERC20(WETH).balanceOf(address(this));
        uint256 currFRAXRecipientAmount = IERC20(FRAX).balanceOf(recipient);

        assertEq(currWETHAmount, prevWETHAmount - amount);
        assertTrue(currFRAXRecipientAmount > prevFRAXRecipientAmount);
    }
}
