// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { StrategyHelperVenueUniswapV3 } from "src/strategies/StrategyHelper.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract StrategyHelperVenueUniswapV3Test is Test {
    using SafeERC20Upgradeable for IERC20;

    address public alice = makeAddr("Alice");

    StrategyHelperVenueUniswapV3 public strategyHelperVenueUniswapV3;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_412_791);

        strategyHelperVenueUniswapV3 = new StrategyHelperVenueUniswapV3(UNISWAP_V3_ROUTER);

        deal(WETH, address(this), 1000e18);
    }

    function test_router() external {
        assertEq(address(strategyHelperVenueUniswapV3.router()), UNISWAP_V3_ROUTER);
    }

    function test_constructor_ShouldFailIfRouterIsNotContract() external {
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new StrategyHelperVenueUniswapV3(address(0));
    }

    function test_constructor() external {
        StrategyHelperVenueUniswapV3 newStrategyHelperVenueUniswapV3 =
            new StrategyHelperVenueUniswapV3(UNISWAP_V3_ROUTER);

        assertEq(address(newStrategyHelperVenueUniswapV3.router()), UNISWAP_V3_ROUTER);
    }

    function test_swap_ShouldFailWithExpiredDeadline() external {
        address asset = WETH;
        bytes memory path = abi.encodePacked(WETH, uint24(3000), USDT);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;
        uint256 deadline = block.timestamp - 1;

        IERC20(WETH).safeTransfer(address(strategyHelperVenueUniswapV3), amount);

        vm.expectRevert("Transaction too old");

        strategyHelperVenueUniswapV3.swap(asset, path, amount, minAmountOut, recipient, deadline);
    }

    function test_swap() external {
        address asset = WETH;
        bytes memory path = abi.encodePacked(WETH, uint24(3000), USDT);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;

        uint256 prevWETHAmount = IERC20(WETH).balanceOf(address(this));
        uint256 prevUSDTRecipientAmount = IERC20(USDT).balanceOf(recipient);

        IERC20(WETH).safeTransfer(address(strategyHelperVenueUniswapV3), amount);
        strategyHelperVenueUniswapV3.swap(asset, path, amount, minAmountOut, recipient, type(uint256).max);

        uint256 currWETHAmount = IERC20(WETH).balanceOf(address(this));
        uint256 currUSDTRecipientAmount = IERC20(USDT).balanceOf(recipient);

        assertEq(currWETHAmount, prevWETHAmount - amount);
        assertTrue(currUSDTRecipientAmount > prevUSDTRecipientAmount);
    }
}
