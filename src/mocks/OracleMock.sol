// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IAdminStructure } from "../interfaces/dollet/IAdminStructure.sol";
import { AddressUtils } from "../libraries/AddressUtils.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/**
 * @title Dollet OracleMock
 * @author Dollet Team
 * @notice Dollet mock oracle contract.
 */
contract OracleMock is Initializable, IOracle {
    using AddressUtils for address;

    IAdminStructure public adminStructure;

    address public token;
    uint256 public price;

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
     * @param _token Token contract address.
     */
    function initialize(address _adminStructure, address _token) external initializer {
        AddressUtils.onlyContract(_adminStructure);
        AddressUtils.onlyContract(_token);

        adminStructure = IAdminStructure(_adminStructure);

        token = _token;
        price = 10 ** IERC20(_token).decimals();
    }

    /// @inheritdoc IOracle
    function setAdminStructure(address _adminStructure) external onlySuperAdmin {
        AddressUtils.onlyContract(_adminStructure);

        adminStructure = IAdminStructure(_adminStructure);
    }

    /**
     * @notice Sets a new token price.
     * @param _price A new token price to set.
     */
    function setPrice(uint256 _price) external {
        price = _price;
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
        // Value of the token it's paired with using it's oracle.
        return int256(price);
    }

    uint256[50] private __gap;
}
