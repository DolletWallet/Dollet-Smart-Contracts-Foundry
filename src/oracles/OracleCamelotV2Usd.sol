// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IAdminStructure } from "../interfaces/dollet/IAdminStructure.sol";
import { ICamelotV2Pair } from "../interfaces/ICamelotV2.sol";
import { AddressUtils } from "../libraries/AddressUtils.sol";
import { IOracle } from "../interfaces/IOracle.sol";

/**
 * @title Dollet OracleCamelotV2Usd contract
 * @author Dollet Team
 * @notice An oracle for a token that uses Camelot V2 pool data to price it. One of the tokens in the pool must be any
 *         USD token.
 */
contract OracleCamelotV2Usd is Initializable, IOracle {
    using AddressUtils for address;

    IAdminStructure public adminStructure;
    ICamelotV2Pair public pair;
    address public usd;

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
     * @param _pair Camelot V2 Pair address.
     * @param _usd USD token address (from Camelot V2 Pair).
     */
    function initialize(address _adminStructure, address _pair, address _usd) external initializer {
        AddressUtils.onlyContract(_adminStructure);
        AddressUtils.onlyContract(_pair);
        AddressUtils.onlyContract(_usd);

        adminStructure = IAdminStructure(_adminStructure);
        pair = ICamelotV2Pair(_pair);
        usd = _usd;
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
        (uint256 _reserve0, uint256 _reserve1,,) = pair.getReserves();

        if (pair.token0() == usd) return int256((_reserve0 * 1e18 / 1e6) * 1e18 / _reserve1);

        return int256((_reserve1 * 1e18 / 1e6) * 1e18 / _reserve0);
    }
}
