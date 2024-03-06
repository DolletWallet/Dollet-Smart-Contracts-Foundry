// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IStrategyHelper } from "../../interfaces/dollet/IStrategyHelper.sol";
import { AddressUtils } from "../../libraries/AddressUtils.sol";
import { PendleStrategyV2 } from "./PendleStrategyV2.sol";
import { ERC20Lib } from "../../libraries/ERC20Lib.sol";

/**
 * @title Dollet PendlesETHStrategy contract
 * @author Dollet Team
 * @notice Contract representing a strategy for managing funds in the Pendle protocol.
 */
contract PendlesETHStrategy is PendleStrategyV2 {
    using AddressUtils for address;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this PendlesETHStrategy contract.
     * @param _initParams Strategy initialization paramters structure.
     */
    function initialize(InitParams calldata _initParams) external initializer {
        _pendleStrategyInitUnchained(_initParams);
    }

    /**
     * @notice Target asset is user token, this function returns same amount.
     * @param _amountIn An amount of tokens to deposit.
     * @return _amountOut Amount of tokens obtained.
     */
    function _getTargetToken(
        address,
        address,
        uint256 _amountIn,
        uint16
    )
        internal
        pure
        override
        returns (uint256 _amountOut)
    {
        _amountOut = _amountIn;
    }

    /**
     * @notice User token is target asset, this function returns same amount.
     * @param _amountIn An amount of tokens to withdraw.
     * @return _amountOut Amount of tokens obtained.
     */
    function _getUserToken(
        address,
        address,
        uint256 _amountIn,
        uint16
    )
        internal
        pure
        override
        returns (uint256 _amountOut)
    {
        _amountOut = _amountIn;
    }

    /**
     * @notice Get WETH token from reward token.
     * @param _tokenIn address of input token to swap.
     * @param _amountIn An amount of reward tokens to swap.
     * @param _slippageTolerance The user accepted slippage tolerance.
     * @return _amountOut Amount of WETH tokens obtained.
     */
    function _getWETHToken(
        address _tokenIn,
        uint256 _amountIn,
        uint16 _slippageTolerance
    )
        internal
        override
        returns (uint256 _amountOut)
    {
        IStrategyHelper _strategyHelper = strategyHelper;

        ERC20Lib.safeApprove(_tokenIn, address(_strategyHelper), _amountIn);

        _amountOut = _strategyHelper.swap(_tokenIn, address(weth), _amountIn, _slippageTolerance, address(this));
    }
}
