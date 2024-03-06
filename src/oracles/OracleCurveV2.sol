// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IStrategyHelper } from "../interfaces/dollet/IStrategyHelper.sol";
import { IAdminStructure } from "../interfaces/dollet/IAdminStructure.sol";
import { OracleErrors } from "../libraries/OracleErrors.sol";
import { AddressUtils } from "../libraries/AddressUtils.sol";
import { ICurvePool } from "../interfaces/ICurve.sol";
import { IOracle } from "../interfaces/IOracle.sol";

/**
 * @title Dollet OracleCurve contract
 * @author Dollet Team
 * @notice An oracle for a token that uses a Curve pool to price it. Can be used only for pools with 2 tokens.
 */
abstract contract OracleCurveV2 is Initializable, IOracle {
    using AddressUtils for address;

    IAdminStructure public adminStructure;
    IStrategyHelper public strategyHelper;
    ICurvePool public pool;

    uint256 public index;
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
     * @param _pool Address of the Curve pool.
     * @param _index Index of the token in the Curve pool.
     * @param _weth WETH token address.
     */
    function _oracleCurveInitUnchained(
        address _adminStructure,
        address _strategyHelper,
        address _pool,
        uint256 _index,
        address _weth
    )
        internal
        onlyInitializing
    {
        AddressUtils.onlyContract(_adminStructure);
        AddressUtils.onlyContract(_strategyHelper);
        AddressUtils.onlyContract(_pool);
        AddressUtils.onlyContract(_weth);

        if (_index > 1) revert OracleErrors.WrongCurvePoolTokenIndex();

        adminStructure = IAdminStructure(_adminStructure);
        strategyHelper = IStrategyHelper(_strategyHelper);
        pool = ICurvePool(_pool);

        index = _index;
        tokenA = _parseToken(ICurvePool(_pool).coins(_index));
        tokenB = _parseToken(ICurvePool(_pool).coins((_index + 1) % 2));

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
     * @notice Get amount of tokenA from another token amount.
     * @dev In case no need to make previous treatment and only use the curve pool,
     *  should return 10 ** tokenA.decimals()
     * @param _tokenA Address tokenA
     * @return _amountTokenA amount of tokenA equivalent to 1 asset
     */
    function _getAmountTokenA(address _tokenA) internal view virtual returns (uint256);

    /**
     * @notice Parse the token address and handle native token.
     * @param _token Address of the token to parse.
     * @return The parsed token address.
     */
    function _parseToken(address _token) private view returns (address) {
        if (_token == address(0) || _token == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) return weth;

        return _token;
    }

    /**
     * @notice Returns the latest answer.
     * @return The latest answer.
     */
    function _latestAnswer() private view returns (int256) {
        int128 _i = int128(int256(index));
        // Price one unit of token (that we are pricing) converted to token (that it's paired with)
        uint256 _amountTokenB = pool.get_dy(_i, (_i + 1) % 2, _getAmountTokenA(tokenA));

        // Value the token it's paired with using it's oracle
        return int256(strategyHelper.value(address(tokenB), _amountTokenB));
    }

    uint256[50] private __gap;
}
