// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { StrategyHelperVenueBalancer } from "src/strategies/StrategyHelper.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract StrategyHelperVenueBalancerTest is Test {
    using SafeERC20Upgradeable for IERC20;

    address public alice = makeAddr("Alice");

    StrategyHelperVenueBalancer public strategyHelperVenueBalancer;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_412_791);

        strategyHelperVenueBalancer = new StrategyHelperVenueBalancer(BALANCER_VAULT);

        deal(PENDLE, address(this), 1000e18);
    }

    function test_vault() external {
        assertEq(address(strategyHelperVenueBalancer.vault()), BALANCER_VAULT);
    }

    function test_constructor_ShouldFailIfVaultIsNotContract() external {
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new StrategyHelperVenueBalancer(address(0));
    }

    function test_constructor() external {
        StrategyHelperVenueBalancer newStrategyHelperVenueBalancer = new StrategyHelperVenueBalancer(BALANCER_VAULT);

        assertEq(address(newStrategyHelperVenueBalancer.vault()), BALANCER_VAULT);
    }

    function test_swap_ShouldFailWithExpiredDeadline() external {
        address asset = PENDLE;
        bytes32 poolId = 0xfd1cf6fd41f229ca86ada0584c63c49c3d66bbc9000200000000000000000438;
        bytes memory path = abi.encode(WETH, poolId);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;
        uint256 deadline = block.timestamp - 1;

        IERC20(PENDLE).safeTransfer(address(strategyHelperVenueBalancer), amount);

        // Balancer error code for SWAP_DEADLINE
        vm.expectRevert("BAL#508");

        strategyHelperVenueBalancer.swap(asset, path, amount, minAmountOut, recipient, deadline);
    }

    function test_swap() external {
        address asset = PENDLE;
        bytes32 poolId = 0xfd1cf6fd41f229ca86ada0584c63c49c3d66bbc9000200000000000000000438;
        bytes memory path = abi.encode(WETH, poolId);
        uint256 amount = 10e18;
        uint256 minAmountOut = 0;
        address recipient = alice;
        uint256 deadline = type(uint256).max;

        uint256 prevAssetAmount = IERC20(asset).balanceOf(address(this));
        uint256 prevWETHRecipientAmount = IERC20(WETH).balanceOf(recipient);

        IERC20(PENDLE).safeTransfer(address(strategyHelperVenueBalancer), amount);
        strategyHelperVenueBalancer.swap(asset, path, amount, minAmountOut, recipient, deadline);

        uint256 currAssetAmount = IERC20(asset).balanceOf(address(this));
        uint256 currWETHRecipientAmount = IERC20(WETH).balanceOf(recipient);

        assertEq(currAssetAmount, prevAssetAmount - amount);
        assertTrue(currWETHRecipientAmount > prevWETHRecipientAmount);
    }
}
