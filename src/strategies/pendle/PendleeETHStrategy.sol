// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IStrategyHelper } from "../../interfaces/dollet/IStrategyHelper.sol";
import { ERC20Lib } from "../../libraries/ERC20Lib.sol";
import { PendleStrategyV2 } from "./PendleStrategyV2.sol";
import { AddressUtils } from "../../libraries/AddressUtils.sol";
import { ILiquidityPool } from "./interfaces/IEtherFi.sol";
import { IWeETH } from "../../interfaces/IWeETH.sol";

/**
 * @title Dollet PendleeETHStrategy contract
 * @author Dollet Team
 * @notice Contract representing a strategy for managing funds in the Pendle protocol.
 */
contract PendleeETHStrategy is PendleStrategyV2 {
    using AddressUtils for address;

    address public eEthLiquidityPool;
    address public weeth;
    address public pendle;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this PendleeETHStrategy contract.
     * @param _initParams Strategy initialization paramters structure.
     * @param _eEthLiquidityPool The ether.fi liquidity pool address.
     * @param _weeth The weEth token address.
     * @param _pendle The pendle token address.
     */
    function initialize(
        InitParams calldata _initParams,
        address _eEthLiquidityPool,
        address _weeth,
        address _pendle
    )
        external
        initializer
    {
        AddressUtils.onlyContract(_eEthLiquidityPool);
        AddressUtils.onlyContract(_weeth);
        AddressUtils.onlyContract(_pendle);

        eEthLiquidityPool = _eEthLiquidityPool;
        weeth = _weeth;
        pendle = _pendle;

        _pendleStrategyInitUnchained(_initParams);
    }

    /**
     * @notice Deposit ETH into ether.fi liquidity pool.
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
        override
        returns (uint256 _amountOut)
    {
        if (_amountIn != 0) {
            // WETH => eETH
            weth.withdraw(_amountIn);
            _amountOut = ILiquidityPool(eEthLiquidityPool).deposit{ value: _amountIn }();
        }
    }

    /**
     * @notice Swaps eETH to WETH.
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
        address _weeth = weeth;

        // eETH => weETH
        ERC20Lib.safeApprove(targetAsset, _weeth, _amountIn);

        _amountOut = IWeETH(_weeth).wrap(_amountIn);

        // weETH => WETH
        IStrategyHelper _strategyHelper = strategyHelper;

        ERC20Lib.safeApprove(_weeth, address(_strategyHelper), _amountOut);

        _amountOut = _strategyHelper.swap(_weeth, address(weth), _amountOut, _slippageTolerance, address(this));
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
        IStrategyHelper _strategyHelper = strategyHelper;
        address _pendle = pendle;

        ERC20Lib.safeApprove(_pendle, address(_strategyHelper), _amountIn);

        _amountOut = _strategyHelper.swap(_pendle, address(weth), _amountIn, _slippageTolerance, address(this));
    }
}
