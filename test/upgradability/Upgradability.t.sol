// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy as Proxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { TemporaryAdminStructure } from "src/admin/TemporaryAdminStructure.sol";
import { IAdminStructure } from "src/interfaces/dollet/IAdminStructure.sol";
import { IStrategyHelper } from "src/interfaces/dollet/IStrategyHelper.sol";
import { StrategyHelper } from "src/strategies/StrategyHelper.sol";
import "forge-std/Test.sol";

contract UpgradabilityTest is Test {
    ProxyAdmin public proxyAdmin;
    TemporaryAdminStructure public temporaryAdminStructure;
    StrategyHelper public strategyHelper;

    address public adminStructureImplementationAddress;
    address public strategyHelperImplementationAddress;

    address public owner = makeAddr("Owner");
    address public alice = makeAddr("Alice");
    address public bob = makeAddr("Bob");

    function setUp() public {
        vm.createSelectFork(vm.envString("RPC_ETH_MAINNET"), 18_973_078);

        vm.startPrank(owner);

        proxyAdmin = new ProxyAdmin();
        adminStructureImplementationAddress = address(new TemporaryAdminStructure());
        strategyHelperImplementationAddress = address(new StrategyHelper());

        // Admin structure
        address adminStructureProxyAddress = address(
            new Proxy(
                adminStructureImplementationAddress,
                address(proxyAdmin),
                abi.encodeWithSignature("initialize()")
            )
        );

        temporaryAdminStructure = TemporaryAdminStructure(adminStructureProxyAddress);

        // Strategy helper
        address strategyHelperProxyAddress = address(
            new Proxy(
                strategyHelperImplementationAddress,
                address(proxyAdmin), // Reusing the proxy admin
                abi.encodeWithSignature(
                    "initialize(address)",
                    address(temporaryAdminStructure)
                )
            )
        );

        strategyHelper = StrategyHelper(strategyHelperProxyAddress);

        vm.stopPrank();
    }

    function test_proxyAdmin_intializationOwner() external {
        vm.startPrank(alice);

        ProxyAdmin localProxyAdmin = new ProxyAdmin();

        assertEq(localProxyAdmin.owner(), alice);

        vm.stopPrank();
    }

    function test_proxyAdmin_transferOwnerFailsInvalidUser() external {
        assertEq(proxyAdmin.owner(), owner);

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");

        proxyAdmin.transferOwnership(alice);
    }

    function test_proxyAdmin_getProxyAdmins() external {
        address expectedProxyAdmin = address(proxyAdmin);

        // Validating Admin Struture
        assertEq(
            proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(temporaryAdminStructure))), expectedProxyAdmin
        );

        // Validating Strategy Helper
        assertEq(proxyAdmin.getProxyAdmin(ITransparentUpgradeableProxy(address(strategyHelper))), expectedProxyAdmin);
    }

    function test_adminStucture_superAdmin() external {
        assertEq(temporaryAdminStructure.superAdmin(), owner);
    }

    function test_proxyAdmin_adminStructureChangeProxyAdmin() external {
        ITransparentUpgradeableProxy transparentUpgradeableProxy =
            ITransparentUpgradeableProxy(address(temporaryAdminStructure));

        vm.startPrank(owner);

        assertEq(proxyAdmin.getProxyAdmin(transparentUpgradeableProxy), address(proxyAdmin));

        ProxyAdmin proxyAdmin2 = new ProxyAdmin();

        proxyAdmin.changeProxyAdmin(transparentUpgradeableProxy, address(proxyAdmin2));

        assertEq(proxyAdmin2.getProxyAdmin(transparentUpgradeableProxy), address(proxyAdmin2));

        vm.stopPrank();
    }

    function test_proxyAdmin_strategyHelperChangeProxyAdmin() external {
        ITransparentUpgradeableProxy transparentUpgradeableProxy = ITransparentUpgradeableProxy(address(strategyHelper));

        vm.startPrank(owner);

        assertEq(proxyAdmin.getProxyAdmin(transparentUpgradeableProxy), address(proxyAdmin));

        ProxyAdmin proxyAdmin2 = new ProxyAdmin();
        proxyAdmin.changeProxyAdmin(transparentUpgradeableProxy, address(proxyAdmin2));

        assertEq(proxyAdmin2.getProxyAdmin(transparentUpgradeableProxy), address(proxyAdmin2));

        vm.stopPrank();
    }

    function test_proxyAdmin_transferOwner() external {
        assertEq(proxyAdmin.owner(), owner);

        vm.prank(owner);

        proxyAdmin.transferOwnership(alice);

        assertEq(proxyAdmin.owner(), alice);
    }

    function test_upgrade_adminStructureUpgradeFailsInvalidUser() external {
        TemporaryAdminStructureV2 temporaryAdminStructureV2 = new TemporaryAdminStructureV2();

        // Invalid user
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(temporaryAdminStructure)),
            address(temporaryAdminStructureV2),
            abi.encodeWithSelector(TemporaryAdminStructureV2.reinitialize.selector, 2)
        );
    }

    function test_upgrade_adminStructureCanBeUpgraded() external {
        address superAdminBefore = temporaryAdminStructure.superAdmin();

        ITransparentUpgradeableProxy transparentUpgradeableProxy =
            ITransparentUpgradeableProxy(address(temporaryAdminStructure));

        // Verify implementation before
        assertEq(adminStructureImplementationAddress, proxyAdmin.getProxyImplementation(transparentUpgradeableProxy));

        // Valid user
        vm.startPrank(owner);

        TemporaryAdminStructureV2 temporaryAdminStructureV2 = new TemporaryAdminStructureV2();

        proxyAdmin.upgradeAndCall(
            transparentUpgradeableProxy,
            address(temporaryAdminStructureV2),
            abi.encodeWithSelector(TemporaryAdminStructureV2.reinitialize.selector, 2)
        );

        // Verify implementation after
        assertEq(address(temporaryAdminStructureV2), proxyAdmin.getProxyImplementation(transparentUpgradeableProxy));

        TemporaryAdminStructureV2 temporaryAdminStructureV2Proxy =
            TemporaryAdminStructureV2(address(temporaryAdminStructure));

        // Reading and writing to new state value
        assertEq(temporaryAdminStructureV2Proxy.newValue(), 0);

        temporaryAdminStructureV2Proxy.setNewValue(100);

        assertEq(temporaryAdminStructureV2Proxy.newValue(), 100);

        // Reading from renamed function
        address[] memory listAdmins = temporaryAdminStructureV2Proxy.getAllAdmins2();

        assertEq(listAdmins.length, 1);
        assertEq(listAdmins[0], owner);
        assertEq(temporaryAdminStructure.superAdmin(), superAdminBefore);
    }

    function test_upgrade_strategyHelperCanBeUpgraded() external {
        IAdminStructure adminStructureBefore = strategyHelper.adminStructure();

        ITransparentUpgradeableProxy transparentUpgradeableProxy = ITransparentUpgradeableProxy(address(strategyHelper));

        // Verify implementation before
        assertEq(strategyHelperImplementationAddress, proxyAdmin.getProxyImplementation(transparentUpgradeableProxy));

        // Valid user
        vm.startPrank(owner);

        StrategyHelperV2 strategyHelperV2 = new StrategyHelperV2();

        proxyAdmin.upgradeAndCall(
            transparentUpgradeableProxy,
            address(strategyHelperV2),
            abi.encodeWithSelector(strategyHelperV2.reinitialize.selector, 2)
        );

        // Verify implementation after
        assertEq(address(strategyHelperV2), proxyAdmin.getProxyImplementation(transparentUpgradeableProxy));

        StrategyHelperV2 strategyHelperV2Proxy = StrategyHelperV2(address(strategyHelper));

        // Reading and writing to new state value
        assertEq(strategyHelperV2Proxy.newValue(), 0);

        strategyHelperV2Proxy.setNewValue(100);

        assertEq(strategyHelperV2Proxy.newValue(), 100);
        assertEq(address(strategyHelper.adminStructure()), address(adminStructureBefore));
    }

    function test_upgrade_adminStructureFailToDirectlyReinitialize() external {
        TemporaryAdminStructureV2 temporaryAdminStructureV2 = new TemporaryAdminStructureV2();

        // Calling the integration directly fails
        vm.expectRevert("Initializable: contract is already initialized");

        temporaryAdminStructureV2.reinitialize(2);

        vm.prank(owner);

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(temporaryAdminStructure)),
            address(temporaryAdminStructureV2),
            abi.encodeWithSelector(TemporaryAdminStructureV2.reinitialize.selector, 2)
        );

        // Calling the proxy fails
        vm.expectRevert("Initializable: contract is already initialized");

        temporaryAdminStructureV2.reinitialize(3);

        // Works with the new version through the proxy admin
        vm.prank(owner);

        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(temporaryAdminStructure)),
            address(temporaryAdminStructureV2),
            abi.encodeWithSelector(TemporaryAdminStructureV2.reinitialize.selector, 3)
        );
    }

    function test_upgrade_adminStructureFailToDirectlyInitialize() external {
        // Calling the integration directly fails
        vm.expectRevert("Initializable: contract is already initialized");

        temporaryAdminStructure.initialize();
    }
}

/**
 * @title Dollet TemporaryAdminStructureV2 test contract
 */
contract TemporaryAdminStructureV2 is Initializable {
    address public superAdmin;
    address public potentialSuperAdmin;
    uint256 public newValue;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Throws an error if the caller is not the super admin.
     * @param _caller The address of the caller.
     */
    modifier onlySuperAdmin(address _caller) {
        require(_caller == superAdmin, "NotSuperAdmin");
        _;
    }

    /**
     * @notice Reinitializes the contract.
     * @param _version A new version of the contract.
     */
    function reinitialize(uint8 _version) external reinitializer(_version) { }

    /**
     * @notice Throws if the caller is not a super admin.
     */
    function isValidSuperAdmin(address _caller) external view onlySuperAdmin(_caller) { }

    /**
     * @notice Returns the list of all admins.
     */
    function getAllAdmins2() external view returns (address[] memory _adminsList) {
        _adminsList = new address[](1);
        _adminsList[0] = superAdmin;
    }

    /**
     * @notice Allows anyone to set the new value.
     * @param _newValue A new value to set.
     */
    function setNewValue(uint256 _newValue) external {
        newValue = _newValue;
    }
}

/**
 * @title Dollet StrategyHelperV2 test contract
 */
contract StrategyHelperV2 is Initializable, IStrategyHelper {
    uint16 public constant ONE_HUNDRED_PERCENTS = 10_000; // 100.00%
    uint16 public constant MAX_SLIPPAGE_TOLERANCE = 3000; // 30.00%

    mapping(address asset => address oracle) public oracles;
    mapping(address from => mapping(address to => Path path)) public paths;
    IAdminStructure public adminStructure;
    uint256 public newValue;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Reinitializes the contract.
     * @param _version A new version of the contract.
     */
    function reinitialize(uint8 _version) external reinitializer(_version) { }

    /// @inheritdoc IStrategyHelper
    function setOracle(address _asset, address _oracle) external { }

    /// @inheritdoc IStrategyHelper
    function setPath(address _from, address _to, address _venue, bytes calldata _path) external { }

    /// @inheritdoc IStrategyHelper
    function swap(
        address _from,
        address _to,
        uint256 _amount,
        uint16 _slippageTolerance,
        address _recipient
    )
        external
        returns (uint256)
    { }

    /// @inheritdoc IStrategyHelper
    function price(address _asset) public view returns (uint256) { }

    /// @inheritdoc IStrategyHelper
    function value(address _asset, uint256 _amount) public view returns (uint256) { }

    /// @inheritdoc IStrategyHelper
    function convert(address _from, address _to, uint256 _amount) public view returns (uint256) { }

    /// @inheritdoc IStrategyHelper
    function setAdminStructure(address _adminStructure) external { }

    /**
     * @notice Allows anyone to set the new value.
     * @param _newValue A new value to set.
     */
    function setNewValue(uint256 _newValue) external {
        newValue = _newValue;
    }
}
