// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IStrategyHelper } from "../interfaces/dollet/IStrategyHelper.sol";
import { IAdminStructure } from "../interfaces/dollet/IAdminStructure.sol";
import { ITraderJoeV1Router } from "../interfaces/ITraderJoeV1.sol";
import { AddressUtils } from "../libraries/AddressUtils.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/**
 * @title Dollet OracleTraderJoe contract
 * @author Dollet Team
 * @notice An oracle for a token that uses a TraderJoe pool to price it. Can be used only for pools with 2 tokens.
 */
contract OracleTraderJoeV1 is Initializable, IOracle {
    using AddressUtils for address;

    IAdminStructure public adminStructure;
    IStrategyHelper public strategyHelper;
    ITraderJoeV1Router public router;
    address public tokenA;
    address public tokenB;
    address public weth;

    /**
     * @notice Checks if a transaction sender is a super admin.
     */
    modifier onlySuperAdmin() {
        adminStructure.isValidSuperAdmin(msg.sender);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this contract in time of deployment.
     * @param _adminStructure AdminStructure contract address.
     * @param _strategyHelper StrategyHelper contract address.
     * @param _router Address of TradeJoe router.
     * @param _tokenA Address of tokenA - token to get price of.
     * @param _tokenB Address of tokenB - paired token in pool.
     * @param _weth WETH token address.
     */
    function initialize(
        address _adminStructure,
        address _strategyHelper,
        address _router,
        address _tokenA,
        address _tokenB,
        address _weth
    )
        external
        initializer
    {
        AddressUtils.onlyContract(_adminStructure);
        AddressUtils.onlyContract(_strategyHelper);
        AddressUtils.onlyContract(_router);
        AddressUtils.onlyContract(_tokenA);
        AddressUtils.onlyContract(_tokenB);
        AddressUtils.onlyContract(_weth);

        adminStructure = IAdminStructure(_adminStructure);
        strategyHelper = IStrategyHelper(_strategyHelper);
        router = ITraderJoeV1Router(_router);
        tokenA = _tokenA;
        tokenB = _tokenB;
        weth = _weth;
    }

    /// @inheritdoc IOracle
    function setAdminStructure(address _adminStructure) external onlySuperAdmin {
        AddressUtils.onlyContract(_adminStructure);

        adminStructure = IAdminStructure(_adminStructure);
    }

    /// @inheritdoc IOracle
    function latestAnswer() external view returns (int256) {
        return _latestAnswer();
    }

    /// @inheritdoc IOracle
    function latestRoundData()
        external
        view
        returns (uint80 _roundId, int256 _answer, uint256 _startedAt, uint256 _updatedAt, uint80 _answeredInRound)
    {
        return (0, _latestAnswer(), block.timestamp, block.timestamp, 0);
    }

    /// @inheritdoc IOracle
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /**
     * @notice Returns the latest answer.
     * @return The latest answer.
     */
    function _latestAnswer() private view returns (int256) {
        address[] memory _path = new address[](2);

        _path[0] = tokenA;
        _path[1] = tokenB;

        uint256[] memory _amounts = router.getAmountsOut(10 ** IERC20(_path[0]).decimals(), _path);

        return int256(strategyHelper.value(_path[1], _amounts[1]));
    }

    uint256[50] private __gap;
}
