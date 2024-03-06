// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { PendleLSDCalculations } from "src/calculations/pendle/PendleLSDCalculations.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { IMarket, ISyToken } from "src/strategies/pendle/interfaces/IPendle.sol";
import { PendleStrategyV2 } from "src/strategies/pendle/PendleStrategyV2.sol";
import { OracleBalancerWeighted } from "src/oracles/OracleBalancerWeighted.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { FeeManager } from "src/FeeManager.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import "../../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract PendleStrategyV2Mock is PendleStrategyV2 {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(InitParams calldata _initParams) external initializer {
        _pendleStrategyInitUnchained(_initParams);
    }

    function _getTargetToken(address, address, uint256 _amountIn, uint16) internal pure override returns (uint256) {
        return _amountIn;
    }

    function _getUserToken(address, address, uint256 _amountIn, uint16) internal pure override returns (uint256) {
        return _amountIn;
    }

    function _getWETHToken(address, uint256 _amountIn, uint16) internal pure override returns (uint256) {
        return _amountIn;
    }
}

contract PendleStrategyV2Test is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;
    address public constant SUPER_ADMIN = 0xB9E3d56C934E89418E294466764D5d19Ac36334B;

    PendleStrategyV2Mock public pendleStrategy;
    CompoundVault public pendleVault;
    StrategyHelper public strategyHelper;
    FeeManager public feeManager;
    IAdminStructure public adminStructure;
    PendleLSDCalculations public pendleCalculations;

    address public token1;
    address public token2;

    IMarket public pendleMarket;
    address public want;

    address[] public depositAllowedTokens;
    address[] public withdrawalAllowedTokens;

    address public performanceFeeRecipient = makeAddr("PerformanceFeeRecipient");
    address public managementFeeRecipient = makeAddr("ManagementFeeRecipient");

    address[] public tokensToCompound = [PENDLE];
    uint256[] public minimumsToCompound = [1e18];

    uint16 public slippage;
    uint32 public pendleOracleTwapPeriod = 1800;
    uint256 public depositCount;

    uint256 constant TOKENIN1_DEPOSIT_LIMIT = 1e2;
    uint256 constant TOKENIN2_DEPOSIT_LIMIT = 1e2;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 19_036_693);

        // TODO make it generic
        // deploy pendle market mock
        // get want address from it

        pendleMarket = IMarket(0xF32e58F92e60f4b0A37A69b95d642A471365EAe8);
        want = 0x62187066FD9C24559ffB54B0495a304ADe26d50B;

        // TODO make it generic
        // deploy tokens
        // token1 = address(new ERC20Upgradeable());
        // token2 = address(new ERC20Upgradeable());

        token1 = ETH;
        token2 = WETH;

        depositAllowedTokens = [token1, token2];
        withdrawalAllowedTokens = [token1, token2];

        slippage = 20; // Slippage for the tests 0.2%
        adminStructure = IAdminStructure(ADMIN_STRUCTURE);

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
            want: want,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: address(pendleMarket),
            twapPeriod: pendleOracleTwapPeriod,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });
        Proxy pendleStrategyProxy = new Proxy(
            address(new PendleStrategyV2Mock()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
        pendleStrategy = PendleStrategyV2Mock(payable(address(pendleStrategyProxy)));

        // =================================
        // ======== Strategy Vault =========
        // =================================
        IVault.DepositLimit[] memory _depositLimits = new IVault.DepositLimit[](2);

        _depositLimits[0] = IVault.DepositLimit(address(token1), TOKENIN1_DEPOSIT_LIMIT);
        _depositLimits[1] = IVault.DepositLimit(address(token2), TOKENIN2_DEPOSIT_LIMIT);

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

        pendleCalculations.setStrategyValues(address(pendleStrategy));

        vm.stopPrank();
    }

    // Allows to intialize the variables
    function test_initialize_Success() public {
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: want,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: address(pendleMarket),
            twapPeriod: pendleOracleTwapPeriod,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });
        Proxy pendleStrategyProxy = new Proxy(
            address(new PendleStrategyV2Mock()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,uint32,address[],uint256[]))",
                initParams
            )
        );
        PendleStrategyV2Mock pendleStrategyLocal = PendleStrategyV2Mock(payable(address(pendleStrategyProxy)));
        assertEq(address(pendleStrategyLocal.pendleRouter()), PENDLE_ROUTER);
        assertEq(address(pendleStrategyLocal.pendleMarket()), address(pendleMarket));
        (address _sy,,) = pendleMarket.readTokens();
        (, address targetAsset,) = ISyToken(_sy).assetInfo();
        assertEq(address(pendleStrategyLocal.targetAsset()), targetAsset);
        assertEq(address(pendleStrategyLocal.calculations()), address(pendleCalculations));
        assertEq(pendleStrategyLocal.twapPeriod(), 1800);
    }

    function test_initialize_Fail_CalledMoreThanOnce() external {
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: want,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: address(pendleMarket),
            twapPeriod: pendleOracleTwapPeriod,
            tokensToCompound: tokensToCompound,
            minimumsToCompound: minimumsToCompound
        });

        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        pendleStrategy.initialize(initParams);
    }

    function test_initialize_Fail_PendleRouterIsNotContract() external {
        PendleStrategyV2Mock _pendleStrategyImpl = new PendleStrategyV2Mock();
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: want,
            calculations: address(pendleCalculations),
            pendleRouter: address(0),
            pendleMarket: address(pendleMarket),
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

    function test_initialize_Fail_PendleMarketIsNotContract() external {
        PendleStrategyV2Mock _pendleStrategyImpl = new PendleStrategyV2Mock();
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: want,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: address(0),
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

    function test_initialize_Fail_CalculationsIsNotContract() external {
        PendleStrategyV2Mock _pendleStrategyImpl = new PendleStrategyV2Mock();
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: want,
            calculations: address(0),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: address(pendleMarket),
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

    function test_setTwapPeriod_Success() external {
        uint32 newTwapPeriod = 10 minutes;

        vm.prank(adminStructure.getAllAdmins()[0]);

        pendleStrategy.setTwapPeriod(newTwapPeriod);

        assertEq(pendleStrategy.twapPeriod(), newTwapPeriod);
    }

    function test_setTwapPeriod_Fail_NotAdminCalling() external {
        vm.expectRevert(bytes("NotUserAdmin"));

        pendleStrategy.setTwapPeriod(10 minutes);
    }

    function test_balance_Success() external {
        // returns balance of want asset
        assertEq(pendleStrategy.balance(), 0);

        deal(want, address(pendleStrategy), 100e18, false);

        assertEq(pendleStrategy.balance(), 100e18);
    }

    function test_getPendingToCompound_Success() public {
        // Before
        (
            uint256[] memory _rewardAmountsBefore,
            address[] memory _rewardTokensBefore,
            bool[] memory _enoughRewardsBefore,
            bool _atLeastOneBefore
        ) = pendleStrategy.getPendingToCompound(_getRewardData(10));
        assertEq(_rewardAmountsBefore[0], 10e18);
        assertEq(_rewardTokensBefore[0], PENDLE);
        assertTrue(_enoughRewardsBefore[0]);
        assertTrue(_atLeastOneBefore);
        // After
        deal(want, address(pendleStrategy), 100e18, false);
        (
            uint256[] memory _rewardAmountsAfter,
            address[] memory _rewardTokensAfter,
            bool[] memory _enoughRewardsAfter,
            bool _atLeastOneAfter
        ) = pendleStrategy.getPendingToCompound(_getRewardData(10));
        assertEq(_rewardAmountsAfter[0], 10e18);
        assertEq(_rewardTokensAfter[0], PENDLE);
        assertTrue(_enoughRewardsAfter[0]);
        assertTrue(_atLeastOneAfter);
    }

    function _getAdditionalData(uint256 _minOut, uint16 _slippage) private pure returns (bytes memory) {
        return abi.encode(_minOut, _slippage);
    }

    function _getRewardData(uint256 _multiplier) private view returns (bytes memory _rewardData) {
        IMarket _pendleMarket = pendleMarket;

        address[] memory _pendleRewardTokens = _pendleMarket.getRewardTokens();
        uint256 _pendleRewardTokensLength = _pendleRewardTokens.length;

        address[] memory _rewardTokens = new address[](_pendleRewardTokensLength);
        uint256[] memory _rewardAmounts = new uint256[](_pendleRewardTokensLength);

        for (uint256 _i; _i < _pendleRewardTokensLength;) {
            _rewardTokens[_i] = _pendleRewardTokens[_i];
            _rewardAmounts[_i] = 10 ** ERC20Upgradeable(_pendleRewardTokens[_i]).decimals() * _multiplier;

            unchecked {
                ++_i;
            }
        }

        return abi.encode(_rewardTokens, _rewardAmounts);
    }
}

contract EmptyMock { }
