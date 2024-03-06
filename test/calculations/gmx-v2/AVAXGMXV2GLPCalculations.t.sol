// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IGMXV2GLPStrategy } from "src/strategies/gmx-v2/interfaces/IGMXV2GLPStrategy.sol";
import { IGLPManager, IRewardTracker } from "src/strategies/gmx-v2/interfaces/IGMXV2.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { GMXV2GLPCalculations } from "src/calculations/gmx-v2/GMXV2GLPCalculations.sol";
import { TemporaryAdminStructure } from "src/admin/TemporaryAdminStructure.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { IStrategy } from "src/interfaces/dollet/IStrategy.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import "addresses/AVAXMainnet.sol";
import "forge-std/Test.sol";

contract AVAXGMXV2GLPCalculationsTest is Test {
    GMXV2GLPCalculations public calculations;
    TemporaryAdminStructure public adminStructure;
    StrategyHelper public strategyHelper;
    Mock public strategy;

    address public alice;

    event UsdSet(address _oldUsd, address _newUsd);

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_AVAX_MAINNET"), 42_162_551);

        Proxy adminStructureProxy = new Proxy(
            address(new TemporaryAdminStructure()),
            abi.encodeWithSignature("initialize()")
        );
        adminStructure = TemporaryAdminStructure(address(adminStructureProxy));

        Proxy GMXV2GLPCalculationsProxy = new Proxy(
            address(new GMXV2GLPCalculations()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), USDC)
        );
        calculations = GMXV2GLPCalculations(address(GMXV2GLPCalculationsProxy));

        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        strategy = new Mock();

        alice = makeAddr("Alice");

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.strategyHelper.selector),
            abi.encode(address(strategyHelper))
        );
        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.weth.selector), abi.encode(WAVAX));
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

        calculations.initialize(address(adminStructure), USDC);
    }

    function test_initialize_ShouldFailWhenUsdIsNotContract() external {
        GMXV2GLPCalculations newCalculations = new GMXV2GLPCalculations();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newCalculations),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), address(0))
        );
    }

    function test_initialize() external {
        Proxy GMXV2GLPCalculationsProxy = new Proxy(
            address(new GMXV2GLPCalculations()),
            abi.encodeWithSignature("initialize(address,address)", address(adminStructure), USDC)
        );
        GMXV2GLPCalculations newCalculations = GMXV2GLPCalculations(address(GMXV2GLPCalculationsProxy));

        assertEq(newCalculations.usd(), USDC);
    }

    function test_usd() external {
        assertEq(calculations.usd(), USDC);
    }

    function test_setUsd_ShouldFailWhenNotAdminIsCalling() external {
        vm.prank(alice);
        vm.expectRevert(bytes("NotSuperAdmin"));

        calculations.setUsd(address(0));
    }

    function test_setUsd_ShouldFailWhenUsdIsNotContract() external {
        vm.prank(adminStructure.getAllAdmins()[0]);
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        calculations.setUsd(address(0));
    }

    function test_setUsd() external {
        address newUsd = USDCe;

        vm.expectEmit(true, true, true, true, address(calculations));

        emit UsdSet(calculations.usd(), newUsd);

        vm.prank(adminStructure.getAllAdmins()[0]);

        calculations.setUsd(newUsd);

        assertEq(calculations.usd(), newUsd);
    }

    function test_getPendingToCompound_ShouldReturnProperResult1() external {
        vm.mockCall(
            address(strategy), abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WAVAX), abi.encode(0.3e17)
        );

        (uint256 claimableWeth, bool isEnoughRewards) = calculations.getPendingToCompound();

        assertEq(claimableWeth, 0);
        assertEq(isEnoughRewards, false);
    }

    function test_getPendingToCompound_ShouldReturnProperResult2() external {
        uint256 minimumToCompound = 0.3e17;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WAVAX),
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
        uint256 minimumToCompound = 0.3e17;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WAVAX),
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
        uint256 minimumToCompound = 0.3e17;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WAVAX),
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

        assertEq(calculations.userDeposit(alice, WAVAX), 0);
        assertEq(calculations.userDeposit(alice, WETHe), 0);
        assertEq(calculations.userDeposit(alice, BTCb), 0);
        assertEq(calculations.userDeposit(alice, WBTCe), 0);
        assertEq(calculations.userDeposit(alice, USDC), 0);
        assertEq(calculations.userDeposit(alice, USDCe), 0);
    }

    function test_userDeposit_ShouldAnswerInWAVAX() external {
        uint256 userWantDeposit = 3_997_917_659_866_072_050_559; // 100 AVAX (WAVAX)
        uint256 expectedUserDeposit = 100e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, WAVAX), expectedUserDeposit, 2e17);
    }

    function test_userDeposit_ShouldAnswerInWETHe() external {
        uint256 userWantDeposit = 3_335_422_120_477_108_475_761; // 1 WETHe
        uint256 expectedUserDeposit = 1e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, WETHe), expectedUserDeposit, 4e15);
    }

    function test_userDeposit_ShouldAnswerInBTCb() external {
        uint256 userWantDeposit = 55_329_671_315_188_216_022_248; // 1 BTCb
        uint256 expectedUserDeposit = 1e8;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, BTCb), expectedUserDeposit, 6e5);
    }

    function test_userDeposit_ShouldAnswerInWBTCe() external {
        uint256 userWantDeposit = 55_229_728_105_587_273_936_107; // 1 WBTCe
        uint256 expectedUserDeposit = 1e8;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, WBTCe), expectedUserDeposit, 7e5);
    }

    function test_userDeposit_ShouldAnswerInUSDC() external {
        uint256 userWantDeposit = 5_403_347_010_006_383_796_117; // 5000 USDC
        uint256 expectedUserDeposit = 5000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, USDC), expectedUserDeposit, 2e7);
    }

    function test_userDeposit_ShouldAnswerInUSDCe() external {
        uint256 userWantDeposit = 1_080_452_769_866_967_592_788; // 1000 USDCe
        uint256 expectedUserDeposit = 1000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, USDCe), expectedUserDeposit, 6e6);
    }

    function test_totalDeposits_ShouldReturnZeroWhenNoDeposit() external {
        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.totalWantDeposits.selector), abi.encode(0));

        assertEq(calculations.totalDeposits(WAVAX), 0);
        assertEq(calculations.totalDeposits(WETHe), 0);
        assertEq(calculations.totalDeposits(BTCb), 0);
        assertEq(calculations.totalDeposits(WBTCe), 0);
        assertEq(calculations.totalDeposits(USDC), 0);
        assertEq(calculations.totalDeposits(USDCe), 0);
    }

    function test_totalDeposits_ShouldAnswerInWAVAX() external {
        uint256 totalWantDeposits = 3_997_917_659_866_072_050_559; // 100 AVAX (WAVAX)
        uint256 expectedTotalDeposit = 100e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(WAVAX), expectedTotalDeposit, 2e17);
    }

    function test_totalDeposits_ShouldAnswerInWETHe() external {
        uint256 totalWantDeposits = 3_335_422_120_477_108_475_761; // 1 WETHe
        uint256 expectedTotalDeposit = 1e18;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(WETHe), expectedTotalDeposit, 4e15);
    }

    function test_totalDeposits_ShouldAnswerInBTCb() external {
        uint256 totalWantDeposits = 55_329_671_315_188_216_022_248; // 1 BTCb
        uint256 expectedTotalDeposit = 1e8;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(BTCb), expectedTotalDeposit, 6e5);
    }

    function test_totalDeposits_ShouldAnswerInWBTCe() external {
        uint256 totalWantDeposits = 55_229_728_105_587_273_936_107; // 1 WBTCe
        uint256 expectedTotalDeposit = 1e8;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(WBTCe), expectedTotalDeposit, 7e5);
    }

    function test_totalDeposits_ShouldAnswerInUSDC() external {
        uint256 totalWantDeposits = 5_403_347_010_006_383_796_117; // 5000 USDC
        uint256 expectedTotalDeposit = 5000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(USDC), expectedTotalDeposit, 2e7);
    }

    function test_totalDeposits_ShouldAnswerInUSDCe() external {
        uint256 totalWantDeposits = 1_080_452_769_866_967_592_788; // 1000 USDCe
        uint256 expectedTotalDeposit = 1000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(USDCe), expectedTotalDeposit, 6e6);
    }

    function test_estimateWantAfterCompound_ShouldReturnPreviousWantBalanceIfNoRewardsToCompound() external {
        uint256 prevWantBalance = 1e18;
        uint256 minimumToCompound = 1e15;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WAVAX),
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
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WAVAX),
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
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WAVAX),
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
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WAVAX),
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

        assertEq(calculations.estimateDeposit(WAVAX, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(WETHe, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(BTCb, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(WBTCe, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDCe, 0, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDC, 0, slippageTolerance, hex""), 0);
    }

    function test_estimateDeposit_ShouldReturnZeroWhenGLPPriceIsZero() external {
        uint16 slippageTolerance = 150; //1.50%

        vm.mockCall(
            address(IGMXV2GLPStrategy(address(strategy)).gmxGlpHandler().glpManager()),
            abi.encodeWithSelector(IGLPManager.getPrice.selector),
            abi.encode(0)
        );

        assertEq(calculations.estimateDeposit(WAVAX, 1e18, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(WETHe, 1e8, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(BTCb, 100e18, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(WBTCe, 100e18, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDCe, 5000e6, slippageTolerance, hex""), 0);
        assertEq(calculations.estimateDeposit(USDC, 1000e6, slippageTolerance, hex""), 0);
    }

    function test_estimateDeposit_ShouldEstimateWithWAVAXDepositToken() external {
        uint256 expectedEstimationResult = 3_997_917_659_866_072_050_559;

        assertApproxEqAbs(calculations.estimateDeposit(WAVAX, 100e18, 100, hex""), expectedEstimationResult, 4e19);
    }

    function test_estimateDeposit_ShouldEstimateWithWETHeDepositToken() external {
        uint256 expectedEstimationResult = 3_335_422_120_477_108_475_761;

        assertApproxEqAbs(calculations.estimateDeposit(WETHe, 1e18, 100, hex""), expectedEstimationResult, 3e19);
    }

    function test_estimateDeposit_ShouldEstimateWithBTCbDepositToken() external {
        uint256 expectedEstimationResult = 55_329_671_315_188_216_022_248;

        assertApproxEqAbs(calculations.estimateDeposit(BTCb, 1e8, 100, hex""), expectedEstimationResult, 3e20);
    }

    function test_estimateDeposit_ShouldEstimateWithWBTCeDepositToken() external {
        uint256 expectedEstimationResult = 55_229_728_105_587_273_936_107;

        assertApproxEqAbs(calculations.estimateDeposit(WBTCe, 1e8, 100, hex""), expectedEstimationResult, 2e20);
    }

    function test_estimateDeposit_ShouldEstimateWithUSDCDepositToken() external {
        uint256 expectedEstimationResult = 5_403_347_010_006_383_796_117;

        assertApproxEqAbs(calculations.estimateDeposit(USDC, 5000e6, 100, hex""), expectedEstimationResult, 5e19);
    }

    function test_estimateDeposit_ShouldEstimateWithUSDCeDepositToken() external {
        uint256 expectedEstimationResult = 1_080_452_769_866_967_592_788;

        assertApproxEqAbs(calculations.estimateDeposit(USDCe, 1000e6, 100, hex""), expectedEstimationResult, 9e18);
    }

    function test_estimateWantToToken_ShouldReturnZeroIfZeroAmountIsUsed() external {
        assertEq(calculations.estimateWantToToken(WAVAX, 0, 100), 0);
    }

    function test_estimateWantToToken_ShouldReturnZeroIfZeroTokenIsUsed() external {
        assertEq(calculations.estimateWantToToken(address(0), 1, 100), 0);
    }

    function test_estimateWantToToken_ShouldAnswerInWAVAX() external {
        address token = WAVAX;
        uint256 wantAmount = 3_997_917_659_866_072_050_559; // 100 AVAX (WAVAX)
        uint256 expectedEstimationResult = 100e18;
        uint16 slippageTolerance = 150; // 1.50%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 2e17);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInWETHe() external {
        address token = WETHe;
        uint256 wantAmount = 3_335_422_120_477_108_475_761; // 1 WETHe
        uint256 expectedEstimationResult = 1e18;
        uint16 slippageTolerance = 200; // 2.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 4e15);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInBTCb() external {
        address token = BTCb;
        uint256 wantAmount = 55_329_671_315_188_216_022_248; // 1 BTCb
        uint256 expectedEstimationResult = 1e8;
        uint16 slippageTolerance = 200; // 2.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 6e5);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInWBTCe() external {
        address token = WBTCe;
        uint256 wantAmount = 55_229_728_105_587_273_936_107; // 1 WBTCe
        uint256 expectedEstimationResult = 1e8;
        uint16 slippageTolerance = 50; // 0.50%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 7e5);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInUSDC() external {
        address token = USDC;
        uint256 wantAmount = 5_403_347_010_006_383_796_117; // 5000 USDC
        uint256 expectedEstimationResult = 5000e6;
        uint16 slippageTolerance = 100; // 1.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 2e7);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInUSDCe() external {
        address token = USDCe;
        uint256 wantAmount = 1_080_452_769_866_967_592_788; // 1000 USDCe
        uint256 expectedEstimationResult = 1000e6;
        uint16 slippageTolerance = 150; // 1.50%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 3e6);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }
}

contract Mock { }
