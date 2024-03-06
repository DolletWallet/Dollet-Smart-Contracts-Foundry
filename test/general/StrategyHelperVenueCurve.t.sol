// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { StrategyHelperVenueCurve } from "src/strategies/StrategyHelper.sol";
import { StrategyHelperErrors } from "src/libraries/StrategyHelperErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract StrategyHelperVenueCurveTest is Test {
    using SafeERC20Upgradeable for IERC20;

    address public constant CURVE_USDC_USDT_DAI_POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    address public alice = makeAddr("Alice");

    StrategyHelperVenueCurve public strategyHelperVenueCurve;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_412_791);

        strategyHelperVenueCurve = new StrategyHelperVenueCurve(WETH);
    }

    function test_ETH() external {
        assertEq(strategyHelperVenueCurve.ETH(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }

    function test_weth() external {
        assertEq(address(strategyHelperVenueCurve.weth()), WETH);
    }

    function test_constructor_ShouldFailIfWethIsNotContract() external {
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new StrategyHelperVenueCurve(address(0));
    }

    function test_constructor() external {
        StrategyHelperVenueCurve newStrategyHelperVenueCurve = new StrategyHelperVenueCurve(WETH);

        assertEq(address(newStrategyHelperVenueCurve.weth()), WETH);
    }

    function test_receive() external {
        uint256 amount = 1e18;

        deal(address(this), amount);

        payable(address(strategyHelperVenueCurve)).transfer(amount);

        assertEq(address(strategyHelperVenueCurve).balance, amount);
    }

    function test_swap_ShouldFailWithExpiredDeadline() external {
        address asset = WETH;
        bytes memory path = hex"";
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;
        uint256 deadline = block.timestamp - 1;

        vm.expectRevert(abi.encodeWithSelector(StrategyHelperErrors.ExpiredDeadline.selector));

        strategyHelperVenueCurve.swap(asset, path, amount, minAmountOut, recipient, deadline);
    }

    function test_swap_ShouldFailIfUnderMinimumOutputAmount() external {
        address asset = WETH;
        address[] memory pools = new address[](1);
        uint256[] memory coinsIn = new uint256[](1);
        uint256[] memory coinsOut = new uint256[](1);

        pools[0] = CURVE_OETH_ETH_POOL;
        coinsIn[0] = 0;
        coinsOut[0] = 1;

        bytes memory path = abi.encode(pools, coinsIn, coinsOut);
        uint256 amount = 10e18;
        uint256 minAmountOut = 100e18;
        address recipient = alice;

        deal(asset, address(this), amount);

        IERC20(WETH).safeTransfer(address(strategyHelperVenueCurve), amount);

        vm.expectRevert(abi.encodeWithSelector(StrategyHelperErrors.UnderMinimumOutputAmount.selector));

        strategyHelperVenueCurve.swap(asset, path, amount, minAmountOut, recipient, type(uint256).max);
    }

    function test_swap_1() external {
        address asset = WETH;
        address[] memory pools = new address[](1);
        uint256[] memory coinsIn = new uint256[](1);
        uint256[] memory coinsOut = new uint256[](1);

        pools[0] = CURVE_OETH_ETH_POOL;
        coinsIn[0] = 0;
        coinsOut[0] = 1;

        bytes memory path = abi.encode(pools, coinsIn, coinsOut);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;

        deal(asset, address(this), amount);

        uint256 prevWETHAmount = IERC20(WETH).balanceOf(address(this));
        uint256 prevOETHRecipientAmount = IERC20(OETH).balanceOf(recipient);

        IERC20(WETH).safeTransfer(address(strategyHelperVenueCurve), amount);
        strategyHelperVenueCurve.swap(asset, path, amount, minAmountOut, recipient, type(uint256).max);

        uint256 currWETHAmount = IERC20(WETH).balanceOf(address(this));
        uint256 currOETHRecipientAmount = IERC20(OETH).balanceOf(recipient);

        assertEq(currWETHAmount, prevWETHAmount - amount);
        assertTrue(currOETHRecipientAmount > prevOETHRecipientAmount);
    }

    function test_swap_2() external {
        address asset = OETH;
        address[] memory pools = new address[](1);
        uint256[] memory coinsIn = new uint256[](1);
        uint256[] memory coinsOut = new uint256[](1);

        pools[0] = CURVE_OETH_ETH_POOL;
        coinsIn[0] = 1;
        coinsOut[0] = 0;

        bytes memory path = abi.encode(pools, coinsIn, coinsOut);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;

        vm.prank(0x94B17476A93b3262d87B9a326965D1E91f9c13E7); // OETH whale

        IERC20(OETH).safeTransfer(address(this), amount);

        uint256 prevOETHAmount = IERC20(OETH).balanceOf(address(this));
        uint256 prevWETHRecipientAmount = IERC20(WETH).balanceOf(recipient);

        IERC20(OETH).safeTransfer(address(strategyHelperVenueCurve), amount);
        strategyHelperVenueCurve.swap(asset, path, amount, minAmountOut, recipient, type(uint256).max);

        uint256 currOETHAmount = IERC20(OETH).balanceOf(address(this));
        uint256 currWETHRecipientAmount = IERC20(WETH).balanceOf(recipient);

        assertEq(currOETHAmount, prevOETHAmount - amount);
        assertTrue(currWETHRecipientAmount > prevWETHRecipientAmount);
    }

    function test_swap_3() external {
        address asset = USDC;
        address[] memory pools = new address[](1);
        uint256[] memory coinsIn = new uint256[](1);
        uint256[] memory coinsOut = new uint256[](1);

        pools[0] = CURVE_USDC_USDT_DAI_POOL;
        coinsIn[0] = 1;
        coinsOut[0] = 2;

        bytes memory path = abi.encode(pools, coinsIn, coinsOut);
        uint256 amount = 100e6;
        uint256 minAmountOut = 0;
        address recipient = alice;

        deal(asset, address(this), amount);

        uint256 prevUSDCAmount = IERC20(USDC).balanceOf(address(this));
        uint256 prevUSDTRecipientAmount = IERC20(USDT).balanceOf(recipient);

        IERC20(USDC).safeTransfer(address(strategyHelperVenueCurve), amount);
        strategyHelperVenueCurve.swap(asset, path, amount, minAmountOut, recipient, type(uint256).max);

        uint256 currUSDCAmount = IERC20(USDC).balanceOf(address(this));
        uint256 currUSDTRecipientAmount = IERC20(USDT).balanceOf(recipient);

        assertEq(currUSDCAmount, prevUSDCAmount - amount);
        assertTrue(currUSDTRecipientAmount > prevUSDTRecipientAmount);
    }
}
