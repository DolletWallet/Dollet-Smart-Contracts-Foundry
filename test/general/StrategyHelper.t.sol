// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { UpgradableContractProxy as Proxy } from "../../src/utils/UpgradableContractProxy.sol";
import { StrategyHelperErrors } from "src/libraries/StrategyHelperErrors.sol";
import { OracleUniswapV3 } from "src/oracles/OracleUniswapV3.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import { IERC20 } from "src/interfaces/IERC20.sol";
import "../../addresses/ETHMainnet.sol";
import {
    StrategyHelper,
    StrategyHelperVenueUniswapV2,
    StrategyHelperVenueUniswapV3
} from "src/strategies/StrategyHelper.sol";
import "forge-std/Test.sol";

contract StrategyHelperTest is Test {
    using SafeERC20Upgradeable for IERC20;

    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;
    address public constant UNISWAP_V3_WETH_USDC_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    address public constant UNISWAP_V3_WETH_USDT_POOL = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;

    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    StrategyHelper public strategyHelper;
    StrategyHelperVenueUniswapV2 public strategyHelperVenueUniswapV2;
    StrategyHelperVenueUniswapV3 public strategyHelperVenueUniswapV3;
    OracleUniswapV3 public usdcOracle;
    OracleUniswapV3 public usdtOracle;

    event OracleSet(address indexed asset, address indexed oracle);
    event PathSet(address indexed from, address indexed to, address indexed venue, bytes path);

    function setUp() external {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_412_791);

        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );

        strategyHelper = StrategyHelper(address(strategyHelperProxy));

        strategyHelperVenueUniswapV2 = new StrategyHelperVenueUniswapV2(UNISWAP_V2_ROUTER);
        strategyHelperVenueUniswapV3 = new StrategyHelperVenueUniswapV3(UNISWAP_V3_ROUTER);

        Proxy usdcOracleProxy = new Proxy(
            address(new OracleUniswapV3()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_V3_WETH_USDC_POOL,
                WETH,
                120,
                43_200
            )
        );

        usdcOracle = OracleUniswapV3(address(usdcOracleProxy));

        Proxy usdtOracleProxy = new Proxy(
            address(new OracleUniswapV3()),
            abi.encodeWithSignature(
                "initialize(address,address,address,address,uint32,uint32)",
                ADMIN_STRUCTURE,
                ETH_ORACLE,
                UNISWAP_V3_WETH_USDT_POOL,
                WETH,
                120,
                43_200
            )
        );

        usdtOracle = OracleUniswapV3(address(usdtOracleProxy));

        vm.startPrank(strategyHelper.adminStructure().getAllAdmins()[0]);

        strategyHelper.setOracle(WETH, ETH_ORACLE);
        strategyHelper.setOracle(USDC, address(usdcOracle));
        strategyHelper.setOracle(USDT, address(usdtOracle));

        strategyHelper.setPath(
            WETH, USDC, address(strategyHelperVenueUniswapV3), abi.encodePacked(WETH, uint24(500), USDC)
        );
        strategyHelper.setPath(
            USDT, WETH, address(strategyHelperVenueUniswapV3), abi.encodePacked(USDT, uint24(3000), WETH)
        );
        strategyHelper.setPath(
            USDC,
            USDT,
            address(strategyHelperVenueUniswapV3),
            abi.encodePacked(USDC, uint24(500), WETH, uint24(3000), USDT)
        );
        strategyHelper.setPath(USDT, USDC, address(strategyHelperVenueUniswapV2), abi.encodePacked(USDT, WETH, USDC));
        strategyHelper.setPath(WETH, USDT, address(strategyHelperVenueUniswapV2), abi.encodePacked(WETH, USDT));

        vm.stopPrank();

        deal(WETH, address(this), 1000e18);
        deal(USDC, address(this), 10_000e6);
        deal(USDT, address(this), 10_000e6);
    }

    function test_oracles() external {
        assertEq(strategyHelper.oracles(address(this)), address(0));
    }

    function test_paths() external {
        (address venue, bytes memory path) = strategyHelper.paths(address(this), address(0));

        assertEq(venue, address(0));
        assertEq(path, hex"");
    }

    function test_adminStructure() external {
        assertEq(address(strategyHelper.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_oneHundredPercents() external {
        assertEq(strategyHelper.ONE_HUNDRED_PERCENTS(), 10_000);
    }

    function test_iInitialize_ShouldFailIfMethodIsCalledMoreThanOnce() external {
        vm.expectRevert(bytes("Initializable: contract is already initialized"));

        strategyHelper.initialize(ADMIN_STRUCTURE);
    }

    function test_initialize_ShouldFailIfAdminStructureIsNotContract() external {
        StrategyHelper newStrategyHelper = new StrategyHelper();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(newStrategyHelper),
            abi.encodeWithSignature("initialize(address)", address(0))
        );
    }

    function test_initialize() external {
        Proxy strategyHelperProxy = new Proxy(
            address(new StrategyHelper()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        StrategyHelper newStrategyHelper = StrategyHelper(address(strategyHelperProxy));

        assertEq(address(newStrategyHelper.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_setAdminStructure_ShouldFailIfNotSuperAdminIsCalling() external {
        vm.expectRevert(bytes("NotSuperAdmin"));

        strategyHelper.setAdminStructure(address(0));
    }

    function test_setAdminStructure_ShouldFailIfAdminStructureIsNotContract() external {
        vm.prank(strategyHelper.adminStructure().superAdmin());
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        strategyHelper.setAdminStructure(address(0));
    }

    function test_setAdminStructure() external {
        address newAdminStructure = address(this);
        address adminStructureBefore = address(strategyHelper.adminStructure());

        vm.prank(strategyHelper.adminStructure().superAdmin());

        strategyHelper.setAdminStructure(newAdminStructure);

        address adminStructureAfter = address(strategyHelper.adminStructure());

        assertTrue(adminStructureAfter == newAdminStructure);
        assertFalse(adminStructureAfter == adminStructureBefore);
    }

    function test_setOracle_ShouldFailIfNotAdminIsCalling() external {
        vm.expectRevert(bytes("NotUserAdmin"));

        strategyHelper.setOracle(address(0), address(0));
    }

    function test_setOracle_ShouldFailIfAssetIsNotContract() external {
        vm.prank(strategyHelper.adminStructure().getAllAdmins()[0]);
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        strategyHelper.setOracle(address(0), address(0));
    }

    function test_setOracle_ShouldFailIfOracleIsNotContract() external {
        vm.prank(strategyHelper.adminStructure().getAllAdmins()[0]);
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        strategyHelper.setOracle(address(this), address(0));
    }

    function test_setOracle() external {
        vm.prank(strategyHelper.adminStructure().getAllAdmins()[0]);
        vm.expectEmit(true, true, true, true, address(strategyHelper));

        address asset = address(this);
        address oracle = address(this);

        emit OracleSet(asset, oracle);

        strategyHelper.setOracle(asset, oracle);

        assertEq(strategyHelper.oracles(asset), oracle);
    }

    function test_setPath_ShouldFailIfNotAdminIsCalling() external {
        vm.expectRevert(bytes("NotUserAdmin"));

        strategyHelper.setPath(address(0), address(0), address(0), hex"");
    }

    function test_setPath_ShouldFailIfFromIsNotContract() external {
        vm.prank(strategyHelper.adminStructure().getAllAdmins()[0]);
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        strategyHelper.setPath(address(0), address(0), address(0), hex"");
    }

    function test_setPath_ShouldFailIfToIsNotContract() external {
        vm.prank(strategyHelper.adminStructure().getAllAdmins()[0]);
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        strategyHelper.setPath(address(this), address(0), address(0), hex"");
    }

    function test_setPath_ShouldFailIfVenueIsNotContract() external {
        vm.prank(strategyHelper.adminStructure().getAllAdmins()[0]);
        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        strategyHelper.setPath(address(this), address(this), address(0), hex"");
    }

    function test_setPath() external {
        vm.prank(strategyHelper.adminStructure().getAllAdmins()[0]);
        vm.expectEmit(true, true, true, true, address(strategyHelper));

        address from = address(this);
        address to = address(this);
        address venue = address(this);
        bytes memory path = bytes("path");

        emit PathSet(from, to, venue, path);

        strategyHelper.setPath(from, to, venue, path);

        (address v, bytes memory p) = strategyHelper.paths(from, to);

        assertEq(v, venue);
        assertEq(p, path);
    }

    function test_swap_ShouldFailIfFromAssetIsNotContract() external {
        uint16 slippageTolerance = strategyHelper.MAX_SLIPPAGE_TOLERANCE();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, alice));

        strategyHelper.swap(alice, USDC, 1, slippageTolerance, address(0));
    }

    function test_swap_ShouldFailIfToAssetIsNotContract() external {
        uint16 slippageTolerance = strategyHelper.MAX_SLIPPAGE_TOLERANCE();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, alice));

        strategyHelper.swap(WETH, alice, 1, slippageTolerance, address(0));
    }

    function test_swap_ShouldFailIfRecipientIsWrong() external {
        uint16 slippageTolerance = strategyHelper.MAX_SLIPPAGE_TOLERANCE();

        vm.expectRevert(StrategyHelperErrors.WrongRecipient.selector);

        strategyHelper.swap(WETH, USDC, 1, slippageTolerance, address(0));
    }

    function test_swap_ShouldReturnZero() external {
        assertEq(strategyHelper.swap(WETH, WETH, 0, strategyHelper.MAX_SLIPPAGE_TOLERANCE(), alice), 0);
    }

    function test_swap_ShouldJustTransferAsset() external {
        address from = WETH;
        address to = WETH;
        uint256 amount = 5e17;
        address recipient = alice;
        uint256 prevBalance = IERC20(WETH).balanceOf(address(this));
        uint256 prevRecipientBalance = IERC20(WETH).balanceOf(recipient);

        IERC20(WETH).safeApprove(address(strategyHelper), amount);

        uint256 out = strategyHelper.swap(from, to, amount, strategyHelper.ONE_HUNDRED_PERCENTS(), recipient);
        uint256 currBalance = IERC20(WETH).balanceOf(address(this));
        uint256 currRecipientBalance = IERC20(WETH).balanceOf(recipient);

        assertEq(out, amount);
        assertEq(currBalance, prevBalance - out);
        assertEq(currRecipientBalance, prevRecipientBalance + out);
    }

    function test_swap_ShouldFailIfPathIsNotSet() external {
        uint16 slippageTolerance = strategyHelper.MAX_SLIPPAGE_TOLERANCE();

        vm.expectRevert(StrategyHelperErrors.UnknownPath.selector);

        strategyHelper.swap(USDC, WETH, 1, slippageTolerance, alice);
    }

    function test_swap_ShouldFailIfSlippageToleranceIsWrong() external {
        uint256 amount = 1;
        uint16 _slippageTolerance = strategyHelper.MAX_SLIPPAGE_TOLERANCE() + 1;

        IERC20(WETH).safeApprove(address(strategyHelper), amount);

        vm.expectRevert(StrategyHelperErrors.WrongSlippageTolerance.selector);

        strategyHelper.swap(WETH, USDC, amount, _slippageTolerance, alice);
    }

    function test_swap_ShouldFailIfZeroMinimumOutputAmount() external {
        uint256 amount = 1;
        uint16 _slippageTolerance = 1;

        IERC20(WETH).safeApprove(address(strategyHelper), amount);

        vm.expectRevert(StrategyHelperErrors.ZeroMinimumOutputAmount.selector);

        strategyHelper.swap(WETH, USDC, amount, _slippageTolerance, alice);
    }

    function test_swap_1() external {
        address from = WETH;
        address to = USDC;
        uint256 amount = 1e18;
        uint16 slippageTolerance = 50;
        address recipient = alice;

        uint256 prevWETHBalance = IERC20(WETH).balanceOf(address(this));
        uint256 prevRecipientUSDCBalance = IERC20(USDC).balanceOf(recipient);

        IERC20(WETH).safeApprove(address(strategyHelper), amount);

        uint256 out = strategyHelper.swap(from, to, amount, slippageTolerance, recipient);
        uint256 currWETHBalance = IERC20(WETH).balanceOf(address(this));
        uint256 currRecipientUSDCBalance = IERC20(USDC).balanceOf(recipient);

        assertEq(currWETHBalance, prevWETHBalance - amount);
        assertEq(currRecipientUSDCBalance, prevRecipientUSDCBalance + out);
    }

    function test_swap_2() external {
        address from = USDT;
        address to = WETH;
        uint256 amount = 1000e6;
        uint16 slippageTolerance = 100;
        address recipient = alice;

        uint256 prevUSDTBalance = IERC20(USDT).balanceOf(address(this));
        uint256 prevRecipientWETHBalance = IERC20(WETH).balanceOf(recipient);

        IERC20(USDT).safeApprove(address(strategyHelper), amount);

        uint256 out = strategyHelper.swap(from, to, amount, slippageTolerance, recipient);
        uint256 currUSDTBalance = IERC20(USDT).balanceOf(address(this));
        uint256 currRecipientWETHBalance = IERC20(WETH).balanceOf(recipient);

        assertEq(currUSDTBalance, prevUSDTBalance - amount);
        assertEq(currRecipientWETHBalance, prevRecipientWETHBalance + out);
    }

    function test_swap_3() external {
        address from = USDC;
        address to = USDT;
        uint256 amount = 500e6;
        uint16 slippageTolerance = 150;
        address recipient = alice;

        uint256 prevUSDCBalance = IERC20(USDC).balanceOf(address(this));
        uint256 prevRecipientUSDTBalance = IERC20(USDT).balanceOf(recipient);

        IERC20(USDC).safeApprove(address(strategyHelper), amount);

        uint256 out = strategyHelper.swap(from, to, amount, slippageTolerance, recipient);
        uint256 currUSDCBalance = IERC20(USDC).balanceOf(address(this));
        uint256 currRecipientUSDTBalance = IERC20(USDT).balanceOf(recipient);

        assertEq(currUSDCBalance, prevUSDCBalance - amount);
        assertEq(currRecipientUSDTBalance, prevRecipientUSDTBalance + out);
    }

    function test_swap_4() external {
        address from = USDT;
        address to = USDC;
        uint256 amount = 10_000e6;
        uint16 slippageTolerance = 200;
        address recipient = bob;

        uint256 prevUSDTBalance = IERC20(USDT).balanceOf(address(this));
        uint256 prevRecipientUSDCBalance = IERC20(USDC).balanceOf(recipient);

        IERC20(USDT).safeApprove(address(strategyHelper), amount);

        uint256 out = strategyHelper.swap(from, to, amount, slippageTolerance, recipient);
        uint256 currUSDTBalance = IERC20(USDT).balanceOf(address(this));
        uint256 currRecipientUSDCBalance = IERC20(USDC).balanceOf(recipient);

        assertEq(currUSDTBalance, prevUSDTBalance - amount);
        assertEq(currRecipientUSDCBalance, prevRecipientUSDCBalance + out);
    }

    function test_swap_5() external {
        address from = WETH;
        address to = USDT;
        uint256 amount = 5e18;
        uint16 slippageTolerance = 250;
        address recipient = bob;

        uint256 prevWETHBalance = IERC20(WETH).balanceOf(address(this));
        uint256 prevRecipientUSDTBalance = IERC20(USDT).balanceOf(recipient);

        IERC20(WETH).safeApprove(address(strategyHelper), amount);

        uint256 out = strategyHelper.swap(from, to, amount, slippageTolerance, recipient);
        uint256 currWETHBalance = IERC20(WETH).balanceOf(address(this));
        uint256 currRecipientUSDTBalance = IERC20(USDT).balanceOf(recipient);

        assertEq(currWETHBalance, prevWETHBalance - amount);
        assertEq(currRecipientUSDTBalance, prevRecipientUSDTBalance + out);
    }

    function test_price_ShouldFailIfOracleIsNotSet() external {
        vm.expectRevert(StrategyHelperErrors.UnknownOracle.selector);

        strategyHelper.price(WBTC);
    }

    function test_price() external {
        assertEq(strategyHelper.price(USDC), 996_582_128_471_419_733);
        assertEq(strategyHelper.price(USDT), 999_176_483_489_967_547);
    }

    function test_value() external {
        address asset = USDC;
        uint256 assetPrice = strategyHelper.price(asset);
        uint256 assetDecimals = IERC20(asset).decimals();
        uint256 assetAmount1 = 100e6;
        uint256 assetAmount2 = 550e5;
        uint256 expectedAssetValue1 = assetPrice * assetAmount1 / 10 ** assetDecimals;
        uint256 expectedAssetValue2 = assetPrice * assetAmount2 / 10 ** assetDecimals;

        assertEq(strategyHelper.value(asset, assetAmount1), expectedAssetValue1);
        assertEq(strategyHelper.value(asset, assetAmount2), expectedAssetValue2);
    }

    function test_convert() external {
        address from = USDC;
        address to = USDT;
        uint256 toPrice = strategyHelper.price(to);
        uint256 toDecimals = IERC20(to).decimals();
        uint256 inputAmount1 = 100e6;
        uint256 inputAmount2 = 550e5;
        uint256 expectedOutputAmount1 = strategyHelper.value(from, inputAmount1) * 10 ** toDecimals / toPrice;
        uint256 expectedOutputAmount2 = strategyHelper.value(from, inputAmount2) * 10 ** toDecimals / toPrice;

        assertEq(strategyHelper.convert(from, to, inputAmount1), expectedOutputAmount1);
        assertEq(strategyHelper.convert(from, to, inputAmount2), expectedOutputAmount2);
    }
}
