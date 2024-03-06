// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";
import { ERC20Lib, Signature } from "../../src/libraries/ERC20Lib.sol";
import { SigningUtils } from "../utils/SigningUtils.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract ERC20LibTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using ERC20Lib for address;

    SigningUtils public signingUtils;
    IERC20Upgradeable public usdc;
    address public alice;
    uint256 public alicePrivateKey;
    uint256 public amount = 100e6;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_174_344);

        signingUtils = new SigningUtils();
        (alice, alicePrivateKey) = makeAddrAndKey("Alice");
        usdc = IERC20Upgradeable(USDC);

        deal(USDC, alice, amount);
    }

    function test_pull() external {
        vm.prank(alice);

        usdc.approve(address(this), amount);
        address(usdc).pull(alice, address(this), amount);

        assertEq(usdc.balanceOf(address(this)), amount);
    }

    function test_push() external {
        deal(USDC, address(this), amount);

        assertEq(usdc.balanceOf(address(this)), amount);

        uint256 amountToSend = amount / 2;
        address recipient = address(9999);

        address(usdc).push(recipient, amountToSend);

        assertEq(usdc.balanceOf(recipient), amountToSend);
        assertEq(usdc.balanceOf(address(this)), amountToSend);
    }

    function test_pushAll_1() external {
        deal(USDC, address(this), amount);

        assertEq(usdc.balanceOf(address(this)), amount);

        address recipient = address(9999);

        address(usdc).pushAll(recipient);

        assertEq(usdc.balanceOf(recipient), amount);
        assertEq(usdc.balanceOf(address(this)), 0);
    }

    function test_pushAll_2() external {
        deal(USDC, address(this), 1000);

        ERC20Lib.pushAll(address(usdc), address(this));

        uint256 finalBalance = usdc.balanceOf(address(this));

        // Assuming the ERC20 token is not upgradable, you can use assert
        assertEq(finalBalance, 1000, "Incorrect token balance after pushAll");
    }

    function test_pushAll_3() external {
        MockErc20LibUsage newContract = new MockErc20LibUsage();

        deal(USDC, address(newContract), 1000);

        address user = address(998_833);

        newContract.transferAllTokens(address(usdc), user);

        uint256 finalBalance = usdc.balanceOf(user);

        // Assuming the ERC20 token is not upgradable, you can use assert
        assertEq(finalBalance, 1000, "Incorrect token balance after pushAll");
    }

    function test_safeApprove_ShouldApproveFrom0AmountSuccessfully() external {
        address spender = makeAddr("spender");

        assertEq(usdc.allowance(address(this), spender), 0);

        address(usdc).safeApprove(spender, amount);

        assertEq(usdc.allowance(address(this), spender), amount);
    }

    function test_safeApprove_ShouldApproveFromNon0AmountSuccessfully() external {
        address spender = makeAddr("spender");

        usdc.approve(spender, amount);

        assertEq(usdc.allowance(address(this), spender), amount);

        address(usdc).safeApprove(spender, amount);

        assertEq(usdc.allowance(address(this), spender), amount);
    }

    // ============================ Pull Permit ============================ //

    function test_pullPermit() external {
        assertEq(usdc.balanceOf(address(this)), 0);

        uint256 deadline = block.timestamp + 100;
        Signature memory signature =
            signingUtils.signPermit(address(usdc), alice, alicePrivateKey, address(this), amount, deadline);

        address(usdc).pullPermit(alice, address(this), amount, signature);

        assertEq(usdc.balanceOf(address(this)), amount);
        assertEq(usdc.balanceOf(alice), 0);
    }

    function test_permit_ShouldFailToUsePermitWhenIsExpired() external {
        uint256 deadline = block.timestamp - 1;
        Signature memory signature =
            signingUtils.signPermit(address(usdc), alice, alicePrivateKey, address(this), amount, deadline);

        vm.expectRevert(bytes("FiatTokenV2: permit is expired"));

        IERC20PermitUpgradeable(address(usdc)).permit(
            alice, address(this), amount, signature.deadline, signature.v, signature.r, signature.s
        );
    }

    function test_permit_ShouldFailToUsePermitOfDifferentSpender() external {
        uint256 deadline = block.timestamp;
        Signature memory signature =
            signingUtils.signPermit(address(usdc), alice, alicePrivateKey, address(1), amount, deadline);

        vm.expectRevert(bytes("EIP2612: invalid signature"));

        IERC20PermitUpgradeable(address(usdc)).permit(
            alice, address(this), amount, signature.deadline, signature.v, signature.r, signature.s
        );
    }

    function test_permit_ShouldFailToPermitWithWrongSignature() external {
        (, uint256 bobPrivateKey) = makeAddrAndKey("Bob");
        uint256 deadline = block.timestamp;
        Signature memory signature =
            signingUtils.signPermit(address(usdc), alice, bobPrivateKey, address(this), amount, deadline);

        vm.expectRevert(bytes("EIP2612: invalid signature"));

        IERC20PermitUpgradeable(address(usdc)).permit(
            alice, address(this), amount, signature.deadline, signature.v, signature.r, signature.s
        );
    }
}

contract MockErc20LibUsage {
    function transferAllTokens(address _token, address _recipient) external {
        ERC20Lib.pushAll(_token, _recipient);
    }
}
