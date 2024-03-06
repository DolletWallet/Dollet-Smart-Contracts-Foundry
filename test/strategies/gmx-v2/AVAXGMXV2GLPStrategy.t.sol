// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { IGMXV2GLPStrategy } from "src/strategies/gmx-v2/interfaces/IGMXV2GLPStrategy.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { GMXV2GLPCalculations } from "src/calculations/gmx-v2/GMXV2GLPCalculations.sol";
import { TemporaryAdminStructure } from "src/admin/TemporaryAdminStructure.sol";
import { GMXV2GLPStrategy } from "src/strategies/gmx-v2/GMXV2GLPStrategy.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { IFeeManager } from "src/interfaces/dollet/IFeeManager.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { StrategyErrors } from "src/libraries/StrategyErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { VaultErrors } from "src/libraries/VaultErrors.sol";
import { SigningUtils } from "../../utils/SigningUtils.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { Signature } from "src/libraries/ERC20Lib.sol";
import { FeeManager } from "src/FeeManager.sol";
import "addresses/AVAXMainnet.sol";
import "forge-std/Test.sol";

contract AVAXGMXV2GLPStrategyTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    SigningUtils public signingUtils;
    TemporaryAdminStructure public adminStructure;
    StrategyHelper public strategyHelper;
    FeeManager public feeManager;
    GMXV2GLPCalculations public calculations;
    GMXV2GLPStrategy public strategy;
    CompoundVault public vault;

    address public alice;
    address public bob;
    address public carol;

    uint256 public alicePrivateKey;

    uint16 public slippageTolerance = 100; // 1.00% (2 decimals)
    address[] public tokensToCompound = [WAVAX];
    uint256[] public minimumsToCompound = [0.3e17];
    address[] public allowedTokens = [AVAX, WAVAX, WETHe, BTCb, WBTCe, USDC, USDCe];
    uint256[] public limits = [2.7e17, 2.7e17, 638e13, 38e3, 38e3, 10e6, 10e6];

    address public managementFeeRecipient = makeAddr("ManagementFeeRecipient");
    address public performanceFeeRecipient = makeAddr("PerformanceFeeRecipient");
    uint16 public managementFee = 0; // 0.00% (2 decimals)
    uint16 public performanceFee = 2000; // 20.00% (2 decimals)

    address public usdcWhale = 0x1205f31718499dBf1fCa446663B532Ef87481fe1;

    IGMXV2GLPStrategy.InitParams private initParams;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_AVAX_MAINNET"), 42_162_551);

        (alice, alicePrivateKey) = makeAddrAndKey("Alice");
        (bob,) = makeAddrAndKey("Bob");
        (carol,) = makeAddrAndKey("Carol");

        signingUtils = new SigningUtils();

        Proxy adminStructureProxy = new Proxy(
            address(new TemporaryAdminStructure()),
            abi.encodeWithSignature("initialize()")
        );
        adminStructure = TemporaryAdminStructure(address(adminStructureProxy));

        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        Proxy feeManagerProxy = new Proxy(
            address(new FeeManager()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        feeManager = FeeManager(address(feeManagerProxy));

        Proxy GMXV2GLPCalculationsProxy = new Proxy(
            address(new GMXV2GLPCalculations()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), USDC)
        );
        calculations = GMXV2GLPCalculations(address(GMXV2GLPCalculationsProxy));

        initParams = IGMXV2GLPStrategy.InitParams({
            adminStructure: address(adminStructure),
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WAVAX,
            want: sGLP,
            calculations: address(calculations),
            gmxGlpHandler: GMX_GLP_HANDLER,
            gmxRewardsHandler: GMX_REWARDS_HANDLER,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });
        Proxy GMXV2GLPStrategyProxy = new Proxy(
            address(new GMXV2GLPStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
        strategy = GMXV2GLPStrategy(payable(address(GMXV2GLPStrategyProxy)));

        IVault.DepositLimit[] memory depositLimits = new IVault.DepositLimit[](limits.length);

        for (uint256 i; i < limits.length; ++i) {
            depositLimits[i] = IVault.DepositLimit(allowedTokens[i], limits[i]);
        }

        Proxy compoundVaultProxy = new Proxy(
            address(new CompoundVault()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure),
                address(strategy),
                WAVAX,
                address(calculations),
                allowedTokens,
                allowedTokens,
                depositLimits
            )
        );
        vault = CompoundVault(address(compoundVaultProxy));

        vm.startPrank(adminStructure.superAdmin());

        strategy.setSlippageTolerance(slippageTolerance);
        strategy.setVault(address(vault));

        calculations.setStrategyValues(address(strategy));

        feeManager.setFee(address(strategy), IFeeManager.FeeType.MANAGEMENT, managementFeeRecipient, managementFee);
        feeManager.setFee(address(strategy), IFeeManager.FeeType.PERFORMANCE, performanceFeeRecipient, performanceFee);

        strategyHelper.setOracle(WAVAX, AVAX_ORACLE);
        strategyHelper.setOracle(WETHe, ETH_ORACLE);
        strategyHelper.setOracle(BTCb, WBTC_ORACLE);
        strategyHelper.setOracle(WBTCe, WBTC_ORACLE);
        strategyHelper.setOracle(USDC, USDC_ORACLE);
        strategyHelper.setOracle(USDCe, USDC_ORACLE);

        vm.stopPrank();
    }

    function test_initialize_ShouldFailWhenCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        strategy.initialize(initParams);
    }

    function test_initialize_ShouldFailWhenGmxGlpHandlerIsNotContract() external {
        GMXV2GLPStrategy newStrategy = new GMXV2GLPStrategy();

        initParams.gmxGlpHandler = address(0);

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newStrategy),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
    }

    function test_initialize_ShouldFailWhenGmxRewardsHandlerIsNotContract() external {
        GMXV2GLPStrategy newStrategy = new GMXV2GLPStrategy();

        initParams.gmxRewardsHandler = address(0);

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newStrategy),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
    }

    function test_initialize() external {
        Proxy GMXV2GLPStrategyProxy = new Proxy(
            address(new GMXV2GLPStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
        GMXV2GLPStrategy newStrategy = GMXV2GLPStrategy(payable(address(GMXV2GLPStrategyProxy)));

        assertEq(address(newStrategy.gmxGlpHandler()), GMX_GLP_HANDLER);
        assertEq(address(newStrategy.gmxRewardsHandler()), GMX_REWARDS_HANDLER);
    }

    function test_gmxGlpHandler() external {
        assertEq(address(strategy.gmxGlpHandler()), GMX_GLP_HANDLER);
    }

    function test_gmxRewardsHandler() external {
        assertEq(address(strategy.gmxRewardsHandler()), GMX_REWARDS_HANDLER);
    }

    function test_balance() external {
        assertEq(strategy.balance(), 0);
    }

    function test_deposit_ShouldFailIfInsufficientDepositTokenOut() external {
        address user = alice;
        address token = WAVAX;
        uint256 amount = 1e18;

        deal(token, user, amount);

        vm.startPrank(user);

        IERC20Upgradeable(token).safeApprove(address(vault), amount);

        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));

        vault.deposit(user, token, amount, _getAdditionalData(amount * amount));

        vm.stopPrank();
    }

    function test_deposit_ShouldDepositInAVAX() external {
        address user = alice;
        address token = AVAX;
        uint256 amount = 100e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 34e18);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 34e18);
    }

    function test_deposit_ShouldDepositInWAVAX() external {
        address user = alice;
        address token = WAVAX;
        uint256 amount = 100e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 34e18);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 34e18);
    }

    function test_deposit_ShouldDepositInWETHe() external {
        address user = alice;
        address token = WETHe;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 23e18);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 23e18);
    }

    function test_deposit_ShouldDepositInBTCb() external {
        address user = alice;
        address token = BTCb;
        uint256 amount = 1e8;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 3e20);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 3e20);
    }

    function test_deposit_ShouldDepositInWBTCe() external {
        address user = alice;
        address token = WBTCe;
        uint256 amount = 1e8;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 2e20);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 2e20);
    }

    function test_deposit_ShouldDepositInUSDC() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 5000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        vm.prank(usdcWhale);

        IERC20Upgradeable(token).safeTransfer(user, amount);

        vm.startPrank(user);

        IERC20Upgradeable(token).safeApprove(address(vault), amount);
        vault.deposit(user, token, amount, _getAdditionalData(depositEstimationResult));

        vm.stopPrank();

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 5e19);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 5e19);
    }

    function test_deposit_ShouldDepositInUSDCe() external {
        address user = alice;
        address token = USDCe;
        uint256 amount = 1000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 9e18);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 9e18);
    }

    function test_deposit_ShouldDepositInUSDCWithPermit() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 5000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        vm.prank(usdcWhale);

        IERC20Upgradeable(token).safeTransfer(user, amount);

        vm.startPrank(user);

        Signature memory signature =
            signingUtils.signPermit(token, user, alicePrivateKey, address(vault), amount, block.timestamp);

        vault.depositWithPermit(user, token, amount, _getAdditionalData(depositEstimationResult), signature);

        vm.stopPrank();

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 5e19);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 5e19);
    }

    function test_deposit_ShouldDepositWithDifferentTokensForAFewTimes() external {
        address user = alice;

        for (uint256 i; i < allowedTokens.length; ++i) {
            if (allowedTokens[i] == USDC) continue; // deal for USDC is not working

            uint256 depositEstimationResult = calculations.estimateDeposit(
                allowedTokens[i] == AVAX ? WAVAX : allowedTokens[i], limits[i], slippageTolerance, hex""
            );

            _deposit(user, allowedTokens[i], limits[i], _getAdditionalData(depositEstimationResult), false, 0);

            assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
            assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 9e19);
            assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 9e19);
        }
    }

    function test_deposit_ShouldProcessDepositsOfAFewUsersProperly() external {
        address[3] memory users = [alice, bob, carol];
        uint256[3] memory amounts = [uint256(2.7e17), 2.7e17, 638e13];

        for (uint256 i; i < users.length; ++i) {
            if (allowedTokens[i] == USDC) continue; // deal for USDC is not working

            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(
                allowedTokens[i] == AVAX ? WAVAX : allowedTokens[i], amounts[i], slippageTolerance, hex""
            );

            _deposit(users[i], allowedTokens[i], amounts[i], _getAdditionalData(depositEstimationResult), false, 0);

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(strategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 3e22);
            assertApproxEqAbs(strategy.userWantDeposit(users[i]), depositEstimationResult, 3e22);
        }
    }

    function test_withdraw_ShouldFailIfWantToWithdrawIsZero() external {
        address user = alice;
        address token = BTCb;
        uint256 amount = 1e8;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.WrongAmount.selector));

        vault.withdraw(bob, token, 0, _getAdditionalData(0));
    }

    function test_withdraw_ShouldFailIfInsufficientWithdrawalTokenOut() external {
        address user = alice;
        uint256 amount = 100e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippageTolerance, hex"");

        _deposit(user, AVAX, amount, _getAdditionalData(depositEstimationResult), false, 0);

        uint256 amountShares = vault.userShares(user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));

        vault.withdraw(bob, USDC, amountShares, _getAdditionalData(200e18));
    }

    function test_withdraw_ShouldWithdrawFullDepositInAVAX() external {
        address user = alice;
        address token = AVAX;
        uint256 amount = 100e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        address recipient = bob;
        uint256 amountShares = vault.calculateSharesToWithdraw(user, 0, slippageTolerance, hex"", true);
        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(user, slippageTolerance, hex"", token);

        assertEq(recipient.balance, 0);

        vm.prank(user);

        vault.withdraw(
            recipient, token, amountShares, _getAdditionalData(withdrawalEstimationResult.depositInTokenAfterFee)
        );

        assertTrue(recipient.balance > withdrawalEstimationResult.depositInTokenAfterFee);
        assertApproxEqAbs(recipient.balance, withdrawalEstimationResult.depositInTokenAfterFee, 7e17);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(user), 0);
    }

    function test_withdraw_ShouldWithdrawFullDepositInWAVAX() external {
        address user = alice;
        address token = WAVAX;
        uint256 amount = 100e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        address recipient = bob;
        uint256 amountShares = vault.calculateSharesToWithdraw(user, 0, slippageTolerance, hex"", true);
        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(user, slippageTolerance, hex"", token);

        assertEq(_balance(token, recipient), 0);

        vm.prank(user);

        vault.withdraw(
            recipient, token, amountShares, _getAdditionalData(withdrawalEstimationResult.depositInTokenAfterFee)
        );

        assertTrue(_balance(token, recipient) > withdrawalEstimationResult.depositInTokenAfterFee);
        assertApproxEqAbs(_balance(token, recipient), withdrawalEstimationResult.depositInTokenAfterFee, 7e17);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(user), 0);
    }

    function test_withdraw_ShouldWithdrawFullDepositInWETHe() external {
        address user = alice;
        address token = WETHe;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        address recipient = bob;
        uint256 amountShares = vault.calculateSharesToWithdraw(user, 0, slippageTolerance, hex"", true);
        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(user, slippageTolerance, hex"", token);

        assertEq(_balance(token, recipient), 0);

        vm.prank(user);

        vault.withdraw(
            recipient, token, amountShares, _getAdditionalData(withdrawalEstimationResult.depositInTokenAfterFee)
        );

        assertTrue(_balance(token, recipient) > withdrawalEstimationResult.depositInTokenAfterFee);
        assertApproxEqAbs(_balance(token, recipient), withdrawalEstimationResult.depositInTokenAfterFee, 9e15);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(user), 0);
    }

    function test_withdraw_ShouldWithdrawFullDepositInBTCb() external {
        address user = alice;
        address token = BTCb;
        uint256 amount = 1e8;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        address recipient = bob;
        uint256 amountShares = vault.calculateSharesToWithdraw(user, 0, slippageTolerance, hex"", true);
        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(user, slippageTolerance, hex"", token);

        assertEq(_balance(token, recipient), 0);

        vm.prank(user);

        vault.withdraw(
            recipient, token, amountShares, _getAdditionalData(withdrawalEstimationResult.depositInTokenAfterFee)
        );

        assertTrue(_balance(token, recipient) > withdrawalEstimationResult.depositInTokenAfterFee);
        assertApproxEqAbs(_balance(token, recipient), withdrawalEstimationResult.depositInTokenAfterFee, 2e6);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(user), 0);
    }

    function test_withdraw_ShouldWithdrawFullDepositInWBTCe() external {
        address user = alice;
        address token = WBTCe;
        uint256 amount = 1e8;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        address recipient = bob;
        uint256 amountShares = vault.calculateSharesToWithdraw(user, 0, slippageTolerance, hex"", true);
        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(user, slippageTolerance, hex"", token);

        assertEq(_balance(token, recipient), 0);

        vm.prank(user);

        vault.withdraw(
            recipient, token, amountShares, _getAdditionalData(withdrawalEstimationResult.depositInTokenAfterFee)
        );

        assertTrue(_balance(token, recipient) > withdrawalEstimationResult.depositInTokenAfterFee);
        assertApproxEqAbs(_balance(token, recipient), withdrawalEstimationResult.depositInTokenAfterFee, 2e6);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(user), 0);
    }

    function test_withdraw_ShouldWithdrawFullDepositInUSDC() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 5000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        vm.prank(usdcWhale);

        IERC20Upgradeable(token).safeTransfer(user, amount);

        vm.startPrank(user);

        IERC20Upgradeable(token).safeApprove(address(vault), amount);
        vault.deposit(user, token, amount, _getAdditionalData(depositEstimationResult));

        vm.stopPrank();

        address recipient = bob;
        uint256 amountShares = vault.calculateSharesToWithdraw(user, 0, slippageTolerance, hex"", true);
        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(user, slippageTolerance, hex"", token);

        assertEq(_balance(token, recipient), 0);

        vm.prank(user);

        vault.withdraw(
            recipient, token, amountShares, _getAdditionalData(withdrawalEstimationResult.depositInTokenAfterFee)
        );

        assertTrue(_balance(token, recipient) > withdrawalEstimationResult.depositInTokenAfterFee);
        assertApproxEqAbs(_balance(token, recipient), withdrawalEstimationResult.depositInTokenAfterFee, 4e7);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(user), 0);
    }

    function test_withdraw_ShouldWithdrawFullDepositInUSDCe() external {
        address user = alice;
        address token = USDCe;
        uint256 amount = 1000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        address recipient = bob;
        uint256 amountShares = vault.calculateSharesToWithdraw(user, 0, slippageTolerance, hex"", true);
        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(user, slippageTolerance, hex"", token);

        assertEq(_balance(token, recipient), 0);

        vm.prank(user);

        vault.withdraw(
            recipient, token, amountShares, _getAdditionalData(withdrawalEstimationResult.depositInTokenAfterFee)
        );

        assertTrue(_balance(token, recipient) > withdrawalEstimationResult.depositInTokenAfterFee);
        assertApproxEqAbs(_balance(token, recipient), withdrawalEstimationResult.depositInTokenAfterFee, 8e6);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(user), 0);
    }

    function test_compound_ShouldNotCompoundIfNotEnoughRewardsToClaimAndCompound() external {
        address user = alice;
        address token = USDCe;
        uint256 amount = 1000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 5 minutes);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(0, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertEq(currStrategyBalance, prevStrategyBalance);
        assertEq(prevStrategyBalance, wantAfterCompoundEstimation);
        assertEq(currStrategyBalance, wantAfterCompoundEstimation);
    }

    function test_compound_ShouldCompoundProperly1() external {
        address user = alice;
        address token = USDCe;
        uint256 amount = 50_000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 2 days);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(0, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertTrue(currStrategyBalance > prevStrategyBalance);
        assertTrue(currStrategyBalance < wantAfterCompoundEstimation);
        assertApproxEqAbs(currStrategyBalance, wantAfterCompoundEstimation, 4e19);
    }

    function test_compound_ShouldCompoundProperly2() external {
        address user = alice;
        address token = WBTCe;
        uint256 amount = 10e8;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 2 days);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(0, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertTrue(currStrategyBalance > prevStrategyBalance);
        assertTrue(currStrategyBalance < wantAfterCompoundEstimation);
        assertApproxEqAbs(currStrategyBalance, wantAfterCompoundEstimation, 33e18);
    }

    function test_compound_ShouldCompoundProperly3() external {
        address user = alice;
        address token = BTCb;
        uint256 amount = 10e8;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 3 days);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(0, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertTrue(currStrategyBalance > prevStrategyBalance);
        assertTrue(currStrategyBalance < wantAfterCompoundEstimation);
        assertApproxEqAbs(currStrategyBalance, wantAfterCompoundEstimation, 5e19);
    }

    function test_compound_ShouldCompoundProperly4() external {
        address user = alice;
        address token = WAVAX;
        uint256 amount = 10_000e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 2 days);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(500, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertTrue(currStrategyBalance > prevStrategyBalance);
        assertTrue(currStrategyBalance < wantAfterCompoundEstimation);
        assertApproxEqAbs(currStrategyBalance, wantAfterCompoundEstimation, 2e18);
    }

    function _deposit(
        address user,
        address token,
        uint256 amount,
        bytes memory additionalData,
        bool withPermit,
        uint256 userPrivateKey
    )
        private
    {
        vm.startPrank(user);

        if (token == address(0)) {
            vm.deal(user, amount);
        } else {
            deal(token, user, amount);

            if (!withPermit) IERC20Upgradeable(token).safeApprove(address(vault), amount);
        }

        if (withPermit) {
            Signature memory signature =
                signingUtils.signPermit(token, user, userPrivateKey, address(vault), amount, block.timestamp);

            vault.depositWithPermit(user, token, amount, additionalData, signature);
        } else {
            vault.deposit{ value: token == address(0) ? amount : 0 }(user, token, amount, additionalData);
        }

        vm.stopPrank();
    }

    function _balance(address token, address user) private view returns (uint256) {
        return IERC20Upgradeable(token).balanceOf(user);
    }

    function _getAdditionalData(uint256 minOut) private pure returns (bytes memory) {
        return abi.encode(minOut);
    }
}
