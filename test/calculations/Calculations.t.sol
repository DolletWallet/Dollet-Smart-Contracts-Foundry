// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { CalculationsErrors } from "src/libraries/CalculationsErrors.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { CalculationsMock } from "src/mocks/CalculationsMock.sol";
import { ExternalProtocol } from "src/mocks/ExternalProtocol.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { FeeManager, IFeeManager } from "src/FeeManager.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { StrategyMock } from "src/mocks/StrategyMock.sol";
import { OracleMock } from "src/mocks/OracleMock.sol";
import { EmptyMock } from "src/mocks/EmptyMock.sol";
import "../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract CalculationsTest is Test {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    address public want;
    address public targetAsset;
    address public rewardAsset;

    address public tokenIn1;
    address public tokenIn2;
    address public tokenOut1;
    address public tokenOut2;

    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    IAdminStructure public adminStructure;
    StrategyHelper public strategyHelper;
    FeeManager public feeManager;
    StrategyMock public strategyMock;
    CalculationsMock public calculationsMock;
    CompoundVault public vault;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    uint16 public slippage;

    address[] public depositAllowedTokens;
    address[] public withdrawalAllowedTokens;
    address[] public tokensToCompound;
    uint256[] public minimumsToCompound;
    uint256 public minimumToCompound;

    IVault.DepositLimit[] public depositLimits;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_281_210);

        adminStructure = IAdminStructure(ADMIN_STRUCTURE);
        slippage = 100;

        // STRATEGY HELPER
        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()), abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        // EXTERNAL CONTRACTS
        ExternalProtocol wantContract = new ExternalProtocol(address(strategyHelper));
        want = address(wantContract);

        ExternalProtocol targetAssetContract = new ExternalProtocol(address(strategyHelper));
        targetAsset = address(targetAssetContract);

        ExternalProtocol rewardAssetContract = new ExternalProtocol(address(strategyHelper));
        rewardAsset = address(rewardAssetContract);

        ERC20Upgradeable tokenIn1Contract = new ERC20Upgradeable();
        tokenIn1 = address(tokenIn1Contract);
        ERC20Upgradeable tokenIn2Contract = new ERC20Upgradeable();
        tokenIn2 = address(tokenIn2Contract);
        ERC20Upgradeable tokenOut1Contract = new ERC20Upgradeable();
        tokenOut1 = address(tokenOut1Contract);
        ERC20Upgradeable tokenOut2Contract = new ERC20Upgradeable();
        tokenOut2 = address(tokenOut2Contract);

        depositAllowedTokens.push(ETH);
        depositAllowedTokens.push(tokenIn1);
        depositAllowedTokens.push(tokenIn2);

        withdrawalAllowedTokens.push(ETH);
        withdrawalAllowedTokens.push(tokenOut1);
        withdrawalAllowedTokens.push(tokenOut2);

        tokensToCompound.push(rewardAsset);
        minimumToCompound = 1e15;
        minimumsToCompound.push(minimumToCompound);

        depositLimits.push(IVault.DepositLimit({ token: ETH, minAmount: 5e15 }));
        depositLimits.push(IVault.DepositLimit({ token: tokenIn1, minAmount: 5e15 }));
        depositLimits.push(IVault.DepositLimit({ token: tokenIn2, minAmount: 5e15 }));

        // FEE MANAGER
        Proxy feeManagerProxy = new Proxy(
            address(new FeeManager()), abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        feeManager = FeeManager(address(feeManagerProxy));

        // ORCALES
        Proxy oracleTokenIn1Proxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), tokenIn1)
        );
        OracleMock oracleTokenIn1 = OracleMock(address(oracleTokenIn1Proxy));

        Proxy oracleTokenIn2Proxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), tokenIn2)
        );
        OracleMock oracleTokenIn2 = OracleMock(address(oracleTokenIn2Proxy));

        Proxy oracleTokenOut1Proxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), tokenOut1)
        );
        OracleMock oracleTokenOut1 = OracleMock(address(oracleTokenOut1Proxy));

        Proxy oracleTokenOut2Proxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), tokenOut2)
        );
        OracleMock oracleTokenOut2 = OracleMock(address(oracleTokenOut2Proxy));

        Proxy oracleWantProxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), want)
        );
        OracleMock oracleWant = OracleMock(address(oracleWantProxy));

        Proxy oracleTargetProxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), targetAsset)
        );
        OracleMock oracleTarget = OracleMock(address(oracleTargetProxy));

        Proxy oracleRewardProxy = new Proxy(
            address(new OracleMock()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), rewardAsset)
        );
        OracleMock oracleReward = OracleMock(address(oracleRewardProxy));

        vm.startPrank(adminStructure.superAdmin());
        strategyHelper.setOracle(WETH, ETH_ORACLE);
        strategyHelper.setOracle(USDC, USDC_ORACLE);
        strategyHelper.setOracle(tokenIn1, address(oracleTokenIn1));
        strategyHelper.setOracle(tokenIn2, address(oracleTokenIn2));
        strategyHelper.setOracle(tokenOut1, address(oracleTokenOut1));
        strategyHelper.setOracle(tokenOut2, address(oracleTokenOut2));
        strategyHelper.setOracle(want, address(oracleWant));
        strategyHelper.setOracle(targetAsset, address(oracleTarget));
        strategyHelper.setOracle(rewardAsset, address(oracleReward));
        vm.stopPrank();

        // CALCULATIONS
        Proxy calculationsProxy = new Proxy(
            address(new CalculationsMock()), abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        calculationsMock = CalculationsMock(address(calculationsProxy));

        // STRATEGY
        Proxy strategyProxy = new Proxy(
            address(new StrategyMock()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],uint256[],address)",
                address(adminStructure),
                address(strategyHelper),
                address(feeManager),
                WETH,
                want,
                address(calculationsMock),
                tokensToCompound,
                minimumsToCompound,
                targetAsset
            )
        );
        strategyMock = StrategyMock(payable(address(strategyProxy)));

        // VAULT
        Proxy vaultProxy = new Proxy(
            address(new CompoundVault()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address[],address[],(address,uint256)[])",
                address(adminStructure),
                address(strategyMock),
                WETH,
                address(calculationsMock),
                depositAllowedTokens,
                withdrawalAllowedTokens,
                depositLimits
            )
        );
        vault = CompoundVault(address(vaultProxy));

        // SET UP
        vm.startPrank(adminStructure.superAdmin());
        strategyMock.setSlippageTolerance(slippage);
        strategyMock.setVault(address(vault));
        feeManager.setFee(
            address(strategyMock),
            IFeeManager.FeeType.MANAGEMENT,
            address(1),
            1000 //10%
        );
        feeManager.setFee(
            address(strategyMock),
            IFeeManager.FeeType.PERFORMANCE,
            address(1),
            500 //10%
        );
        calculationsMock.setStrategyValues(address(strategyMock));
        vm.stopPrank();
    }

    // init

    function test_initialize_Fail_CalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        calculationsMock.initialize(address(adminStructure));
    }

    function test_initialize_Fail_AdminStructureIsNotContract() external {
        CalculationsMock _calculationsImpl = new CalculationsMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(address(_calculationsImpl), abi.encodeWithSignature("initialize(address)", address(0)));
    }

    function test_initialize_Success() public {
        Proxy calculationsMockProxy = new Proxy(
            address(new CalculationsMock()), abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        StrategyMock calculationsMockLocal = StrategyMock(payable(address(calculationsMockProxy)));

        assertEq(address(calculationsMockLocal.adminStructure()), address(adminStructure));
    }

    // setStrategyValues

    function test_setStrategyValues_Fail_NotSuperAdminUsingUser() public {
        address strategyBefore = address(calculationsMock.strategy());
        address newStrategy = address(new EmptyMock());

        vm.startPrank(alice);
        vm.expectRevert(bytes("NotSuperAdmin"));
        calculationsMock.setStrategyValues(address(newStrategy));
        vm.stopPrank();

        address strategyAfter = address(calculationsMock.strategy());
        assertEq(strategyBefore, strategyAfter);
    }

    function test_setStrategyValues_Fail_NotSuperAdminUsingAdmin() public {
        address strategyBefore = address(calculationsMock.strategy());
        address newStrategy = address(new EmptyMock());

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(bytes("NotSuperAdmin"));
        calculationsMock.setStrategyValues(address(newStrategy));
        vm.stopPrank();

        address strategyAfter = address(calculationsMock.strategy());
        assertEq(strategyBefore, strategyAfter);
    }

    function test_setStrategyValues_Fail_NotAContract() public {
        address strategyBefore = address(calculationsMock.strategy());
        address newStrategy = address(99_999);

        vm.startPrank(adminStructure.superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(99_999)));
        calculationsMock.setStrategyValues(address(newStrategy));
        vm.stopPrank();

        address strategyAfter = address(calculationsMock.strategy());
        assertEq(strategyBefore, strategyAfter);
    }

    function test_setStrategyValues_Success() public {
        address strategyBefore = address(calculationsMock.strategy());
        address newStrategy = address(new StrategyMock());

        vm.startPrank(adminStructure.superAdmin());
        calculationsMock.setStrategyValues(address(newStrategy));
        vm.stopPrank();

        address strategyAfter = address(calculationsMock.strategy());
        assertFalse(strategyBefore == strategyAfter);
        assertTrue(strategyAfter == newStrategy);
    }

    // userDeposit

    function test_userDeposit_NoDepositERC20() public {
        assertEq(calculationsMock.userDeposit(alice, tokenIn1), 0);
        assertEq(calculationsMock.userDeposit(alice, tokenIn2), 0);
        assertEq(calculationsMock.userDeposit(alice, tokenOut1), 0);
        assertEq(calculationsMock.userDeposit(alice, tokenOut2), 0);
    }

    function test_userDeposit_NoDepositNT() public {
        assertEq(calculationsMock.userDeposit(alice, WETH), 0);
    }

    function test_userDeposit_DepositERC20() public {
        uint256 _wantAmount = 1e18;
        strategyMock.editUserWantDeposit(alice, _wantAmount);

        uint256 _targetAmount = calculationsMock.convertWantToTarget(_wantAmount);

        assertEq(
            calculationsMock.userDeposit(alice, tokenIn1), strategyHelper.convert(targetAsset, tokenIn1, _targetAmount)
        );
        assertEq(
            calculationsMock.userDeposit(alice, tokenIn2), strategyHelper.convert(targetAsset, tokenIn2, _targetAmount)
        );
        assertEq(
            calculationsMock.userDeposit(alice, tokenOut1),
            strategyHelper.convert(targetAsset, tokenOut1, _targetAmount)
        );
        assertEq(
            calculationsMock.userDeposit(alice, tokenOut2),
            strategyHelper.convert(targetAsset, tokenOut2, _targetAmount)
        );
    }

    function test_userDeposit_DepositNT() public {
        uint256 _wantAmount = 1e18;
        strategyMock.editUserWantDeposit(alice, _wantAmount);

        uint256 _targetAmount = calculationsMock.convertWantToTarget(_wantAmount);

        assertEq(calculationsMock.userDeposit(alice, WETH), strategyHelper.convert(targetAsset, WETH, _targetAmount));
    }

    // totalDeposits

    function test_totalDeposits_NoDepositERC20() public {
        assertEq(calculationsMock.totalDeposits(tokenIn1), 0);
        assertEq(calculationsMock.totalDeposits(tokenIn2), 0);
        assertEq(calculationsMock.totalDeposits(tokenOut1), 0);
        assertEq(calculationsMock.totalDeposits(tokenOut2), 0);
    }

    function test_totalDeposits_NoDepositNT() public {
        assertEq(calculationsMock.totalDeposits(WETH), 0);
    }

    function test_totalDeposits_DepositERC20() public {
        uint256 _wantAmount = 1e18;
        strategyMock.editTotalWantDeposit(_wantAmount);

        uint256 _targetAmount = calculationsMock.convertWantToTarget(_wantAmount);

        assertEq(calculationsMock.totalDeposits(tokenIn1), strategyHelper.convert(targetAsset, tokenIn1, _targetAmount));
        assertEq(calculationsMock.totalDeposits(tokenIn2), strategyHelper.convert(targetAsset, tokenIn2, _targetAmount));
        assertEq(
            calculationsMock.totalDeposits(tokenOut1), strategyHelper.convert(targetAsset, tokenOut1, _targetAmount)
        );
        assertEq(
            calculationsMock.totalDeposits(tokenOut2), strategyHelper.convert(targetAsset, tokenOut2, _targetAmount)
        );
    }

    function test_totalDeposits_DepositNT() public {
        uint256 _wantAmount = 1e18;
        strategyMock.editTotalWantDeposit(_wantAmount);

        uint256 _targetAmount = calculationsMock.convertWantToTarget(_wantAmount);

        assertEq(calculationsMock.totalDeposits(WETH), strategyHelper.convert(targetAsset, WETH, _targetAmount));
    }

    // estimateWantAfterCompound

    function test_estimateWantAfterCompound_CorrectEstimationNotEnoughReward() external {
        uint256 amountToCompound = 1e14;
        uint256 rewardEstimationResult =
            calculationsMock.estimateWantAfterCompound(slippage, _getRewardData(amountToCompound));

        assertEq(rewardEstimationResult, 0);
    }

    function test_estimateWantAfterCompound_CorrectEstimationEnoughReward() external {
        address token = rewardAsset;
        uint256 amountToCompound = 1e15;
        uint256 rewardEstimationResult =
            calculationsMock.estimateWantAfterCompound(slippage, _getRewardData(amountToCompound));

        assertEq(
            rewardEstimationResult,
            calculationsMock.getMinimumOutputAmount(
                amountToCompound * strategyHelper.price(token) / 10 ** ERC20Upgradeable(token).decimals(), slippage
            )
        );
    }

    // estimateDeposit

    function test_estimateDeposit_CorrectEstimationERC20() external {
        address token = tokenIn1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(token, amount, slippage, hex"");

        assertEq(
            depositEstimationResult,
            calculationsMock.getMinimumOutputAmount(
                amount * strategyHelper.price(token) / 10 ** ERC20Upgradeable(token).decimals(), slippage
            )
        );
    }

    function test_estimateDeposit_CorrectEstimationNT() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        assertEq(
            depositEstimationResult,
            calculationsMock.getMinimumOutputAmount(amount * strategyHelper.price(WETH) / 1e18, slippage)
        );
    }

    // estimateWantToToken

    function test_estimateWantToToken_CorrectEstimationERC20() external {
        address token = tokenIn1;
        uint256 amount = 1e18;
        uint256 withdrawalEstimationResult = calculationsMock.estimateWantToToken(token, amount, slippage);

        assertEq(
            withdrawalEstimationResult,
            calculationsMock.getMinimumOutputAmount(
                amount * 10 ** ERC20Upgradeable(token).decimals() / strategyHelper.price(token), slippage
            )
        );
    }

    function test_estimateWantToToken_CorrectEstimationNT() external {
        uint256 amount = 1e18;
        uint256 withdrawalEstimationResult = calculationsMock.estimateWantToToken(WETH, amount, slippage);

        assertEq(
            withdrawalEstimationResult,
            calculationsMock.getMinimumOutputAmount(amount * 1e18 / strategyHelper.price(WETH), slippage)
        );
    }

    // getWithdrawableAmount

    // Should test the case of a Withdrawal 100% Rewards, 0% Deposit
    function test_calculations_getWithdrawableAmount_NoDepositNoRrewards() public {
        uint256 _userDeposit = 0;
        uint256 _rewards = 0;
        strategyMock.editUserWantDeposit(alice, _userDeposit);

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            calculationsMock.getWithdrawableAmount(alice, _rewards, _userDeposit + _rewards, USDC, slippage);

        assertEq(_withdrawalEstimation.wantDeposit, 0);
        assertEq(_withdrawalEstimation.wantDepositAfterFee, 0);
        assertEq(_withdrawalEstimation.wantRewards, _rewards);
        assertEq(_withdrawalEstimation.wantRewardsAfterFee, 0);
    }

    // Should test the case of a Withdrawal 100% Rewards, 0% Deposit
    function test_calculations_getWithdrawableAmount_FullRewards() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            calculationsMock.getWithdrawableAmount(alice, _rewards, _userDeposit + _rewards, USDC, slippage);

        assertEq(_withdrawalEstimation.wantDeposit, 0);
        assertEq(_withdrawalEstimation.wantDepositAfterFee, 0);
        assertEq(_withdrawalEstimation.wantRewards, _rewards);
        assertEq(_withdrawalEstimation.wantRewardsAfterFee, calculationsMock.getMinimumOutputAmount(_rewards, 500));
    }

    // Should test the case of a Withdrawal 50% Rewards, 0% Deposit
    function test_calculations_getWithdrawableAmount_HalfRewards() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            calculationsMock.getWithdrawableAmount(alice, _rewards / 2, _userDeposit + _rewards, USDC, slippage);

        assertEq(_withdrawalEstimation.wantDeposit, 0); // 0 %
        assertEq(_withdrawalEstimation.wantRewards, _rewards / 2); // 50%
        assertEq(_withdrawalEstimation.wantDepositAfterFee, 0);
        assertEq(_withdrawalEstimation.wantRewardsAfterFee, calculationsMock.getMinimumOutputAmount(_rewards / 2, 500));
    }

    // Should test the case of a Withdrawal 100% Rewards, 100% Deposit
    function test_calculations_getWithdrawableAmount_FullRewardsAndDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation = calculationsMock.getWithdrawableAmount(
            alice, _userDeposit + _rewards, _userDeposit + _rewards, USDC, slippage
        );

        assertEq(_withdrawalEstimation.wantDeposit, _userDeposit); // 100%
        assertEq(_withdrawalEstimation.wantRewards, _rewards); // 100%
        assertEq(_withdrawalEstimation.wantDepositAfterFee, calculationsMock.getMinimumOutputAmount(_userDeposit, 1000));
        assertEq(_withdrawalEstimation.wantRewardsAfterFee, calculationsMock.getMinimumOutputAmount(_rewards, 500));
    }

    // Should test the case of a Withdrawal 100% Rewards, 50% Deposit
    function test_calculations_getWithdrawableAmount_FullRewardsAndHalfDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation = calculationsMock.getWithdrawableAmount(
            alice, (_userDeposit / 2) + _rewards, _userDeposit + _rewards, USDC, slippage
        );
        assertEq(_withdrawalEstimation.wantDeposit, _userDeposit / 2); // 50%
        assertEq(_withdrawalEstimation.wantRewards, _rewards); // 100%
        assertEq(
            _withdrawalEstimation.wantDepositAfterFee, calculationsMock.getMinimumOutputAmount(_userDeposit / 2, 1000)
        );
        assertEq(_withdrawalEstimation.wantRewardsAfterFee, calculationsMock.getMinimumOutputAmount(_rewards, 500));
    }

    // Should test the case of a Withdrawal 0% Rewards, 100% Deposit
    function test_calculations_getWithdrawableAmount_FullDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 0;
        strategyMock.editUserWantDeposit(alice, _userDeposit);

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation = calculationsMock.getWithdrawableAmount(
            alice, _userDeposit + _rewards, _userDeposit + _rewards, USDC, slippage
        );

        assertEq(_withdrawalEstimation.wantDeposit, _userDeposit, "1"); // 100%
        assertEq(_withdrawalEstimation.wantRewards, _rewards, "2"); // 0%
        assertEq(
            _withdrawalEstimation.wantDepositAfterFee, calculationsMock.getMinimumOutputAmount(_userDeposit, 1000), "3"
        );
        assertEq(_withdrawalEstimation.wantRewardsAfterFee, 0, "4");
    }

    // Should test the case of a Withdrawal 0% Rewards, 50% Deposit
    function test_calculations_getWithdrawableAmount_HalfDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 0;
        strategyMock.editUserWantDeposit(alice, _userDeposit);

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            calculationsMock.getWithdrawableAmount(alice, _userDeposit / 2, _userDeposit + _rewards, USDC, slippage);

        assertEq(_withdrawalEstimation.wantDeposit, _userDeposit / 2); // 100%
        assertEq(_withdrawalEstimation.wantRewards, _rewards); // 0%
        assertEq(
            _withdrawalEstimation.wantDepositAfterFee, calculationsMock.getMinimumOutputAmount(_userDeposit / 2, 1000)
        );
        assertEq(_withdrawalEstimation.wantRewardsAfterFee, 0);
    }

    // Should test the case of a Withdrawal 0% Rewards, 0% Deposit
    function test_calculations_getWithdrawableAmount_ZeroAmounts() public {
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            calculationsMock.getWithdrawableAmount(alice, 0, 0, USDC, slippage);

        assertEq(_withdrawalEstimation.wantDeposit, 0);
        assertEq(_withdrawalEstimation.wantRewards, 0);
        assertEq(_withdrawalEstimation.wantDepositAfterFee, 0);
        assertEq(_withdrawalEstimation.wantRewardsAfterFee, 0);
    }

    // calculateUsedAmounts

    // Should test the case of a Withdrawal 100% Rewards, 0% Deposit
    function test_calculations_calculateUsedAmounts_FullRewards() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        uint256 _withdrawalTokenOut = 100e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _depositUsed, uint256 _rewardsUsed, uint256 _wantDeposit, uint256 _wantRewards) =
            calculationsMock.calculateUsedAmounts(alice, _rewards, _userDeposit + _rewards, _withdrawalTokenOut);
        assertEq(_depositUsed, 0); // 0 %
        assertEq(_rewardsUsed, _withdrawalTokenOut); // 100%
        assertEq(_wantDeposit, 0); // 0 %
        assertEq(_wantRewards, _rewards); // 100%
    }

    // Should test the case of a Withdrawal 50% Rewards, 0% Deposit
    function test_calculations_calculateUsedAmounts_HalfRewards() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        uint256 _withdrawalTokenOut = 100e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _depositUsed, uint256 _rewardsUsed, uint256 _wantDeposit, uint256 _wantRewards) =
            calculationsMock.calculateUsedAmounts(alice, _rewards / 2, _userDeposit + _rewards, _withdrawalTokenOut);
        assertEq(_depositUsed, 0); // 0 %
        assertEq(_rewardsUsed, _withdrawalTokenOut); // 50%
        assertEq(_wantDeposit, 0); // 0 %
        assertEq(_wantRewards, _rewards / 2); // 100%
    }

    // Should test the case of a Withdrawal 100% Rewards, 100% Deposit
    function test_calculations_calculateUsedAmounts_FullRewardsAndDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        uint256 _withdrawalTokenOut = 100e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _depositUsed, uint256 _rewardsUsed, uint256 _wantDeposit, uint256 _wantRewards) = calculationsMock
            .calculateUsedAmounts(alice, _userDeposit + _rewards, _userDeposit + _rewards, _withdrawalTokenOut);
        uint256 _expectedDepositToken =
            (((_userDeposit * 1e18) / (_userDeposit + _rewards)) * _withdrawalTokenOut) / 1e18;
        uint256 _expectedRewardsToken = _withdrawalTokenOut - _expectedDepositToken;
        assertEq(_rewardsUsed + _depositUsed, _withdrawalTokenOut);
        assertEq(_rewardsUsed, _expectedRewardsToken);
        assertEq(_depositUsed, _expectedDepositToken);
        assertEq(_wantDeposit, _userDeposit);
        assertEq(_wantRewards, _rewards);
    }

    // Should test the case of a Withdrawal 100% Rewards, 50% Deposit
    function test_calculations_calculateUsedAmounts_FullRewardsAndHalfDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        uint256 _withdrawalTokenOut = 100e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _depositUsed, uint256 _rewardsUsed, uint256 _wantDeposit, uint256 _wantRewards) = calculationsMock
            .calculateUsedAmounts(alice, (_userDeposit / 2) + _rewards, _userDeposit + _rewards, _withdrawalTokenOut);
        uint256 _expectedDepositToken =
            ((((_userDeposit / 2) * 1e18) / (_userDeposit / 2 + _rewards)) * _withdrawalTokenOut) / 1e18;
        uint256 _expectedRewardsToken = _withdrawalTokenOut - _expectedDepositToken;
        assertEq(_rewardsUsed + _depositUsed, _withdrawalTokenOut);
        assertEq(_rewardsUsed, _expectedRewardsToken);
        assertEq(_depositUsed, _expectedDepositToken);
        assertEq(_wantDeposit, _userDeposit / 2); // 50%
        assertEq(_wantRewards, _rewards); // 100%
    }

    // Should test the case of a Withdrawal 0% Rewards, 100% Deposit
    function test_calculations_calculateUsedAmounts_FullDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 0;
        uint256 _withdrawalTokenOut = 100e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _depositUsed, uint256 _rewardsUsed, uint256 _wantDeposit, uint256 _wantRewards) = calculationsMock
            .calculateUsedAmounts(alice, _userDeposit + _rewards, _userDeposit + _rewards, _withdrawalTokenOut);
        assertEq(_rewardsUsed + _depositUsed, _withdrawalTokenOut);
        assertEq(_rewardsUsed, 0);
        assertEq(_depositUsed, _withdrawalTokenOut);
        assertEq(_wantDeposit, _userDeposit);
        assertEq(_wantRewards, _rewards);
    }

    // Should test the case of a Withdrawal 0% Rewards, 50% Deposit
    function test_calculations_calculateUsedAmounts_HalfDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 0;
        uint256 _withdrawalTokenOut = 100e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _depositUsed, uint256 _rewardsUsed, uint256 _wantDeposit, uint256 _wantRewards) =
            calculationsMock.calculateUsedAmounts(alice, _userDeposit / 2, _userDeposit + _rewards, _withdrawalTokenOut);
        assertEq(_rewardsUsed + _depositUsed, _withdrawalTokenOut);
        assertEq(_rewardsUsed, 0);
        assertEq(_depositUsed, _withdrawalTokenOut);
        assertEq(_wantDeposit, _userDeposit / 2); // 100%
        assertEq(_wantRewards, _rewards); // 0%
    }

    // calculateWithdrawalDistribution

    function test_calculations_calculateWithdrawalDistribution_Fail_TooHigh() public {
        vm.expectRevert(CalculationsErrors.WantToWithdrawIsTooHigh.selector);
        calculationsMock.calculateWithdrawalDistribution(alice, 1001, 1000);
    }

    // Should test the case of a Withdrawal 100% Rewards, 0% Deposit
    function test_calculations_calculateWithdrawalDistribution_FullRewards() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _wantDeposit, uint256 _wantRewards) =
            calculationsMock.calculateWithdrawalDistribution(alice, _rewards, _userDeposit + _rewards);
        assertEq(_wantDeposit, 0); // 0 %
        assertEq(_wantRewards, _rewards); // 100%
    }

    // Should test the case of a Withdrawal 50% Rewards, 0% Deposit
    function test_calculations_calculateWithdrawalDistribution_HalfRewards() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _wantDeposit, uint256 _wantRewards) =
            calculationsMock.calculateWithdrawalDistribution(alice, _rewards / 2, _userDeposit + _rewards);
        assertEq(_wantDeposit, 0); // 0 %
        assertEq(_wantRewards, _rewards / 2); // 50%
    }

    // Should test the case of a Withdrawal 100% Rewards, 100% Deposit
    function test_calculations_calculateWithdrawalDistribution_FullRewardsAndDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _wantDeposit, uint256 _wantRewards) =
            calculationsMock.calculateWithdrawalDistribution(alice, _userDeposit + _rewards, _userDeposit + _rewards);
        assertEq(_wantDeposit, _userDeposit); // 100%
        assertEq(_wantRewards, _rewards); // 100%
    }

    // Should test the case of a Withdrawal 100% Rewards, 50% Deposit
    function test_calculations_calculateWithdrawalDistribution_FullRewardsAndHalfDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 1e18;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _wantDeposit, uint256 _wantRewards) = calculationsMock.calculateWithdrawalDistribution(
            alice, (_userDeposit / 2) + _rewards, _userDeposit + _rewards
        );
        assertEq(_wantDeposit, _userDeposit / 2); // 50%
        assertEq(_wantRewards, _rewards); // 100%
    }

    // Should test the case of a Withdrawal 0% Rewards, 100% Deposit
    function test_calculations_calculateWithdrawalDistribution_FullDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 0;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _wantDeposit, uint256 _wantRewards) =
            calculationsMock.calculateWithdrawalDistribution(alice, _userDeposit + _rewards, _userDeposit + _rewards);
        assertEq(_wantDeposit, _userDeposit); // 100%
        assertEq(_wantRewards, _rewards); // 0%
    }

    // Should test the case of a Withdrawal 0% Rewards, 50% Deposit
    function test_calculations_calculateWithdrawalDistribution_HalfDeposit() public {
        uint256 _userDeposit = 10e18;
        uint256 _rewards = 0;
        strategyMock.editUserWantDeposit(alice, _userDeposit);
        (uint256 _wantDeposit, uint256 _wantRewards) =
            calculationsMock.calculateWithdrawalDistribution(alice, _userDeposit / 2, _userDeposit + _rewards);
        assertEq(_wantDeposit, _userDeposit / 2); // 100%
        assertEq(_wantRewards, _rewards); // 0%
    }

    // getMinimumOutputAmount

    function test_util_GetsTheMinimumOutputAmount() public {
        uint256 amount = 1e18;

        uint256 obtained = calculationsMock.getMinimumOutputAmount(amount, slippage);
        assertEq(obtained, amount - ((amount * slippage) / strategyMock.ONE_HUNDRED_PERCENTS()));
    }

    // HELPERS

    function _getRewardData(uint256 _rewardAmount) private view returns (bytes memory _rewardData) {
        address[] memory _rewardTokens = new address[](1);
        uint256[] memory _rewardAmounts = new uint256[](1);

        _rewardTokens[0] = rewardAsset;
        _rewardAmounts[0] = _rewardAmount;

        return abi.encode(_rewardTokens, _rewardAmounts);
    }
}
