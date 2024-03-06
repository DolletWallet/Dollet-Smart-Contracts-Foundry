// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { PendleLSDCalculations } from "src/calculations/pendle/PendleLSDCalculations.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { IPMarket } from "@pendle/core-v2/contracts/oracles/PendleLpOracleLib.sol";
import { PendleLSDStrategy } from "src/strategies/pendle/PendleLSDStrategy.sol";
import { IPPtOracle } from "@pendle/core-v2/contracts/interfaces/IPPtOracle.sol";
import { OracleBalancerWeighted } from "src/oracles/OracleBalancerWeighted.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { CalculationsErrors } from "src/libraries/CalculationsErrors.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { IMarket } from "src/strategies/pendle/interfaces/IPendle.sol";
import { StrategyErrors } from "src/libraries/StrategyErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { FeeManager, IFeeManager } from "src/FeeManager.sol";
import { VaultErrors } from "src/libraries/VaultErrors.sol";
import { SigningUtils } from "../../utils/SigningUtils.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { OracleCurve } from "src/oracles/OracleCurve.sol";
import { Signature } from "src/libraries/ERC20Lib.sol";
import {
    StrategyHelperVenueUniswapV3,
    StrategyHelperVenueBalancer,
    StrategyHelperVenueCurve,
    StrategyHelper
} from "src/strategies/StrategyHelper.sol";
import "../../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract StrategyPendleLSDTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address constant PENDLE_MARKET = 0x62187066FD9C24559ffB54B0495a304ADe26d50B;
    address constant WANT = 0x62187066FD9C24559ffB54B0495a304ADe26d50B;
    address constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;
    address constant SUPER_ADMIN = 0xB9E3d56C934E89418E294466764D5d19Ac36334B;
    address constant PENDLE_PT_ORACLE = 0x14030836AEc15B2ad48bB097bd57032559339c92;
    uint256 constant OETH_INDEX = 1;

    PendleLSDStrategy public pendleStrategy;
    CompoundVault public pendleVault;
    StrategyHelper public strategyHelper;
    FeeManager public feeManager;
    IAdminStructure public adminStructure;
    SigningUtils public signingUtils;
    PendleLSDCalculations public pendleCalculations;
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
    IERC20Upgradeable public wbtc = IERC20Upgradeable(WBTC);
    IERC20Upgradeable public usdc = IERC20Upgradeable(USDC);
    IERC20Upgradeable public usdt = IERC20Upgradeable(USDT);
    IERC20Upgradeable public pendle = IERC20Upgradeable(PENDLE);
    address[] public tokensToCompound = [PENDLE];
    uint256[] public minimumsToCompound = [1e18];
    uint16 public slippage;
    uint32 pendleOracleTwapPeriod = 1800;
    uint256 public depositCount;

    uint256 constant USDC_DEPOSIT_LIMIT = 1e6;
    uint256 constant USDT_DEPOSIT_LIMIT = 1e6;
    uint256 constant WBTC_DEPOSIT_LIMIT = 1e2;
    uint256 constant ETH_DEPOSIT_LIMIT = 1e2;

    event ChargedFees(IFeeManager.FeeType feeType, uint256 feeAmount, address feeRecipient, address _token);

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_458_866);

        slippage = 20; // Slippage for the tests 0.2%
        adminStructure = IAdminStructure(ADMIN_STRUCTURE);
        (alice, alicePrivateKey) = makeAddrAndKey("Alice");
        (bob, bobPrivateKey) = makeAddrAndKey("Bob");
        signingUtils = new SigningUtils();

        // ETH/WBTC/USDT/USDC
        depositAllowedTokens = [ETH, WBTC, USDC, USDT];
        withdrawalAllowedTokens = [ETH, WBTC, USDC, USDT];

        // =================================
        // ======= LSD Calculations ========
        // =================================
        Proxy pendleLSDCalculationsProxy = new Proxy(
            address(new PendleLSDCalculations()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        pendleCalculations = PendleLSDCalculations(address(pendleLSDCalculationsProxy));

        // =================================
        // ======== Strategy Helper ========
        // =================================
        Proxy strategyHelperProxy =
            new Proxy(address(new StrategyHelper()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE));
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        StrategyHelperVenueUniswapV3 hlpV3 = new StrategyHelperVenueUniswapV3(UNISWAP_V3_ROUTER);

        // PENDLE REWARD TO USD
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

        Proxy oracleCurveProxy = new Proxy(
            address(new OracleCurve()),
            abi.encodeWithSignature(
                "initialize(address,address,address,uint256,address)",
                adminStructure,
                address(strategyHelper),
                CURVE_OETH_ETH_POOL,
                OETH_INDEX,
                WETH
            )
        );
        OracleCurve oCurveOethEth = OracleCurve(address(oracleCurveProxy));

        vm.startPrank(adminStructure.superAdmin());

        strategyHelper.setOracle(address(pendle), address(oBalancerWeightedPendleWeth)); // PENDLE/USD
        strategyHelper.setOracle(WETH, ETH_ORACLE); // WETH/USD = ETH/USD
        strategyHelper.setOracle(USDC, USDC_ORACLE); // USDC/USD
        strategyHelper.setOracle(USDT, USDT_ORACLE); // USDT/USD
        strategyHelper.setOracle(WBTC, WBTC_ORACLE); // WBTC/USD = BTC/USD
        strategyHelper.setOracle(OETH, address(oCurveOethEth)); // OETH/USD

        // USDC/WETH
        strategyHelper.setPath(
            address(USDC), address(WETH), address(hlpV3), abi.encodePacked(address(USDC), uint24(500), address(WETH))
        );
        strategyHelper.setPath(
            address(WETH), address(USDC), address(hlpV3), abi.encodePacked(address(WETH), uint24(500), address(USDC))
        );

        // USDT/WETH
        strategyHelper.setPath(
            address(USDT), address(WETH), address(hlpV3), abi.encodePacked(address(USDT), uint24(500), address(WETH))
        );
        strategyHelper.setPath(
            address(WETH), address(USDT), address(hlpV3), abi.encodePacked(address(WETH), uint24(500), address(USDT))
        );

        // WTBC/WETH
        strategyHelper.setPath(
            address(WBTC), address(WETH), address(hlpV3), abi.encodePacked(address(WBTC), uint24(500), address(WETH))
        );
        strategyHelper.setPath(
            address(WETH), address(WBTC), address(hlpV3), abi.encodePacked(address(WETH), uint24(500), address(WBTC))
        );

        // PENDLE/WETH
        StrategyHelperVenueBalancer strategyHelperVenueBalancer = new StrategyHelperVenueBalancer(BALANCER_VAULT);
        bytes32 poolId = 0xfd1cf6fd41f229ca86ada0584c63c49c3d66bbc9000200000000000000000438;

        strategyHelper.setPath(
            address(PENDLE), address(WETH), address(strategyHelperVenueBalancer), abi.encode(WETH, poolId)
        );

        // WETH/OETH
        StrategyHelperVenueCurve strategyHelperVenueCurve = new StrategyHelperVenueCurve(WETH);
        address[] memory pools = new address[](1);
        uint256[] memory coinsIn = new uint256[](1);
        uint256[] memory coinsOut = new uint256[](1);

        pools[0] = CURVE_OETH_ETH_POOL;

        coinsIn[0] = 0;
        coinsOut[0] = 1;
        strategyHelper.setPath(
            address(WETH), address(OETH), address(strategyHelperVenueCurve), abi.encode(pools, coinsIn, coinsOut)
        );

        coinsIn[0] = 1;
        coinsOut[0] = 0;
        strategyHelper.setPath(
            address(OETH), address(WETH), address(strategyHelperVenueCurve), abi.encode(pools, coinsIn, coinsOut)
        );

        vm.stopPrank();

        // =================================
        // ========== Fee Manager ==========
        // =================================
        Proxy feeManagerProxy =
            new Proxy(address(new FeeManager()), abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE));
        feeManager = FeeManager(address(feeManagerProxy));

        // =================================
        // =========== Strategy ============
        // =================================
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
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
            address(new PendleLSDStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
        pendleStrategy = PendleLSDStrategy(payable(address(pendleStrategyProxy)));

        // =================================
        // ======== Strategy Vault =========
        // =================================
        IVault.DepositLimit[] memory _depositLimits = new IVault.DepositLimit[](4);

        _depositLimits[0] = IVault.DepositLimit(USDC, USDC_DEPOSIT_LIMIT);
        _depositLimits[1] = IVault.DepositLimit(USDT, USDT_DEPOSIT_LIMIT);
        _depositLimits[2] = IVault.DepositLimit(WBTC, WBTC_DEPOSIT_LIMIT);
        _depositLimits[3] = IVault.DepositLimit(ETH, ETH_DEPOSIT_LIMIT);

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

        vm.startPrank(adminStructure.superAdmin());

        pendleStrategy.setSlippageTolerance(105); // 1.05% system slippage
        pendleStrategy.setVault(address(pendleVault));
        feeManager.setFee(
            address(pendleStrategy),
            IFeeManager.FeeType.MANAGEMENT,
            managementFeeRecipient,
            1000 //10%
        );
        feeManager.setFee(
            address(pendleStrategy),
            IFeeManager.FeeType.PERFORMANCE,
            performanceFeeRecipient,
            1000 //10%
        );
        pendleCalculations.setStrategyValues(address(pendleStrategy));

        vm.stopPrank();

        vm.startPrank(0xF977814e90dA44bFA03b6295A0616a897441aceC); // USDT Whale

        IERC20Upgradeable(USDT).safeTransfer(alice, 10_000e6);
        IERC20Upgradeable(USDT).safeTransfer(bob, 10_000e6);

        vm.stopPrank();

        deal(USDC, alice, 10_000e6, true);
        deal(USDC, bob, 10_000e6, true);
        deal(WBTC, alice, 100e8, true);
        deal(WBTC, bob, 100e8, true);
        deal(alice, 1000e18);
        deal(bob, 1000e18);

        (bool increaseCardinality, uint256 cardinalityRequired,) =
            IPPtOracle(PENDLE_PT_ORACLE).getOracleState(PENDLE_MARKET, 1800);

        if (increaseCardinality) {
            IPMarket(PENDLE_MARKET).increaseObservationsCardinalityNext(uint16(cardinalityRequired));
        }

        setLabels();
    }

    function makeDeposit(address _user, address _token, uint256 _amount) public {
        // =====================================
        // ======== Making a pre-deposit =======
        // =====================================
        CompoundVault _pendleVault = pendleVault;
        uint256 _sharesBefore = _pendleVault.userShares(_user);
        uint256 _wantBefore = _pendleVault.balance();
        vm.startPrank(_user);
        if (_token != address(0)) {
            if (_token == address(USDT)) {
                IERC20Upgradeable(_token).safeApprove(address(_pendleVault), type(uint256).max);
            } else {
                IERC20Upgradeable(_token).safeApprove(address(_pendleVault), type(uint256).max);
            }
        }
        depositCount++;
        _pendleVault.deposit{ value: _token == address(0) ? _amount : 0 }(
            _user, _token, _amount, getAdditionalDataDeposit(0)
        );
        uint256 _sharesAdded = _pendleVault.userShares(_user) - _sharesBefore;
        uint256 _wantAdded = _pendleVault.balance() - _wantBefore;
        assertGt(_sharesAdded, 0);
        assertGt(_wantAdded, 0);
    }

    // ////////////// INITIALIZATION //////////////

    // Allows to intialize the variables
    function test_ShouldReadTheIntializedVariables() public {
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
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
            address(new PendleLSDStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
        PendleLSDStrategy pendleStrategyLocal = PendleLSDStrategy(payable(address(pendleStrategyProxy)));
        assertEq(address(pendleStrategyLocal.pendleRouter()), PENDLE_ROUTER);
        assertEq(address(pendleStrategyLocal.pendleMarket()), PENDLE_MARKET);
        assertEq(address(pendleStrategyLocal.targetAsset()), OETH);
        assertEq(address(pendleStrategyLocal.calculations()), address(pendleCalculations));
        assertEq(pendleStrategyLocal.twapPeriod(), 1800);
    }

    ////////////// GENERAL //////////////

    function test_initialize_ShouldFailIfPendleRouterIsNotContract() external {
        PendleLSDStrategy _pendleStrategyImpl = new PendleLSDStrategy();
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: WANT,
            calculations: address(pendleCalculations),
            pendleRouter: address(0), // Invalid address
            pendleMarket: PENDLE_MARKET,
            twapPeriod: pendleOracleTwapPeriod,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(_pendleStrategyImpl),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
    }

    function test_initialize_ShouldFailIfPendleMarketIsNotContract() external {
        PendleLSDStrategy _pendleStrategyImpl = new PendleLSDStrategy();
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: WANT,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: address(0), // Invalid address,
            twapPeriod: pendleOracleTwapPeriod,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(_pendleStrategyImpl),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
    }

    function test_initialize_ShouldFailIfCalculationsIsNotContract() external {
        PendleLSDStrategy _pendleStrategyImpl = new PendleLSDStrategy();
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: WANT,
            calculations: address(0), // Invalid address,
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: PENDLE_MARKET,
            twapPeriod: pendleOracleTwapPeriod,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(_pendleStrategyImpl),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
    }

    function test_adminStructure_allowsToChangeTheAdminStructure() public {
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

    // Allows to make the admins to edit the twap period
    function test_oracle_ShouldAllowAdminToEditTheTwapPeriod() public {
        // Fails with invalid user
        vm.prank(alice); // Some not admin user
        vm.expectRevert(bytes("NotUserAdmin"));
        pendleStrategy.setTwapPeriod(uint32(1900));
        // Works well with valid user
        vm.startPrank(adminStructure.getAllAdmins()[0]);
        uint32 twapPeriodBefore = pendleStrategy.twapPeriod();
        assertEq(twapPeriodBefore, 1800);
        pendleStrategy.setTwapPeriod(uint32(1900));
        uint32 twapPeriodAfter = pendleStrategy.twapPeriod();
        assertEq(twapPeriodAfter, 1900);
    }

    function test_estimates_ShouldGetTheUserDepositUsdc() public {
        makeDeposit(alice, USDC, 1000e6);
        uint256 _userDepositExpected = 1000e6;
        uint256 _userDepositObtained = pendleVault.userDeposit(alice, USDC);
        assertApproxEqAbs(_userDepositExpected, _userDepositObtained, 3e6);
    }

    function test_estimates_ShouldGetTheUserDepositUsdt() public {
        makeDeposit(alice, USDT, 1000e6);
        uint256 _userDepositExpected = 1000e6;
        uint256 _userDepositObtained = pendleVault.userDeposit(alice, USDT);
        assertApproxEqAbs(_userDepositExpected, _userDepositObtained, 3e6);
    }

    function test_estimates_ShouldGetTheUserDepositWbtc() public {
        makeDeposit(alice, WBTC, 2_895_400);
        uint256 _userDepositExpected = 2_895_400;
        uint256 _userDepositObtained = pendleVault.userDeposit(alice, WBTC);
        // Around $3 difference
        assertApproxEqAbs(_userDepositExpected, _userDepositObtained, 9500);
    }

    function test_estimates_ShouldGetTheUserDepositWbtcUsdc() public {
        makeDeposit(alice, WBTC, 2_895_400);
        uint256 _userDepositExpected = 1002e6;
        uint256 _userDepositObtained = pendleVault.userDeposit(alice, USDC);
        assertApproxEqAbs(_userDepositExpected, _userDepositObtained, 4e5);
    }

    function test_estimates_ShouldGetTheUserDepositEth() public {
        makeDeposit(alice, ETH, 550_000_000_000_000_000);
        uint256 _userDepositExpected = 550_000_000_000_000_000;
        uint256 _userDepositObtained = pendleVault.userDeposit(alice, ETH);
        // Less than $2 difference
        assertApproxEqAbs(_userDepositExpected, _userDepositObtained, 6e14);
    }

    function test_estimates_ShouldGetTheUserDepositEthUsdc() public {
        makeDeposit(alice, ETH, 550_000_000_000_000_000);
        uint256 _userDepositExpected = 992e6;
        uint256 _userDepositObtained = pendleVault.userDeposit(alice, USDC);
        assertApproxEqAbs(_userDepositExpected, _userDepositObtained, 4e5);
    }

    function test_estimates_ShouldFailtGetTheUserDepositWithInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.NotAllowedDepositToken.selector, PENDLE));
        pendleVault.userDeposit(alice, PENDLE);
    }

    function test_estimates_ShouldGetTheTotalDepositUsdc() public {
        makeDeposit(alice, USDC, 1000e6);
        makeDeposit(bob, WBTC, 2_895_400);
        uint256 _totalDepositExpected = 2000e6;
        uint256 _totalDepositObtained = pendleVault.totalDeposits(USDC);
        assertApproxEqAbs(_totalDepositExpected, _totalDepositObtained, 7e6);
    }

    function test_estimates_ShouldGetTheTotalDepositUsdt() public {
        makeDeposit(alice, USDT, 1000e6);
        makeDeposit(bob, WBTC, 2_895_400);
        uint256 _totalDepositExpected = 2000e6;
        uint256 _totalDepositObtained = pendleVault.totalDeposits(USDT);
        assertApproxEqAbs(_totalDepositExpected, _totalDepositObtained, 5e6);
    }

    function test_estimates_ShouldGetTheTotalDepositWbtc() public {
        makeDeposit(alice, USDT, 1000e6);
        makeDeposit(alice, WBTC, 2_895_400);
        uint256 _totalDepositExpected = 2_895_400 * 2;
        uint256 _totalDepositObtained = pendleVault.totalDeposits(WBTC);
        // Around $3 difference
        assertApproxEqAbs(_totalDepositExpected, _totalDepositObtained, 10_500);
    }

    function test_estimates_ShouldGetTheTotalDepositEth() public {
        makeDeposit(alice, ETH, 0.55e18);
        makeDeposit(bob, ETH, 0.55e18);
        uint256 _totalDepositExpected = 0.55e18 * 2;
        uint256 _totalDepositObtained = pendleVault.totalDeposits(ETH);
        // Around $3 difference
        assertApproxEqAbs(_totalDepositExpected, _totalDepositObtained, 11.6e14);
    }

    function test_estimates_ShouldFailtGetTheTotalDepositWithInvalidToken() public {
        makeDeposit(alice, USDC, 1000e6);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.NotAllowedDepositToken.selector, PENDLE));
        pendleVault.totalDeposits(PENDLE);
    }

    function test_estimates_ShouldFailToEstimateDepositWithInvalidToken() public {
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.NotAllowedDepositToken.selector, PENDLE));
        pendleVault.estimateDeposit(PENDLE, 0, 0, hex"", getRewardData(0));
    }

    function test_estimates_ShouldEstimateZeroWantToToken() public {
        uint256 _amountInTokenZero = pendleCalculations.estimateWantToToken(USDC, 0, 0);
        assertEq(_amountInTokenZero, 0);
    }

    function test_estimates_ShouldEstimateWantToToken() public {
        uint256 _amountInToken = pendleCalculations.estimateWantToToken(USDC, 1e18, 0);
        assertGt(_amountInToken, 0);
    }

    function test_estimates_ShouldEstimateZeroWithdrawalDistribution() public {
        (uint256 _wantDepositZero, uint256 _wantRewardsZero) =
            pendleCalculations.calculateWithdrawalDistribution(alice, 0, 0);
        assertEq(_wantDepositZero, 0);
        assertEq(_wantRewardsZero, 0);
    }

    function test_estimates_ShouldEstimateWithdrawalDistributionNoDeposit() public {
        (uint256 _wantDeposit, uint256 _wantRewards) =
            pendleCalculations.calculateWithdrawalDistribution(alice, 10e18, 10e18);
        assertEq(_wantDeposit, 0); // The user has 0 deposit
        assertEq(_wantRewards, 10e18); // 100% on rewards
    }

    function test_estimates_ShouldEstimateWithdrawalDistributionWithDeposit() public {
        makeDeposit(alice, USDC, 1000e6);
        (uint256 _wantDeposit, uint256 _wantRewards) =
            pendleCalculations.calculateWithdrawalDistribution(alice, 10e18, 10e18);
        assertGt(_wantDeposit, 0);
        assertEq(_wantRewards, 10e18 - _wantDeposit);
    }

    function test_estimates_ShouldEstimateUsedAmountsNoDeposit() public {
        (uint256 _depositUsed, uint256 _rewardsUsed, uint256 _wantDeposit, uint256 _wantRewards) =
            pendleCalculations.calculateUsedAmounts(alice, 10e18, 10e18, 100e18);
        assertEq(_depositUsed, 0);
        assertEq(_rewardsUsed, 100e18);
        assertEq(_wantDeposit, 0);
        assertEq(_wantRewards, 10e18);
    }

    function test_estimates_ShouldEstimateUsedAmountsWithDeposit() public {
        makeDeposit(alice, USDC, 1000e6);
        uint256 _totalRewards = 100e18;
        (uint256 _depositUsed, uint256 _rewardsUsed, uint256 _wantDeposit, uint256 _wantRewards) =
            pendleCalculations.calculateUsedAmounts(alice, 10e18, 10e18, _totalRewards);
        uint256 _wantDepositPercentage = _wantDeposit * 1e18 / (_wantDeposit + _wantRewards);
        uint256 _expectedDepositAmount = _wantDepositPercentage * _totalRewards / 1e18;
        uint256 _expectedRewardsAmount = _totalRewards - _expectedDepositAmount;
        assertEq(_depositUsed, _expectedDepositAmount);
        assertEq(_rewardsUsed, _expectedRewardsAmount);
    }

    function test_estimates_ShouldEstimateWithdrawalDistribution() public {
        bytes memory revertReason = abi.encodeWithSelector(CalculationsErrors.WantToWithdrawIsTooHigh.selector);
        vm.expectRevert(revertReason);
        pendleCalculations.calculateWithdrawalDistribution(alice, 2, 1);
    }

    function test_estimates_ShouldEstimateFirstDepositUsdc() public {
        (uint256 _amountShares, uint256 _amountWant) =
            pendleVault.estimateDeposit(USDC, 1000e6, slippage, hex"", getRewardData(0));
        makeDeposit(alice, USDC, 1000e6);
        uint256 _obtainedShares = pendleVault.userShares(alice);
        uint256 _obtainedWant = pendleVault.balance();
        assertGe(_obtainedShares, _amountShares);
        assertGe(_obtainedWant, _amountWant);
        assertApproxEqAbs(_obtainedShares, _amountShares, 1e15);
        assertApproxEqAbs(_obtainedWant, _amountWant, 1e15);
    }

    function test_estimates_ShouldEstimateFirstDepositUsdt() public {
        (uint256 _amountShares, uint256 _amountWant) =
            pendleVault.estimateDeposit(USDT, 1000e6, 10, hex"", getRewardData(0));
        makeDeposit(alice, USDT, 1000e6);
        uint256 _obtainedShares = pendleVault.userShares(alice);
        uint256 _obtainedWant = pendleVault.balance();
        assertGe(_obtainedShares, _amountShares);
        assertGe(_obtainedWant, _amountWant);
        assertApproxEqAbs(_obtainedShares, _amountShares, 3e14);
        assertApproxEqAbs(_obtainedWant, _amountWant, 3e14);
    }

    function test_estimates_ShouldEstimateFirstDepositWbtc() public {
        (uint256 _amountShares, uint256 _amountWant) =
            pendleVault.estimateDeposit(WBTC, 2_895_400, 0, hex"", getRewardData(0));
        makeDeposit(alice, WBTC, 2_895_400);
        uint256 _obtainedShares = pendleVault.userShares(alice);
        uint256 _obtainedWant = pendleVault.balance();
        assertGe(_obtainedShares, _amountShares);
        assertGe(_obtainedWant, _amountWant);
        assertApproxEqAbs(_obtainedShares, _amountShares, 9e14);
        assertApproxEqAbs(_obtainedWant, _amountWant, 9e14);
    }

    function test_estimates_ShouldEstimateFirstDepositEth() public {
        (uint256 _amountShares, uint256 _amountWant) =
            pendleVault.estimateDeposit(ETH, 0.55e18, 10, hex"", getRewardData(0));
        makeDeposit(alice, ETH, 0.55e18);
        uint256 _obtainedShares = pendleVault.userShares(alice);
        uint256 _obtainedWant = pendleVault.balance();
        assertGe(_obtainedShares, _amountShares);
        assertGe(_obtainedWant, _amountWant);
        assertApproxEqAbs(_obtainedShares, _amountShares, 2e14);
        assertApproxEqAbs(_obtainedWant, _amountWant, 2e14);
    }

    function test_estimates_ShouldEstimateSecondDeposit() public {
        makeDeposit(alice, ETH, 0.55e18);
        (uint256 _amountShares, uint256 _amountWant) =
            pendleVault.estimateDeposit(ETH, 0.55e18, 12, hex"", getRewardData(0));
        uint256 _sharesBefore = pendleVault.userShares(alice);
        uint256 _wantBefore = pendleVault.balance();
        makeDeposit(alice, ETH, 0.55e18);
        uint256 _obtainedShares = pendleVault.userShares(alice) - _sharesBefore;
        uint256 _obtainedWant = pendleVault.balance() - _wantBefore;
        assertGe(_obtainedShares, _amountShares);
        assertGe(_obtainedWant, _amountWant);
        assertApproxEqAbs(_obtainedShares, _amountShares, 2e14);
        assertApproxEqAbs(_obtainedWant, _amountWant, 2e14);
    }

    function test_estimates_ShouldEstimateDepositAndRewardInToken() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);

        bytes memory _rewardData = getRewardData(10);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        deal(PENDLE, address(pendleStrategy), 10e18, true);
        assertApproxEqAbs(_withdrawalEstimation.depositInToken, 1000e6, 0.6e17);
        assertApproxEqAbs(_withdrawalEstimation.rewardsInToken, 9e6, 8e5);

        assertGt(_withdrawalEstimation.depositInToken, _withdrawalEstimation.depositInTokenAfterFee);
        assertGt(_withdrawalEstimation.rewardsInToken, _withdrawalEstimation.rewardsInTokenAfterFee);
    }

    function test_estimates_ShouldEstimateAmountsInTokenEqualWhenNoFees() public {
        vm.startPrank(adminStructure.superAdmin());
        feeManager.setFee(address(pendleStrategy), IFeeManager.FeeType.MANAGEMENT, managementFeeRecipient, 0);
        feeManager.setFee(address(pendleStrategy), IFeeManager.FeeType.PERFORMANCE, performanceFeeRecipient, 0);

        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);

        bytes memory _rewardData = getRewardData(10);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        deal(PENDLE, address(pendleStrategy), 10e18, true);

        assertEq(_withdrawalEstimation.depositInToken, _withdrawalEstimation.depositInTokenAfterFee);
        assertEq(_withdrawalEstimation.rewardsInToken, _withdrawalEstimation.rewardsInTokenAfterFee);
    }

    function test_estimates_ShouldEstimateAmountsDepositAndRewards() public {
        vm.startPrank(adminStructure.superAdmin());
        feeManager.setFee(address(pendleStrategy), IFeeManager.FeeType.MANAGEMENT, managementFeeRecipient, 0);
        feeManager.setFee(address(pendleStrategy), IFeeManager.FeeType.PERFORMANCE, performanceFeeRecipient, 0);

        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);

        bytes memory _rewardData = getRewardData(10);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        deal(PENDLE, address(pendleStrategy), 10e18, true);

        uint256 _sharesToWithdraw = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _rewardData, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        uint256 _minTokenOut = 997_814_737; // 997.8 - 0,31% Pendle Fee
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);
        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;

        assertApproxEqAbs(
            _withdrawalEstimation.depositInToken + _withdrawalEstimation.rewardsInToken, _obtainedAmount, 3e6
        );
    }

    function test_general_ShouldCompoundWithNoPreviousDeposit() public {
        deal(PENDLE, address(pendleStrategy), 100e18, true);
        uint256 balanceBefore = pendleVault.balance();
        pendleStrategy.compound(hex"");
        uint256 balanceAfter = pendleVault.balance();
        assertGt(balanceAfter, balanceBefore);
    }

    function test_general_ShouldCompoundWithDeposit() public {
        makeDeposit(alice, USDC, 1000e6);

        deal(PENDLE, address(pendleStrategy), 100e18, true);
        uint256 balanceBefore = pendleVault.balance();
        pendleStrategy.compound(hex"");
        uint256 balanceAfter = pendleVault.balance();
        assertGt(balanceAfter, balanceBefore);
    }

    function test_general_ShouldNotFailToCompoundWithNewRewardToken() public {
        uint256 balanceBefore = pendleVault.balance();
        deal(PENDLE, address(pendleStrategy), 100e18, true);
        address[] memory _rewardTokens = new address[](2);
        _rewardTokens[0] = OETH;
        _rewardTokens[1] = PENDLE;
        vm.mockCall(PENDLE_MARKET, abi.encodeWithSelector(IMarket.getRewardTokens.selector), abi.encode(_rewardTokens));
        pendleStrategy.compound(hex"");
        uint256 balanceAfter = pendleVault.balance();
        assertGt(balanceAfter, balanceBefore);
    }

    function test_general_convertTargetToWant() public {
        uint256 _amountTarget = 1e18;
        uint256 _obtained = pendleCalculations.convertTargetToWant(_amountTarget);
        assertApproxEqAbs(_obtained, 0.4986 ether, 1e14 ether);
    }

    function test_general_convertWantToTarget() public {
        uint256 _amountWant = 1e18;
        uint256 _obtained = pendleCalculations.convertWantToTarget(_amountWant);
        assertApproxEqAbs(_obtained, 2 ether, 1e14 ether);
    }

    function test_general_FailsToDepositLessThanMinDepositLimit() public {
        vm.startPrank(alice);
        uint256 depositAmount = 1;
        bytes memory revertReason =
            abi.encodeWithSelector(VaultErrors.InvalidDepositAmount.selector, USDC, depositAmount);
        vm.expectRevert(revertReason);
        pendleVault.deposit(alice, USDC, depositAmount, hex"");
    }

    // Validates that the withdrawals pay the performance and management fees
    function test_ShouldChargeBothFees() public {
        IERC20Upgradeable token = usdc;
        uint256 balancePerformanceFeeRecipientBefore = token.balanceOf(performanceFeeRecipient);
        uint256 managementFeeRecipientBefore = token.balanceOf(managementFeeRecipient);
        makeDeposit(alice, address(token), 1000e6);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, USDC);

        uint256 _balanceAliceBefore = token.balanceOf(alice);
        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(1000e6, slippage), 1000);
        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage), 1000);
        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 3e6);
        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);

        uint256 _wantToWithdraw = _withdrawalEstimation.wantDepositAfterFee + _withdrawalEstimation.wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(uint256(998_000_000), slippage); // _minTokenOut
        IFeeManager.FeeType feeType1 = IFeeManager.FeeType.MANAGEMENT;
        IFeeManager.FeeType feeType2 = IFeeManager.FeeType.PERFORMANCE;
        vm.expectEmit(true, false, true, false, address(pendleStrategy));
        emit ChargedFees(feeType1, 0, managementFeeRecipient, address(token));
        vm.expectEmit(true, false, true, false, address(pendleStrategy));
        emit ChargedFees(feeType2, 0, performanceFeeRecipient, address(token));

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);

        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 balancePerformanceFeeRecipientAfter = token.balanceOf(performanceFeeRecipient);
        uint256 managementFeeRecipientAfter = token.balanceOf(managementFeeRecipient);
        assertGt(balancePerformanceFeeRecipientAfter, balancePerformanceFeeRecipientBefore);
        assertGt(managementFeeRecipientAfter, managementFeeRecipientBefore);

        assertApproxEqAbs(
            token.balanceOf(alice) - _balanceAliceBefore,
            _withdrawalEstimation.depositInTokenAfterFee + _withdrawalEstimation.rewardsInTokenAfterFee,
            4e6
        );
    }

    // Validates that the withdrawals pay zero fees if they are set to 0%
    function test_ShouldChargeZeroFees() public {
        vm.prank(address(adminStructure.superAdmin()));
        feeManager.setFee(address(pendleStrategy), IFeeManager.FeeType.MANAGEMENT, address(this), 0);
        vm.prank(address(adminStructure.superAdmin()));
        feeManager.setFee(address(pendleStrategy), IFeeManager.FeeType.PERFORMANCE, address(this), 0);

        IERC20Upgradeable token = usdc;
        uint256 balancePerformanceFeeRecipientBefore = token.balanceOf(performanceFeeRecipient);
        uint256 managementFeeRecipientBefore = token.balanceOf(managementFeeRecipient);
        makeDeposit(alice, address(token), 1000e6);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, USDC);

        uint256 _balanceAliceBefore = token.balanceOf(alice);
        uint256 _expectedAfterManagementFee = _minusPercentage(1000e6, slippage);
        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage);

        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 3.2e6);
        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);

        uint256 _wantToWithdraw = _withdrawalEstimation.wantDepositAfterFee + _withdrawalEstimation.wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(998_000_000, slippage);
        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 balancePerformanceFeeRecipientAfter = token.balanceOf(performanceFeeRecipient);
        uint256 managementFeeRecipientAfter = token.balanceOf(managementFeeRecipient);
        assertEq(balancePerformanceFeeRecipientAfter, balancePerformanceFeeRecipientBefore);
        assertEq(managementFeeRecipientAfter, managementFeeRecipientBefore);

        assertApproxEqAbs(
            token.balanceOf(alice) - _balanceAliceBefore,
            _withdrawalEstimation.depositInTokenAfterFee + _withdrawalEstimation.rewardsInTokenAfterFee,
            4e6
        );
    }

    // Allows to withdraw using a recipient address
    function test_ShouldWithdrawUsingARecipient() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
        uint256 _sharesToWithdraw = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, getRewardData(0), true);
        uint256 _minTokenOut = 997_814_737; // 997,8 - 0,31% Pendle Fee
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        address _recipient = address(98_998);
        uint256 _balanceBeforeAlice = token.balanceOf(alice);
        uint256 _balanceBeforeRecipient = token.balanceOf(_recipient);
        pendleVault.withdraw(_recipient, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        uint256 _obtainedAmountAlice = token.balanceOf(alice) - _balanceBeforeAlice;
        uint256 _obtainedAmountRecipient = token.balanceOf(_recipient) - _balanceBeforeRecipient;
        // =====================================
        // ============ Validations ============
        // =====================================
        assertEq(_obtainedAmountAlice, 0); // Didn't obtain more token
        assertGe(_obtainedAmountRecipient, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmountRecipient, _minusPercentage(_minTokenOut, 1000), 2e6);
        // Alice doesn't keep the shares after withdrawal
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);
    }

    // Estimates all users rewards
    function test_estimatesAllUsersRewards() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
        makeDeposit(bob, address(token), 1000e6);
        slippage = 0; // Setting 0 slippage
        // Estimate the want for the single user who deposited (Alice)
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAlice =
            pendleVault.estimateWithdrawal(alice, slippage, getRewardData(10), USDC);

        // Estimate the want for the single user who deposited (Bob)
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationBob =
            pendleVault.estimateWithdrawal(bob, slippage, getRewardData(10), USDC);

        // Estimate the want for all the users who deposited
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAll =
            pendleVault.estimateWithdrawal(address(pendleStrategy), slippage, getRewardData(10), USDC);

        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(2000e6, slippage), 1000);
        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 10e18), slippage), 1000);

        assertApproxEqAbs(
            _withdrawalEstimationAlice.wantDeposit + _withdrawalEstimationBob.wantDeposit,
            _withdrawalEstimationAll.wantDeposit,
            1e1
        );
        assertApproxEqAbs(
            _withdrawalEstimationAlice.wantRewards + _withdrawalEstimationBob.wantRewards,
            _withdrawalEstimationAll.wantRewards,
            1e1
        );
        assertApproxEqAbs(
            _withdrawalEstimationAlice.wantDepositAfterFee + _withdrawalEstimationBob.wantDepositAfterFee,
            _withdrawalEstimationAll.wantDepositAfterFee,
            1e1
        );
        assertApproxEqAbs(
            _withdrawalEstimationAlice.wantRewardsAfterFee + _withdrawalEstimationBob.wantRewardsAfterFee,
            _withdrawalEstimationAll.wantRewardsAfterFee,
            1e1
        );

        assertApproxEqAbs(
            _expectedAfterManagementFee + _expectedAfterPerformanceFee,
            _withdrawalEstimationAll.depositInTokenAfterFee + _withdrawalEstimationAll.rewardsInTokenAfterFee,
            2.1e6
        );
    }

    // Estimates user want deposit correctly
    function test_estimatesWantDeposited() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
        makeDeposit(bob, address(token), 1000e6);

        bytes memory _rewardData = getRewardData(10);

        // Estimate the want for the single user who deposited (Alice)
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAlice =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(0));
        uint256 _wantDepositAlice1 = _withdrawalEstimationAlice.wantDeposit;

        // Estimate the want for the single user who deposited (Bob)
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationBob =
            pendleVault.estimateWithdrawal(bob, slippage, _rewardData, address(0));
        uint256 _wantDepositBob = _withdrawalEstimationBob.wantDeposit;

        assertEq(_wantDepositAlice1, pendleStrategy.userWantDeposit(alice));
        assertEq(_wantDepositBob, pendleStrategy.userWantDeposit(bob));
        assertEq(_wantDepositAlice1 + _wantDepositBob, pendleStrategy.totalWantDeposits());

        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAlice2 =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(0));
        uint256 _wantDepositAfterFee = _withdrawalEstimationAlice2.wantDepositAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee / 2;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(0, slippage);
        uint256 wantBefore = pendleVault.balance();
        vm.startPrank(alice);
        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        uint256 wantWithdrawn = wantBefore - pendleVault.balance();
        // Estimate the want for the single user who deposited (Alice)
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAlice3 =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(0));
        uint256 _wantDepositAlice2 = _withdrawalEstimationAlice3.wantDeposit;
        assertApproxEqAbs(_wantDepositAlice1 - _wantDepositAlice2, wantWithdrawn, 1e2);
        assertApproxEqAbs(_wantDepositAlice2 + _wantDepositBob, pendleStrategy.totalWantDeposits(), 1e2);
    }

    // Estimates user token deposit correctly
    function test_estimatesTokenDeposited() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
        makeDeposit(bob, address(token), 1000e6);

        bytes memory _rewardData = getRewardData(10);
        slippage = 0; // Setting 0 slippage

        // Estimate the token for the single user who deposited (Alice)
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAlice =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _tokenDepositAlice1 = _withdrawalEstimationAlice.depositInTokenAfterFee;

        // Estimate the token for the single user who deposited (Bob)
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationBob =
            pendleVault.estimateWithdrawal(bob, slippage, _rewardData, address(token));
        uint256 _tokenDepositBob = _withdrawalEstimationBob.depositInTokenAfterFee;

        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(1000e6, slippage), 1000);
        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 5e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimationAlice.depositInTokenAfterFee, _expectedAfterManagementFee, 2e6);
        assertApproxEqAbs(_withdrawalEstimationAlice.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);
        assertApproxEqAbs(_withdrawalEstimationBob.depositInTokenAfterFee, _expectedAfterManagementFee, 1e6);
        assertApproxEqAbs(_withdrawalEstimationBob.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);
        assertApproxEqAbs(_tokenDepositAlice1, _tokenDepositBob, 1e6);
    }

    function test_estimateWantAfterCompoundWithRewards() public {
        deal(WANT, address(pendleStrategy), 100e18, false);
        uint16 _slippageTolerance = 100; // 1%
        uint256 _simpleWantBefore = pendleVault.balance();
        uint256 _wantAfterCompound1 = pendleCalculations.estimateWantAfterCompound(_slippageTolerance, getRewardData(0));
        // Now rewards should be equal as normal balance want
        assertEq(_simpleWantBefore, _wantAfterCompound1);
        // Sending some tokens as rewards to the strategy
        deal(PENDLE, address(pendleStrategy), 100e18, false);
        uint256 _wantAfterCompound2 =
            pendleCalculations.estimateWantAfterCompound(_slippageTolerance, getRewardData(1000));
        uint256 _simpleWantAfter = pendleVault.balance();
        assertEq(_simpleWantBefore, _simpleWantAfter);
        assertGt(_wantAfterCompound2, _wantAfterCompound1);
    }

    function test_getPendingToCompound() public {
        // Before
        (
            uint256[] memory _rewardAmountsBefore,
            address[] memory _rewardTokensBefore,
            bool[] memory _enoughRewardsBefore,
            bool _atLeastOneBefore
        ) = pendleStrategy.getPendingToCompound(getRewardData(10));
        assertEq(_rewardAmountsBefore[0], 10e18);
        assertEq(_rewardTokensBefore[0], PENDLE);
        assertTrue(_enoughRewardsBefore[0]);
        assertTrue(_atLeastOneBefore);
        // After
        deal(WANT, address(pendleStrategy), 100e18, false);
        (
            uint256[] memory _rewardAmountsAfter,
            address[] memory _rewardTokensAfter,
            bool[] memory _enoughRewardsAfter,
            bool _atLeastOneAfter
        ) = pendleStrategy.getPendingToCompound(getRewardData(10));
        assertEq(_rewardAmountsAfter[0], 10e18);
        assertEq(_rewardTokensAfter[0], PENDLE);
        assertTrue(_enoughRewardsAfter[0]);
        assertTrue(_atLeastOneAfter);
    }

    // Calculates shares to withdraw with zero want
    function test_calculateSharesToWithdrawWithZeroWant() public {
        uint256 _userShares = pendleVault.calculateSharesToWithdraw(alice, 0, 1, getRewardData(0), false);
        assertEq(_userShares, 0);
    }

    // Gets User Max Want With Compound with some shares
    function test_compareUserMaxWantWithCompoundShares() public {
        makeDeposit(alice, USDC, 1000e6);
        deal(PENDLE, address(pendleStrategy), 90e18, true);
        uint256 _maxWantBeforeCompound = pendleVault.getUserMaxWant(alice);
        uint256 _maxWant1 = pendleVault.getUserMaxWantWithCompound(alice, 10, getRewardData(10));
        deal(PENDLE, address(pendleStrategy), 100e18, true);
        pendleStrategy.compound(hex"");
        uint256 _maxWantAfterCompoud = pendleVault.getUserMaxWant(alice);
        uint256 _maxWant2 = pendleVault.getUserMaxWantWithCompound(alice, 1, getRewardData(0));
        assertLt(_maxWantBeforeCompound, _maxWant1);
        assertLt(_maxWantBeforeCompound, _maxWantAfterCompoud);
        assertApproxEqAbs(_maxWant1, _maxWantAfterCompoud, 3e14);
        assertEq(_maxWantAfterCompoud, _maxWant2);
    }

    // Gets User Max Want With Compound with zero shares
    function test_getUserMaxWantWithCompoundWithZeroShares() public {
        uint256 _maxWant = pendleVault.getUserMaxWantWithCompound(alice, 1, getRewardData(0));
        assertEq(_maxWant, 0);
    }

    // Gets User Max Want With Compound with some shares
    function test_compareSharesToWantAfterCompound() public {
        makeDeposit(alice, address(usdc), 1000e6);
        uint256 _shares = 999_999;
        deal(PENDLE, address(pendleStrategy), 90e18, true);
        uint256 _wantObtainedBeforeCompound = pendleVault.sharesToWant(_shares);

        uint256 _wantAmount1 = pendleVault.sharesToWantAfterCompound(_shares, 1, getRewardData(10));
        deal(PENDLE, address(pendleStrategy), 100e18, true);

        pendleStrategy.compound(hex"");
        uint256 _wantObtainedAfterCompound = pendleVault.sharesToWant(_shares);
        uint256 _wantAmount2 = pendleVault.sharesToWantAfterCompound(_shares, 1, getRewardData(0));
        assertLt(_wantObtainedBeforeCompound, _wantAmount1);
        assertLt(_wantObtainedBeforeCompound, _wantObtainedAfterCompound);
        assertApproxEqAbs(_wantAmount1, _wantObtainedAfterCompound, 2e14);
        assertEq(_wantObtainedAfterCompound, _wantAmount2);
    }

    // Calculatates shares to want (without compound)
    function test_getSharesToWant() public {
        makeDeposit(alice, address(usdc), 1000e6);
        uint256 _shares = 999_999;
        uint256 _wantExpected =
            (_shares * IERC20Upgradeable(WANT).balanceOf(address(pendleStrategy))) / pendleVault.totalShares();
        uint256 _wantObtained = pendleVault.sharesToWant(_shares);
        assertEq(_wantExpected, _wantObtained);
    }

    // Calculatates want to shares (without compound)
    function test_getWantToShares() public {
        makeDeposit(alice, address(usdc), 1000e6);
        uint256 _want = 1e18;
        uint256 _sharesExpected =
            (_want * pendleVault.totalShares()) / IERC20Upgradeable(WANT).balanceOf(address(pendleStrategy));
        uint256 _sharesObtained = pendleVault.wantToShares(_want);
        assertEq(_sharesExpected, _sharesObtained);
    }

    // Fails to calculate Shares To Withdraw with invalid want
    function test_FailsToCalculateSharesToWithdrawWithInvalidWant() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.WantToWithdrawTooHigh.selector));
        bytes memory something = getRewardData(0);
        pendleVault.calculateSharesToWithdraw(alice, 1e18, 1, something, false);
    }

    // Fails to deposit with different value and token amount
    function test_ShouldFailToDepositWithDifferentValueAndAmount() public {
        address _token = ETH;
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.ValueAndAmountMismatch.selector));
        pendleVault.deposit{ value: 1 }(alice, _token, 1e6, getAdditionalDataDeposit(0));
    }

    // Allows to partially withdraw the deposited amount, it has no rewards, charges management fee (Eth)
    function test_FailsToUseAnInvalidETHRecipient() public {
        address token = address(0);
        makeDeposit(alice, token, 550_000_000_000_000_000);

        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(0);
        uint256 _minTokenOut = 274_680_055_471_891_946; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, token);
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantToWithdraw = _wantDepositAfterFee / 2;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        // Invalid recipient (missing receive() payable)
        address recipient = address(new EmptyMock());
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.ETHTransferError.selector));
        pendleVault.withdraw(recipient, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
    }

    // Fails to deposit if the minimum token out is not enought
    function test_ShouldFailToDepositIfMinTokenOutReached() public {
        CompoundVault _pendleVault = pendleVault;
        vm.startPrank(alice);
        address _token = USDC;
        uint256 _amount = 1e6;
        IERC20Upgradeable(_token).safeApprove(address(_pendleVault), type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));
        _pendleVault.deposit{ value: _token == address(0) ? _amount : 0 }(
            alice, _token, _amount, getAdditionalDataDeposit(1e18)
        );
    }

    // Fails to withdraw if the minimum token out is not enought
    function test_ShouldFailToWithdrawIfMinTokenOutReached() public {
        IERC20Upgradeable token = usdc;
        uint256 _depositAmount = 1000e6;
        makeDeposit(alice, address(token), 1000e6);

        uint256 _sharesToWithdraw = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, getRewardData(0), true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        uint256 _minTokenOut = _depositAmount * 2; // Making this big on purpose

        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));
        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, abi.encode(_minTokenOut, slippage));
    }

    //////////////////////////////////
    ////////////// USDC //////////////
    //////////////////////////////////

    // Allows to make a deposit with permit on the strategy (Usdc)
    function test_usdc_ShouldDepositOnPendleWithPermit() public {
        // =====================================
        // ======== Making a pre-deposit =======
        // =====================================
        IERC20Upgradeable token = usdc;
        vm.startPrank(alice);
        uint256 amount = 1000e6;
        Signature memory signature = signingUtils.signPermit(
            address(token), alice, alicePrivateKey, address(pendleVault), amount, block.timestamp + 100
        );
        // Intentionally not making an approval
        pendleVault.depositWithPermit(alice, address(token), amount, getAdditionalDataDeposit(0), signature);
        assertGt(pendleVault.userShares(alice), 0);
        assertGt(pendleVault.balance(), 0);
    }

    // Allows to make a deposit on the strategy (Usdc)
    function test_usdc_ShouldDepositOnPendle() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
    }

    // Allows to make a deposit on the strategy (Usdc) multiple times
    function test_usdc_ShouldDepositOnPendleMultipleTimes() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(bob, address(token), 1000e6);
        makeDeposit(alice, address(token), 1000e6);
        makeDeposit(bob, address(token), 1000e6);
        makeDeposit(alice, address(token), 1000e6);
    }

    // Estimates the same amount of shares when using withdraw all
    function test_usdc_EstimatesEqualShares() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee + _wantRewardsAfterFee;
        uint256 _userShares1 =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        uint256 _userShares2 = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _rewardData, true);
        assertEq(_userShares1, _userShares2);
    }

    // Allows to withdraw the entire deposited amount, it has no rewards, charges management fee (Usdc)
    // Using the flag to withdraw all
    function test_usdc_ShouldWithdrawAllDepositUsingWithdrawAllFlag() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        uint256 _sharesToWithdraw = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, getRewardData(0), true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        uint256 _minTokenOut = 997_814_737; // 997.8 - 0,31% Pendle Fee
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);
        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10% for the fee
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 2e6);
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);
    }

    // Allows to withdraw the entire deposited amount, it has no rewards, charges management fee (Usdc)
    function test_usdc_ShouldWithdrawAllDeposit() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(0);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));

        assertEq(_withdrawalEstimation.rewardsInTokenAfterFee, 0);

        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantToWithdraw = _wantDepositAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        uint256 _expectedDeposit = _minusPercentage(_minusPercentage(1000e6, slippage), 1000);

        uint256 _minTokenOut = 997_814_737; // 997.8
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAfter =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10% for the fee
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 2e6);
        assertApproxEqAbs(_obtainedAmount, _expectedDeposit, 1e6);
        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.depositInTokenAfterFee, 3e6);
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);
        assertEq(_withdrawalEstimationAfter.depositInTokenAfterFee, 0);
        assertEq(_withdrawalEstimationAfter.rewardsInTokenAfterFee, 0);
    }

    // Allows to partially withdraw the deposited amount, it has no rewards, charges management fee (Usdc)
    function test_usdc_ShouldWithdrawPartialDeposit() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);

        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(0);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _balanceWantBefore = pendleVault.balance();
        uint256 _minTokenOut = 498_907_865; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;

        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(1000e6, slippage), 1000);
        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 3e6);
        assertEq(_withdrawalEstimation.rewardsInTokenAfterFee, 0);
        uint256 _depositInToken = _withdrawalEstimation.depositInTokenAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee / 2;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 1e6);
        assertApproxEqAbs(_obtainedAmount, _depositInToken / 2, 2e6);
        // Checking withdrawal estimate
        assertApproxEqAbs(pendleVault.userShares(alice), _userSharesBefore / 2, 1e4);
        assertApproxEqAbs(pendleVault.balance(), _balanceWantBefore / 2, 1e4);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit / 2, 1e4);

        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.depositInTokenAfterFee / 2, 3e6);
    }

    // Allows to withdraw the all the deposit+rewards, charges management and performance fee (Usdc)
    function test_usdc_ShouldWithdrawAllDepositAndRewards() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        uint256 _minTokenOut = 1_156_929_272; // 0,31% Pendle Fee

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(1000e6, slippage), 1000);
        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 3e6);
        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);

        uint256 _wantToWithdraw = _wantDepositAfterFee + _wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 1042e6, 1e6);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);

        assertApproxEqAbs(
            _obtainedAmount,
            _withdrawalEstimation.depositInTokenAfterFee + _withdrawalEstimation.rewardsInTokenAfterFee,
            4e6
        );
    }

    // Allows to withdraw the all the rewards, keeps the deposit, charges performance fee (Usdc)
    function test_usdc_ShouldWithdrawAllRewardsOnly() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _minTokenOut = 158_740_733; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);

        uint256 _wantToWithdraw = _wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 143e6, 2e6);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), _userSharesBefore - _sharesToWithdraw);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit, 3.6e14);
        assertEq(pendleVault.balance(), pendleVault.getUserMaxWant(alice));
        assertApproxEqAbs(pendleVault.balance(), _wantDeposit, 3.6e14);

        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.rewardsInTokenAfterFee, 2e6);
    }

    // Allows to withdraw partial rewards, keeps the deposit, charges performance fee (Usdc)
    function test_usdc_ShouldWithdrawPartialRewards() public {
        IERC20Upgradeable token = usdc;
        makeDeposit(alice, address(token), 1000e6);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _minTokenOut = 79_370_000; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantRewards = _withdrawalEstimation.wantRewards;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee / 2, _expectedAfterPerformanceFee / 2, 1e6);

        uint256 _wantToWithdraw = _wantRewardsAfterFee / 2;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 715e5, 1e6);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), _userSharesBefore - _sharesToWithdraw);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit + (_wantRewardsAfterFee / 2), 3e15);
        assertEq(pendleVault.balance(), pendleVault.getUserMaxWant(alice));
        assertApproxEqAbs(pendleVault.balance(), _wantDeposit + (_wantRewards / 2), 3.9e14);

        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.rewardsInTokenAfterFee / 2, 2e6);
    }

    //////////////////////////////////
    ////////////// USDT //////////////
    //////////////////////////////////

    // Allows to make a deposit on the strategy (Usdt)
    function test_usdt_ShouldDepositOnPendle() public {
        IERC20Upgradeable token = usdt;
        makeDeposit(alice, address(token), 1000e6);
    }

    // Estimates the same amount of shares if there are no changes (Usdt)
    function test_usdt_estimatesEqualShares() public {
        IERC20Upgradeable token = usdt;
        makeDeposit(alice, address(token), 1000e6);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee + _wantRewardsAfterFee;
        uint256 _userShares1 =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        uint256 _userShares2 = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _rewardData, true);
        assertEq(_userShares1, _userShares2);
    }

    // Allows to withdraw the entire deposited amount, it has no rewards, charges management fee (Usdt)
    function test_usdt_ShouldWithdrawAllDeposit() public {
        IERC20Upgradeable token = usdt;
        makeDeposit(alice, address(token), 1000e6);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(0);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));

        assertEq(_withdrawalEstimation.rewardsInTokenAfterFee, 0);

        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantToWithdraw = _wantDepositAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        uint256 _expectedDeposit = _minusPercentage(_minusPercentage(1000e6, slippage), 1000);
        uint256 _minTokenOut = 996_671_484;
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10% for the fee
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 2e6);
        assertApproxEqAbs(_obtainedAmount, _expectedDeposit, 1e6);
        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.depositInTokenAfterFee, 3e6);
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);

        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAfter =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        assertEq(_withdrawalEstimationAfter.depositInTokenAfterFee, 0);
        assertEq(_withdrawalEstimationAfter.rewardsInTokenAfterFee, 0);
    }

    // Allows to partially withdraw the deposited amount, it has no rewards, charges management fee (Usdt)
    function test_usdt_ShouldWithdrawPartialDeposit() public {
        IERC20Upgradeable token = usdt;
        makeDeposit(alice, address(token), 1000e6);

        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(0);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _balanceWantBefore = pendleVault.balance();
        uint256 _minTokenOut = 498_468_907; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;

        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(1000e6, slippage), 1000);
        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 3e6);
        assertEq(_withdrawalEstimation.rewardsInTokenAfterFee, 0);
        uint256 _depositInToken = _withdrawalEstimation.depositInTokenAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee / 2;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 1e6);
        assertApproxEqAbs(_obtainedAmount, _depositInToken / 2, 2e6);
        // Checking withdrawal estimate
        assertApproxEqAbs(pendleVault.userShares(alice), _userSharesBefore / 2, 1e4);
        assertApproxEqAbs(pendleVault.balance(), _balanceWantBefore / 2, 1e4);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit / 2, 1e4);

        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.depositInTokenAfterFee / 2, 3e6);
    }

    // Allows to withdraw the all the deposit+rewards, charges management and performance fee (Usdt)
    function test_usdt_ShouldWithdrawAllDepositAndRewards() public {
        IERC20Upgradeable token = usdt;
        makeDeposit(alice, address(token), 1000e6);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        uint256 _minTokenOut = 1_156_072_893; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(1000e6, slippage), 1000);
        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 3e6);
        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);

        uint256 _wantToWithdraw = _wantDepositAfterFee + _wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 1042e6, 1e6);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);

        assertApproxEqAbs(
            _obtainedAmount,
            _withdrawalEstimation.depositInTokenAfterFee + _withdrawalEstimation.rewardsInTokenAfterFee,
            4e6
        );
    }

    // Allows to withdraw the all the rewards, keeps the deposit, charges performance fee (Usdt)
    function test_usdt_ShouldWithdrawAllRewardsOnly() public {
        IERC20Upgradeable token = usdt;
        makeDeposit(alice, address(token), 1000e6);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _minTokenOut = 157_000_000; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);

        uint256 _wantToWithdraw = _wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 143e6, 2e6);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), _userSharesBefore - _sharesToWithdraw);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit, 3.6e14);
        assertEq(pendleVault.balance(), pendleVault.getUserMaxWant(alice));
        assertApproxEqAbs(pendleVault.balance(), _wantDeposit, 3.6e14);

        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.rewardsInTokenAfterFee, 4e6);
    }

    //////////////////////////////////
    ////////////// WBTC //////////////
    //////////////////////////////////

    // Allows to make a deposit on the strategy (Wbtc)
    function test_wbtc_ShouldDepositOnPendle() public {
        IERC20Upgradeable token = wbtc;
        makeDeposit(alice, address(token), 2_895_400);
    }

    // Allows to make a deposit on the strategy (Wbtc) multiple times
    function test_wbtc_ShouldDepositOnPendleMultipleTimes() public {
        IERC20Upgradeable token = wbtc;

        makeDeposit(bob, address(token), 2_895_400);
        makeDeposit(bob, address(token), 2_895_400);
    }

    // Estimates the same amount of shares if there are no changes (Wbtc)
    function test_wbtc_estimatesEqualShares() public {
        IERC20Upgradeable token = wbtc;
        makeDeposit(alice, address(token), 2_895_400);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee + _wantRewardsAfterFee;
        uint256 _userShares1 =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        uint256 _userShares2 = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _rewardData, true);
        assertEq(_userShares1, _userShares2);
    }

    // Allows to withdraw the entire deposited amount, it has no rewards, charges management fee (Wbtc)
    function test_wbtc_ShouldWithdrawAllDeposit() public {
        IERC20Upgradeable token = wbtc;
        makeDeposit(alice, address(token), 2_895_400);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        slippage = 50;

        bytes memory _rewardData = getRewardData(0);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));

        assertEq(_withdrawalEstimation.rewardsInTokenAfterFee, 0);

        uint256 _sharesToWithdraw = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, getRewardData(0), true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        uint256 _expectedDeposit = _minusPercentage(_minusPercentage(2_895_400, slippage), 1000);
        uint256 _minTokenOut = 2_885_330; // 998 - 0,31% Pendle Fee
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10% for the fee
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 4e4);
        assertApproxEqAbs(_obtainedAmount, _expectedDeposit, 8e3);
        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.depositInTokenAfterFee, 17e3);
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);

        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAfter =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        assertEq(_withdrawalEstimationAfter.depositInTokenAfterFee, 0);
        assertEq(_withdrawalEstimationAfter.rewardsInTokenAfterFee, 0);
    }

    // Allows to partially withdraw the deposited amount, it has no rewards, charges management fee (Wbtc)
    function test_wbtc_ShouldWithdrawPartialDeposit() public {
        IERC20Upgradeable token = wbtc;
        makeDeposit(alice, address(token), 2_895_400);

        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        slippage = 50;
        bytes memory _rewardData = getRewardData(0);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _balanceWantBefore = pendleVault.balance();
        uint256 _minTokenOut = 1_443_080; // 0,31% Pendle Fee

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;

        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(2_895_400, slippage), 1000);
        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 1e4);
        assertEq(_withdrawalEstimation.rewardsInTokenAfterFee, 0);
        uint256 _depositInToken = _withdrawalEstimation.depositInTokenAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee / 2;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 1e6);
        assertApproxEqAbs(_obtainedAmount, _depositInToken / 2, 2e6);
        // Checking withdrawal estimate
        assertApproxEqAbs(pendleVault.userShares(alice), _userSharesBefore / 2, 1e4);
        assertApproxEqAbs(pendleVault.balance(), _balanceWantBefore / 2, 1e4);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit / 2, 1e4);

        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.depositInTokenAfterFee / 2, 1e4);
    }

    // Allows to withdraw the all the deposit+rewards, charges management and performance fee (Wbtc)
    function test_wbtc_ShouldWithdrawAllDepositAndRewards() public {
        IERC20Upgradeable token = wbtc;
        makeDeposit(alice, address(token), 2_895_400);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        slippage = 50;
        bytes memory _rewardData = getRewardData(10);
        uint256 _minTokenOut = 3_345_496; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterManagementFee = _minusPercentage(_minusPercentage(2_895_400, slippage), 1000);
        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 9e3);
        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 7e3);

        uint256 _wantToWithdraw = _wantDepositAfterFee + _wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 3_016_594, 1.8e4);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);

        assertApproxEqAbs(
            _obtainedAmount,
            _withdrawalEstimation.depositInTokenAfterFee + _withdrawalEstimation.rewardsInTokenAfterFee,
            1.9e4
        );
    }

    // Allows to withdraw the all the rewards, keeps the deposit, charges performance fee (Wbtc)
    function test_wbtc_ShouldWithdrawAllRewardsOnly() public {
        IERC20Upgradeable token = wbtc;
        makeDeposit(alice, address(token), 2_895_400);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        slippage = 50;
        bytes memory _rewardData = getRewardData(10);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _minTokenOut = 459_149; // 0,31% Pendle Fee

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, address(token), 179e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 1e6);

        uint256 _wantToWithdraw = _wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = token.balanceOf(alice);

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = token.balanceOf(alice) - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 413_235, 1e6);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), _userSharesBefore - _sharesToWithdraw);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit, 3e14);
        assertEq(pendleVault.balance(), pendleVault.getUserMaxWant(alice));
        assertApproxEqAbs(pendleVault.balance(), _wantDeposit, 3e14);
        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.rewardsInTokenAfterFee, 2.6e3);
    }

    //////////////////////////////////
    ////////////// ETH //////////////
    /////////////////////////////////

    // Allows to make a deposit on the strategy (Eth)
    function test_eth_ShouldDepositOnPendle() public {
        address token = address(0);
        makeDeposit(alice, token, 550_000_000_000_000_000);
    }

    // Allows to make multiple deposits on the strategy (Eth)
    function test_eth_ShouldDepositOnPendleMultipleTimes() public {
        address token = address(0);
        makeDeposit(alice, token, 550_000_000_000_000_000);
        makeDeposit(alice, token, 550_000_000_000_000_000);
        makeDeposit(alice, token, 550_000_000_000_000_000);
        makeDeposit(alice, token, 550_000_000_000_000_000);
    }

    // Estimates the same amount of shares if there are no changes (Eth)
    function test_eth_EstimatesEqualShares() public {
        address token = address(0);
        makeDeposit(alice, token, 550_000_000_000_000_000);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee + _wantRewardsAfterFee;
        uint256 _userShares1 =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        uint256 _userShares2 = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, _rewardData, true);
        assertEq(_userShares1, _userShares2);
    }

    // Allows to withdraw the entire deposited amount, it has no rewards, charges management fee (Eth)
    function test_eth_ShouldWithdrawAllDeposit() public {
        address token = address(0);
        makeDeposit(alice, token, 550_000_000_000_000_000);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(0);
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));

        assertEq(_withdrawalEstimation.rewardsInTokenAfterFee, 0);

        uint256 _sharesToWithdraw = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, getRewardData(0), true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        uint256 _expectedDeposit = _minusPercentage(_minusPercentage(550_000_000_000_000_000, slippage), 1000);
        uint256 _minTokenOut = 549_359_879_624_071_145;
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = alice.balance;

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        ICalculations.WithdrawalEstimation memory _withdrawalEstimationAfter =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _obtainedAmount = alice.balance - _balanceBefore;
        // Obtained must be >= the minimum minius 10% for the fee
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 2e6);
        assertApproxEqAbs(_obtainedAmount, _expectedDeposit, 5e14, "1");
        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.depositInTokenAfterFee, 2e15, "2");
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);
        assertEq(_withdrawalEstimationAfter.depositInTokenAfterFee, 0);
        assertEq(_withdrawalEstimationAfter.rewardsInTokenAfterFee, 0);
    }

    // Allows to partially withdraw the deposited amount, it has no rewards, charges management fee (Eth)
    function test_eth_ShouldWithdrawPartialDeposit() public {
        address token = address(0);
        makeDeposit(alice, token, 550_000_000_000_000_000);

        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(0);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _balanceWantBefore = pendleVault.balance();
        uint256 _minTokenOut = 274_680_055_471_891_946; // 0,31% Pendle Fee

        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;

        uint256 _expectedAfterManagementFee =
            _minusPercentage(_minusPercentage(550_000_000_000_000_000, slippage), 1000);
        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 1.5e15);
        assertEq(_withdrawalEstimation.rewardsInTokenAfterFee, 0);
        uint256 _depositInToken = _withdrawalEstimation.depositInTokenAfterFee;

        uint256 _wantToWithdraw = _wantDepositAfterFee / 2;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = alice.balance;

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = alice.balance - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, _minusPercentage(_minTokenOut, 1000), 1e6);
        assertApproxEqAbs(_obtainedAmount, _depositInToken / 2, 1e15);

        // Checking withdrawal estimate
        assertApproxEqAbs(pendleVault.userShares(alice), _userSharesBefore / 2, 1e4);
        assertApproxEqAbs(pendleVault.balance(), _balanceWantBefore / 2, 1e4);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit / 2, 1e4);

        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.depositInTokenAfterFee / 2, 1e15);
    }

    // Allows to withdraw the all the deposit+rewards, charges management and performance fee (Eth)
    function test_eth_ShouldWithdrawAllDepositAndRewards() public {
        address token = address(0);
        makeDeposit(alice, token, 550_000_000_000_000_000);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        uint256 _minTokenOut = 637_537_387_242_727_687; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDepositAfterFee = _withdrawalEstimation.wantDepositAfterFee;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterManagementFee =
            _minusPercentage(_minusPercentage(550_000_000_000_000_000, slippage), 1000);
        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, WETH, 179e18), slippage), 1000);

        assertApproxEqAbs(_withdrawalEstimation.depositInTokenAfterFee, _expectedAfterManagementFee, 1.5e15);
        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 5e14);

        uint256 _wantToWithdraw = _wantDepositAfterFee + _wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = alice.balance;
        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = alice.balance - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 0.574e18, 2.2e14);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), 0);
        assertEq(pendleVault.balance(), 0);

        assertApproxEqAbs(
            _obtainedAmount,
            _withdrawalEstimation.depositInTokenAfterFee + _withdrawalEstimation.rewardsInTokenAfterFee,
            2.5e15
        );
    }

    // Allows to withdraw the all the rewards, keeps the deposit, charges performance fee (Eth)
    function test_eth_ShouldWithdrawAllRewardsOnly() public {
        address token = address(0);
        makeDeposit(alice, token, 550_000_000_000_000_000);

        // Sending some tokens to trigger a compound, aprox 115 USD
        deal(PENDLE, address(pendleStrategy), 169e18, true);
        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        bytes memory _rewardData = getRewardData(10);
        uint256 _userSharesBefore = pendleVault.userShares(alice);
        uint256 _minTokenOut = 88_436_842_209_118_096; // 0,31% Pendle Fee
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, _rewardData, address(token));
        uint256 _wantDeposit = _withdrawalEstimation.wantDeposit;
        uint256 _wantRewardsAfterFee = _withdrawalEstimation.wantRewardsAfterFee;

        uint256 _expectedAfterPerformanceFee =
            _minusPercentage(_minusPercentage(strategyHelper.convert(PENDLE, WETH, 179e18), slippage), 1000);
        assertApproxEqAbs(_withdrawalEstimation.rewardsInTokenAfterFee, _expectedAfterPerformanceFee, 5e14);

        uint256 _wantToWithdraw = _wantRewardsAfterFee;
        uint256 _sharesToWithdraw =
            pendleVault.calculateSharesToWithdraw(alice, _wantToWithdraw, slippage, _rewardData, false);
        deal(PENDLE, address(pendleStrategy), 179e18, true);
        // =====================================
        // ======== Withdraw all funds =========
        // =====================================
        _additionalDataWithdrawal = abi.encode(_minTokenOut, slippage);
        uint256 _balanceBefore = alice.balance;

        pendleVault.withdraw(alice, address(token), _sharesToWithdraw, _additionalDataWithdrawal);
        // =====================================
        // ============ Validations ============
        // =====================================
        uint256 _obtainedAmount = alice.balance - _balanceBefore;
        // Obtained must be >= the minimum minius 10%
        assertGe(_obtainedAmount, _minusPercentage(_minTokenOut, 1000));
        // Obtained must be close to the minimum minius 10%
        assertApproxEqAbs(_obtainedAmount, 0.07964e18, 3.6e14);
        // Checking withdrawal estimate
        assertEq(pendleVault.userShares(alice), _userSharesBefore - _sharesToWithdraw);
        assertApproxEqAbs(pendleVault.getUserMaxWant(alice), _wantDeposit, 3.6e14);
        assertEq(pendleVault.balance(), pendleVault.getUserMaxWant(alice));
        assertApproxEqAbs(pendleVault.balance(), _wantDeposit, 3.6e14);

        assertApproxEqAbs(_obtainedAmount, _withdrawalEstimation.rewardsInTokenAfterFee, 4e14);
    }

    //////////////////////////////////
    //////// COMBINED TOKENS /////////
    //////////////////////////////////

    // Allows to make a deposit on the strategy using all tokens (Usdc, Eth, Wbtc, Usdt)
    function test_combinedTokens_ShouldDepositOnPendleUsdcEthWbtcUsdt() public {
        uint256 _sharesBalance1 = pendleVault.userShares(alice);
        assertEq(_sharesBalance1, 0);
        makeDeposit(alice, address(usdc), 1000e6);
        uint256 _sharesBalance2 = pendleVault.userShares(alice);
        uint256 _addedShares2 = _sharesBalance2 - _sharesBalance1;
        makeDeposit(alice, address(0), 550_000_000_000_000_000);
        uint256 _sharesBalance3 = pendleVault.userShares(alice);
        uint256 _addedShares3 = _sharesBalance3 - _sharesBalance2;
        makeDeposit(alice, address(wbtc), 2_895_400);
        uint256 _sharesBalance4 = pendleVault.userShares(alice);
        uint256 _addedShares4 = _sharesBalance4 - _sharesBalance3;
        makeDeposit(alice, address(usdt), 1000e6);
        uint256 _sharesBalance5 = pendleVault.userShares(alice);
        uint256 _addedShares5 = _sharesBalance5 - _sharesBalance4;
        assertApproxEqAbs(_addedShares2, _addedShares3, 4e17);
        assertApproxEqAbs(_addedShares3, _addedShares4, 4e17);
        assertApproxEqAbs(_addedShares4, _addedShares5, 4e17);
    }

    // Allows to make a deposit on the strategy using all tokens and different users
    // Alice (Usdc + Eth) Bob (Wbtc + Usdt)
    function test_combinedTokens_ShouldDepositOnPendleMultipleTokensAndUsers() public {
        // Alice Eth
        uint256 _sharesBalanceAlice1 = pendleVault.userShares(alice);
        assertEq(_sharesBalanceAlice1, 0);
        makeDeposit(alice, address(0), 550_000_000_000_000_000);
        uint256 _sharesBalanceAlice2 = pendleVault.userShares(alice);
        uint256 _addedShares2 = _sharesBalanceAlice2 - _sharesBalanceAlice1;
        // Alice Usdc
        makeDeposit(alice, address(usdc), 1000e6);
        uint256 _sharesBalanceAlice3 = pendleVault.userShares(alice);
        uint256 _addedShares3 = _sharesBalanceAlice3 - _sharesBalanceAlice2;
        // Bob Wbtc
        uint256 _sharesBalanceBob1 = pendleVault.userShares(bob);
        assertEq(_sharesBalanceBob1, 0);
        makeDeposit(bob, address(wbtc), 2_895_400);
        uint256 _sharesBalanceBob2 = pendleVault.userShares(bob);
        uint256 _addedShares4 = _sharesBalanceBob2 - _sharesBalanceBob1;
        // Bob Usdt
        makeDeposit(bob, address(usdt), 1000e6);
        uint256 _sharesBalanceBob3 = pendleVault.userShares(bob);
        uint256 _addedShares5 = _sharesBalanceBob3 - _sharesBalanceBob2;
        assertApproxEqAbs(_addedShares2, _addedShares3, 4e17);
        assertApproxEqAbs(_addedShares3, _addedShares4, 4e17);
        assertApproxEqAbs(_addedShares4, _addedShares5, 4e17);
    }

    // Allows to make a deposit on the strategy using all Usdc and withdraw Eth
    function test_combinedTokens_ShouldDepositUsdcWithdrawEth() public {
        makeDeposit(alice, address(usdc), 1000e6);

        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, getRewardData(10), ETH);

        uint256 _balanceAliceBefore = alice.balance;

        uint256 _sharesToWithdraw = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, getRewardData(10), true);

        deal(PENDLE, address(pendleStrategy), 10e18, true);

        _additionalDataWithdrawal = abi.encode(uint256(0), slippage); // _minTokenOut

        pendleVault.withdraw(alice, ETH, _sharesToWithdraw, _additionalDataWithdrawal);

        assertApproxEqAbs(
            alice.balance - _balanceAliceBefore,
            _withdrawalEstimation.depositInTokenAfterFee + _withdrawalEstimation.rewardsInTokenAfterFee,
            2e15 // $4
        );
    }

    // Allows to make a deposit on the strategy using all Usdc and withdraw Eth
    function test_combinedTokens_ShouldDepositEthWithdrawWbtc() public {
        address token = address(0); // WETH
        makeDeposit(alice, token, 550_000_000_000_000_000);

        // =====================================
        // ====== Withdrawable estimation ======
        // =====================================
        slippage = 50;
        ICalculations.WithdrawalEstimation memory _withdrawalEstimation =
            pendleVault.estimateWithdrawal(alice, slippage, getRewardData(10), WBTC);

        uint256 _balanceAliceBefore = IERC20Upgradeable(WBTC).balanceOf(alice);
        uint256 _sharesToWithdraw = pendleVault.calculateSharesToWithdraw(alice, 0, slippage, getRewardData(10), true);

        deal(PENDLE, address(pendleStrategy), 10e18, true);

        _additionalDataWithdrawal = abi.encode(uint256(0), slippage); // _minTokenOut

        pendleVault.withdraw(alice, WBTC, _sharesToWithdraw, _additionalDataWithdrawal);
        assertApproxEqAbs(
            IERC20Upgradeable(WBTC).balanceOf(alice) - _balanceAliceBefore,
            _withdrawalEstimation.depositInTokenAfterFee + _withdrawalEstimation.rewardsInTokenAfterFee,
            1.7e4
        );
    }

    function getRewardData(uint256 _multiplier) public pure returns (bytes memory _rewardData) {
        address[] memory _rewardTokens = new address[](1);
        uint256[] memory _rewardAmounts = new uint256[](1);

        _rewardTokens[0] = PENDLE;
        _rewardAmounts[0] = 1e18 * _multiplier;

        return abi.encode(_rewardTokens, _rewardAmounts);
    }

    function getAdditionalDataDeposit(uint256 _minLPOut) public returns (bytes memory) {
        _additionalDataDeposit = abi.encode(_minLPOut, slippage);

        return _additionalDataDeposit;
    }

    function printGas(address _token, string memory _methodName, uint256 _gasUsed) public view {
        console.log("DepositCount:", depositCount);

        if (_token == address(USDC)) {
            console2.log("++ USDC", _methodName, "GasUsed:", _gasUsed);
        } else if (_token == address(USDT)) {
            console2.log("++ USDT", _methodName, "GasUsed:", _gasUsed);
        } else if (_token == address(ETH)) {
            console2.log("++ ETH", _methodName, "GasUsed:", _gasUsed);
        } else if (_token == address(WBTC)) {
            console2.log("++ WBTC", _methodName, "GasUsed:", _gasUsed);
        } else {
            revert("Test: Token not recognized");
        }
    }

    function _minusPercentage(uint256 _amount, uint256 _percentage) internal view returns (uint256) {
        return _amount - ((_amount * _percentage) / pendleStrategy.ONE_HUNDRED_PERCENTS());
    }

    function setLabels() public {
        vm.label(alice, "Alice");
        vm.label(address(pendleVault), "PendleVault");
        vm.label(address(strategyHelper), "StrategyHelper");
        vm.label(address(pendleStrategy), "PendleLSDStrategy");
        vm.label(address(feeManager), "FeeManager");
        vm.label(ADMIN_STRUCTURE, "ADMIN_STRUCTURE");
        vm.label(USDC, "USDC");
        vm.label(OETH, "OETH");
        vm.label(WETH, "WETH");
        vm.label(PENDLE_ROUTER, "PENDLE_ROUTER");
        vm.label(PENDLE_MARKET, "PENDLE_MARKET");
        vm.label(PENDLE, "PENDLE");
        vm.label(SUPER_ADMIN, "SUPER_ADMIN");
    }
}

contract EmptyMock { }
