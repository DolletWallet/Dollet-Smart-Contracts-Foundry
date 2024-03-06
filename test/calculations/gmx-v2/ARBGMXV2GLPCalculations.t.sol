// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IGMXV2GLPStrategy } from "src/strategies/gmx-v2/interfaces/IGMXV2GLPStrategy.sol";
import { IGLPManager, IRewardTracker } from "src/strategies/gmx-v2/interfaces/IGMXV2.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { GMXV2GLPCalculations } from "src/calculations/gmx-v2/GMXV2GLPCalculations.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { IStrategy } from "src/interfaces/dollet/IStrategy.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import "addresses/ARBMainnet.sol";
import "forge-std/Test.sol";

contract ARBGMXV2GLPCalculationsTest is Test {
    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;

    GMXV2GLPCalculations public calculations;
    IAdminStructure public adminStructure;
    StrategyHelper public strategyHelper;
    Mock public strategy;

    address public alice;

    event UsdSet(address _oldUsd, address _newUsd);

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ARB_MAINNET"), 170_976_799);

        adminStructure = IAdminStructure(ADMIN_STRUCTURE);

        Proxy GMXV2GLPCalculationsProxy = new Proxy(
            address(new GMXV2GLPCalculations()),
            abi.encodeWithSignature("initialize(address,address)", ADMIN_STRUCTURE, USDC)
        );
        calculations = GMXV2GLPCalculations(address(GMXV2GLPCalculationsProxy));

        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        strategy = new Mock();

        alice = makeAddr("Alice");

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.strategyHelper.selector),
            abi.encode(address(strategyHelper))
        );
        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.weth.selector), abi.encode(WETH));
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IGMXV2GLPStrategy.gmxGlpHandler.selector),
            abi.encode(GMX_GLP_HANDLER)
        );
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IGMXV2GLPStrategy.gmxRewardsHandler.selector),
            abi.encode(GMX_REWARDS_HANDLER)
        );

        vm.startPrank(adminStructure.superAdmin());

        calculations.setStrategyValues(address(strategy));

        strategyHelper.setOracle(WETH, ETH_ORACLE);
        strategyHelper.setOracle(USDC, USDC_ORACLE);
        strategyHelper.setOracle(USDCe, USDC_ORACLE);
        strategyHelper.setOracle(USDT, USDT_ORACLE);
        strategyHelper.setOracle(DAI, DAI_ORACLE);
        strategyHelper.setOracle(WBTC, WBTC_ORACLE);
        strategyHelper.setOracle(LINK, LINK_ORACLE);
        strategyHelper.setOracle(UNI, UNI_ORACLE);
        strategyHelper.setOracle(FRAX, FRAX_ORACLE);

        vm.stopPrank();
    }

    function test_initialize_ShouldFailWhenCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        calculations.initialize(ADMIN_STRUCTURE, USDC);
    }

    function test_initialize_ShouldFailWhenUsdIsNotContract() external {
        GMXV2GLPCalculations newCalculations = new GMXV2GLPCalculations();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newCalculations),
            abi.encodeWithSignature("initialize(address,address)", ADMIN_STRUCTURE, address(0))
        );
    }

    function test_initialize() external {
        Proxy GMXV2GLPCalculationsProxy = new Proxy(
            address(new GMXV2GLPCalculations()),
            abi.encodeWithSignature("initialize(address,address)", ADMIN_STRUCTURE, USDC)
        );
        GMXV2GLPCalculations newCalculations = GMXV2GLPCalculations(address(GMXV2GLPCalculationsProxy));

        assertEq(newCalculations.usd(), USDC);
    }

    function test_usd() external {
        assertEq(calculations.usd(), USDC);
    }

    function test_setUsd_ShouldFailWhenNotAdminIsCalling() external {
        vm.expectRevert(bytes("NotUserAdmin"));

        calculations.setUsd(address(0));
    }

    function test_setUsd_ShouldFailWhenUsdIsNotContract() external {
        vm.prank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        calculations.setUsd(address(0));
    }

    function test_setUsd() external {
        address newUsd = USDT;

        vm.expectEmit(true, true, true, true, address(calculations));

        emit UsdSet(calculations.usd(), newUsd);

        vm.prank(adminStructure.getAllAdmins()[0]);

        calculations.setUsd(newUsd);

        assertEq(calculations.usd(), newUsd);
    }

    function test_getPendingToCompound_ShouldReturnProperResult1() external {
        vm.mockCall(
            address(strategy), abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WETH), abi.encode(1e15)
        );

        (uint256 claimableWeth, bool isEnoughRewards) = calculations.getPendingToCompound();

        assertEq(claimableWeth, 0);
        assertEq(isEnoughRewards, false);
    }

    function test_getPendingToCompound_ShouldReturnProperResult2() external {
        uint256 minimumToCompound = 1e15;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WETH),
            abi.encode(minimumToCompound)
        );
        vm.mockCall(
            address(IGMXV2GLPStrategy(address(strategy)).gmxRewardsHandler().feeGlpTracker()),
            abi.encodeWithSelector(IRewardTracker.claimable.selector, address(strategy)),
            abi.encode(minimumToCompound - 1)
        );

        (uint256 claimableWeth, bool isEnoughRewards) = calculations.getPendingToCompound();

        assertEq(claimableWeth, minimumToCompound - 1);
        assertEq(isEnoughRewards, false);
    }

    function test_getPendingToCompound_ShouldReturnProperResult3() external {
        uint256 minimumToCompound = 1e15;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WETH),
            abi.encode(minimumToCompound)
        );
        vm.mockCall(
            address(IGMXV2GLPStrategy(address(strategy)).gmxRewardsHandler().feeGlpTracker()),
            abi.encodeWithSelector(IRewardTracker.claimable.selector, address(strategy)),
            abi.encode(minimumToCompound)
        );

        (uint256 claimableWeth, bool isEnoughRewards) = calculations.getPendingToCompound();

        assertEq(claimableWeth, minimumToCompound);
        assertEq(isEnoughRewards, true);
    }

    function test_getPendingToCompound_ShouldReturnProperResult4() external {
        uint256 minimumToCompound = 1e15;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WETH),
            abi.encode(minimumToCompound)
        );
        vm.mockCall(
            address(IGMXV2GLPStrategy(address(strategy)).gmxRewardsHandler().feeGlpTracker()),
            abi.encodeWithSelector(IRewardTracker.claimable.selector, address(strategy)),
            abi.encode(minimumToCompound * 2)
        );

        (uint256 claimableWeth, bool isEnoughRewards) = calculations.getPendingToCompound();

        assertEq(claimableWeth, minimumToCompound * 2);
        assertEq(isEnoughRewards, true);
    }

    function test_userDeposit_ShouldReturnZeroWhenNoDeposit() external {
        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice), abi.encode(0));

        assertEq(calculations.userDeposit(alice, WETH), 0);
        assertEq(calculations.userDeposit(alice, USDC), 0);
        assertEq(calculations.userDeposit(alice, USDCe), 0);
        assertEq(calculations.userDeposit(alice, USDT), 0);
        assertEq(calculations.userDeposit(alice, DAI), 0);
        assertEq(calculations.userDeposit(alice, WBTC), 0);
        assertEq(calculations.userDeposit(alice, LINK), 0);
        assertEq(calculations.userDeposit(alice, UNI), 0);
        assertEq(calculations.userDeposit(alice, FRAX), 0);
    }

    function test_userDeposit_ShouldAnswerInWETH() external {
        uint256 userWantDeposit = 2_129_564_178_879_256_732_751; // 1 ETH (WETH)
        uint256 expectedUserDeposit = 1e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, WETH), expectedUserDeposit, 2e15);
    }

    function test_userDeposit_ShouldAnswerInWBTC() external {
        uint256 userWantDeposit = 35_918_386_346_394_918_710_955; // 1 WBTC
        uint256 expectedUserDeposit = 1e8;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, WBTC), expectedUserDeposit, 3e6);
    }

    function test_userDeposit_ShouldAnswerInLINK() external {
        uint256 userWantDeposit = 1_269_011_388_929_448_391_896; // 100 LINK
        uint256 expectedUserDeposit = 100e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, LINK), expectedUserDeposit, 3e17);
    }

    function test_userDeposit_ShouldAnswerInUNI() external {
        uint256 userWantDeposit = 576_440_067_478_318_099_148; // 100 UNI
        uint256 expectedUserDeposit = 100e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, UNI), expectedUserDeposit, 8e16);
    }

    function test_userDeposit_ShouldAnswerInUSDCe() external {
        uint256 userWantDeposit = 838_397_890_930_558_862_361; // 1000 USDCe
        uint256 expectedUserDeposit = 1000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, USDCe), expectedUserDeposit, 1);
    }

    function test_userDeposit_ShouldAnswerInUSDC() external {
        uint256 userWantDeposit = 4_191_989_454_652_794_311_806; // 5000 USDC
        uint256 expectedUserDeposit = 5000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, USDC), expectedUserDeposit, 1);
    }

    function test_userDeposit_ShouldAnswerInUSDT() external {
        uint256 userWantDeposit = 419_198_945_465_279_431_180; // 500 USDT
        uint256 expectedUserDeposit = 500e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, USDT), expectedUserDeposit, 5e5);
    }

    function test_userDeposit_ShouldAnswerInDAI() external {
        uint256 userWantDeposit = 8_383_978_909_305_588_623_612; // 10000 DAI
        uint256 expectedUserDeposit = 10_000e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, DAI), expectedUserDeposit, 5e18);
    }

    function test_userDeposit_ShouldAnswerInFRAX() external {
        uint256 userWantDeposit = 4_173_544_701_052_322_016_834; // 5000 FRAX
        uint256 expectedUserDeposit = 5000e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, FRAX), expectedUserDeposit, 2e19);
    }

    function test_totalDeposits_ShouldReturnZeroWhenNoDeposit() external {
        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.totalWantDeposits.selector), abi.encode(0));

        assertEq(calculations.totalDeposits(WETH), 0);
        assertEq(calculations.totalDeposits(USDC), 0);
        assertEq(calculations.totalDeposits(USDCe), 0);
        assertEq(calculations.totalDeposits(USDT), 0);
        assertEq(calculations.totalDeposits(DAI), 0);
        assertEq(calculations.totalDeposits(WBTC), 0);
        assertEq(calculations.totalDeposits(LINK), 0);
        assertEq(calculations.totalDeposits(UNI), 0);
        assertEq(calculations.totalDeposits(FRAX), 0);
    }

    function test_totalDeposits_ShouldAnswerInWETH() external {
        uint256 totalWantDeposits = 2_129_564_178_879_256_732_751; // 1 ETH (WETH)
        uint256 expectedTotalDeposit = 1e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(WETH), expectedTotalDeposit, 2e15);
    }

    function test_totalDeposits_ShouldAnswerInWBTC() external {
        uint256 totalWantDeposits = 35_918_386_346_394_918_710_955; // 1 WBTC
        uint256 expectedTotalDeposit = 1e8;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(WBTC), expectedTotalDeposit, 3e6);
    }

    function test_totalDeposits_ShouldAnswerInLINK() external {
        uint256 totalWantDeposits = 1_269_011_388_929_448_391_896; // 100 LINK
        uint256 expectedTotalDeposit = 100e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(LINK), expectedTotalDeposit, 3e17);
    }

    function test_totalDeposits_ShouldAnswerInUNI() external {
        uint256 totalWantDeposits = 576_440_067_478_318_099_148; // 100 UNI
        uint256 expectedTotalDeposit = 100e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(UNI), expectedTotalDeposit, 8e16);
    }

    function test_totalDeposits_ShouldAnswerInUSDCe() external {
        uint256 totalWantDeposits = 838_397_890_930_558_862_361; // 1000 USDCe
        uint256 expectedTotalDeposit = 1000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(USDCe), expectedTotalDeposit, 1);
    }

    function test_totalDeposits_ShouldAnswerInUSDC() external {
        uint256 totalWantDeposits = 4_191_989_454_652_794_311_806; // 5000 USDC
        uint256 expectedTotalDeposit = 5000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(USDC), expectedTotalDeposit, 1);
    }

    function test_totalDeposits_ShouldAnswerInUSDT() external {
        uint256 totalWantDeposits = 419_198_945_465_279_431_180; // 500 USDT
        uint256 expectedTotalDeposit = 500e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(USDT), expectedTotalDeposit, 5e5);
    }

    function test_totalDeposits_ShouldAnswerInDAI() external {
        uint256 totalWantDeposits = 8_383_978_909_305_588_623_612; // 10000 DAI
        uint256 expectedTotalDeposit = 10_000e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(DAI), expectedTotalDeposit, 5e18);
    }

    function test_totalDeposits_ShouldAnswerInFRAX() external {
        uint256 totalWantDeposits = 4_173_544_701_052_322_016_834; // 5000 FRAX
        uint256 expectedTotalDeposit = 5000e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(FRAX), expectedTotalDeposit, 2e19);
    }

    function test_estimateWantAfterCompound_ShouldReturnPreviousWantBalanceIfNoRewardsToCompound() external {
        uint256 prevWantBalance = 1e18;
        uint256 minimumToCompound = 1e15;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WETH),
            abi.encode(minimumToCompound)
        );

        assertEq(calculations.estimateWantAfterCompound(100, hex""), prevWantBalance);
    }

    function test_estimateWantAfterCompound_ShouldReturnPreviousWantBalanceIfMinimumToCompoundIsNotReached() external {
        uint256 prevWantBalance = 10e18;
        uint256 minimumToCompound = 1e15;
        uint256 claimable = minimumToCompound - 1;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WETH),
            abi.encode(minimumToCompound)
        );
        vm.mockCall(
            address(IGMXV2GLPStrategy(address(strategy)).gmxRewardsHandler().feeGlpTracker()),
            abi.encodeWithSelector(IRewardTracker.claimable.selector, address(strategy)),
            abi.encode(claimable)
        );

        assertEq(calculations.estimateWantAfterCompound(100, hex""), prevWantBalance);
    }

    function test_estimateWantAfterCompound_ShouldReturnProperResultIfMinimumToCompoundIsReached1() external {
        uint256 prevWantBalance = 5e18;
        uint256 minimumToCompound = 1e15;
        uint256 claimable = minimumToCompound;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WETH),
            abi.encode(minimumToCompound)
        );
        vm.mockCall(
            address(IGMXV2GLPStrategy(address(strategy)).gmxRewardsHandler().feeGlpTracker()),
            abi.encodeWithSelector(IRewardTracker.claimable.selector, address(strategy)),
            abi.encode(claimable)
        );

        assertTrue(calculations.estimateWantAfterCompound(100, hex"") > prevWantBalance);
    }

    function test_estimateWantAfterCompound_ShouldReturnProperResultIfMinimumToCompoundIsReached2() external {
        uint256 prevWantBalance = 5e18;
        uint256 minimumToCompound = 1e15;
        uint256 claimable = minimumToCompound * 2;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WETH),
            abi.encode(minimumToCompound)
        );
        vm.mockCall(
            address(IGMXV2GLPStrategy(address(strategy)).gmxRewardsHandler().feeGlpTracker()),
            abi.encodeWithSelector(IRewardTracker.claimable.selector, address(strategy)),
            abi.encode(claimable)
        );

        assertTrue(calculations.estimateWantAfterCompound(100, hex"") > prevWantBalance);
    }

    function test_estimateDeposit_ShouldReturnZeroWhenZeroAmountIsUsed() external {
        uint16 slippageTolerance = 100; //1.00%

        assertEq(calculations.estimateDeposit(WETH, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(WBTC, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(LINK, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(UNI, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDC, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDCe, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDT, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(DAI, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(FRAX, 0, slippageTolerance, hex""), 0);
    }

    function test_estimateDeposit_ShouldReturnZeroWhenGLPPriceIsZero() external {
        uint16 slippageTolerance = 150; //1.50%

        vm.mockCall(
            address(IGMXV2GLPStrategy(address(strategy)).gmxGlpHandler().glpManager()),
            abi.encodeWithSelector(IGLPManager.getPrice.selector),
            abi.encode(0)
        );

        assertEq(calculations.estimateDeposit(WETH, 1e18, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(WBTC, 1e8, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(LINK, 100e18, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(UNI, 100e18, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDC, 1000e6, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDCe, 5000e6, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDT, 500e6, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(DAI, 10_000e18, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(FRAX, 5000e18, slippageTolerance, hex""), 0);
    }

    function test_estimateDeposit_ShouldEstimateWithWETHDepositToken() external {
        uint256 expectedEstimationResult = 2_129_564_178_879_256_732_751;

        assertApproxEqAbs(calculations.estimateDeposit(WETH, 1e18, 100, hex""), expectedEstimationResult, 5e19);
    }

    function test_estimateDeposit_ShouldEstimateWithWBTCDepositToken() external {
        uint256 expectedEstimationResult = 35_918_386_346_394_918_710_955;

        assertApproxEqAbs(calculations.estimateDeposit(WBTC, 1e8, 100, hex""), expectedEstimationResult, 3e20);
    }

    function test_estimateDeposit_ShouldEstimateWithLINKDepositToken() external {
        uint256 expectedEstimationResult = 1_269_011_388_929_448_391_896;

        assertApproxEqAbs(calculations.estimateDeposit(LINK, 100e18, 100, hex""), expectedEstimationResult, 1e19);
    }

    function test_estimateDeposit_ShouldEstimateWithUNIDepositToken() external {
        uint256 expectedEstimationResult = 576_440_067_478_318_099_148;

        assertApproxEqAbs(calculations.estimateDeposit(UNI, 100e18, 100, hex""), expectedEstimationResult, 7e18);
    }

    function test_estimateDeposit_ShouldEstimateWithUSDCeDepositToken() external {
        uint256 expectedEstimationResult = 838_397_890_930_558_862_361;

        assertApproxEqAbs(calculations.estimateDeposit(USDCe, 1000e6, 100, hex""), expectedEstimationResult, 9e18);
    }

    function test_estimateDeposit_ShouldEstimateWithUSDCDepositToken() external {
        uint256 expectedEstimationResult = 4_191_989_454_652_794_311_806;

        assertApproxEqAbs(calculations.estimateDeposit(USDC, 5000e6, 100, hex""), expectedEstimationResult, 5e19);
    }

    function test_estimateDeposit_ShouldEstimateWithUSDTDepositToken() external {
        uint256 expectedEstimationResult = 419_198_945_465_279_431_180;

        assertApproxEqAbs(calculations.estimateDeposit(USDT, 500e6, 100, hex""), expectedEstimationResult, 5e18);
    }

    function test_estimateDeposit_ShouldEstimateWithDAIDepositToken() external {
        uint256 expectedEstimationResult = 8_383_978_909_305_588_623_612;

        assertApproxEqAbs(calculations.estimateDeposit(DAI, 10_000e18, 100, hex""), expectedEstimationResult, 9e19);
    }

    function test_estimateDeposit_ShouldEstimateWithFRAXDepositToken() external {
        uint256 expectedEstimationResult = 4_173_544_701_052_322_016_834;

        assertApproxEqAbs(calculations.estimateDeposit(FRAX, 5000e18, 100, hex""), expectedEstimationResult, 4e19);
    }

    function test_estimateWantToToken_ShouldReturnZeroIfZeroAmountIsUsed() external {
        assertEq(calculations.estimateWantToToken(WETH, 0, 100), 0);
    }

    function test_estimateWantToToken_ShouldReturnZeroIfZeroTokenIsUsed() external {
        assertEq(calculations.estimateWantToToken(address(0), 1, 100), 0);
    }

    function test_estimateWantToToken_ShouldAnswerInWETH() external {
        address token = WETH;
        uint256 wantAmount = 2_129_564_178_879_256_732_751; // 1 ETH (WETH)
        uint256 expectedEstimationResult = 1e18;
        uint16 slippageTolerance = 150; // 1.50%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 2e15);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInWBTC() external {
        address token = WBTC;
        uint256 wantAmount = 35_918_386_346_394_918_710_955; // 1 WBTC
        uint256 expectedEstimationResult = 1e8;
        uint16 slippageTolerance = 200; // 2.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 3e5);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInLINK() external {
        address token = LINK;
        uint256 wantAmount = 1_269_011_388_929_448_391_896; // 100 LINK
        uint256 expectedEstimationResult = 100e18;
        uint16 slippageTolerance = 200; // 2.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 3e17);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInUNI() external {
        address token = UNI;
        uint256 wantAmount = 576_440_067_478_318_099_148; // 100 UNI
        uint256 expectedEstimationResult = 100e18;
        uint16 slippageTolerance = 50; // 0.50%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 8e16);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInUSDCe() external {
        address token = USDCe;
        uint256 wantAmount = 838_397_890_930_558_862_361; // 1000 USDCe
        uint256 expectedEstimationResult = 1000e6;
        uint16 slippageTolerance = 150; // 1.50%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 1);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInUSDC() external {
        address token = USDC;
        uint256 wantAmount = 4_191_989_454_652_794_311_806; // 5000 USDC
        uint256 expectedEstimationResult = 5000e6;
        uint16 slippageTolerance = 100; // 1.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 1);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInUSDT() external {
        address token = USDT;
        uint256 wantAmount = 419_198_945_465_279_431_180; // 500 USDT
        uint256 expectedEstimationResult = 500e6;
        uint16 slippageTolerance = 200; // 2.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 5e5);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInDAI() external {
        address token = DAI;
        uint256 wantAmount = 8_383_978_909_305_588_623_612; // 10000 DAI
        uint256 expectedEstimationResult = 10_000e18;
        uint16 slippageTolerance = 150; // 1.50%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 5e18);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInFRAX() external {
        address token = FRAX;
        uint256 wantAmount = 4_173_544_701_052_322_016_834; // 5000 FRAX
        uint256 expectedEstimationResult = 5000e18;
        uint16 slippageTolerance = 50; // 0.50%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 14e18);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }
}

contract Mock { }
