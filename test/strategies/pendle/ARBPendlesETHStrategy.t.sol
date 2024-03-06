// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { StrategyHelper, StrategyHelperVenueUniswapV3 } from "src/strategies/StrategyHelper.sol";
import { PendleLSDCalculations } from "src/calculations/pendle/PendleLSDCalculations.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { IPMarket } from "@pendle/core-v2/contracts/oracles/PendleLpOracleLib.sol";
import { PendlesETHStrategy } from "src/strategies/pendle/PendlesETHStrategy.sol";
import { IPPtOracle } from "@pendle/core-v2/contracts/interfaces/IPPtOracle.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { StrategyErrors } from "src/libraries/StrategyErrors.sol";
import { OracleUniswapV3 } from "src/oracles/OracleUniswapV3.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { FeeManager, IFeeManager } from "src/FeeManager.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import "../../../addresses/ARBMainnet.sol";
import "forge-std/Test.sol";

contract PendlesETHStrategyTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public constant PENDLE_MARKET = 0xACcd9A7cb5518326BeD715f90bD32CDf2fEc2D14;
    address public constant WANT = 0xACcd9A7cb5518326BeD715f90bD32CDf2fEc2D14;
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;
    address public constant SUPER_ADMIN = 0xB9E3d56C934E89418E294466764D5d19Ac36334B;
    address public constant PENDLE_PT_ORACLE = 0x7e16e4253CE4a1C96422a9567B23b4b5Ebc207F1;

    PendlesETHStrategy public pendleStrategy;
    CompoundVault public pendleVault;
    StrategyHelper public strategyHelper;
    FeeManager public feeManager;
    IAdminStructure public adminStructure;
    PendleLSDCalculations public pendleCalculations;

    IPendleStrategy.InitParams public initParams;

    address[] public depositAllowedTokens;
    address[] public withdrawalAllowedTokens;

    address public alice;
    uint256 public alicePrivateKey;
    address public bob;
    uint256 public bobPrivateKey;

    address public performanceFeeRecipient = makeAddr("PerformanceFeeRecipient");
    address public managementFeeRecipient = makeAddr("ManagementFeeRecipient");

    bytes public _additionalDataDeposit;
    bytes public _additionalDataWithdrawal;

    IERC20Upgradeable public arb = IERC20Upgradeable(ARB);
    IERC20Upgradeable public weth = IERC20Upgradeable(WETH);

    address[] public tokensToCompound = [ARB, PENDLE];
    uint256[] public minimumsToCompound = [5e17, 3e17];

    uint16 public slippage;
    uint32 public twapPeriod = 180 seconds;
    uint256 public depositCount;

    uint256 public constant ETH_DEPOSIT_LIMIT = 1e2;
    uint256 public constant WETH_DEPOSIT_LIMIT = 1e2;

    event ChargedFees(IFeeManager.FeeType feeType, uint256 feeAmount, address feeRecipient, address _token);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ARB_MAINNET"), 183_460_334);

        slippage = 80;
        adminStructure = IAdminStructure(ADMIN_STRUCTURE);
        (alice, alicePrivateKey) = makeAddrAndKey("Alice");
        (bob, bobPrivateKey) = makeAddrAndKey("Bob");

        depositAllowedTokens = [ETH, WETH];
        withdrawalAllowedTokens = [ETH, WETH];

        // STRATEGY HELPER
        Proxy strategyHelperProxy =
            new Proxy(address(new StrategyHelper()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE));
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        // FEE MANAGER
        Proxy feeManagerProxy =
            new Proxy(address(new FeeManager()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE));
        feeManager = FeeManager(address(feeManagerProxy));

        // SWAPS
        StrategyHelperVenueUniswapV3 strategyHelperVenueUniswapV3 = new StrategyHelperVenueUniswapV3(UNISWAP_V3_ROUTER);

        vm.startPrank(adminStructure.superAdmin());
        strategyHelper.setPath(
            PENDLE, WETH, address(strategyHelperVenueUniswapV3), abi.encodePacked(PENDLE, uint24(3000), WETH)
        );
        strategyHelper.setPath(
            ARB, WETH, address(strategyHelperVenueUniswapV3), abi.encodePacked(ARB, uint24(500), WETH)
        );
        vm.stopPrank();

        // ORACLES
        Proxy oracleUniswapPendleProxy = new Proxy(
            address(new OracleUniswapV3()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_V3_PENDLE_WETH_POOL,
                WETH,
                twapPeriod,
                6 hours
            )
        );
        OracleUniswapV3 oracleUniswapPendle = OracleUniswapV3(address(oracleUniswapPendleProxy));

        vm.startPrank(adminStructure.superAdmin());
        strategyHelper.setOracle(WETH, ETH_ORACLE); // WETH/USD = ETH/USD
        strategyHelper.setOracle(PENDLE, address(oracleUniswapPendle)); // PENDLE/USD
        strategyHelper.setOracle(ARB, ARB_ORACLE); // ARB/USD
        vm.stopPrank();

        (bool increaseCardinality, uint256 cardinalityRequired,) =
            IPPtOracle(PENDLE_PT_ORACLE).getOracleState(PENDLE_MARKET, twapPeriod);

        if (increaseCardinality) {
            IPMarket(PENDLE_MARKET).increaseObservationsCardinalityNext(uint16(cardinalityRequired));
        }

        // CALCULATIONS
        Proxy pendleLSDCalculationsProxy = new Proxy(
            address(new PendleLSDCalculations()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        pendleCalculations = PendleLSDCalculations(address(pendleLSDCalculationsProxy));

        // STRATEGY
        initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: WANT,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: PENDLE_MARKET,
            twapPeriod: twapPeriod,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });
        Proxy pendleStrategyProxy = new Proxy(
            address(new PendlesETHStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
        pendleStrategy = PendlesETHStrategy(payable(address(pendleStrategyProxy)));

        // VAULT
        IVault.DepositLimit[] memory _depositLimits = new IVault.DepositLimit[](2);

        _depositLimits[0] = IVault.DepositLimit(ETH, ETH_DEPOSIT_LIMIT);
        _depositLimits[1] = IVault.DepositLimit(WETH, WETH_DEPOSIT_LIMIT);

        Proxy pendleVaultProxy = new Proxy(
            address(new CompoundVault()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                ADMIN_STRUCTURE,
                address(pendleStrategy),
                WETH,
                address(pendleCalculations),
                depositAllowedTokens,
                withdrawalAllowedTokens,
                _depositLimits
            )
        );
        pendleVault = CompoundVault(address(pendleVaultProxy));

        // SET UP
        vm.startPrank(adminStructure.superAdmin());
        pendleStrategy.setSlippageTolerance(slippage);
        pendleStrategy.setVault(address(pendleVault));
        feeManager.setFee(
            address(pendleStrategy),
            IFeeManager.FeeType.MANAGEMENT,
            managementFeeRecipient,
            20 // 20%
        );
        feeManager.setFee(
            address(pendleStrategy),
            IFeeManager.FeeType.PERFORMANCE,
            performanceFeeRecipient,
            20 // 20%
        );
        pendleCalculations.setStrategyValues(address(pendleStrategy));
        vm.stopPrank();

        // DISTRIBUTION

        deal(WETH, alice, 1000e18);
        deal(WETH, bob, 1000e18);

        deal(alice, 1000e18);
        deal(bob, 1000e18);
    }

    // ==============
    // ||   INIT   ||
    // ==============

    function test_initialize_Success() public {
        Proxy pendleStrategyProxy = new Proxy(
            address(new PendlesETHStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
        PendlesETHStrategy pendleStrategyLocal = PendlesETHStrategy(payable(address(pendleStrategyProxy)));
        assertEq(address(pendleStrategyLocal.pendleRouter()), PENDLE_ROUTER);
        assertEq(address(pendleStrategyLocal.pendleMarket()), PENDLE_MARKET);
        assertEq(address(pendleStrategyLocal.targetAsset()), WETH);
        assertEq(address(pendleStrategyLocal.calculations()), address(pendleCalculations));
        assertEq(pendleStrategyLocal.twapPeriod(), twapPeriod);
    }

    function test_initialize_Fail_CalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        pendleStrategy.initialize(initParams);
    }

    // =================
    // ||   DEPOSIT   ||
    // =================

    // ETH

    function test_deposit_Success_DepositInETH() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        assertTrue(pendleStrategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(pendleStrategy.userWantDeposit(alice) > depositEstimationResult);
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), depositEstimationResult, 4e15);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), depositEstimationResult, 4e15);
    }

    function test_deposit_Success_DepositInETHMultipleTimesSameUser() external {
        address token = ETH;
        uint256[2] memory amounts = [uint256(2e18), uint256(5e18)];

        for (uint256 i; i < amounts.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amounts[i], slippage, hex"");

            _deposit(alice, token, amounts[i], _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(pendleStrategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 2e16);
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 2e16
            );
        }
    }

    function test_deposit_Success_DepositInETHMultipleTimesDifferentUsers() external {
        address token = ETH;
        uint256 amount = 1e18;
        address[2] memory users = [alice, bob];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

            _deposit(users[i], token, amount, _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(pendleStrategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 4e15);
            assertApproxEqAbs(pendleStrategy.userWantDeposit(users[i]), depositEstimationResult, 4e15);
        }
    }

    function test_deposit_Success_DepositWithCompoundInETHMultipleTimesSameUser() external {
        address token = ETH;
        uint256[2] memory amounts = [uint256(2e18), uint256(5e18)];

        for (uint256 i; i < amounts.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amounts[i], slippage, hex"");

            _deposit(alice, token, amounts[i], _getAdditionalData(depositEstimationResult, slippage));

            // Sending some reward token to trigger a compound
            deal(ARB, address(pendleStrategy), 169e18, true);
            deal(PENDLE, address(pendleStrategy), 169e18, true);

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(pendleStrategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 2e16);
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 2e16
            );
        }
    }

    function test_deposit_Success_DepositWithCompoundInETHMultipleTimesDifferentUser() external {
        address token = ETH;
        uint256 amount = 1e18;
        address[2] memory users = [alice, bob];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

            _deposit(users[i], token, amount, _getAdditionalData(depositEstimationResult, slippage));

            // Sending some reward token to trigger a compound
            deal(ARB, address(pendleStrategy), 169e18, true);
            deal(PENDLE, address(pendleStrategy), 169e18, true);

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(pendleStrategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 4e15);
            assertApproxEqAbs(pendleStrategy.userWantDeposit(users[i]), depositEstimationResult, 4e15);
        }
    }

    function test_deposit_Fail_InsufficientDepositTokenOutETH() external {
        address token = ETH;
        uint256 amount = 1e18;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));
        pendleVault.deposit{ value: amount }(alice, token, amount, _getAdditionalData(amount * amount, slippage));
        vm.stopPrank();
    }

    // WETH

    function test_deposit_Success_DepositInWETH() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        assertTrue(pendleStrategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(pendleStrategy.userWantDeposit(alice) > depositEstimationResult);
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), depositEstimationResult, 4e15);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), depositEstimationResult, 4e15);
    }

    function test_deposit_Success_DepositInWETHMultipleTimesSameUser() external {
        address token = WETH;
        uint256[2] memory amounts = [uint256(2e18), uint256(5e18)];

        for (uint256 i; i < amounts.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amounts[i], slippage, hex"");

            _deposit(alice, token, amounts[i], _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(pendleStrategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 2e16);
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 2e16
            );
        }
    }

    function test_deposit_Success_DepositInWETHMultipleTimesDifferentUsers() external {
        address token = WETH;
        uint256 amount = 1e18;
        address[2] memory users = [alice, bob];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

            _deposit(users[i], token, amount, _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(pendleStrategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 4e15);
            assertApproxEqAbs(pendleStrategy.userWantDeposit(users[i]), depositEstimationResult, 4e15);
        }
    }

    function test_deposit_Success_DepositWithCompoundInWETHMultipleTimesSameUser() external {
        address token = WETH;
        uint256[2] memory amounts = [uint256(2e18), uint256(5e18)];

        for (uint256 i; i < amounts.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amounts[i], slippage, hex"");

            _deposit(alice, token, amounts[i], _getAdditionalData(depositEstimationResult, slippage));

            // Sending some reward token to trigger a compound
            deal(ARB, address(pendleStrategy), 169e18, true);
            deal(PENDLE, address(pendleStrategy), 169e18, true);

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(pendleStrategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 2e16);
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 2e16
            );
        }
    }

    function test_deposit_Success_DepositWithCompoundInWETHMultipleTimesDifferentUser() external {
        address token = WETH;
        uint256 amount = 1e18;
        address[2] memory users = [alice, bob];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

            _deposit(users[i], token, amount, _getAdditionalData(depositEstimationResult, slippage));

            // Sending some reward token to trigger a compound
            deal(ARB, address(pendleStrategy), 169e18, true);
            deal(PENDLE, address(pendleStrategy), 169e18, true);

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(pendleStrategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 4e15);
            assertApproxEqAbs(pendleStrategy.userWantDeposit(users[i]), depositEstimationResult, 4e15);
        }
    }

    function test_deposit_Fail_InsufficientDepositTokenOutWETH() external {
        address token = WETH;
        uint256 amount = 1e18;

        vm.startPrank(alice);
        IERC20Upgradeable(WETH).safeApprove(address(pendleVault), amount);

        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));
        pendleVault.deposit{ value: 0 }(alice, token, amount, _getAdditionalData(amount * amount, slippage));
        vm.stopPrank();
    }

    // COMBINED

    function test_deposit_Success_DepositWithDifferentTokens() external {
        uint256 amount = 1e18;

        for (uint256 i; i < depositAllowedTokens.length; ++i) {
            uint256 prevTotalWantDeposits = pendleStrategy.totalWantDeposits();
            uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

            _deposit(alice, depositAllowedTokens[i], amount, _getAdditionalData(depositEstimationResult, slippage));

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(pendleStrategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 4e15);
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 4e15
            );
        }
    }

    // ==================
    // ||   WITHDRAW   ||
    // ==================

    function test_withdraw_ChargeBothFees() public {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        IFeeManager.FeeType managementFee = IFeeManager.FeeType.MANAGEMENT;
        IFeeManager.FeeType performanceFee = IFeeManager.FeeType.PERFORMANCE;

        vm.prank(alice);

        vm.expectEmit(true, false, true, false, address(pendleStrategy));
        emit ChargedFees(managementFee, 0, managementFeeRecipient, token);
        vm.expectEmit(true, false, true, false, address(pendleStrategy));
        emit ChargedFees(performanceFee, 0, performanceFeeRecipient, token);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));
    }

    // ETH

    function test_withdraw_Success_WithdrawAllInETHFlag() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(0), true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllInETHNoFlag() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_PartialWithdrawInETH() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 7.1e13);
        assertApproxEqAbs(
            pendleStrategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5.1e14
        );
        assertApproxEqAbs(
            pendleStrategy.userWantDeposit(alice),
            withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw,
            5.1e14
        );
    }

    function test_withdraw_Success_PartialWithdrawInETHMultipleTimes() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);
        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 7.1e13);
        assertApproxEqAbs(
            pendleStrategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5.1e14
        );
        assertApproxEqAbs(
            pendleStrategy.userWantDeposit(alice),
            withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw,
            5.1e14
        );

        vm.prank(alice);
        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(
            bob.balance - balanceBefore,
            pendleCalculations.convertWantToTarget(withdrawalEstimationResult.wantDepositAfterFee),
            1.5e14
        );
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), 0, 5);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), 0, 5);
    }

    function test_withdraw_Fail_InsufficientDepositTokenOutETH() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        uint256 amountShares = pendleVault.userShares(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));
        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(amount * amount, slippage));
    }

    // WETH

    function test_withdraw_Success_WithdrawAllInWETHFlag() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(0), true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllInWETHNoFlag() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_PartialWithdrawInWETH() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 7.1e13);
        assertApproxEqAbs(
            pendleStrategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5.1e14
        );
        assertApproxEqAbs(
            pendleStrategy.userWantDeposit(alice),
            withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw,
            5.1e14
        );
    }

    function test_withdraw_Success_PartialWithdrawInWETHMultipleTimes() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);
        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 7.1e13);
        assertApproxEqAbs(
            pendleStrategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5.1e14
        );
        assertApproxEqAbs(
            pendleStrategy.userWantDeposit(alice),
            withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw,
            5.1e14
        );

        vm.prank(alice);
        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(
            IERC20Upgradeable(token).balanceOf(bob) - balanceBefore,
            pendleCalculations.convertWantToTarget(withdrawalEstimationResult.wantDepositAfterFee),
            1.5e14
        );
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), 0, 5);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), 0, 5);
    }

    function test_withdraw_Fail_InsufficientDepositTokenOutWETH() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        uint256 amountShares = pendleVault.userShares(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));
        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(amount * amount, slippage));
    }

    // COMBINED

    function test_withdraw_Success_WithdrawAllFromETHToWETH() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, ETH, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), WETH);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(WETH).balanceOf(bob);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        pendleVault.withdraw(bob, WETH, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(WETH).balanceOf(bob) - balanceBefore, expectedAmountOut, 1.5e14);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllFromWETHToETH() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, WETH, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(0), ETH);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        pendleVault.withdraw(bob, ETH, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 1.5e14);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    // ================
    // ||   REWARD   ||
    // ================

    // ETH

    function test_withdraw_Success_WithdrawAllAndRewardsInETHFlag() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(10), true);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsInETNoFlag() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawOnlyRewardsInETH() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 3.1e14);
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), depositEstimationResult, 4e15);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), depositEstimationResult, 4e15);
    }

    // WETH

    function test_withdraw_Success_WithdrawAllAndRewardsInWETHFlag() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(10), true);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsInWETNoFlag() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawOnlyRewardsInWETH() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 3.1e14);
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), depositEstimationResult, 4e15);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), depositEstimationResult, 4e15);
    }

    // COMBINED

    function test_withdraw_Success_WithdrawAllAndRewardsFromETHToWETH() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, ETH, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), WETH);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(WETH).balanceOf(bob);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, WETH, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(WETH).balanceOf(bob) - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsFromWETHToETH() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, WETH, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(ARB, address(pendleStrategy), 169e18, true);
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), ETH);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(ARB, address(pendleStrategy), 179e18, true);
        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, ETH, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 1.5e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    // =================
    // ||   HELPERS   ||
    // =================

    function _deposit(address user, address token, uint256 amount, bytes memory additionalData) private {
        vm.startPrank(user);

        if (token != address(0)) {
            IERC20Upgradeable(token).safeApprove(address(pendleVault), amount);
        }
        pendleVault.deposit{ value: token == address(0) ? amount : 0 }(user, token, amount, additionalData);

        vm.stopPrank();
    }

    function _getAdditionalData(uint256 _minOut, uint16 _slippage) private pure returns (bytes memory) {
        return abi.encode(_minOut, _slippage);
    }

    function _getRewardData(uint256 _multiplier) private pure returns (bytes memory _rewardData) {
        address[] memory _rewardTokens = new address[](2);
        uint256[] memory _rewardAmounts = new uint256[](2);

        _rewardTokens[0] = ARB;
        _rewardTokens[1] = PENDLE;
        _rewardAmounts[0] = 1e18 * _multiplier;
        _rewardAmounts[1] = 1e18 * _multiplier;

        return abi.encode(_rewardTokens, _rewardAmounts);
    }
}
