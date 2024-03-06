// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PendleLSDCalculations } from "src/calculations/pendle/PendleLSDCalculations.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { PendleLSDStrategy } from "src/strategies/pendle/PendleLSDStrategy.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { ERC20Lib, Signature } from "src/libraries/ERC20Lib.sol";
import { IStrategy } from "src/interfaces/dollet/IStrategy.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { VaultErrors } from "src/libraries/VaultErrors.sol";
import { StrategyMock } from "../mocks/StrategyMock.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { Signature } from "src/libraries/ERC20Lib.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract CompoundVaultTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    CompoundVault public pendleVault;
    PendleLSDStrategy public pendleStrategy;
    PendleLSDCalculations public pendleCalculations;
    address[] public depositAllowedTokens;
    address[] public withdrawalAllowedTokens;
    address public constant WANT = 0x62187066FD9C24559ffB54B0495a304ADe26d50B;
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;
    address public token1 = address(99_999);
    address public token2 = address(88_888);
    IAdminStructure public adminStructure;
    address public alice;
    uint256 public alicePrivateKey;
    StrategyMock public strategyMock;
    IVault.DepositLimit[] public depositLimits;
    address[] public tokensToCompound = [PENDLE];
    uint256[] public minimumsToCompound = [1e18];
    uint256 private constant _NOT_ALLOWED = 0;
    uint256 private constant _ALLOWED = 1;

    event DepositLimitsSet(IVault.DepositLimit _limitBefore, IVault.DepositLimit _limitAfter);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_281_210);
        (alice, alicePrivateKey) = makeAddrAndKey("Alice");
        adminStructure = IAdminStructure(ADMIN_STRUCTURE);
        depositAllowedTokens = [WBTC, USDC, USDT];
        withdrawalAllowedTokens = [WBTC, USDC, USDT];

        // ======= LSD Calculations ========
        Proxy pendleLSDCalculationsProxy = new Proxy(
            address(new PendleLSDCalculations()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        pendleCalculations = PendleLSDCalculations(address(pendleLSDCalculationsProxy));

        // ======= Strategy ========
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(new EmptyMock()),
            feeManager: address(new EmptyMock()),
            weth: WETH,
            want: WANT,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: WANT,
            twapPeriod: 1800,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });

        Proxy pendleStrategyProxy = new Proxy(
            address(new PendleLSDStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
        pendleStrategy = PendleLSDStrategy(payable(address(pendleStrategyProxy)));

        depositLimits.push(IVault.DepositLimit(USDC, 1e6));
        depositLimits.push(IVault.DepositLimit(USDT, 1e6));
        depositLimits.push(IVault.DepositLimit(WBTC, 1e2));
        Proxy pendleVaultProxy = new Proxy(
            address(new CompoundVault()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(pendleStrategy), // strategy
                WETH, // weth
                address(pendleCalculations),
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
        pendleVault = CompoundVault(address(pendleVaultProxy));
        strategyMock = new StrategyMock();
        vm.prank(adminStructure.superAdmin());
        pendleCalculations.setStrategyValues(address(pendleStrategy));
    }

    ////////////// GENERAL //////////////

    function test_general_AllowsToChangeTheAddress() public {
        address newAddress = address(new EmptyMock());
        // Invalid caller
        vm.expectRevert(bytes("NotSuperAdmin"));
        pendleVault.setAdminStructure(newAddress);

        vm.startPrank(adminStructure.superAdmin());
        // Invalid address used
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(99_999)));
        // Works well, address changes
        pendleVault.setAdminStructure(address(99_999));
        address adminStructureBefore = address(pendleVault.adminStructure());
        pendleVault.setAdminStructure(newAddress);
        address adminStructureAfter = address(pendleVault.adminStructure());
        assertTrue(adminStructureAfter == newAddress);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_general_AllowsToEditTheDepositLimit() public {
        vm.startPrank(adminStructure.superAdmin());
        depositLimits[0] = IVault.DepositLimit(USDC, 10e6);
        IVault.DepositLimit memory depositLimitBefore = pendleVault.getDepositLimit(USDC);

        vm.expectEmit(true, true, false, false, address(pendleVault));
        emit DepositLimitsSet(depositLimitBefore, depositLimits[0]);

        pendleVault.editDepositLimit(depositLimits);
        IVault.DepositLimit memory depositLimitAfter = pendleVault.getDepositLimit(USDC);
        // Expecting before and after to be different
        assertFalse(depositLimitBefore.minAmount == depositLimitAfter.minAmount);
        assertEq(depositLimitAfter.minAmount, 10e6);
        assertEq(depositLimitAfter.token, USDC);
    }

    function test_general_FailsToSetInvalidDepositLimits() public {
        depositLimits[0] = IVault.DepositLimit(USDC, 0);
        vm.startPrank(adminStructure.superAdmin());
        IVault.DepositLimit memory depositLimitBefore = pendleVault.getDepositLimit(USDC);
        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.ZeroMinDepositAmount.selector);
        vm.expectRevert(revertReason);
        pendleVault.editDepositLimit(depositLimits);
        IVault.DepositLimit memory depositLimitAfter = pendleVault.getDepositLimit(USDC);
        // Expecting before and after to be the same
        assertTrue(depositLimitBefore.minAmount == depositLimitAfter.minAmount);
    }

    function test_general_FailsToSetDepositLimitsForInvalidToken() public {
        depositLimits[0] = IVault.DepositLimit(PENDLE, 1e18);
        vm.startPrank(adminStructure.superAdmin());
        IVault.DepositLimit memory depositLimitBefore = pendleVault.getDepositLimit(USDC);
        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.NotAllowedDepositToken.selector, PENDLE);
        vm.expectRevert(revertReason);
        pendleVault.editDepositLimit(depositLimits);
        IVault.DepositLimit memory depositLimitAfter1 = pendleVault.getDepositLimit(USDC);
        // Expecting before and after to be the same
        assertTrue(depositLimitBefore.minAmount == depositLimitAfter1.minAmount);

        depositLimits[0] = IVault.DepositLimit(address(0), 10e6);
        bytes memory revertReason2 = abi.encodeWithSelector(VaultErrors.NotAllowedDepositToken.selector, address(0));
        vm.expectRevert(revertReason2);
        pendleVault.editDepositLimit(depositLimits);
    }

    function test_general_FailsToInitializeWithInvalidDepositLimits() public {
        depositLimits[0] = IVault.DepositLimit(USDC, 0);
        CompoundVault _pendleVault = new CompoundVault();
        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.ZeroMinDepositAmount.selector);
        vm.expectRevert(revertReason);
        new Proxy(
            address(_pendleVault),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(strategyMock), // strategy MOCK
                WETH, // weth
                address(pendleCalculations),
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
    }

    function test_general_FailsToInitializeWithEmptyDepositTokensList() public {
        CompoundVault _pendleVault = new CompoundVault();
        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.WrongDepositAllowedTokensCount.selector);
        vm.expectRevert(revertReason);
        new Proxy(
            address(_pendleVault),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(pendleStrategy), // strategy
                WETH, // weth
                address(pendleCalculations),
                new address[](0), // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
    }

    function test_general_FailsToInitializeWithEmptyWithdrawakTokensList() public {
        CompoundVault _pendleVault = new CompoundVault();
        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.WrongWithdrawalAllowedTokensCount.selector);
        vm.expectRevert(revertReason);
        new Proxy(
            address(_pendleVault),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(pendleStrategy), // strategy
                WETH, // weth
                address(pendleCalculations),
                depositAllowedTokens, // depositAllowedTokens
                new address[](0), // withdrawalAllowedTokens
                depositLimits
            )
        );
    }

    function test_general_FailsToInitializeWithCalculations() public {
        CompoundVault _pendleVault = new CompoundVault();
        bytes memory revertReason = abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0));
        vm.expectRevert(revertReason);
        new Proxy(
            address(_pendleVault),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(pendleStrategy), // strategy
                WETH, // weth
                address(0),
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
    }

    function test_general_FailsToInitializeWithInvalidTokenDepositLimit() public {
        CompoundVault _pendleVault = new CompoundVault();
        depositAllowedTokens = [WBTC, USDT];

        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.NotAllowedDepositToken.selector, USDC);
        vm.expectRevert(revertReason);
        new Proxy(
            address(_pendleVault),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(pendleStrategy), // strategy
                WETH, // weth
                address(pendleCalculations),
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
    }

    function test_general_FailsToInitializeWithDuplicateTokenDepositLimit() public {
        CompoundVault _pendleVault = new CompoundVault();
        depositAllowedTokens = [WBTC, WBTC, USDT];

        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.DuplicateDepositAllowedToken.selector);
        vm.expectRevert(revertReason);
        new Proxy(
            address(_pendleVault),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(pendleStrategy), // strategy
                WETH, // weth
                address(pendleCalculations),
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
    }

    function test_general_FailsToInitializeWithDuplicateWithdrawalDepositLimit() public {
        CompoundVault _pendleVault = new CompoundVault();
        withdrawalAllowedTokens = [WBTC, WBTC, USDT];

        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.DuplicateWithdrawalAllowedToken.selector);
        vm.expectRevert(revertReason);
        new Proxy(
            address(_pendleVault),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(pendleStrategy), // strategy
                WETH, // weth
                address(pendleCalculations),
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
    }
    ////////////// PAUSE & UNPAUSE //////////////

    function test_pauseAndUnpause_FailsToTogglePauseWithInvalidUser() public {
        vm.expectRevert(bytes("NotUserAdmin"));
        pendleVault.togglePause();
    }

    function test_pauseAndUnpause_TogglePause() public {
        vm.startPrank(adminStructure.superAdmin());
        bool pausedBefore = pendleVault.paused();
        assertEq(pausedBefore, false);

        pendleVault.togglePause();
        bool pausedAfterPause = pendleVault.paused();
        assertEq(pausedAfterPause, true);

        pendleVault.togglePause();
        bool pausedAfterUnpause = pendleVault.paused();
        pendleVault.togglePause();
        assertEq(pausedAfterUnpause, false);
    }

    function test_pauseAndUnpause_FailsToDepositWhenPaused() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.togglePause();
        bool pausedAfterPause = pendleVault.paused();
        assertEq(pausedAfterPause, true);
        vm.expectRevert(bytes("Pausable: paused"));
        pendleVault.deposit(address(0), address(0), uint256(0), hex"");
    }

    function test_pauseAndUnpause_FailsToDepositWithPermitWhenPaused() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.togglePause();
        bool pausedAfterPause = pendleVault.paused();
        assertEq(pausedAfterPause, true);
        vm.expectRevert(bytes("Pausable: paused"));
        pendleVault.depositWithPermit(address(0), address(0), uint256(0), hex"", new Signature[](1)[0]);
    }

    ////////////// WITHDRAW STUCK TOKENS //////////////

    function test_stuckTokens_FailsToWithdrawStuckTokensWithInvalidUser() public {
        vm.expectRevert(bytes("NotUserAdmin"));
        pendleVault.inCaseTokensGetStuck(address(0));
    }

    function test_stuckTokens_AllowsToWithdrawStuckTokens() public {
        deal(USDC, address(pendleVault), 10e6);
        address superAdmin = adminStructure.superAdmin();
        vm.startPrank(superAdmin);
        uint256 balanceBefore = IERC20Upgradeable(USDC).balanceOf(superAdmin);
        pendleVault.inCaseTokensGetStuck(USDC);
        uint256 balanceAfter = IERC20Upgradeable(USDC).balanceOf(superAdmin);
        assertEq(balanceAfter - balanceBefore, 10e6);
    }

    function test_stuckTokens_FailsToWithdrawWantToken() public {
        deal(WANT, address(pendleVault), 10e6);
        address superAdmin = adminStructure.superAdmin();
        vm.startPrank(superAdmin);
        uint256 balanceBefore = IERC20Upgradeable(WANT).balanceOf(superAdmin);
        bytes memory revertReason = abi.encodeWithSelector(VaultErrors.WithdrawStuckWrongToken.selector);
        vm.expectRevert(revertReason);
        pendleVault.inCaseTokensGetStuck(WANT);
        uint256 balanceAfter = IERC20Upgradeable(WANT).balanceOf(superAdmin);
        assertEq(balanceAfter, balanceBefore);
    }

    ////////////// REENTRANCY //////////////

    function test_reentrancy_FailsToReenterTheDeposit() public {
        Proxy pendleVaultProxy = new Proxy(
            address(new CompoundVault()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(strategyMock), // strategy MOCK
                WETH, // weth
                address(pendleCalculations), // pendleCalculations
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
        pendleVault = CompoundVault(address(pendleVaultProxy));

        strategyMock.setVault(address(pendleVault));
        strategyMock.setTarget(StrategyMock.Target.Deposit);
        deal(USDC, alice, 100e6, true);
        vm.startPrank(alice);
        IERC20Upgradeable(USDC).safeApprove(address(pendleVault), 100e6);
        bytes memory _data = abi.encode(alice, USDC, 100e6, hex"");
        vm.expectRevert(bytes("ReentrancyGuard: reentrant call"));
        pendleVault.deposit(alice, USDC, 100e6, _data);
    }

    function test_reentrancy_FailsToReenterTheDepositWithPermit() public {
        Proxy pendleVaultProxy = new Proxy(
            address(new CompoundVault()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(strategyMock), // strategy MOCK
                WETH, // weth
                address(pendleCalculations), // pendleCalculations
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
        pendleVault = CompoundVault(address(pendleVaultProxy));

        strategyMock.setVault(address(pendleVault));
        strategyMock.setTarget(StrategyMock.Target.DepositWithPermit);
        deal(USDC, alice, 100e6, true);
        vm.startPrank(alice);
        IERC20Upgradeable(USDC).safeApprove(address(pendleVault), 100e6);
        bytes memory _data = abi.encode(alice, USDC, 100e6, hex"");
        vm.expectRevert(bytes("ReentrancyGuard: reentrant call"));
        pendleVault.depositWithPermit(alice, USDC, 100e6, _data, new Signature[](1)[0]);
    }

    function test_reentrancy_FailsToReenterTheWithdrawal() public {
        Proxy pendleVaultProxy = new Proxy(
            address(new CompoundVault()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(strategyMock), // strategy MOCK
                WETH, // weth
                address(pendleCalculations), // pendleCalculations
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
        pendleVault = CompoundVault(address(pendleVaultProxy));

        strategyMock.setVault(address(pendleVault));
        strategyMock.setTarget(StrategyMock.Target.Withdraw);
        deal(USDC, alice, 100e6, true);
        vm.startPrank(alice);
        vm.expectRevert(bytes("ReentrancyGuard: reentrant call"));
        pendleVault.withdraw(alice, USDC, 0, hex"");
    }

    function test_reentrancy_FailsToUseANonContract() public {
        CompoundVault _implementation = new CompoundVault();
        // Adding an address that is not a contract as a deposit token
        depositAllowedTokens.push(address(1));
        bytes memory revertReason = abi.encodeWithSelector(AddressUtils.NotContract.selector, address(1));
        vm.expectRevert(revertReason);
        new Proxy(
            address(_implementation),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure), // adminStructure
                address(strategyMock), // strategy MOCK
                WETH, // weth
                address(pendleCalculations), // pendleCalculations
                depositAllowedTokens, // depositAllowedTokens
                withdrawalAllowedTokens, // withdrawalAllowedTokens
                depositLimits
            )
        );
    }

    ////////////// ALLOWED_TOKENS //////////////

    function test_allowedTokens_CheckEditDepositAllowedTokensOnlyOwner() public {
        vm.expectRevert(bytes("NotSuperAdmin"));
        pendleVault.editDepositAllowedTokens(token1, _ALLOWED);
    }

    function test_allowedTokens_CheckEditWithdrawalAllowedTokensOnlyOwner() public {
        vm.expectRevert(bytes("NotSuperAdmin"));
        pendleVault.editWithdrawalAllowedTokens(token1, _ALLOWED);
    }

    function test_allowedTokens_CheckAddNewDepositToken() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editDepositAllowedTokens(token1, _ALLOWED);
        // Token1 should be allowed for deposit
        assertEq(pendleVault.depositAllowedTokens(token1), _ALLOWED);
        bool exists = checkToken(pendleVault.getListAllowedTokens(IVault.TokenType.Deposit), token1);
        assertTrue(exists);
    }

    function test_allowedTokens_CheckAddNewWithdrawalToken() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editWithdrawalAllowedTokens(token1, _ALLOWED);
        // Token1 should be allowed for withdrawal
        assertEq(pendleVault.withdrawalAllowedTokens(token1), _ALLOWED);
        bool exists = checkToken(pendleVault.getListAllowedTokens(IVault.TokenType.Withdrawal), token1);
        assertTrue(exists);
    }

    function test_allowedTokens_CheckDeleteDepositToken() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editDepositAllowedTokens(USDC, _NOT_ALLOWED);
        // USDC should be disabled for deposit
        assertEq(pendleVault.depositAllowedTokens(USDC), _NOT_ALLOWED);
        bool exists = checkToken(pendleVault.getListAllowedTokens(IVault.TokenType.Deposit), USDC);
        assertFalse(exists);
    }

    function test_allowedTokens_CheckDeleteWithdrawalToken() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editWithdrawalAllowedTokens(USDC, _NOT_ALLOWED);
        // USDC should be disabled for withdrawal
        assertEq(pendleVault.withdrawalAllowedTokens(USDC), _NOT_ALLOWED);
        bool exists = checkToken(pendleVault.getListAllowedTokens(IVault.TokenType.Withdrawal), USDC);
        assertFalse(exists);
    }

    function test_allowedTokens_CheckTokenWontChangeDepositToken() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editDepositAllowedTokens(USDC, _NOT_ALLOWED);
        bytes memory revertReason =
            abi.encodeWithSelector(VaultErrors.TokenWontChange.selector, IVault.TokenType.Deposit, USDC);
        vm.expectRevert(revertReason);
        pendleVault.editDepositAllowedTokens(USDC, _NOT_ALLOWED);
        pendleVault.editDepositAllowedTokens(USDC, _ALLOWED);
        vm.expectRevert(revertReason);
        pendleVault.editDepositAllowedTokens(USDC, _ALLOWED);
    }

    function test_allowedTokens_CheckTokenWontChangeWithdrawalToken() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editWithdrawalAllowedTokens(USDC, _NOT_ALLOWED);
        bytes memory revertReason =
            abi.encodeWithSelector(VaultErrors.TokenWontChange.selector, IVault.TokenType.Withdrawal, USDC);
        vm.expectRevert(revertReason);
        pendleVault.editWithdrawalAllowedTokens(USDC, _NOT_ALLOWED);
        pendleVault.editWithdrawalAllowedTokens(USDC, _ALLOWED);
        vm.expectRevert(revertReason);
        pendleVault.editWithdrawalAllowedTokens(USDC, _ALLOWED);
    }

    function test_allowedTokens_CheckKeepAtLeastOneWithdrawal() public {
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editWithdrawalAllowedTokens(WBTC, _NOT_ALLOWED);
        pendleVault.editWithdrawalAllowedTokens(USDT, _NOT_ALLOWED);
        bytes memory revertReason =
            abi.encodeWithSelector(VaultErrors.MustKeepOneToken.selector, IVault.TokenType.Withdrawal);
        vm.expectRevert(revertReason);
        pendleVault.editWithdrawalAllowedTokens(USDC, _NOT_ALLOWED);
        assertEq(pendleVault.getListAllowedTokens(IVault.TokenType.Withdrawal).length, 1);
    }

    function test_allowedTokens_CheckGetListDepositAllowedTokens() public {
        // Initially the same
        assertTrue(compareArrays(pendleVault.getListAllowedTokens(IVault.TokenType.Deposit), depositAllowedTokens));
        vm.prank(adminStructure.superAdmin());
        pendleVault.editDepositAllowedTokens(WBTC, _NOT_ALLOWED);
        address[] memory newList = pendleVault.getListAllowedTokens(IVault.TokenType.Deposit);
        assertEq(newList.length, 2);
        assertEq(newList[0], USDT);
        assertEq(newList[1], USDC);
    }

    function test_allowedTokens_CheckGetListWithdrawalAllowedTokens() public {
        // Initially the same
        assertTrue(
            compareArrays(pendleVault.getListAllowedTokens(IVault.TokenType.Withdrawal), withdrawalAllowedTokens)
        );
        vm.prank(adminStructure.superAdmin());
        pendleVault.editWithdrawalAllowedTokens(WBTC, _NOT_ALLOWED);
        address[] memory newList = pendleVault.getListAllowedTokens(IVault.TokenType.Withdrawal);
        assertEq(newList.length, 2);
        assertEq(newList[0], USDT);
        assertEq(newList[1], USDC);
    }

    function test_allowedTokens_FailsToDepositWithNotAllowedToken() public {
        // Disabling WBTC
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editDepositAllowedTokens(WBTC, _NOT_ALLOWED);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.NotAllowedDepositToken.selector, WBTC));
        pendleVault.deposit(alice, WBTC, 10e6, hex"");
    }

    function test_allowedTokens_FailsToEditAllowedWithInvalidStatus() public {
        uint256 _invalidStatus = 3;
        vm.startPrank(adminStructure.superAdmin());
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.InvalidTokenStatus.selector));
        pendleVault.editWithdrawalAllowedTokens(WBTC, _invalidStatus);
    }

    function test_allowedTokens_FailsToWithdrawWithNotAllowedToken() public {
        // Disabling WBTC
        vm.startPrank(adminStructure.superAdmin());
        pendleVault.editWithdrawalAllowedTokens(WBTC, _NOT_ALLOWED);
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.NotAllowedWithdrawalToken.selector, WBTC));
        pendleVault.withdraw(alice, WBTC, 0, hex"");
    }

    function test_FailsToEstimateWithdrawalInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.NotAllowedWithdrawalToken.selector, WANT));
        pendleVault.estimateWithdrawal(alice, 0, hex"", WANT);
    }

    ////////////// Shares //////////////

    function test_shares_FailsToWithdrawWithInsufficientShares() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.InsufficientAmount.selector));
        pendleVault.withdraw(alice, WBTC, 10, hex"");
    }

    function test_shares_ShowsEquivalentWantToSharesFirstDeposit() public {
        deal(WANT, address(pendleVault), 10e18);
        uint256 _expected = 10e18;
        uint256 _shares = pendleVault.wantToShares(10e18);
        assertEq(_expected, _shares);
    }

    function compareArrays(address[] memory array1, address[] memory array2) public pure returns (bool areEqual) {
        return keccak256(abi.encodePacked(array1)) == keccak256(abi.encodePacked(array2));
    }

    function checkToken(address[] memory _list, address _token) public pure returns (bool) {
        for (uint256 i; i < _list.length; i++) {
            if (_list[i] == _token) return true;
        }
        return false;
    }
}

contract EmptyMock { }
