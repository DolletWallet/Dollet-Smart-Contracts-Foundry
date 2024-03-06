// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { PendleLSDCalculations } from "src/calculations/pendle/PendleLSDCalculations.sol";
import { UpgradableContractProxy as Proxy } from "src/utils/UpgradableContractProxy.sol";
import { IPendleStrategy } from "src/strategies/pendle/interfaces/IPendleStrategy.sol";
import { PendleLSDStrategy } from "src/strategies/pendle/PendleLSDStrategy.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { CalculationsErrors } from "src/libraries/CalculationsErrors.sol";
import { Calculations } from "src/calculations/Calculations.sol";
import { AddressUtils } from "src/libraries/AddressUtils.sol";
import "../../../addresses/ETHMainnet.sol";
import "forge-std/Test.sol";

contract MockCalculations is Calculations {
    bool public didWork;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this PendleLSDCalculations contract.
     * @param _adminStructure AdminStructure contraxct address.
     */
    function initialize(address _adminStructure) external initializer {
        _calculationsInitUnchained(_adminStructure);
    }

    function doAdminAction() public {
        _onlyAdmin();
        didWork = true;
    }

    function _userDeposit(address _user, address _token) internal view virtual override returns (uint256) { }

    function _totalDeposits(address _token) internal view virtual override returns (uint256) { }

    function _estimateWantAfterCompound(
        uint16 _slippageTolerance,
        bytes memory _rewardData
    )
        internal
        view
        virtual
        override
        returns (uint256)
    { }

    function _estimateDeposit(
        address _token,
        uint256 _amount,
        uint256 _slippageTolerance,
        bytes calldata _data
    )
        internal
        view
        virtual
        override
        returns (uint256)
    { }

    function _estimateWantToToken(
        address _token,
        uint256 _amount,
        uint16 _slippageTolerance
    )
        internal
        view
        virtual
        override
        returns (uint256)
    { }
}

contract PendleLSDCalculationsTest is Test {
    PendleLSDCalculations public pendleCalculations;
    PendleLSDStrategy public pendleStrategy;
    IAdminStructure public adminStructure;
    address[] public tokensToCompound = [PENDLE];
    uint256[] public minimumsToCompound = [1e18];

    address public constant ADMIN_STRUCTURE = 0x75700B44B1423bf9feC3c0f7b2ba31b1689B8373;
    address public constant WANT = 0x62187066FD9C24559ffB54B0495a304ADe26d50B;

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_281_210);

        adminStructure = IAdminStructure(ADMIN_STRUCTURE);

        Proxy pendleLSDCalculationsProxy = new Proxy(
            address(new PendleLSDCalculations()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        pendleCalculations = PendleLSDCalculations(address(pendleLSDCalculationsProxy));
    }

    function test_adminStructure() public {
        assertEq(address(pendleCalculations.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_initialize_FailsToInitializeWithInvalidAdminStructure() public {
        PendleLSDCalculations implementation = new PendleLSDCalculations();

        vm.expectRevert(abi.encodeWithSelector(AddressUtils.NotContract.selector, address(0)));

        new Proxy(
            address(implementation),
            abi.encodeWithSignature("initialize(address)", address(0))
        );
    }

    function test_initialize() public {
        Proxy pendleLSDCalculationsProxy = new Proxy(
            address(new PendleLSDCalculations()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        PendleLSDCalculations newPendleCalculations = PendleLSDCalculations(address(pendleLSDCalculationsProxy));

        assertEq(address(newPendleCalculations.adminStructure()), ADMIN_STRUCTURE);
    }

    function test_allowsToSetStrategyValues() public {
        address strategyHelper = address(new EmptyMock());
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: strategyHelper,
            feeManager: address(new EmptyMock()),
            weth: WETH,
            want: WANT,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: WANT,
            twapPeriod: 1800,
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

        assertEq(address(pendleCalculations.strategy()), address(0));
        assertEq(address(pendleCalculations.strategyHelper()), address(0));

        vm.prank(adminStructure.superAdmin());

        pendleCalculations.setStrategyValues(address(pendleStrategy));

        assertEq(address(pendleCalculations.strategy()), address(pendleStrategy));
        assertEq(address(pendleCalculations.strategyHelper()), strategyHelper);
    }

    function test_getMinimumOutputAmountFromSlippage() public {
        uint256 amount = 1000 ether;
        uint256 expected = 1000 ether - 100 ether; // -10%
        uint256 obtained = pendleCalculations.getMinimumOutputAmount(amount, 1000);

        assertEq(obtained, expected);
    }

    function test_failsIfLengthsMismatchPendingToCompound() public {
        address[] memory tokens = new address[](2);
        address[] memory amounts = new address[](1);

        tokens[0] = address(1);
        tokens[1] = address(2);

        bytes memory _data = abi.encode(tokens, amounts);

        vm.expectRevert(abi.encodeWithSelector(CalculationsErrors.LengthsMismatch.selector));

        pendleCalculations.getPendingToCompound(_data);
    }

    function test_failsIfCallerIsNotAdmin() public {
        Proxy mockCalculationsProxy = new Proxy(
            address(new MockCalculations()),
            abi.encodeWithSignature("initialize(address)", ADMIN_STRUCTURE)
        );
        MockCalculations mockCalculations = MockCalculations(address(mockCalculationsProxy));

        address strategyHelper = address(new EmptyMock());
        IPendleStrategy.InitParams memory initParams = IPendleStrategy.InitParams({
            adminStructure: ADMIN_STRUCTURE,
            strategyHelper: strategyHelper,
            feeManager: address(new EmptyMock()),
            weth: WETH,
            want: WANT,
            calculations: address(pendleCalculations),
            pendleRouter: PENDLE_ROUTER,
            pendleMarket: WANT,
            twapPeriod: 1800,
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

        assertEq(address(pendleCalculations.strategy()), address(0));
        assertEq(address(pendleCalculations.strategyHelper()), address(0));

        vm.prank(adminStructure.superAdmin());

        mockCalculations.setStrategyValues(address(pendleStrategy));
        vm.expectRevert("NotUserAdmin");
        mockCalculations.doAdminAction();
    }
}

contract EmptyMock { }
