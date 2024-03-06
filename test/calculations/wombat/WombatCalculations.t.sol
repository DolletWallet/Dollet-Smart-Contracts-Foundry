// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IWombatStrategy } from "src/strategies/wombat/interfaces/IWombatStrategy.sol";
import { WombatCalculations } from "src/calculations/wombat/WombatCalculations.sol";
import { IMasterWombat, IPool } from "src/strategies/wombat/interfaces/IWombat.sol";
import { TemporaryAdminStructure } from "src/admin/TemporaryAdminStructure.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import { IStrategy } from "src/interfaces/dollet/IStrategy.sol";
import "addresses/OPMainnet.sol";
import "forge-std/Test.sol";

contract WombatCalculationsTest is Test {
    address public constant WANT = 0x0321D1D769cc1e81Ba21a157992b635363740f86; // FRAX pool, LP-USDC

    WombatCalculations public calculations;
    TemporaryAdminStructure public adminStructure;
    StrategyHelper public strategyHelper;
    Mock public strategy;

    address public alice;
    uint256 public pid;

    address[] public rewardTokens = [OP, FXS, WOM];
    uint256[] public minimumToCompound = [1e18, 0.25e18, 0];

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_OP_MAINNET"), 115_591_962);

        Proxy adminStructureProxy = new Proxy(
            address(new TemporaryAdminStructure()),
            abi.encodeWithSignature("initialize()")
        );
        adminStructure = TemporaryAdminStructure(address(adminStructureProxy));

        Proxy wombatCalculationsProxy = new Proxy(
            address(new WombatCalculations()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        calculations = WombatCalculations(address(wombatCalculationsProxy));

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
        vm.mockCall(address(strategy), abi.encodeWithSelector(IWombatStrategy.targetAsset.selector), abi.encode(USDC));
        vm.mockCall(
            address(strategy), abi.encodeWithSelector(IWombatStrategy.pool.selector), abi.encode(WOMBAT_FRAX_USDC_POOL)
        );
        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.want.selector), abi.encode(WANT));
        vm.mockCall(address(strategy), abi.encodeWithSelector(IWombatStrategy.wom.selector), abi.encode(WOM));

        for (uint256 i = 0; i < minimumToCompound.length; ++i) {
            vm.mockCall(
                address(strategy),
                abi.encodeWithSelector(IStrategy.minimumToCompound.selector, rewardTokens[i]),
                abi.encode(minimumToCompound[i])
            );
        }

        pid = IWombatStrategy(address(strategy)).pool().masterWombat().getAssetPid(IStrategy(address(strategy)).want());

        vm.startPrank(adminStructure.superAdmin());

        calculations.setStrategyValues(address(strategy));

        strategyHelper.setOracle(USDC, USDC_ORACLE);
        strategyHelper.setOracle(USDT, USDT_ORACLE);
        strategyHelper.setOracle(OP, OP_ORACLE);
        strategyHelper.setOracle(FXS, FXS_ORACLE);

        vm.stopPrank();
    }

    function test_initialize_ShouldFailWhenCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        calculations.initialize(address(adminStructure));
    }

    function test_initialize() external {
        Proxy wombatCalculationsProxy = new Proxy(
            address(new WombatCalculations()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        WombatCalculations newCalculations = WombatCalculations(address(wombatCalculationsProxy));

        assertEq(address(newCalculations.adminStructure()), address(adminStructure));
    }

    function test_getPendingToCompound_ShouldReturnProperResult1() external {
        (address[] memory rewTokens, uint256[] memory rewardAmounts, bool[] memory enoughRewards, bool atLeastOne) =
            calculations.getPendingToCompound();

        assertEq(rewTokens.length, 3);
        assertEq(rewardAmounts.length, 3);
        assertEq(enoughRewards.length, 3);
        assertEq(rewTokens, rewardTokens);

        for (uint256 i; i < rewardAmounts.length; ++i) {
            assertEq(rewardAmounts[i], 0);
            assertEq(enoughRewards[i], false);
        }

        assertEq(atLeastOne, false);
    }

    function test_getPendingToCompound_ShouldReturnProperResult2() external {
        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool().masterWombat()),
            abi.encodeWithSelector(IMasterWombat.pendingTokens.selector, pid, address(strategy)),
            _getRewardData(0, minimumToCompound[0] - 1, minimumToCompound[1] - 1)
        );

        (address[] memory rewTokens, uint256[] memory rewardAmounts, bool[] memory enoughRewards, bool atLeastOne) =
            calculations.getPendingToCompound();

        assertEq(rewTokens.length, 3);
        assertEq(rewardAmounts.length, 3);
        assertEq(enoughRewards.length, 3);
        assertEq(rewTokens, rewardTokens);

        for (uint256 i; i < rewardAmounts.length; ++i) {
            assertEq(rewardAmounts[i], minimumToCompound[i] > 0 ? minimumToCompound[i] - 1 : 0);
            assertEq(enoughRewards[i], false);
        }

        assertEq(atLeastOne, false);
    }

    function test_getPendingToCompound_ShouldReturnProperResult3() external {
        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool().masterWombat()),
            abi.encodeWithSelector(IMasterWombat.pendingTokens.selector, pid, address(strategy)),
            _getRewardData(0, minimumToCompound[0] - 1, minimumToCompound[1])
        );

        (address[] memory rewTokens, uint256[] memory rewardAmounts, bool[] memory enoughRewards, bool atLeastOne) =
            calculations.getPendingToCompound();

        assertEq(rewTokens.length, 3);
        assertEq(rewardAmounts.length, 3);
        assertEq(enoughRewards.length, 3);
        assertEq(rewTokens, rewardTokens);
        assertEq(rewardAmounts[0], minimumToCompound[0] - 1);
        assertEq(rewardAmounts[1], minimumToCompound[1]);
        assertEq(enoughRewards[0], false);
        assertEq(enoughRewards[1], true);
        assertEq(atLeastOne, true);
    }

    function test_getPendingToCompound_ShouldReturnProperResult4() external {
        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool().masterWombat()),
            abi.encodeWithSelector(IMasterWombat.pendingTokens.selector, pid, address(strategy)),
            _getRewardData(0, minimumToCompound[0], minimumToCompound[1])
        );

        (address[] memory rewTokens, uint256[] memory rewardAmounts, bool[] memory enoughRewards, bool atLeastOne) =
            calculations.getPendingToCompound();

        assertEq(rewTokens.length, 3);
        assertEq(rewardAmounts.length, 3);
        assertEq(enoughRewards.length, 3);
        assertEq(rewTokens, rewardTokens);

        for (uint256 i; i < rewardAmounts.length; ++i) {
            assertEq(rewardAmounts[i], minimumToCompound[i] > 0 ? minimumToCompound[i] : 0);
            assertEq(enoughRewards[i], minimumToCompound[i] > 0 ? true : false);
        }

        assertEq(atLeastOne, true);
    }

    function test_getPendingToCompound_ShouldReturnProperResult5() external {
        uint256 minimumToCompoundWom = 10e18;

        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool().masterWombat()),
            abi.encodeWithSelector(IMasterWombat.pendingTokens.selector, pid, address(strategy)),
            _getRewardData(minimumToCompoundWom, minimumToCompound[0], minimumToCompound[1])
        );
        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.minimumToCompound.selector, WOM),
            abi.encode(minimumToCompoundWom)
        );

        (address[] memory rewTokens, uint256[] memory rewardAmounts, bool[] memory enoughRewards, bool atLeastOne) =
            calculations.getPendingToCompound();

        assertEq(rewTokens.length, 3);
        assertEq(rewardAmounts.length, 3);
        assertEq(enoughRewards.length, 3);
        assertEq(rewTokens, rewardTokens);

        for (uint256 i; i < rewardAmounts.length; ++i) {
            assertEq(rewardAmounts[i], minimumToCompound[i] > 0 ? minimumToCompound[i] : minimumToCompoundWom);
            assertEq(enoughRewards[i], true);
        }

        assertEq(atLeastOne, true);
    }

    function test_userDeposit_ShouldReturnZeroWhenNoDeposit() external {
        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice), abi.encode(0));

        assertEq(calculations.userDeposit(alice, USDC), 0);
    }

    function test_userDeposit_ShouldAnswerInUSDC() external {
        uint256 userWantDeposit = 996_848_849_905_757_984_257; // 1000 USDC
        uint256 expectedUserDeposit = 1000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, USDC), expectedUserDeposit, 1e6);
    }

    function test_userDeposit_ShouldAnswerInUSDT() external {
        uint256 userWantDeposit = 996_848_849_905_757_984_257; // 1000 USDC
        uint256 expectedUserDeposit = 1000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.userWantDeposit.selector, alice),
            abi.encode(userWantDeposit)
        );

        assertApproxEqAbs(calculations.userDeposit(alice, USDT), expectedUserDeposit, 2e6);
    }

    function test_totalDeposits_ShouldReturnZeroWhenNoDeposit() external {
        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.totalWantDeposits.selector), abi.encode(0));

        assertEq(calculations.totalDeposits(USDC), 0);
    }

    function test_totalDeposits_ShouldAnswerInUSDC() external {
        uint256 totalWantDeposits = 996_848_849_905_757_984_257; // 1000 USDC
        uint256 expectedTotalDeposit = 1000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(USDC), expectedTotalDeposit, 1e6);
    }

    function test_totalDeposits_ShouldAnswerInUSDT() external {
        uint256 totalWantDeposits = 996_848_849_905_757_984_257; // 1000 USDC
        uint256 expectedTotalDeposit = 1000e6;

        vm.mockCall(
            address(strategy),
            abi.encodeWithSelector(IStrategy.totalWantDeposits.selector),
            abi.encode(totalWantDeposits)
        );

        assertApproxEqAbs(calculations.totalDeposits(USDT), expectedTotalDeposit, 2e6);
    }

    function test_estimateWantAfterCompound_ShouldReturnPreviousWantBalanceIfNoRewardsToCompound() external {
        uint256 prevWantBalance = 1e18;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));

        assertEq(calculations.estimateWantAfterCompound(100, hex""), prevWantBalance);
    }

    function test_estimateWantAfterCompound_ShouldReturnPreviousWantBalanceIfMinimumToCompoundIsNotReached() external {
        uint256 prevWantBalance = 10e18;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool().masterWombat()),
            abi.encodeWithSelector(IMasterWombat.pendingTokens.selector, pid, address(strategy)),
            _getRewardData(0, minimumToCompound[0] - 1, minimumToCompound[1] - 1)
        );

        assertEq(calculations.estimateWantAfterCompound(100, hex""), prevWantBalance);
    }

    function test_estimateWantAfterCompound_ShouldReturnProperResultIfMinimumToCompoundIsReached1() external {
        uint256 prevWantBalance = 5e18;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool().masterWombat()),
            abi.encodeWithSelector(IMasterWombat.pendingTokens.selector, pid, address(strategy)),
            _getRewardData(0, minimumToCompound[0], minimumToCompound[1] - 1)
        );

        assertTrue(calculations.estimateWantAfterCompound(100, hex"") > prevWantBalance);
    }

    function test_estimateWantAfterCompound_ShouldReturnProperResultIfMinimumToCompoundIsReached2() external {
        uint256 prevWantBalance = 5e18;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool().masterWombat()),
            abi.encodeWithSelector(IMasterWombat.pendingTokens.selector, pid, address(strategy)),
            _getRewardData(0, minimumToCompound[0] - 1, minimumToCompound[1])
        );

        assertTrue(calculations.estimateWantAfterCompound(100, hex"") > prevWantBalance);
    }

    function test_estimateWantAfterCompound_ShouldReturnProperResultIfMinimumToCompoundIsReached3() external {
        uint256 prevWantBalance = 5e18;

        vm.mockCall(address(strategy), abi.encodeWithSelector(IStrategy.balance.selector), abi.encode(prevWantBalance));
        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool().masterWombat()),
            abi.encodeWithSelector(IMasterWombat.pendingTokens.selector, pid, address(strategy)),
            _getRewardData(0, minimumToCompound[0], minimumToCompound[1])
        );

        assertTrue(calculations.estimateWantAfterCompound(100, hex"") > prevWantBalance);
    }

    function test_estimateDeposit_ShouldReturnZeroWhenZeroAmountIsUsed() external {
        assertEq(calculations.estimateDeposit(USDC, 0, 100, hex""), 0);
    }

    function test_estimateDeposit_ShouldReturnZeroWhenExchangeRateIsZero() external {
        vm.mockCall(
            address(IWombatStrategy(address(strategy)).pool()),
            abi.encodeWithSelector(IPool.exchangeRate.selector),
            abi.encode(0)
        );

        assertEq(calculations.estimateDeposit(USDC, 1000e6, 150, hex""), 0);
    }

    function test_estimateDeposit_ShouldEstimateWithUSDCDepositToken() external {
        uint256 expectedEstimationResult = 996_848_849_905_757_984_257;

        assertApproxEqAbs(calculations.estimateDeposit(USDC, 1000e6, 100, hex""), expectedEstimationResult, 2e19);
    }

    function test_estimateDeposit_ShouldEstimateWithUSDTDepositToken() external {
        uint256 expectedEstimationResult = 996_848_849_905_757_984_257;

        assertApproxEqAbs(calculations.estimateDeposit(USDT, 1000e6, 100, hex""), expectedEstimationResult, 2e19);
    }

    function test_estimateWantToToken_ShouldReturnZeroIfZeroAmountIsUsed() external {
        assertEq(calculations.estimateWantToToken(USDC, 0, 100), 0);
    }

    function test_estimateWantToToken_ShouldReturnZeroIfZeroTokenIsUsed() external {
        assertEq(calculations.estimateWantToToken(address(0), 1, 100), 0);
    }

    function test_estimateWantToToken_ShouldAnswerInUSDC() external {
        address token = USDC;
        uint256 wantAmount = 996_848_849_905_757_984_257; // 1000 USDC
        uint256 expectedEstimationResult = 1000e6;
        uint16 slippageTolerance = 100; // 1.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 1e6);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function test_estimateWantToToken_ShouldAnswerInUSDT() external {
        address token = USDT;
        uint256 wantAmount = 996_848_849_905_757_984_257; // 1000 USDC
        uint256 expectedEstimationResult = 1000e6;
        uint16 slippageTolerance = 100; // 1.00%

        assertApproxEqAbs(calculations.estimateWantToToken(token, wantAmount, 0), expectedEstimationResult, 2e6);
        assertApproxEqAbs(
            calculations.estimateWantToToken(token, wantAmount, slippageTolerance),
            expectedEstimationResult,
            expectedEstimationResult * 10_000 / slippageTolerance
        );
    }

    function _getRewardData(
        uint256 pendingRewardsWOM,
        uint256 pendingBonusRewardsOP,
        uint256 pendingBonusRewardsFXS
    )
        private
        pure
        returns (bytes memory)
    {
        address[] memory tokens = new address[](2);
        string[] memory symbols = new string[](2);
        uint256[] memory amounts = new uint256[](2);

        tokens[0] = OP;
        tokens[1] = FXS;

        symbols[0] = "OP";
        symbols[1] = "FXS";

        amounts[0] = pendingBonusRewardsOP;
        amounts[1] = pendingBonusRewardsFXS;

        return abi.encode(pendingRewardsWOM, tokens, symbols, amounts);
    }
}

contract Mock { }
