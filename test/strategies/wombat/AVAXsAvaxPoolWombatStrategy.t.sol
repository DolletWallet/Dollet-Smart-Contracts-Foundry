// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { StrategyHelperVenueTraderJoeV1, StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IWombatStrategy } from "src/strategies/wombat/interfaces/IWombatStrategy.sol";
import { WombatCalculations } from "src/calculations/wombat/WombatCalculations.sol";
import { TemporaryAdminStructure } from "src/admin/TemporaryAdminStructure.sol";
import { WombatStrategy } from "src/strategies/wombat/WombatStrategy.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { OracleTraderJoeV1 } from "src/oracles/OracleTraderJoeV1.sol";
import { IFeeManager } from "src/interfaces/dollet/IFeeManager.sol";
import { StrategyErrors } from "src/libraries/StrategyErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { SigningUtils } from "../../utils/SigningUtils.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { FeeManager } from "src/FeeManager.sol";
import "addresses/AVAXMainnet.sol";
import "forge-std/Test.sol";

contract AVAXsAVAXPoolWombatStrategyTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    SigningUtils public signingUtils;
    TemporaryAdminStructure public adminStructure;
    StrategyHelper public strategyHelper;
    FeeManager public feeManager;
    WombatCalculationsMock public calculations;
    WombatStrategy public strategy;
    CompoundVault public vault;

    address public alice;
    address public bob;
    address public carol;

    uint256 public alicePrivateKey;

    address public want = 0x29eeB257a2A6eCDE2984aCeDF80A1B687f18eC91; // LP-AVAX
    uint16 public slippage = 100; // 1.00% (2 decimals)
    address[] public tokensToCompound = [WOM, QI];
    uint256[] public minimumsToCompound = [27e18, 45e18];
    address[] public allowedTokens = [AVAX, WAVAX];
    uint256[] public limits = [2.3e17, 2.3e17];

    address public managementFeeRecipient = makeAddr("ManagementFeeRecipient");
    address public performanceFeeRecipient = makeAddr("PerformanceFeeRecipient");
    uint16 public managementFee = 0; // 0.00% (2 decimals)
    uint16 public performanceFee = 2000; // 20.00% (2 decimals)

    WombatStrategy.InitParams private initParams;

    address public QI_WHALE = 0x142eB2ed775e6d497aa8D03A2151D016bbfE7Fc2;

    event ChargedFees(IFeeManager.FeeType feeType, uint256 feeAmount, address feeRecipient, address _token);

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_AVAX_MAINNET"), 42_300_708);

        (alice, alicePrivateKey) = makeAddrAndKey("Alice");
        (bob,) = makeAddrAndKey("Bob");
        (carol,) = makeAddrAndKey("Carol");

        signingUtils = new SigningUtils();

        Proxy adminStructureProxy =
            new Proxy(address(new TemporaryAdminStructure()), abi.encodeWithSignature("initialize()"));
        adminStructure = TemporaryAdminStructure(address(adminStructureProxy));

        // STRATEGY HELPER
        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()), abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        // FEE MANAGER
        Proxy feeManagerProxy = new Proxy(
            address(new FeeManager()), abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        feeManager = FeeManager(address(feeManagerProxy));

        // SWAPS
        StrategyHelperVenueTraderJoeV1 strategyHelperVenueTraderJoeV1 =
            new StrategyHelperVenueTraderJoeV1(TRADER_JOE_V1_ROUTER);

        vm.startPrank(adminStructure.superAdmin());
        strategyHelper.setPath(WOM, WAVAX, address(strategyHelperVenueTraderJoeV1), abi.encodePacked(WOM, WAVAX)); // WOM/WAVAX
        strategyHelper.setPath(QI, WAVAX, address(strategyHelperVenueTraderJoeV1), abi.encodePacked(QI, WAVAX)); // QI/WAVAX
        vm.stopPrank();

        // ORACLES
        Proxy womOracleProxy = new Proxy(
            address(new OracleTraderJoeV1()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address)",
                address(adminStructure),
                address(strategyHelper),
                TRADER_JOE_V1_ROUTER,
                WOM,
                WAVAX,
                WAVAX
            )
        );
        OracleTraderJoeV1 womOracle = OracleTraderJoeV1(address(womOracleProxy));

        vm.startPrank(adminStructure.superAdmin());
        strategyHelper.setOracle(WAVAX, AVAX_ORACLE);
        strategyHelper.setOracle(WOM, address(womOracle));
        strategyHelper.setOracle(QI, QI_ORACLE);
        vm.stopPrank();

        // CALCULATIONS
        Proxy wombatCalculationsProxy = new Proxy(
            address(new WombatCalculationsMock()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        calculations = WombatCalculationsMock(address(wombatCalculationsProxy));

        // STRATEGY
        initParams = IWombatStrategy.InitParams({
            adminStructure: address(adminStructure),
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WAVAX,
            want: want,
            pool: WOMBAT_AVAX_sAVAX_POOL,
            wom: WOM,
            targetAsset: WAVAX,
            calculations: address(calculations),
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });
        Proxy wombatStrategyProxy = new Proxy(
            address(new WombatStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
        strategy = WombatStrategy(payable(address(wombatStrategyProxy)));

        // VAULT
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

        // SET UP
        vm.startPrank(adminStructure.superAdmin());
        strategy.setSlippageTolerance(slippage);
        strategy.setVault(address(vault));
        feeManager.setFee(address(strategy), IFeeManager.FeeType.MANAGEMENT, managementFeeRecipient, managementFee);
        feeManager.setFee(address(strategy), IFeeManager.FeeType.PERFORMANCE, performanceFeeRecipient, performanceFee);
        calculations.setStrategyValues(address(strategy));
        vm.stopPrank();

        // DISTRIBUTION
        deal(WAVAX, alice, 1000e18);
        deal(WAVAX, bob, 1000e18);

        deal(alice, 1000e18);
        deal(bob, 1000e18);
    }

    // ==============
    // ||   INIT   ||
    // ==============

    function test_initialize_Success() public {
        Proxy strategyProxy = new Proxy(
            address(new WombatStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );

        WombatStrategy strategyLocal = WombatStrategy(payable(address(strategyProxy)));
        assertEq(address(strategyLocal.pool()), initParams.pool);
        assertEq(address(strategyLocal.wom()), initParams.wom);
        assertEq(address(strategyLocal.targetAsset()), initParams.targetAsset);
    }

    function test_initialize_Fail_CalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        strategy.initialize(initParams);
    }

    function test_initialize_Fail_PoolIsNotContract() external {
        WombatStrategy newStrategy = new WombatStrategy();

        initParams.pool = address(0);

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newStrategy),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
    }

    function test_initialize_Fail_WomIsNotContract() external {
        WombatStrategy newStrategy = new WombatStrategy();

        initParams.wom = address(0);

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newStrategy),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
    }

    function test_initialize_Fail_TargetAssetIsNotContract() external {
        WombatStrategy newStrategy = new WombatStrategy();

        initParams.targetAsset = address(0);

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newStrategy),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
    }

    // =================
    // ||   DEPOSIT   ||
    // =================

    // AVAX

    function test_deposit_Success_DepositInAVAX() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(alice) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 1e16);
        assertApproxEqAbs(strategy.userWantDeposit(alice), depositEstimationResult, 1e16);
    }

    function test_deposit_Success_DepositInAVAXMultipleTimesSameUser() external {
        address token = AVAX;
        uint256[2] memory amounts = [uint256(2e18), uint256(5e18)];

        for (uint256 i; i < amounts.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amounts[i], slippage, hex"");

            _deposit(alice, token, amounts[i], _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(strategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 5e17);
            assertApproxEqAbs(strategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 5e17);
        }
    }

    function test_deposit_Success_DepositInAVAXMultipleTimesDifferentUsers() external {
        address token = AVAX;
        uint256 amount = 1e18;
        address[2] memory users = [alice, bob];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

            _deposit(users[i], token, amount, _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(strategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 1e16);
            assertApproxEqAbs(strategy.userWantDeposit(users[i]), depositEstimationResult, 1e16);
        }
    }

    function test_deposit_Success_DepositWithCompoundInAVAXMultipleTimesSameUser() external {
        address token = AVAX;
        uint256[2] memory amounts = [uint256(2e18), uint256(5e18)];

        for (uint256 i; i < amounts.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amounts[i], slippage, hex"");

            _deposit(alice, token, amounts[i], _getAdditionalData(depositEstimationResult, slippage));

            // Sending some reward token to trigger a compound
            deal(WOM, address(strategy), 169e18, true);
            vm.prank(QI_WHALE);
            ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(strategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 5e17);
            assertApproxEqAbs(strategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 5e17);
        }
    }

    function test_deposit_Success_DepositWithCompoundInAVAXMultipleTimesDifferentUser() external {
        address token = AVAX;
        uint256 amount = 1e18;
        address[2] memory users = [alice, bob];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

            _deposit(users[i], token, amount, _getAdditionalData(depositEstimationResult, slippage));

            // Sending some reward token to trigger a compound
            deal(WOM, address(strategy), 169e18, true);
            vm.prank(QI_WHALE);
            ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(strategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 1e16);
            assertApproxEqAbs(strategy.userWantDeposit(users[i]), depositEstimationResult, 1e16);
        }
    }

    function test_deposit_Fail_InsufficientDepositTokenOutAVAX() external {
        address token = AVAX;
        uint256 amount = 1e18;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));
        vault.deposit{ value: amount }(alice, token, amount, _getAdditionalData(amount * amount, slippage));
        vm.stopPrank();
    }

    // WAVAX

    function test_deposit_Success_DepositInWAVAX() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(alice) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 1e16);
        assertApproxEqAbs(strategy.userWantDeposit(alice), depositEstimationResult, 1e16);
    }

    function test_deposit_Success_DepositInWAVAXMultipleTimesSameUser() external {
        address token = WAVAX;
        uint256[2] memory amounts = [uint256(2e18), uint256(5e18)];

        for (uint256 i; i < amounts.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amounts[i], slippage, hex"");

            _deposit(alice, token, amounts[i], _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(strategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 5e17);
            assertApproxEqAbs(strategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 5e17);
        }
    }

    function test_deposit_Success_DepositInWAVAXMultipleTimesDifferentUsers() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        address[2] memory users = [alice, bob];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

            _deposit(users[i], token, amount, _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(strategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 1e16);
            assertApproxEqAbs(strategy.userWantDeposit(users[i]), depositEstimationResult, 1e16);
        }
    }

    function test_deposit_Success_DepositWithCompoundInWAVAXMultipleTimesSameUser() external {
        address token = WAVAX;
        uint256[2] memory amounts = [uint256(2e18), uint256(5e18)];

        for (uint256 i; i < amounts.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amounts[i], slippage, hex"");

            _deposit(alice, token, amounts[i], _getAdditionalData(depositEstimationResult, slippage));

            // Sending some reward token to trigger a compound
            deal(WOM, address(strategy), 169e18, true);
            vm.prank(QI_WHALE);
            ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(strategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 5e17);
            assertApproxEqAbs(strategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 5e17);
        }
    }

    function test_deposit_Success_DepositWithCompoundInWAVAXMultipleTimesDifferentUser() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        address[2] memory users = [alice, bob];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

            _deposit(users[i], token, amount, _getAdditionalData(depositEstimationResult, slippage));

            // Sending some reward token to trigger a compound
            deal(WOM, address(strategy), 169e18, true);
            vm.prank(QI_WHALE);
            ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(strategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 1e16);
            assertApproxEqAbs(strategy.userWantDeposit(users[i]), depositEstimationResult, 1e16);
        }
    }

    function test_deposit_Fail_InsufficientDepositTokenOutWAVAX() external {
        address token = WAVAX;
        uint256 amount = 1e18;

        vm.startPrank(alice);
        IERC20Upgradeable(WAVAX).safeApprove(address(vault), amount);

        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));
        vault.deposit{ value: 0 }(alice, token, amount, _getAdditionalData(amount * amount, slippage));
        vm.stopPrank();
    }

    // COMBINED

    function test_deposit_Success_DepositWithDifferentTokens() external {
        uint256 amount = 1e18;

        for (uint256 i; i < allowedTokens.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

            _deposit(alice, allowedTokens[i], amount, _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(strategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 1e16);
            assertApproxEqAbs(strategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 1e16);
        }
    }

    // ==================
    // ||   WITHDRAW   ||
    // ==================

    function test_withdraw_ChargePerfomanceFee() public {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        IFeeManager.FeeType performanceFeeType = IFeeManager.FeeType.PERFORMANCE;

        vm.startPrank(alice);
        vm.expectEmit(true, false, true, false, address(strategy));

        emit ChargedFees(performanceFeeType, 0, performanceFeeRecipient, token);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));
    }

    // AVAX

    function test_withdraw_Success_WithdrawAllInAVAXFlag() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares = vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(0), true);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2.6e13);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllInAVAXNoFlag() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2.6e13);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_PartialWithdrawInAVAX() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 1.3e13);
        assertApproxEqAbs(
            strategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 2
        );
        assertApproxEqAbs(
            strategy.userWantDeposit(alice), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 2
        );
    }

    function test_withdraw_Success_PartialWithdrawInAVAXMultipleTimes() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);
        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 1.3e13);
        assertApproxEqAbs(
            strategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 2
        );
        assertApproxEqAbs(
            strategy.userWantDeposit(alice), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 2
        );

        vm.prank(alice);
        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(
            bob.balance - balanceBefore,
            calculations.convertWantToTargetAsset(withdrawalEstimationResult.wantDepositAfterFee),
            2.6e13
        );
        assertApproxEqAbs(strategy.totalWantDeposits(), 0, 5);
        assertApproxEqAbs(strategy.userWantDeposit(alice), 0, 5);
    }

    function test_withdraw_Fail_InsufficientDepositTokenOutAVAX() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        uint256 amountShares = vault.userShares(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));
        vault.withdraw(bob, token, amountShares, _getAdditionalData(amount * amount, slippage));
    }

    // WAVAX

    function test_withdraw_Success_WithdrawAllInWAVAXFlag() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares = vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(0), true);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 2.6e13);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllInWAVAXNoFlag() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 2.6e13);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_PartialWithdrawInWAVAX() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 1.3e13);
        assertApproxEqAbs(
            strategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 2
        );
        assertApproxEqAbs(
            strategy.userWantDeposit(alice), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 2
        );
    }

    function test_withdraw_Success_PartialWithdrawInWAVAXMultipleTimes() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);
        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 1.3e13);
        assertApproxEqAbs(
            strategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 2
        );
        assertApproxEqAbs(
            strategy.userWantDeposit(alice), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 2
        );

        vm.prank(alice);
        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(
            IERC20Upgradeable(token).balanceOf(bob) - balanceBefore,
            calculations.convertWantToTargetAsset(withdrawalEstimationResult.wantDepositAfterFee),
            2.6e13
        );
        assertApproxEqAbs(strategy.totalWantDeposits(), 0, 5);
        assertApproxEqAbs(strategy.userWantDeposit(alice), 0, 5);
    }

    function test_withdraw_Fail_InsufficientDepositTokenOutWAVAX() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        uint256 amountShares = vault.userShares(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));
        vault.withdraw(bob, token, amountShares, _getAdditionalData(amount * amount, slippage));
    }

    // COMBINED

    function test_withdraw_Success_WithdrawAllFromAVAXToWAVAX() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, AVAX, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), WAVAX);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(WAVAX).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, WAVAX, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(WAVAX).balanceOf(bob) - balanceBefore, expectedAmountOut, 2.6e13);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllFromWAVAXToAVAX() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, WAVAX, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), AVAX);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, AVAX, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2.6e13);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    // ================
    // ||   REWARD   ||
    // ================

    // AVAX

    function test_withdraw_Success_WithdrawAllAndRewardsInAVAXFlag() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares = vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(10), true);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 3.2e16);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsInETNoFlag() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 3.2e16);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawOnlyRewardsInAVAX() external {
        address token = AVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2.8e15);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 1.9e16);
        assertApproxEqAbs(strategy.userWantDeposit(alice), depositEstimationResult, 1.9e16);
    }

    // WAVAX

    function test_withdraw_Success_WithdrawAllAndRewardsInWAVAXFlag() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares = vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(10), true);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 3.2e16);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsInWETNoFlag() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 3.2e16);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawOnlyRewardsInWAVAX() external {
        address token = WAVAX;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        vm.prank(alice);

        vault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 2.8e15);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 1.9e16);
        assertApproxEqAbs(strategy.userWantDeposit(alice), depositEstimationResult, 1.9e16);
    }

    // COMBINED

    function test_withdraw_Success_WithdrawAllAndRewardsFromAVAXToWAVAX() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, AVAX, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), WAVAX);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(WAVAX).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        vm.prank(alice);

        vault.withdraw(bob, WAVAX, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(WAVAX).balanceOf(bob) - balanceBefore, expectedAmountOut, 3.2e16);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsFromWAVAXToAVAX() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculations.estimateDeposit(WAVAX, amount, slippage, hex"");

        _deposit(alice, WAVAX, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(WOM, address(strategy), 169e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 169e18);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(10), AVAX);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = calculations.convertWantToTargetAsset(wantToWithdraw);
        uint256 minAmountOut = calculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(WOM, address(strategy), 179e18, true);
        vm.prank(QI_WHALE);
        ERC20Upgradeable(QI).transfer(address(strategy), 179e18);

        vm.prank(alice);

        vault.withdraw(bob, AVAX, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 3.2e16);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(alice), 0);
    }

    // =================
    // ||   HELPERS   ||
    // =================

    function _deposit(address user, address token, uint256 amount, bytes memory additionalData) private {
        vm.startPrank(user);

        if (token != address(0)) {
            IERC20Upgradeable(token).safeApprove(address(vault), amount);
        }
        vault.deposit{ value: token == address(0) ? amount : 0 }(user, token, amount, additionalData);

        vm.stopPrank();
    }

    function _getAdditionalData(uint256 _minOut, uint16 _slippage) private pure returns (bytes memory) {
        return abi.encode(_minOut, _slippage);
    }

    function _getRewardData(uint256 _multiplier) private pure returns (bytes memory _rewardData) {
        address[] memory _rewardTokens = new address[](2);
        uint256[] memory _rewardAmounts = new uint256[](2);

        _rewardTokens[0] = WOM;
        _rewardTokens[1] = QI;
        _rewardAmounts[0] = 1e18 * _multiplier;
        _rewardAmounts[1] = 1e18 * _multiplier;

        return abi.encode(_rewardTokens, _rewardAmounts);
    }
}

contract WombatCalculationsMock is WombatCalculations {
    function convertWantToTargetAsset(uint256 _wantAmount) external view returns (uint256) {
        // 1e36 == 1e18 (exchange rate precision) + 1e18 (want token precision)
        return IWombatStrategy(strategy).pool().exchangeRate(WAVAX) * _wantAmount
            * 10 ** ERC20Upgradeable(WAVAX).decimals() / 1e36;
    }
}
