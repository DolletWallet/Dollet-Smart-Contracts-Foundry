// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { OracleLibrary } from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import { IAdminStructure } from "../interfaces/dollet/IAdminStructure.sol";
import { OracleErrors } from "../libraries/OracleErrors.sol";
import { AddressUtils } from "../libraries/AddressUtils.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/**
 * @title Dollet OracleUniswapV3 contract
 * @author Dollet Team
 * @notice An oracle for a token that uses Uniswap V3 pool's TWAP to price it. One of the tokens in the pool must be
 *         WETH.
 */
contract OracleUniswapV3 is Initializable, IOracle {
    using AddressUtils for address;

    uint32 public constant MAX_VALIDITY_DURATION = 2 days;
    uint32 public constant MIN_TWAB_PERIOD = 2 minutes;

    IAdminStructure public adminStructure;
    IOracle public ethOracle;
    IUniswapV3Pool public pool;
    address public weth;
    uint32 public twapPeriod;
    uint32 public validityDuration;

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
     * @param _adminStructure Admin structure contract address.
     * @param _ethOracle ETH oracle address.
     * @param _pool Uniswap V3 pool address.
     * @param _weth WETH token address.
     * @param _twapPeriod TWAP period (in seconds) that will be used to price the token.
     * @param _validityDuration A duration (in seconds) during which the latest answer from the ETH oracle is valid.
     */
    function initialize(
        address _adminStructure,
        address _ethOracle,
        address _pool,
        address _weth,
        uint32 _twapPeriod,
        uint32 _validityDuration
    )
        external
        initializer
    {
        AddressUtils.onlyContract(_adminStructure);
        AddressUtils.onlyContract(_ethOracle);
        AddressUtils.onlyContract(_pool);
        AddressUtils.onlyContract(_weth);

        adminStructure = IAdminStructure(_adminStructure);
        ethOracle = IOracle(_ethOracle);
        pool = IUniswapV3Pool(_pool);
        weth = _weth;

        _setTwapPeriod(_twapPeriod);
        _setValidityDuration(_validityDuration);
    }

    /// @inheritdoc IOracle
    function setAdminStructure(address _adminStructure) external onlySuperAdmin {
        AddressUtils.onlyContract(_adminStructure);

        adminStructure = IAdminStructure(_adminStructure);
    }

    /**
     * @notice Sets a new TWAP period (in seconds) by a super admin.
     * @param _newTwapPeriod New TWAP period (in seconds) that will be used to price the token.
     */
    function setTwapPeriod(uint32 _newTwapPeriod) external onlySuperAdmin {
        _setTwapPeriod(_newTwapPeriod);
    }

    /**
     * @notice Sets a new validity duration (in seconds) by a super admin.
     * @param _newValidityDuration A new duration (in seconds) during which the latest answer from the ETH oracle is valid.
     */
    function setValidityDuration(uint32 _newValidityDuration) external onlySuperAdmin {
        _setValidityDuration(_newValidityDuration);
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
     * @notice Sets a new TWAP period (in seconds).
     * @param _newTwapPeriod New TWAP period (in seconds) that will be used to price the token.
     */
    function _setTwapPeriod(uint32 _newTwapPeriod) private {
        if (_newTwapPeriod < MIN_TWAB_PERIOD) revert OracleErrors.WrongTwabPeriod();

        twapPeriod = _newTwapPeriod;
    }

    /**
     * @notice Sets a new validity duration (in seconds).
     * @param _newValidityDuration A new duration (in seconds) during which the latest answer from the ETH oracle is valid.
     */
    function _setValidityDuration(uint32 _newValidityDuration) private {
        if (_newValidityDuration == 0 || _newValidityDuration > MAX_VALIDITY_DURATION) {
            revert OracleErrors.WrongValidityDuration();
        }

        validityDuration = _newValidityDuration;
    }

    /**
     * @notice Returns the latest answer.
     * @return The latest answer.
     */
    function _latestAnswer() private view returns (int256) {
        IOracle _ethOracle = ethOracle;
        (, int256 _answer,, uint256 _updatedAt,) = _ethOracle.latestRoundData();

        if (block.timestamp - _updatedAt > validityDuration) revert OracleErrors.StalePrice();

        IUniswapV3Pool _pool = pool;
        address _weth = weth;
        address _token0 = _pool.token0();
        address _token = _token0 == _weth ? _pool.token1() : _token0;
        uint32 _twapPeriod = twapPeriod;
        uint32[] memory _secondsAgos = new uint32[](2);

        _secondsAgos[0] = _twapPeriod;

        (int56[] memory _tickCumulatives,) = _pool.observe(_secondsAgos);
        int56 _tickCumulativesDelta = _tickCumulatives[1] - _tickCumulatives[0];
        int24 _tick = int24(_tickCumulativesDelta / int32(_twapPeriod));

        if (_tickCumulativesDelta < 0 && (_tickCumulativesDelta % int32(_twapPeriod) != 0)) --_tick;

        uint256 _price = OracleLibrary.getQuoteAtTick(_tick, uint128(10) ** IERC20(_token).decimals(), _token, _weth);

        return (int256(_price) * _answer) / int256(10 ** _ethOracle.decimals());
    }
}
