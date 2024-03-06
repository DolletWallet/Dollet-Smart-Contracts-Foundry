// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { AddressUtils } from "../libraries/AddressUtils.sol";
import { OracleCurveV2 } from "./OracleCurveV2.sol";
import { IERC20 } from "../interfaces/IERC20.sol";

/**
 * @title Dollet OracleCurveWeETH contract
 * @author Dollet Team
 * @notice An oracle for a token that uses a Curve pool to price it. Can be used only for pools with 2 tokens.
 */
contract OracleCurveWeETH is OracleCurveV2 {
    using AddressUtils for address;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this OracleCurveWeETH contract.
     * @param _adminStructure AdminStructure contract address.
     * @param _strategyHelper StrategyHelper contract address.
     * @param _pool Address of the Curve pool.
     * @param _index Index of the token in the Curve pool.
     * @param _weth WETH token address.
     */
    function initialize(
        address _adminStructure,
        address _strategyHelper,
        address _pool,
        uint256 _index,
        address _weth
    )
        external
        initializer
    {
        _oracleCurveInitUnchained(_adminStructure, _strategyHelper, _pool, _index, _weth);
    }

    /**
     * @notice Get amount of tokenA from another token amount.
     * @dev In case no need to make previous treatment and only use the curve pool,
     *  should return 10 ** IERC20(_tokenA).decimals()
     * @param _tokenA Address tokenA
     * @return _amountTokenA amount of tokenA equivalent to 1 asset
     */
    function _getAmountTokenA(address _tokenA) internal view override returns (uint256) {
        return 10 ** IERC20(_tokenA).decimals();
    }
}
