// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { StrategyHelperVenueTraderJoeV1 } from "src/strategies/StrategyHelper.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import "../../addresses/AVAXMainnet.sol";
import "forge-std/Test.sol";

contract StrategyHelperVenueTraderJoeV1Test is Test {
    using SafeERC20Upgradeable for IERC20;

    address public alice = makeAddr("Alice");

    StrategyHelperVenueTraderJoeV1 public strategyHelperVenueTraderJoeV1;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_AVAX_MAINNET"), 42_300_708);

        strategyHelperVenueTraderJoeV1 = new StrategyHelperVenueTraderJoeV1(TRADER_JOE_V1_ROUTER);

        deal(WAVAX, address(this), 1000e18);
        deal(WOM, address(this), 1000e18);
    }

    function test_router() external {
        assertEq(address(strategyHelperVenueTraderJoeV1.router()), TRADER_JOE_V1_ROUTER);
    }

    function test_constructor_ShouldFailIfRouterIsNotContract() external {
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new StrategyHelperVenueTraderJoeV1(address(0));
    }

    function test_constructor() external {
        StrategyHelperVenueTraderJoeV1 newStrategyHelperVenueTraderJoeV1 =
            new StrategyHelperVenueTraderJoeV1(TRADER_JOE_V1_ROUTER);

        assertEq(address(newStrategyHelperVenueTraderJoeV1.router()), TRADER_JOE_V1_ROUTER);
    }

    function test_swap_ShouldFailWithExpiredDeadline() external {
        address asset = WOM;
        bytes memory path = abi.encodePacked(WOM, WAVAX);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;
        uint256 deadline = block.timestamp - 1;

        IERC20(WOM).safeTransfer(address(strategyHelperVenueTraderJoeV1), amount);

        vm.expectRevert("JoeRouter: EXPIRED");

        strategyHelperVenueTraderJoeV1.swap(asset, path, amount, minAmountOut, recipient, deadline);
    }

    function test_swap() external {
        address asset = WOM;
        bytes memory path = abi.encodePacked(WOM, WAVAX);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;

        uint256 prevWOMAmount = IERC20(WOM).balanceOf(address(this));
        uint256 prevWAVAXRecipientAmount = IERC20(WAVAX).balanceOf(recipient);

        IERC20(WOM).safeTransfer(address(strategyHelperVenueTraderJoeV1), amount);
        strategyHelperVenueTraderJoeV1.swap(asset, path, amount, minAmountOut, recipient, type(uint256).max);

        uint256 currWOMAmount = IERC20(WOM).balanceOf(address(this));
        uint256 currWAVAXRecipientAmount = IERC20(WAVAX).balanceOf(recipient);

        assertEq(currWOMAmount, prevWOMAmount - amount);
        assertTrue(currWAVAXRecipientAmount > prevWAVAXRecipientAmount);
    }
}
