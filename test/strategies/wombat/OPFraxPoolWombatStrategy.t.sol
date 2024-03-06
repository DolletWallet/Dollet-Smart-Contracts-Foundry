// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IWombatStrategy } from "src/strategies/wombat/interfaces/IWombatStrategy.sol";
import { WombatCalculations } from "src/calculations/wombat/WombatCalculations.sol";
import { TemporaryAdminStructure } from "src/admin/TemporaryAdminStructure.sol";
import { WombatStrategy } from "src/strategies/wombat/WombatStrategy.sol";
import { ICalculations } from "src/interfaces/dollet/ICalculations.sol";
import { IFeeManager } from "src/interfaces/dollet/IFeeManager.sol";
import { StrategyErrors } from "src/libraries/StrategyErrors.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { CompoundVault } from "src/vaults/CompoundVault.sol";
import { SigningUtils } from "../../utils/SigningUtils.sol";
import { VaultErrors } from "src/libraries/VaultErrors.sol";
import { IVault } from "src/interfaces/dollet/IVault.sol";
import { Signature } from "src/libraries/ERC20Lib.sol";
import { FeeManager } from "src/FeeManager.sol";
import {
    StrategyHelperVenueFraxswapV2,
    StrategyHelperVenueUniswapV3,
    StrategyHelper
} from "src/strategies/StrategyHelper.sol";
import "addresses/OPMainnet.sol";
import "forge-std/Test.sol";

contract OPFraxPoolWombatStrategyTest is Test {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    SigningUtils public signingUtils;
    TemporaryAdminStructure public adminStructure;
    StrategyHelper public strategyHelper;
    FeeManager public feeManager;
    WombatCalculations public calculations;
    WombatStrategy public strategy;
    CompoundVault public vault;

    address public alice;
    address public bob;
    address public carol;

    uint256 public alicePrivateKey;

    address public want = 0x0321D1D769cc1e81Ba21a157992b635363740f86; // FRAX pool, LP-USDC
    uint16 public slippageTolerance = 100; // 1.00% (2 decimals)
    address[] public tokensToCompound = [OP, FXS];
    uint256[] public minimumsToCompound = [1e18, 0.25e18];
    address[] public allowedTokens = [USDC];
    uint256[] public limits = [10e6];

    address public managementFeeRecipient = makeAddr("ManagementFeeRecipient");
    address public performanceFeeRecipient = makeAddr("PerformanceFeeRecipient");
    uint16 public managementFee = 0; // 0.00% (2 decimals)
    uint16 public performanceFee = 2000; // 20.00% (2 decimals)

    address public usdcWhale = 0x1AB4973a48dc892Cd9971ECE8e01DcC7688f8F23;

    WombatStrategy.InitParams private initParams;

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_OP_MAINNET"), 115_591_962);

        (alice, alicePrivateKey) = makeAddrAndKey("Alice");
        (bob,) = makeAddrAndKey("Bob");
        (carol,) = makeAddrAndKey("Carol");

        signingUtils = new SigningUtils();

        Proxy adminStructureProxy = new Proxy(
            address(new TemporaryAdminStructure()),
            abi.encodeWithSignature("initialize()")
        );
        adminStructure = TemporaryAdminStructure(address(adminStructureProxy));

        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        Proxy feeManagerProxy = new Proxy(
            address(new FeeManager()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        feeManager = FeeManager(address(feeManagerProxy));

        Proxy wombatCalculationsProxy = new Proxy(
            address(new WombatCalculations()),
            abi.encodeWithSignature("initialize(address)", address(adminStructure))
        );
        calculations = WombatCalculations(address(wombatCalculationsProxy));

        initParams = IWombatStrategy.InitParams({
            adminStructure: address(adminStructure),
            strategyHelper: address(strategyHelper),
            feeManager: address(feeManager),
            weth: WETH,
            want: want,
            pool: WOMBAT_FRAX_USDC_POOL,
            wom: WOM,
            targetAsset: USDC,
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
                WETH,
                address(calculations),
                allowedTokens,
                allowedTokens,
                depositLimits
            )
        );
        vault = CompoundVault(address(compoundVaultProxy));

        StrategyHelperVenueUniswapV3 strategyHelperVenueUniswapV3 = new StrategyHelperVenueUniswapV3(UNISWAP_V3_ROUTER);
        StrategyHelperVenueFraxswapV2 strategyHelperVenueFraxswapV2 =
            new StrategyHelperVenueFraxswapV2(FRAXSWAP_V2_ROUTER);

        vm.startPrank(adminStructure.superAdmin());

        strategy.setSlippageTolerance(slippageTolerance);
        strategy.setVault(address(vault));

        calculations.setStrategyValues(address(strategy));

        feeManager.setFee(address(strategy), IFeeManager.FeeType.MANAGEMENT, managementFeeRecipient, managementFee);
        feeManager.setFee(address(strategy), IFeeManager.FeeType.PERFORMANCE, performanceFeeRecipient, performanceFee);

        strategyHelper.setOracle(WETH, ETH_ORACLE);
        strategyHelper.setOracle(USDC, USDC_ORACLE);
        strategyHelper.setOracle(OP, OP_ORACLE);
        strategyHelper.setOracle(FXS, FXS_ORACLE);

        // OP/WETH
        strategyHelper.setPath(
            OP, WETH, address(strategyHelperVenueUniswapV3), abi.encodePacked(OP, uint24(3000), WETH)
        );

        // FXS/WETH
        strategyHelper.setPath(FXS, WETH, address(strategyHelperVenueFraxswapV2), abi.encodePacked(FXS, FRAX, WETH));

        // WETH/USDC
        strategyHelper.setPath(
            WETH, USDC, address(strategyHelperVenueUniswapV3), abi.encodePacked(WETH, uint24(500), USDC)
        );

        vm.stopPrank();
    }

    function test_initialize_ShouldFailWhenCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        strategy.initialize(initParams);
    }

    function test_initialize_ShouldFailWhenPoolIsNotContract() external {
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

    function test_initialize_ShouldFailWhenWomIsNotContract() external {
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

    function test_initialize_ShouldFailWhenTargetAssetIsNotContract() external {
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

    function test_initialize() external {
        Proxy wombatStrategyProxy = new Proxy(
            address(new WombatStrategy()),
            abi.encodeWithSignature(
                "initialize((address,address,address,address,address,address,address,address,address,address[],uint256[]))",
                initParams
            )
        );
        WombatStrategy newStrategy = WombatStrategy(payable(address(wombatStrategyProxy)));

        assertEq(address(newStrategy.pool()), initParams.pool);
        assertEq(address(newStrategy.wom()), initParams.wom);
        assertEq(address(newStrategy.targetAsset()), initParams.targetAsset);
    }

    function test_pool() external {
        assertEq(address(strategy.pool()), initParams.pool);
    }

    function test_wom() external {
        assertEq(address(strategy.wom()), initParams.wom);
    }

    function test_targetAsset() external {
        assertEq(address(strategy.targetAsset()), initParams.targetAsset);
    }

    function test_balance() external {
        assertEq(strategy.balance(), 0);
    }

    function test_deposit_ShouldFailIfInsufficientDepositTokenOut() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 1000e6;

        _deal(user, amount);

        vm.startPrank(user);

        IERC20Upgradeable(token).safeApprove(address(vault), amount);

        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientDepositTokenOut.selector));

        vault.deposit(user, token, amount, _getAdditionalData(amount * 1e18));

        vm.stopPrank();
    }

    function test_deposit_ShouldDepositInUSDC() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 1000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 2e19);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 2e19);
    }

    function test_deposit_ShouldDepositInUSDCWithPermit() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 1000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), true, alicePrivateKey);

        assertTrue(strategy.totalWantDeposits() > depositEstimationResult);
        assertTrue(strategy.userWantDeposit(user) > depositEstimationResult);
        assertApproxEqAbs(strategy.totalWantDeposits(), depositEstimationResult, 2e19);
        assertApproxEqAbs(strategy.userWantDeposit(user), depositEstimationResult, 2e19);
    }

    function test_deposit_ShouldProcessDepositsOfAFewUsersProperly() external {
        address[3] memory users = [alice, bob, carol];
        uint256[3] memory amounts = [uint256(100e6), 500e6, 1000e6];

        for (uint256 i; i < users.length; ++i) {
            uint256 prevTotalWantDeposits = strategy.totalWantDeposits();
            uint256 depositEstimationResult =
                calculations.estimateDeposit(allowedTokens[0], amounts[i], slippageTolerance, hex"");

            _deposit(users[i], allowedTokens[0], amounts[i], _getAdditionalData(depositEstimationResult), false, 0);

            assertTrue(strategy.totalWantDeposits() > prevTotalWantDeposits);
            assertTrue(strategy.userWantDeposit(users[i]) > depositEstimationResult);
            assertApproxEqAbs(strategy.totalWantDeposits(), prevTotalWantDeposits + depositEstimationResult, 2e19);
            assertApproxEqAbs(strategy.userWantDeposit(users[i]), depositEstimationResult, 2e19);
        }
    }

    function test_withdraw_ShouldFailIfWantToWithdrawIsZero() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 5000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultErrors.WrongAmount.selector));

        vault.withdraw(bob, token, 0, _getAdditionalData(0));
    }

    function test_withdraw_ShouldFailIfInsufficientWithdrawalTokenOut() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 1000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        uint256 amountShares = vault.userShares(user);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(StrategyErrors.InsufficientWithdrawalTokenOut.selector));

        vault.withdraw(bob, token, amountShares, _getAdditionalData(amount * 2));
    }

    function test_withdraw_ShouldWithdrawFullDepositInUSDC() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 1000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        address recipient = bob;
        uint256 amountShares = vault.calculateSharesToWithdraw(user, 0, slippageTolerance, hex"", true);
        ICalculations.WithdrawalEstimation memory withdrawalEstimationResult =
            vault.estimateWithdrawal(user, slippageTolerance, hex"", token);

        assertEq(_balance(token, recipient), 0);

        vm.prank(user);

        vault.withdraw(
            recipient, token, amountShares, _getAdditionalData(withdrawalEstimationResult.depositInTokenAfterFee)
        );

        assertTrue(_balance(token, recipient) > withdrawalEstimationResult.depositInTokenAfterFee);
        assertApproxEqAbs(_balance(token, recipient), withdrawalEstimationResult.depositInTokenAfterFee, 10e6);
        assertEq(strategy.totalWantDeposits(), 0);
        assertEq(strategy.userWantDeposit(user), 0);
    }

    function test_compound_ShouldNotCompoundIfNotEnoughRewardsToClaimAndCompound() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 1000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 6 hours);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(0, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertEq(currStrategyBalance, prevStrategyBalance);
        assertEq(prevStrategyBalance, wantAfterCompoundEstimation);
        assertEq(currStrategyBalance, wantAfterCompoundEstimation);
    }

    function test_compound_ShouldCompoundProperly1() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 50_000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 2 days);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(0, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertTrue(currStrategyBalance > prevStrategyBalance);
        assertTrue(currStrategyBalance < wantAfterCompoundEstimation);
        assertApproxEqAbs(currStrategyBalance, wantAfterCompoundEstimation, 2e17);
    }

    function test_compound_ShouldCompoundProperly2() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 100_000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 5 days);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(0, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertTrue(currStrategyBalance > prevStrategyBalance);
        assertTrue(currStrategyBalance < wantAfterCompoundEstimation);
        assertApproxEqAbs(currStrategyBalance, wantAfterCompoundEstimation, 6e17);
    }

    function test_compound_ShouldCompoundProperly3() external {
        address user = alice;
        address token = USDC;
        uint256 amount = 30_000e6;
        uint256 depositEstimationResult = calculations.estimateDeposit(token, amount, slippageTolerance, hex"");

        _deposit(user, token, amount, _getAdditionalData(depositEstimationResult), false, 0);

        vm.warp(block.timestamp + 3 days);

        uint256 wantAfterCompoundEstimation = calculations.estimateWantAfterCompound(0, hex"");
        uint256 prevStrategyBalance = strategy.balance();

        strategy.compound(hex"");

        uint256 currStrategyBalance = strategy.balance();

        assertTrue(currStrategyBalance > prevStrategyBalance);
        assertTrue(currStrategyBalance < wantAfterCompoundEstimation);
        assertApproxEqAbs(currStrategyBalance, wantAfterCompoundEstimation, 3e17);
    }

    function _deal(address user, uint256 amount) private {
        vm.prank(usdcWhale);

        IERC20Upgradeable(USDC).transfer(user, amount);
    }

    function _deposit(
        address user,
        address token,
        uint256 amount,
        bytes memory additionalData,
        bool withPermit,
        uint256 userPrivateKey
    )
        private
    {
        _deal(user, amount);

        vm.startPrank(user);

        if (withPermit) {
            Signature memory signature =
                signingUtils.signPermit(token, user, userPrivateKey, address(vault), amount, block.timestamp);

            vault.depositWithPermit(user, token, amount, additionalData, signature);
        } else {
            IERC20Upgradeable(token).safeApprove(address(vault), amount);

            vault.deposit(user, token, amount, additionalData);
        }

        vm.stopPrank();
    }

    function _balance(address token, address user) private view returns (uint256) {
        return IERC20Upgradeable(token).balanceOf(user);
    }

    function _getAdditionalData(uint256 minOut) private pure returns (bytes memory) {
        return abi.encode(minOut);
    }
}
