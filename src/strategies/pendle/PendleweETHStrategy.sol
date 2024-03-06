// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IStrategyHelper } from "../../interfaces/dollet/IStrategyHelper.sol";
import { ERC20Lib } from "../../libraries/ERC20Lib.sol";
import { PendleStrategyV2 } from "./PendleStrategyV2.sol";
import { AddressUtils } from "../../libraries/AddressUtils.sol";
import { IWETH } from "../../interfaces/IWETH.sol";

/**
 * @title Dollet PendleweETHStrategy contract
 * @author Dollet Team
 * @notice Contract representing a strategy for managing funds in the Pendle protocol.
 */
contract PendleweETHStrategy is PendleStrategyV2 {
    using AddressUtils for address;

    address public weeth;
    address public pendle;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this PendleweETHStrategy contract.
     * @param _initParams Strategy initialization paramters structure.
     * @param _weeth The weEth token address.
     * @param _pendle The pendle token address.
     */
    function initialize(InitParams calldata _initParams, address _weeth, address _pendle) external initializer {
        AddressUtils.onlyContract(_weeth);
        AddressUtils.onlyContract(_pendle);

        weeth = _weeth;
        pendle = _pendle;

        _pendleStrategyInitUnchained(_initParams);
    }

    /**
     * @notice This function overrides targetAsset from initialization.
     * @param _targetAsset The address of asset to provide to Pendle.
     */
    function setTargetAsset(address _targetAsset) external {
        _onlySuperAdmin();

        AddressUtils.onlyContract(_targetAsset);

        targetAsset = _targetAsset;
    }

    /**
     * @notice Swaps WETH to WeETH.
     * @param _amountIn An amount of tokens to deposit.
     * @param _slippageTolerance The user accepted slippage tolerance.
     * @return _amountOut Amount of tokens obtained.
     */
    function _getTargetToken(
        address,
        address,
        uint256 _amountIn,
        uint16 _slippageTolerance
    )
        internal
        override
        returns (uint256 _amountOut)
    {
        // WETH => weETH
        IStrategyHelper _strategyHelper = strategyHelper;
        IWETH _weth = weth;

        ERC20Lib.safeApprove(address(_weth), address(_strategyHelper), _amountIn);

        _amountOut = _strategyHelper.swap(address(_weth), weeth, _amountIn, _slippageTolerance, address(this));
    }

    /**
     * @notice Swaps WeETH to WETH.
     * @param _amountIn An amount of tokens to swap.
     * @param _slippageTolerance The user accepted slippage tolerance.
     * @return _amountOut Amount of tokens obtained.
     */
    function _getUserToken(
        address,
        address,
        uint256 _amountIn,
        uint16 _slippageTolerance
    )
        internal
        override
        returns (uint256 _amountOut)
    {
        // weETH => WETH
        IStrategyHelper _strategyHelper = strategyHelper;
        address _weeth = weeth;

        ERC20Lib.safeApprove(_weeth, address(_strategyHelper), _amountIn);

        _amountOut = _strategyHelper.swap(_weeth, address(weth), _amountIn, _slippageTolerance, address(this));
    }

    /**
     * @notice Get WETH token from PENDLE token.
     * @param _amountIn An amount of pendle tokens to swap.
     * @param _slippageTolerance The user accepted slippage tolerance.
     * @return _amountOut Amount of WETH tokens obtained.
     */
    function _getWETHToken(
        address,
        uint256 _amountIn,
        uint16 _slippageTolerance
    )
        internal
        override
        returns (uint256 _amountOut)
    {
        // pendle => WETH
        IStrategyHelper _strategyHelper = strategyHelper;
        address _pendle = pendle;

        ERC20Lib.safeApprove(_pendle, address(_strategyHelper), _amountIn);

        _amountOut = _strategyHelper.swap(_pendle, address(weth), _amountIn, _slippageTolerance, address(this));
    }
}
