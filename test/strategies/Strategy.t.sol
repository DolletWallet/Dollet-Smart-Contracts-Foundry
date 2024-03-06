// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { StrategyErrors } from "src/libraries/StrategyErrors.sol";
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

contract StrategyTest is Test {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    uint16 public constant ONE_HUNDRED_PERCENTS = 10_000; // 100.00%

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
    uint16 public managementFee = 1000;
    uint16 public performanceFee = 1000;

    address[] public depositAllowedTokens;
    address[] public withdrawalAllowedTokens;
    address[] public tokensToCompound;
    uint256[] public minimumsToCompound;
    uint256 public minimumToCompound;

    IVault.DepositLimit[] public depositLimits;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 19_272_040);

        adminStructure = IAdminStructure(ADMIN_STRUCTURE);
        slippage = 0;

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
        feeManager.setFee(address(strategyMock), IFeeManager.FeeType.MANAGEMENT, address(1), managementFee);
        feeManager.setFee(address(strategyMock), IFeeManager.FeeType.PERFORMANCE, address(1), performanceFee);
        calculationsMock.setStrategyValues(address(strategyMock));
        vm.stopPrank();

        // DISTRIBUTION
        deal(alice, 1000e18);
        deal(bob, 1000e18);

        deal(tokenIn1, alice, 1000e18);
        deal(tokenIn1, bob, 1000e18);

        deal(tokenIn2, alice, 1000e18);
        deal(tokenIn2, bob, 1000e18);
    }

    // setAdminStructure

    function test_setAdminStructure_Fail_NotSuperAdminUsingUser() public {
        address adminStructureBefore = address(strategyMock.adminStructure());
        address newAdminStructure = address(new EmptyMock());

        vm.startPrank(alice);
        vm.expectRevert(bytes("NotSuperAdmin"));
        strategyMock.setAdminStructure(newAdminStructure);
        vm.stopPrank();

        address adminStructureAfter = address(strategyMock.adminStructure());
        assertEq(adminStructureBefore, adminStructureAfter);
    }

    function test_setAdminStructure_Fail_NotSuperAdminUsingAdmin() public {
        address adminStructureBefore = address(strategyMock.adminStructure());
        address newAdminStructure = address(new EmptyMock());

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(bytes("NotSuperAdmin"));
        strategyMock.setAdminStructure(newAdminStructure);
        vm.stopPrank();

        address adminStructureAfter = address(strategyMock.adminStructure());
        assertEq(adminStructureBefore, adminStructureAfter);
    }

    function test_setAdminStructure_Fail_NotAContract() public {
        address adminStructureBefore = address(strategyMock.adminStructure());
        address newAdminStructure = address(99_999);

        vm.startPrank(adminStructure.superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(99_999)));
        strategyMock.setAdminStructure(newAdminStructure);
        vm.stopPrank();

        address adminStructureAfter = address(strategyMock.adminStructure());
        assertEq(adminStructureBefore, adminStructureAfter);
    }

    function test_setAdminStructure_Success() public {
        address adminStructureBefore = address(strategyMock.adminStructure());
        address newAdminStructure = address(new EmptyMock());

        vm.startPrank(adminStructure.superAdmin());
        strategyMock.setAdminStructure(newAdminStructure);
        vm.stopPrank();

        address adminStructureAfter = address(strategyMock.adminStructure());
        assertFalse(adminStructureBefore == adminStructureAfter);
        assertTrue(adminStructureAfter == newAdminStructure);
    }

    // setVault

    function test_setVault_Fail_NotSuperAdminUsingUser() public {
        address vaultBefore = address(strategyMock.vault());
        address newVault = address(new EmptyMock());

        vm.startPrank(alice);
        vm.expectRevert(bytes("NotSuperAdmin"));
        strategyMock.setVault(newVault);
        vm.stopPrank();

        address vaultAfter = address(strategyMock.vault());
        assertEq(vaultBefore, vaultAfter);
    }

    function test_setVault_Fail_NotSuperAdminUsingAdmin() public {
        address vaultBefore = address(strategyMock.vault());
        address newVault = address(new EmptyMock());

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(bytes("NotSuperAdmin"));
        strategyMock.setVault(newVault);
        vm.stopPrank();

        address vaultAfter = address(strategyMock.vault());
        assertEq(vaultBefore, vaultAfter);
    }

    function test_setVault_Fail_NotAContract() public {
        address vaultBefore = address(strategyMock.vault());
        address newVault = address(99_999);

        vm.startPrank(adminStructure.superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(99_999)));
        strategyMock.setVault(newVault);
        vm.stopPrank();

        address vaultAfter = address(strategyMock.vault());
        assertEq(vaultBefore, vaultAfter);
    }

    function test_setVault_Success() public {
        address vaultBefore = address(strategyMock.vault());
        address newVault = address(new EmptyMock());

        vm.startPrank(adminStructure.superAdmin());
        strategyMock.setVault(newVault);
        vm.stopPrank();

        address vaultAfter = address(strategyMock.vault());
        assertFalse(vaultBefore == vaultAfter);
        assertTrue(vaultAfter == newVault);
    }

    // setSlippageTolerance

    function test_setSlippageTolerance_Fail_NotSuperAdminUsingUser() public {
        uint16 slippageToleranceBefore = strategyMock.slippageTolerance();
        uint16 newSlippageTolerance = 30;

        vm.startPrank(alice);
        vm.expectRevert(bytes("NotSuperAdmin"));
        strategyMock.setSlippageTolerance(newSlippageTolerance);
        vm.stopPrank();

        uint16 slippageToleranceAfter = strategyMock.slippageTolerance();
        assertEq(slippageToleranceBefore, slippageToleranceAfter);
    }

    function test_setSlippageTolerance_Fail_NotSuperAdminUsingAdmin() public {
        uint16 slippageToleranceBefore = strategyMock.slippageTolerance();
        uint16 newSlippageTolerance = 30;

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(bytes("NotSuperAdmin"));
        strategyMock.setSlippageTolerance(newSlippageTolerance);
        vm.stopPrank();

        uint16 slippageToleranceAfter = strategyMock.slippageTolerance();
        assertEq(slippageToleranceBefore, slippageToleranceAfter);
    }

    function test_setSlippageTolerance_Fail_SlippageTooHigh() public {
        uint16 slippageToleranceBefore = strategyMock.slippageTolerance();
        uint16 newSlippageTolerance = 3500;

        vm.startPrank(adminStructure.superAdmin());
        vm.expectRevert(StrategyErrors.SlippageToleranceTooHigh.selector);
        strategyMock.setSlippageTolerance(newSlippageTolerance);
        vm.stopPrank();

        uint16 slippageToleranceAfter = strategyMock.slippageTolerance();
        assertEq(slippageToleranceBefore, slippageToleranceAfter);
    }

    function test_setSlippageTolerance_Success() public {
        uint16 slippageToleranceBefore = strategyMock.slippageTolerance();
        uint16 newSlippageTolerance = 30;

        vm.startPrank(adminStructure.superAdmin());
        strategyMock.setSlippageTolerance(newSlippageTolerance);
        vm.stopPrank();

        uint16 slippageToleranceAfter = strategyMock.slippageTolerance();
        assertFalse(slippageToleranceBefore == slippageToleranceAfter);
        assertTrue(slippageToleranceAfter == newSlippageTolerance);
    }

    // inCaseTokensGetStuck

    function test_inCaseTokensGetStuck_Fail_NotAdminUsingUser() public {
        address superAdmin = adminStructure.superAdmin();

        uint256 balanceBefore = ERC20Upgradeable(want).balanceOf(superAdmin);
        assertEq(balanceBefore, 0);

        vm.startPrank(alice);
        vm.expectRevert(bytes("NotUserAdmin"));
        strategyMock.inCaseTokensGetStuck(tokenIn1);
        vm.stopPrank();

        uint256 balanceAfter = ERC20Upgradeable(want).balanceOf(superAdmin);
        assertEq(balanceAfter, 0);
    }

    function test_inCaseTokensGetStuck_Fail_WrongStuckToken() public {
        address superAdmin = adminStructure.superAdmin();

        uint256 balanceBefore = ERC20Upgradeable(want).balanceOf(superAdmin);
        assertEq(balanceBefore, 0);

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(StrategyErrors.WrongStuckToken.selector);
        strategyMock.inCaseTokensGetStuck(want);
        vm.stopPrank();

        uint256 balanceAfter = ERC20Upgradeable(want).balanceOf(superAdmin);
        assertEq(balanceAfter, 0);
    }

    function test_inCaseTokensGetStuck_Success_WithdrawERC20() public {
        address superAdmin = adminStructure.superAdmin();

        uint256 stuckedAmount = 1e18;
        deal(tokenIn1, address(strategyMock), stuckedAmount, true);

        uint256 balanceBefore = ERC20Upgradeable(tokenIn1).balanceOf(superAdmin);
        assertEq(balanceBefore, 0);

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        strategyMock.inCaseTokensGetStuck(tokenIn1);
        vm.stopPrank();

        uint256 balanceAfter = ERC20Upgradeable(tokenIn1).balanceOf(superAdmin);
        assertEq(balanceAfter, stuckedAmount);
    }

    function test_inCaseTokensGetStuck_Success_WithdrawNT() public {
        address superAdmin = adminStructure.superAdmin();

        uint256 stuckedAmount = 1e18;
        deal(address(strategyMock), stuckedAmount);

        uint256 balanceBefore = superAdmin.balance;
        assertEq(balanceBefore, 0);

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        strategyMock.inCaseTokensGetStuck(ETH);
        vm.stopPrank();

        uint256 balanceAfter = superAdmin.balance;
        assertEq(balanceAfter, stuckedAmount);
    }

    // editMinimumTokenCompound

    function test_editMinimumTokenCompound_Fail_NotAdminUsingUser() public {
        address[] memory _tokensToCompound = new address[](2);
        uint256[] memory _minimumsToCompound = new uint256[](2);
        _tokensToCompound[0] = WBTC;
        _tokensToCompound[1] = USDC;
        _minimumsToCompound[0] = 0.5e18;
        _minimumsToCompound[1] = 10e18;

        vm.startPrank(alice);
        vm.expectRevert(bytes("NotUserAdmin"));
        strategyMock.editMinimumTokenCompound(_tokensToCompound, _minimumsToCompound);
        vm.stopPrank();

        assertTrue(strategyMock.minimumToCompound(rewardAsset) == minimumToCompound);
        assertFalse(strategyMock.minimumToCompound(WBTC) == _minimumsToCompound[0]);
        assertFalse(strategyMock.minimumToCompound(USDC) == _minimumsToCompound[1]);
    }

    function test_editMinimumTokenCompound_Fail_LengthsMismatch() public {
        address[] memory _tokensToCompound = new address[](2);
        uint256[] memory _minimumsToCompound = new uint256[](1);
        _tokensToCompound[0] = WBTC;
        _tokensToCompound[1] = USDC;
        _minimumsToCompound[0] = 0.5e18;

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(StrategyErrors.LengthsMismatch.selector);
        strategyMock.editMinimumTokenCompound(_tokensToCompound, _minimumsToCompound);
        vm.stopPrank();

        assertTrue(strategyMock.minimumToCompound(rewardAsset) == minimumToCompound);
        assertFalse(strategyMock.minimumToCompound(WBTC) == _minimumsToCompound[0]);
        assertTrue(strategyMock.minimumToCompound(USDC) == 0);
    }

    function test_editMinimumTokenCompound_Success() public {
        address[] memory _tokensToCompound = new address[](2);
        uint256[] memory _minimumsToCompound = new uint256[](2);
        _tokensToCompound[0] = WBTC;
        _tokensToCompound[1] = USDC;
        _minimumsToCompound[0] = 0.5e18;
        _minimumsToCompound[1] = 10e18;

        vm.startPrank(adminStructure.getAllAdmins()[0]);
        strategyMock.editMinimumTokenCompound(_tokensToCompound, _minimumsToCompound);
        vm.stopPrank();

        assertTrue(strategyMock.minimumToCompound(rewardAsset) == minimumToCompound);
        assertTrue(strategyMock.minimumToCompound(WBTC) == _minimumsToCompound[0]);
        assertTrue(strategyMock.minimumToCompound(USDC) == _minimumsToCompound[1]);
    }

    // init

    function test_initialize_Fail_CalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));
        strategyMock.initialize(
            address(adminStructure),
            address(strategyHelper),
            address(feeManager),
            WETH,
            want,
            address(calculationsMock),
            tokensToCompound,
            minimumsToCompound,
            targetAsset
        );
    }

    function test_initialize_Fail_AdminStructureIsNotContract() external {
        StrategyMock _strategyImpl = new StrategyMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_strategyImpl),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],uint256[],address)",
                address(0),
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
    }

    function test_initialize_Fail_StrategyHelperIsNotContract() external {
        StrategyMock _strategyImpl = new StrategyMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_strategyImpl),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],uint256[],address)",
                address(adminStructure),
                address(0),
                address(feeManager),
                WETH,
                want,
                address(calculationsMock),
                tokensToCompound,
                minimumsToCompound,
                targetAsset
            )
        );
    }

    function test_initialize_Fail_FeeManagerIsNotContract() external {
        StrategyMock _strategyImpl = new StrategyMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_strategyImpl),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],uint256[],address)",
                address(adminStructure),
                address(strategyHelper),
                address(0),
                WETH,
                want,
                address(calculationsMock),
                tokensToCompound,
                minimumsToCompound,
                targetAsset
            )
        );
    }

    function test_initialize_Fail_WETHIsNotContract() external {
        StrategyMock _strategyImpl = new StrategyMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_strategyImpl),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],uint256[],address)",
                address(adminStructure),
                address(strategyHelper),
                address(feeManager),
                address(0),
                want,
                address(calculationsMock),
                tokensToCompound,
                minimumsToCompound,
                targetAsset
            )
        );
    }

    function test_initialize_Fail_WantIsNotContract() external {
        StrategyMock _strategyImpl = new StrategyMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_strategyImpl),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],uint256[],address)",
                address(adminStructure),
                address(strategyHelper),
                address(feeManager),
                WETH,
                address(0),
                address(calculationsMock),
                tokensToCompound,
                minimumsToCompound,
                targetAsset
            )
        );
    }

    function test_initialize_Fail_CalculationsIsNotContract() external {
        StrategyMock _strategyImpl = new StrategyMock();
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_strategyImpl),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,address,address[],uint256[],address)",
                address(adminStructure),
                address(strategyHelper),
                address(feeManager),
                WETH,
                want,
                address(0),
                tokensToCompound,
                minimumsToCompound,
                targetAsset
            )
        );
    }

    function test_initialize_Success() public {
        Proxy strategyMockProxy = new Proxy(
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
        StrategyMock strategyMockLocal = StrategyMock(payable(address(strategyMockProxy)));

        assertEq(address(strategyMockLocal.adminStructure()), address(adminStructure));
        assertEq(address(strategyMockLocal.strategyHelper()), address(strategyHelper));
        assertEq(address(strategyMockLocal.feeManager()), address(feeManager));
        assertEq(address(strategyMockLocal.weth()), WETH);
        assertEq(address(strategyMockLocal.want()), address(want));
        assertEq(address(strategyMockLocal.calculations()), address(calculationsMock));
    }

    // deposit

    function test_deposit_Fail_NotVaultERC20() public {
        address token = tokenIn1;
        uint256 amount = 1e18;
        uint256 depositEstimation = calculationsMock.estimateDeposit(tokenIn1, amount, slippage, hex"");

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.NotVault.selector, alice));
        strategyMock.deposit(alice, token, amount, _getAdditionalData(depositEstimation, slippage));
        vm.stopPrank();

        assertTrue(strategyMock.totalWantDeposits() == 0);
        assertTrue(strategyMock.userWantDeposit(alice) == 0);
    }

    function test_deposit_Fail_NotVaultNT() public {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimation = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.NotVault.selector, alice));
        strategyMock.deposit(alice, token, amount, _getAdditionalData(depositEstimation, slippage));
        vm.stopPrank();

        assertTrue(strategyMock.totalWantDeposits() == 0);
        assertTrue(strategyMock.userWantDeposit(alice) == 0);
    }

    function test_deposit_Fail_InsufficientDepositTokenOutERC20() external {
        address token = tokenIn1;
        uint256 amount = 1e18;

        vm.startPrank(alice);
        ERC20Upgradeable(token).safeApprove(address(vault), amount);

        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));
        vault.deposit{ value: 0 }(alice, token, amount, _getAdditionalData(amount * amount, slippage));
        vm.stopPrank();
    }

    function test_deposit_Fail_InsufficientDepositTokenOutNT() external {
        address token = ETH;
        uint256 amount = 1e18;

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));
        vault.deposit{ value: amount }(alice, token, amount, _getAdditionalData(amount * amount, slippage));
        vm.stopPrank();
    }

    function test_deposit_Success_DepositERC20() external {
        address token = tokenIn1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(token, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        assertEq(strategyMock.totalWantDeposits(), depositEstimationResult);
        assertEq(strategyMock.userWantDeposit(alice), depositEstimationResult);
    }

    function test_deposit_Success_DepositNT() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        assertEq(strategyMock.totalWantDeposits(), depositEstimationResult);
        assertEq(strategyMock.userWantDeposit(alice), depositEstimationResult);
    }

    // withdraw

    function test_withdraw_Fail_NotVaultERC20() public {
        address tokenIn = tokenIn1;
        address tokenOut = tokenOut1;
        uint256 amount = 1e18;
        uint256 depositEstimation = calculationsMock.estimateDeposit(tokenIn, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimation, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimation =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimation.wantDepositAfterFee;
        uint256 expectedAmountOut = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = ERC20Upgradeable(tokenOut).balanceOf(bob);

        uint256 amountShares = vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(0), true);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.NotVault.selector, alice));
        strategyMock.withdraw(
            bob, alice, tokenIn, tokenOut, amountShares, amountShares, _getAdditionalData(minAmountOut, slippage)
        );
        vm.stopPrank();

        assertEq(ERC20Upgradeable(tokenOut).balanceOf(bob), balanceBefore);
        assertApproxEqAbs(strategyMock.totalWantDeposits(), depositEstimation, 0);
        assertApproxEqAbs(strategyMock.userWantDeposit(alice), depositEstimation, 0);
    }

    function test_withdraw_Fail_NotVaultNT() public {
        address tokenIn = ETH;
        address tokenOut = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimation = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimation, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimation =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimation.wantDepositAfterFee;
        uint256 expectedAmountOut = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares = vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(0), true);

        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.NotVault.selector, alice));
        strategyMock.withdraw(
            bob, alice, tokenIn, tokenOut, amountShares, amountShares, _getAdditionalData(minAmountOut, slippage)
        );
        vm.stopPrank();

        assertEq(bob.balance, balanceBefore);
        assertApproxEqAbs(strategyMock.totalWantDeposits(), depositEstimation, 0);
        assertApproxEqAbs(strategyMock.userWantDeposit(alice), depositEstimation, 0);
    }

    function test_withdraw_Fail_InsufficientDepositTokenOutERC20() external {
        address tokenIn = tokenIn1;
        address tokenOut = tokenOut1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(tokenIn, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        uint256 amountShares = vault.userShares(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));
        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(amount * amount, slippage));
    }

    function test_withdraw_Fail_InsufficientDepositTokenOutNT() external {
        address tokenIn = ETH;
        address tokenOut = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        uint256 amountShares = vault.userShares(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));
        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(amount * amount, slippage));
    }

    function test_withdraw_Success_CompleteWithdrawFlagERC20() external {
        address tokenIn = tokenIn1;
        address tokenOut = tokenOut1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(tokenIn, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, tokenOut, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(tokenOut, wantToWithdraw, slippage);
        uint256 balanceBefore = ERC20Upgradeable(tokenOut).balanceOf(bob);

        uint256 amountShares = vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(0), true);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertEq(ERC20Upgradeable(tokenOut).balanceOf(bob) - balanceBefore, expectedAmountOut);
        assertEq(strategyMock.totalWantDeposits(), 0);
        assertEq(strategyMock.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_CompleteWithdrawFlagNT() external {
        address tokenIn = ETH;
        address tokenOut = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, WETH, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(WETH, wantToWithdraw, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares = vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(0), true);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertEq(bob.balance - balanceBefore, expectedAmountOut);
        assertEq(strategyMock.totalWantDeposits(), 0);
        assertEq(strategyMock.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_CompleteWithdrawNoFlagERC20() external {
        address tokenIn = tokenIn1;
        address tokenOut = tokenOut1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(tokenIn, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, tokenOut, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(tokenOut, wantToWithdraw, slippage);
        uint256 balanceBefore = ERC20Upgradeable(tokenOut).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertEq(ERC20Upgradeable(tokenOut).balanceOf(bob) - balanceBefore, expectedAmountOut);
        assertEq(strategyMock.totalWantDeposits(), 0);
        assertEq(strategyMock.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_CompleteWithdrawNoFlagNT() external {
        address tokenIn = ETH;
        address tokenOut = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, WETH, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(WETH, wantToWithdraw, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertEq(bob.balance - balanceBefore, expectedAmountOut);
        assertEq(strategyMock.totalWantDeposits(), 0);
        assertEq(strategyMock.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_PartialWithdrawERC20() external {
        address tokenIn = tokenIn1;
        address tokenOut = tokenOut1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(tokenIn, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, tokenOut, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(tokenOut, wantToWithdraw, slippage);
        uint256 balanceBefore = ERC20Upgradeable(tokenOut).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertEq(ERC20Upgradeable(tokenOut).balanceOf(bob) - balanceBefore, expectedAmountOut);
        assertEq(strategyMock.totalWantDeposits(), depositEstimationResult - vault.sharesToWant(amountShares));
        assertEq(strategyMock.userWantDeposit(alice), depositEstimationResult - vault.sharesToWant(amountShares));
    }

    function test_withdraw_Success_PartialWithdrawNT() external {
        address tokenIn = ETH;
        address tokenOut = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(0), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantDepositAfterFee / 2;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, WETH, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(WETH, wantToWithdraw, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(0), false);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertEq(bob.balance - balanceBefore, expectedAmountOut);
        assertEq(strategyMock.totalWantDeposits(), depositEstimationResult - vault.sharesToWant(amountShares));
        assertEq(strategyMock.userWantDeposit(alice), depositEstimationResult - vault.sharesToWant(amountShares));
    }

    // compound

    function test_withdraw_Success_CompleteWithdrawAndRewardsFlagERC20() external {
        address tokenIn = tokenIn1;
        address tokenOut = tokenOut1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(tokenIn, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ExternalProtocol(rewardAsset).setClaimAmount(minimumToCompound);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(minimumToCompound), tokenOut);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, tokenOut, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(tokenOut, wantToWithdraw, slippage);
        uint256 balanceBefore = ERC20Upgradeable(tokenOut).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(minimumToCompound), true);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(ERC20Upgradeable(tokenOut).balanceOf(bob) - balanceBefore, expectedAmountOut, 1);
        assertEq(strategyMock.totalWantDeposits(), 0);
        assertEq(strategyMock.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_CompleteWithdrawAndRewardsFlagNT() external {
        address tokenIn = ETH;
        address tokenOut = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ExternalProtocol(rewardAsset).setClaimAmount(minimumToCompound);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(minimumToCompound), tokenOut);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, WETH, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(WETH, wantToWithdraw, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(minimumToCompound), true);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2);
        assertEq(strategyMock.totalWantDeposits(), 0);
        assertEq(strategyMock.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_CompleteWithdrawAndRewardsNoFlagERC20() external {
        address tokenIn = tokenIn1;
        address tokenOut = tokenOut1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(tokenIn, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ExternalProtocol(rewardAsset).setClaimAmount(minimumToCompound);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(minimumToCompound), tokenOut);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, tokenOut, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(tokenOut, wantToWithdraw, slippage);
        uint256 balanceBefore = ERC20Upgradeable(tokenOut).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(minimumToCompound), false);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(ERC20Upgradeable(tokenOut).balanceOf(bob) - balanceBefore, expectedAmountOut, 1);
        assertEq(strategyMock.totalWantDeposits(), 0);
        assertEq(strategyMock.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_CompleteWithdrawAndRewardsNoFlagNT() external {
        address tokenIn = ETH;
        address tokenOut = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ExternalProtocol(rewardAsset).setClaimAmount(minimumToCompound);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(minimumToCompound), tokenOut);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, WETH, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(WETH, wantToWithdraw, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(minimumToCompound), false);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2);
        assertEq(strategyMock.totalWantDeposits(), 0);
        assertEq(strategyMock.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_OnlyRewardsERC20() external {
        address tokenIn = tokenIn1;
        address tokenOut = tokenOut1;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(tokenIn, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ExternalProtocol(rewardAsset).setClaimAmount(minimumToCompound);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(minimumToCompound), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, tokenOut, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(tokenOut, wantToWithdraw, slippage);
        uint256 balanceBefore = ERC20Upgradeable(tokenOut).balanceOf(bob);

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(minimumToCompound), false);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertEq(ERC20Upgradeable(tokenOut).balanceOf(bob) - balanceBefore, expectedAmountOut);
        assertEq(strategyMock.totalWantDeposits(), depositEstimationResult);
        assertEq(strategyMock.userWantDeposit(alice), depositEstimationResult);
    }

    function test_withdraw_Success_OnlyRewardsNT() external {
        address tokenIn = ETH;
        address tokenOut = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = calculationsMock.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, tokenIn, amount, _getAdditionalData(depositEstimationResult, slippage));

        ExternalProtocol(rewardAsset).setClaimAmount(minimumToCompound);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(alice, slippage, _getRewardData(minimumToCompound), tokenOut);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 wantToTarget = calculationsMock.convertWantToTarget(wantToWithdraw);
        uint256 targetToTokenOut = strategyHelper.convert(targetAsset, WETH, wantToTarget);
        uint256 minAmountOut = calculationsMock.getMinimumOutputAmount(targetToTokenOut, slippage);
        uint256 expectedAmountOut = calculationsMock.estimateWantToToken(WETH, wantToWithdraw, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            vault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(minimumToCompound), false);

        vm.prank(alice);

        vault.withdraw(bob, tokenOut, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertEq(bob.balance - balanceBefore, expectedAmountOut);
        assertEq(strategyMock.totalWantDeposits(), depositEstimationResult);
        assertEq(strategyMock.userWantDeposit(alice), depositEstimationResult);
    }

    // HELPERS

    function _deposit(address user, address token, uint256 amount, bytes memory additionalData) private {
        vm.startPrank(user);

        if (token != address(0)) {
            ERC20Upgradeable(token).safeApprove(address(vault), amount);
        }
        vault.deposit{ value: token == address(0) ? amount : 0 }(user, token, amount, additionalData);

        vm.stopPrank();
    }

    function _getAdditionalData(uint256 _minTokenOut, uint16 _slippage) private pure returns (bytes memory) {
        return abi.encode(_minTokenOut, _slippage);
    }

    function _getRewardData(uint256 _rewardAmount) private view returns (bytes memory _rewardData) {
        address[] memory _rewardTokens = new address[](1);
        uint256[] memory _rewardAmounts = new uint256[](1);

        _rewardTokens[0] = rewardAsset;
        _rewardAmounts[0] = _rewardAmount;

        return abi.encode(_rewardTokens, _rewardAmounts);
    }
}
