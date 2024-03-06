// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PendleLSDCalculations } from "src/calculations/pendle/PendleLSDCalculations.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { IPMarket } from "@pendle/core-v2/contracts/oracles/PendleLpOracleLib.sol";
import { PendleeETHStrategy } from "src/strategies/pendle/PendleeETHStrategy.sol";
import { IPPtOracle } from "@pendle/core-v2/contracts/interfaces/IPPtOracle.sol";
import { OracleBalancerWeighted } from "src/oracles/OracleBalancerWeighted.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { StrategyErrors } from "src/libraries/StrategyErrors.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { FeeManager, IFeeManager } from "src/FeeManager.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { OracleCurveeETH } from "src/oracles/OracleCurveeETH.sol";
import { OracleCurveWeETH } from "src/oracles/OracleCurveWeETH.sol";
import {
    StrategyHelperVenueBalancer, StrategyHelperVenueCurve, StrategyHelper
} from "src/strategies/StrategyHelper.sol";
import "../../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract PendleeETHStrategyTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address constant PENDLE_MARKET = 0xF32e58F92e60f4b0A37A69b95d642A471365EAe8;
    address constant WANT = 0xF32e58F92e60f4b0A37A69b95d642A471365EAe8;
    // PSY: 0xAC0047886a985071476a1186bE89222659970d65
    // PPT: 0xc69Ad9baB1dEE23F4605a82b3354F8E40d1E5966
    // PYT: 0xfb35Fd0095dD1096b1Ca49AD44d8C5812A201677
    address constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;
    address constant SUPER_ADMIN = 0xB9E3d56C934E89418E294466764D5d19Ac36334B;
    address constant PENDLE_PT_ORACLE = 0x14030836AEc15B2ad48bB097bd57032559339c92;
    uint256 constant WEETH_INDEX = 0;

    PendleeETHStrategy public pendleStrategy;
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

    IERC20Upgradeable public eeth = IERC20Upgradeable(EETH);
    IERC20Upgradeable public weeth = IERC20Upgradeable(WEETH);
    IERC20Upgradeable public weth = IERC20Upgradeable(WETH);
    IERC20Upgradeable public pendle = IERC20Upgradeable(PENDLE);

    address[] public tokensToCompound = [PENDLE];
    uint256[] public minimumsToCompound = [1e18];

    uint16 public slippage;
    uint32 pendleOracleTwapPeriod = 1 minutes;
    uint256 public depositCount;

    uint256 constant ETH_DEPOSIT_LIMIT = 1e2;
    uint256 constant WETH_DEPOSIT_LIMIT = 1e2;

    address constant WETH_WHALE = 0x6B44ba0a126a2A1a8aa6cD1AdeeD002e141Bcd44;

    event ChargedFees(IFeeManager.FeeType feeType, uint256 feeAmount, address feeRecipient, address _token);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 19_036_693);

        slippage = 290; // Slippage for the tests 2.90%
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
        StrategyHelperVenueBalancer strategyHelperVenueBalancer = new StrategyHelperVenueBalancer(BALANCER_VAULT);
        bytes32 poolId = 0xfd1cf6fd41f229ca86ada0584c63c49c3d66bbc9000200000000000000000438;

        StrategyHelperVenueCurve strategyHelperVenueCurve = new StrategyHelperVenueCurve(WETH);
        address[] memory pools = new address[](1);
        uint256[] memory coinsIn = new uint256[](1);
        uint256[] memory coinsOut = new uint256[](1);

        vm.startPrank(adminStructure.superAdmin());
        strategyHelper.setPath(
            address(PENDLE), address(WETH), address(strategyHelperVenueBalancer), abi.encode(WETH, poolId)
        );
        pools[0] = CURVE_WEETH_WETH_POOL;
        coinsIn[0] = 0;
        coinsOut[0] = 1;
        strategyHelper.setPath(WEETH, WETH, address(strategyHelperVenueCurve), abi.encode(pools, coinsIn, coinsOut));
        coinsIn[0] = 1;
        coinsOut[0] = 0;
        strategyHelper.setPath(WETH, WEETH, address(strategyHelperVenueCurve), abi.encode(pools, coinsIn, coinsOut));
        vm.stopPrank();

        // ORACLES
        Proxy oracleBalancerWeightedProxy = new Proxy(
            address(new OracleBalancerWeighted()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,address,uint32)",
                adminStructure,
                BALANCER_VAULT,
                BALANCER_PENDLE_WETH_POOL,
                ETH_ORACLE,
                WETH,
                12 hours
            )
        );
        OracleBalancerWeighted oBalancerWeightedPendleWeth =
            OracleBalancerWeighted(address(oracleBalancerWeightedProxy));

        Proxy oracleCurveeEthProxy = new Proxy(
            address(new OracleCurveeETH()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address,address)",
                adminStructure,
                address(strategyHelper),
                CURVE_WEETH_WETH_POOL,
                WEETH_INDEX,
                WETH,
                EETH
            )
        );
        OracleCurveeETH oracleCurveeEth = OracleCurveeETH(address(oracleCurveeEthProxy));

        Proxy oracleCurveWeEthProxy = new Proxy(
            address(new OracleCurveWeETH()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                adminStructure,
                address(strategyHelper),
                CURVE_WEETH_WETH_POOL,
                WEETH_INDEX,
                WETH
            )
        );
        OracleCurveWeETH oracleCurveWeEth = OracleCurveWeETH(address(oracleCurveWeEthProxy));

        vm.startPrank(adminStructure.superAdmin());
        strategyHelper.setOracle(PENDLE, address(oBalancerWeightedPendleWeth)); // PENDLE/USD
        strategyHelper.setOracle(WETH, ETH_ORACLE); // WETH/USD = ETH/USD
        strategyHelper.setOracle(EETH, address(oracleCurveeEth)); // EETH/USD
        strategyHelper.setOracle(WEETH, address(oracleCurveWeEth)); // WEETH/USD
        vm.stopPrank();

        (bool increaseCardinality, uint256 cardinalityRequired,) =
            IPPtOracle(PENDLE_PT_ORACLE).getOracleState(PENDLE_MARKET, pendleOracleTwapPeriod);

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
            twapPeriod: pendleOracleTwapPeriod,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });
        Proxy pendleStrategyProxy = new Proxy(
            address(new PendleeETHStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]),address,address,address)",
                initParams,
                ETHER_FI_EETH_LIQUIDITY_POOL,
                WEETH,
                PENDLE
            )
        );
        pendleStrategy = PendleeETHStrategy(payable(address(pendleStrategyProxy)));

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

        vm.startPrank(WETH_WHALE);
        IERC20Upgradeable(WETH).safeTransfer(alice, 1000e18);
        IERC20Upgradeable(WETH).safeTransfer(bob, 1000e18);
        vm.stopPrank();

        deal(alice, 1000e18);
        deal(bob, 1000e18);
    }

    // ==============
    // ||   INIT   ||
    // ==============

    function test_initialize_Success() public {
        Proxy pendleStrategyProxy = new Proxy(
            address(new PendleeETHStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]),address,address,address)",
                initParams,
                ETHER_FI_EETH_LIQUIDITY_POOL,
                WEETH,
                PENDLE
            )
        );
        PendleeETHStrategy pendleStrategyLocal = PendleeETHStrategy(payable(address(pendleStrategyProxy)));
        assertEq(address(pendleStrategyLocal.pendleRouter()), PENDLE_ROUTER);
        assertEq(address(pendleStrategyLocal.pendleMarket()), PENDLE_MARKET);
        assertEq(address(pendleStrategyLocal.targetAsset()), EETH);
        assertEq(address(pendleStrategyLocal.calculations()), address(pendleCalculations));
        assertEq(pendleStrategyLocal.twapPeriod(), pendleOracleTwapPeriod);

        assertEq(pendleStrategyLocal.eEthLiquidityPool(), ETHER_FI_EETH_LIQUIDITY_POOL);
        assertEq(pendleStrategyLocal.weeth(), WEETH);
        assertEq(pendleStrategyLocal.pendle(), PENDLE);
    }

    function test_initialize_Fail_CalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        pendleStrategy.initialize(initParams, ETHER_FI_EETH_LIQUIDITY_POOL, WEETH, PENDLE);
    }

    function test_initialize_Fail_EethLiquidityPoolIsNotContract() external {
        PendleeETHStrategy _pendleStrategyImpl = new PendleeETHStrategy();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_pendleStrategyImpl),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]),address,address,address)",
                initParams,
                address(0),
                WEETH,
                PENDLE
            )
        );
    }

    function test_initialize_Fail_WeethIsNotContract() external {
        PendleeETHStrategy _pendleStrategyImpl = new PendleeETHStrategy();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_pendleStrategyImpl),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]),address,address,address)",
                initParams,
                ETHER_FI_EETH_LIQUIDITY_POOL,
                address(0),
                PENDLE
            )
        );
    }

    function test_initialize_Fail_PendleIsNotContract() external {
        PendleeETHStrategy _pendleStrategyImpl = new PendleeETHStrategy();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));
        new Proxy(
            address(_pendleStrategyImpl),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]),address,address,address)",
                initParams,
                ETHER_FI_EETH_LIQUIDITY_POOL,
                WEETH,
                address(0)
            )
        );
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
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), depositEstimationResult, 3.3e13);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), depositEstimationResult, 3.3e13);
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
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 8.9e13
            );
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 8.9e13
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
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 3.3e13
            );
            assertApproxEqAbs(pendleStrategy.userWantDeposit(users[i]), depositEstimationResult, 3.3e13);
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
            deal(PENDLE, address(pendleStrategy), 169e18, true);

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(pendleStrategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 7.4e13
            );
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 7.4e13
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
            deal(PENDLE, address(pendleStrategy), 169e18, true);

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(pendleStrategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 3.6e13
            );
            assertApproxEqAbs(pendleStrategy.userWantDeposit(users[i]), depositEstimationResult, 3.6e13);
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
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), depositEstimationResult, 3.3e13);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), depositEstimationResult, 3.3e13);
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
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 8.9e13
            );
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 8.9e13
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
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 3.3e13
            );
            assertApproxEqAbs(pendleStrategy.userWantDeposit(users[i]), depositEstimationResult, 3.3e13);
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
            deal(PENDLE, address(pendleStrategy), 169e18, true);

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(pendleStrategy.userWantDeposit(alice) > prevTotalWantDeposits + depositEstimationResult);
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 7.4e13
            );
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 7.4e13
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
            deal(PENDLE, address(pendleStrategy), 169e18, true);

            assertTrue(pendleStrategy.totalWantDeposits() > prevTotalWantDeposits + depositEstimationResult);
            assertTrue(pendleStrategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 3.6e13
            );
            assertApproxEqAbs(pendleStrategy.userWantDeposit(users[i]), depositEstimationResult, 3.6e13);
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
            assertApproxEqAbs(
                pendleStrategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 3.3e13
            );
            assertApproxEqAbs(
                pendleStrategy.userWantDeposit(alice), prevTotalWantDeposits + depositEstimationResult, 3.3e13
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
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

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

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 5.6e14);
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

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 5.6e14);
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

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 5.6e14);
        assertApproxEqAbs(
            pendleStrategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5e14
        );
        assertApproxEqAbs(
            pendleStrategy.userWantDeposit(alice), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5e14
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

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 5.6e14);
        assertApproxEqAbs(
            pendleStrategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5e14
        );
        assertApproxEqAbs(
            pendleStrategy.userWantDeposit(alice), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5e14
        );

        vm.prank(alice);
        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(
            bob.balance - balanceBefore,
            pendleCalculations.convertWantToTarget(withdrawalEstimationResult.wantDepositAfterFee),
            5.5e14
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

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 5.6e14);
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

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 5.6e14);
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

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 5.6e14);
        assertApproxEqAbs(
            pendleStrategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5e14
        );
        assertApproxEqAbs(
            pendleStrategy.userWantDeposit(alice), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5e14
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

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 5.6e14);
        assertApproxEqAbs(
            pendleStrategy.totalWantDeposits(), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5e14
        );
        assertApproxEqAbs(
            pendleStrategy.userWantDeposit(alice), withdrawalEstimationResult.wantDepositAfterFee - wantToWithdraw, 5e14
        );

        vm.prank(alice);
        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(
            IERC20Upgradeable(token).balanceOf(bob) - balanceBefore,
            pendleCalculations.convertWantToTarget(withdrawalEstimationResult.wantDepositAfterFee),
            5.5e14
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

        assertApproxEqAbs(IERC20Upgradeable(WETH).balanceOf(bob) - balanceBefore, expectedAmountOut, 5.6e14);
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

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 5.6e14);
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
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(10), true);

        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2.1e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsInETNoFlag() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
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

        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2.1e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawOnlyRewardsInETH() external {
        address token = ETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = bob.balance;

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2e15);
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), depositEstimationResult, 6.1e14);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), depositEstimationResult, 6.1e14);
    }

    // WETH

    function test_withdraw_Success_WithdrawAllAndRewardsInWETHFlag() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw =
            withdrawalEstimationResult.wantDepositAfterFee + withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _getRewardData(10), true);

        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 2.1e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsInWETNoFlag() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
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

        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 2.1e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawOnlyRewardsInWETH() external {
        address token = WETH;
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, token, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
        deal(PENDLE, address(pendleStrategy), 169e18, true);

        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            pendleVault.estimateWithdrawal(alice, slippage, _getRewardData(10), token);
        uint256 wantToWithdraw = withdrawalEstimationResult.wantRewardsAfterFee;
        uint256 expectedAmountOut = pendleCalculations.convertWantToTarget(wantToWithdraw);
        uint256 minAmountOut = pendleCalculations.getMinimumOutputAmount(expectedAmountOut, slippage);
        uint256 balanceBefore = IERC20Upgradeable(token).balanceOf(bob);

        uint256 amountShares =
            pendleVault.calculateSharesToWithdraw(alice, wantToWithdraw, slippage, _getRewardData(10), false);

        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, token, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(token).balanceOf(bob) - balanceBefore, expectedAmountOut, 2e15);
        assertApproxEqAbs(pendleStrategy.totalWantDeposits(), depositEstimationResult, 6.1e14);
        assertApproxEqAbs(pendleStrategy.userWantDeposit(alice), depositEstimationResult, 6.1e14);
    }

    // COMBINED

    function test_withdraw_Success_WithdrawAllAndRewardsFromETHToWETH() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, ETH, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
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

        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, WETH, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(IERC20Upgradeable(WETH).balanceOf(bob) - balanceBefore, expectedAmountOut, 2.1e15);
        assertEq(pendleStrategy.totalWantDeposits(), 0);
        assertEq(pendleStrategy.userWantDeposit(alice), 0);
    }

    function test_withdraw_Success_WithdrawAllAndRewardsFromWETHToETH() external {
        uint256 amount = 1e18;
        uint256 depositEstimationResult = pendleCalculations.estimateDeposit(WETH, amount, slippage, hex"");

        _deposit(alice, WETH, amount, _getAdditionalData(depositEstimationResult, slippage));

        // Sending some reward token to trigger a compound
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

        deal(PENDLE, address(pendleStrategy), 179e18, true);

        vm.prank(alice);

        pendleVault.withdraw(bob, ETH, amountShares, _getAdditionalData(minAmountOut, slippage));

        assertApproxEqAbs(bob.balance - balanceBefore, expectedAmountOut, 2.1e15);
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
        address[] memory _rewardTokens = new address[](1);
        uint256[] memory _rewardAmounts = new uint256[](1);

        _rewardTokens[0] = PENDLE;
        _rewardAmounts[0] = 1e18 * _multiplier;

        return abi.encode(_rewardTokens, _rewardAmounts);
    }
}
