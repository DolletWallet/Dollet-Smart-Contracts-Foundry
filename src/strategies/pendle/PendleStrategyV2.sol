// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IPendleCalculations } from "../../calculations/pendle/interfaces/IPendleCalculations.sol";
import { IMarket, ISwapAggregator, IRouter, ISyToken } from "./interfaces/IPendle.sol";
import { IPendleStrategy } from "./interfaces/IPendleStrategy.sol";
import { AddressUtils } from "../../libraries/AddressUtils.sol";
import { ERC20Lib } from "../../libraries/ERC20Lib.sol";
import { Strategy } from "../Strategy.sol";
import { StrategyErrors } from "../../libraries/StrategyErrors.sol";

/**
 * @title Dollet PendleStrategyV2 contract
 * @author Dollet Team
 * @notice Abstract contract representing a strategy for managing funds in the Pendle protocol.
 */
abstract contract PendleStrategyV2 is Strategy, IPendleStrategy {
    using AddressUtils for address;

    // Addresses of Pendle protocol contracts
    IRouter public pendleRouter;
    IMarket public pendleMarket;

    // Address of the target asset in the strategy
    address public targetAsset;

    // Time-weighted average price (TWAP) period for oracle calculations
    uint32 public twapPeriod;

    /// @inheritdoc IPendleStrategy
    function setTwapPeriod(uint32 _newTwapPeriod) external {
        _onlyAdmin();

        twapPeriod = _newTwapPeriod;
    }

    /// @inheritdoc IPendleStrategy
    function balance() public view virtual override(Strategy, IPendleStrategy) returns (uint256) {
        return _getTokenBalance(want);
    }

    /// @inheritdoc IPendleStrategy
    function getPendingToCompound(bytes calldata _rewardData)
        public
        view
        returns (
            uint256[] memory _rewardAmounts,
            address[] memory _rewardTokens,
            bool[] memory _enoughRewards,
            bool _atLeastOne
        )
    {
        return IPendleCalculations(address(calculations)).getPendingToCompound(_rewardData);
    }

    /**
     * @notice Initializes this Pendle Strategy contract.
     * @param _initParams Strategy initialization parameters structure.
     */
    function _pendleStrategyInitUnchained(InitParams calldata _initParams) internal onlyInitializing {
        AddressUtils.onlyContract(_initParams.pendleRouter);
        AddressUtils.onlyContract(_initParams.pendleMarket);

        pendleRouter = IRouter(_initParams.pendleRouter);
        pendleMarket = IMarket(_initParams.pendleMarket);

        _strategyInitUnchained(
            _initParams.adminStructure,
            _initParams.strategyHelper,
            _initParams.feeManager,
            _initParams.weth,
            _initParams.want,
            _initParams.calculations,
            _initParams.tokensToCompound,
            _initParams.minimumsToCompound
        );

        (address _sy,,) = pendleMarket.readTokens();
        (, targetAsset,) = ISyToken(_sy).assetInfo();
        twapPeriod = _initParams.twapPeriod;
    }

    /**
     * @notice Performs a deposit operation.
     * @param _tokenIn Address of the token to deposit.
     * @param _amountIn Amount of the token to deposit.
     * @param _additionalData Additional encoded data for the deposit.
     */
    function _deposit(address _tokenIn, uint256 _amountIn, bytes calldata _additionalData) internal override {
        (uint256 _minTokenOut, uint16 _slippageTolerance) = abi.decode(_additionalData, (uint256, uint16));

        uint256 _amountOut = _addLiquidityPendle(_getTargetToken(_tokenIn, targetAsset, _amountIn, _slippageTolerance));

        if (_amountOut < _minTokenOut) revert StrategyErrors.InsufficientDepositTokenOut();
    }

    /**
     * @notice Withdraws the deposit from pendle.
     * @param _tokenOut Address of the token to withdraw in.
     * @param _wantToWithdraw The want amount to withdraw.
     * @param _additionalData Encoded data which will be used in the time of withdraw.
     */
    function _withdraw(address _tokenOut, uint256 _wantToWithdraw, bytes calldata _additionalData) internal override {
        (uint256 _minTokenOut, uint16 _slippageTolerance) = abi.decode(_additionalData, (uint256, uint16));

        uint256 _amountOut =
            _getUserToken(targetAsset, _tokenOut, _removeLiquidityPendle(_wantToWithdraw), _slippageTolerance);

        if (_amountOut < _minTokenOut) revert StrategyErrors.InsufficientWithdrawalTokenOut();
    }

    /**
     * @notice Compounds rewards by claiming and converting them to the target asset. Optional param: Encoded data
     *         containing information about the compound operation.
     */
    function _compound(bytes memory) internal override {
        IMarket _pendleMarket = pendleMarket;

        _pendleMarket.redeemRewards(address(this));

        address[] memory _rewardTokens = _pendleMarket.getRewardTokens();
        uint256 _rewardTokensLength = _rewardTokens.length;
        uint256 _bal;

        uint16 _slippageTolerance = slippageTolerance;
        uint256 _wethAmountOut;

        for (uint256 _i; _i < _rewardTokensLength;) {
            _bal = _getTokenBalance(_rewardTokens[_i]);

            if (_bal == 0 || _bal < minimumToCompound[_rewardTokens[_i]]) {
                unchecked {
                    ++_i;
                }

                continue;
            }

            _wethAmountOut += _getWETHToken(_rewardTokens[_i], _bal, _slippageTolerance);

            unchecked {
                ++_i;
            }
        }

        uint256 _pendleLPAmountOut =
            _addLiquidityPendle(_getTargetToken(address(weth), targetAsset, _wethAmountOut, _slippageTolerance));

        emit Compounded(_pendleLPAmountOut);
    }

    /**
     * @notice Interacts with Pendle to make a deposit directly in the underlying token.
     * @param _amountIn An amount of `targetAsset` tokens to add as liquidity to the Pendle protocol.
     * @return _amountOut The obtained want
     */
    function _addLiquidityPendle(uint256 _amountIn) internal returns (uint256 _amountOut) {
        if (_amountIn == 0) return 0;

        IRouter _pendleRouter = pendleRouter;
        address _targetAsset = targetAsset;

        ERC20Lib.safeApprove(_targetAsset, address(_pendleRouter), _amountIn);

        (_amountOut,) = _pendleRouter.addLiquiditySingleToken(
            address(this),
            address(pendleMarket),
            0,
            IMarket.ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e14
            }),
            IRouter.TokenInput({
                tokenIn: _targetAsset,
                netTokenIn: _amountIn,
                tokenMintSy: _targetAsset,
                bulk: address(0),
                pendleSwap: address(0),
                swapData: (new ISwapAggregator.SwapData[](1))[0]
            })
        );
    }

    /**
     * @notice Interacts with Pendle to make a withdrawal.
     * @param _amountWantToRemove The amount of want (LP) tokens to withdraw.
     * @return _amountOut The minimum expected token amount.
     */
    function _removeLiquidityPendle(uint256 _amountWantToRemove) internal returns (uint256 _amountOut) {
        IMarket _pendleMarket = pendleMarket;
        IRouter _pendleRouter = pendleRouter;
        address _targetAsset = targetAsset;
        IRouter.TokenOutput memory _tokenOutput = IRouter.TokenOutput({
            tokenOut: _targetAsset,
            minTokenOut: 0,
            tokenRedeemSy: _targetAsset,
            bulk: address(0),
            pendleSwap: address(0),
            swapData: (new ISwapAggregator.SwapData[](1))[0]
        });

        ERC20Lib.safeApprove(address(_pendleMarket), address(_pendleRouter), _amountWantToRemove);

        (_amountOut,) = _pendleRouter.removeLiquiditySingleToken(
            address(this), address(_pendleMarket), _amountWantToRemove, _tokenOutput
        );
    }

    /**
     * @notice Exchange user token to target token.
     * @param _tokenIn The user token address.
     * @param _tokenOut The target token address.
     * @param _amountIn An amount of tokens to transfer.
     * @param _slippageTolerance The user accepted slippage tolerance.
     * @return _amountOut Amount of tokens obtained.
     */
    function _getTargetToken(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint16 _slippageTolerance
    )
        internal
        virtual
        returns (uint256 _amountOut);

    /**
     * @notice Exchange target token to user token.
     * @param _tokenIn The target token address.
     * @param _tokenOut The user token address.
     * @param _amountIn An amount of tokens to transfer.
     * @param _slippageTolerance The user accepted slippage tolerance.
     * @return _amountOut Amount of tokens obtained.
     */
    function _getUserToken(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint16 _slippageTolerance
    )
        internal
        virtual
        returns (uint256 _amountOut);

    /**
     * @notice Get WETH token from reward token.
     * @param _tokenIn The reward token address.
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
        virtual
        returns (uint256 _amountOut);

    uint256[50] private __gap;
}
