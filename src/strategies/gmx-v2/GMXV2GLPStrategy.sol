// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IGMXV2GLPStrategy } from "./interfaces/IGMXV2GLPStrategy.sol";
import { StrategyErrors } from "../../libraries/StrategyErrors.sol";
import { IStrategy } from "../../interfaces/dollet/IStrategy.sol";
import { AddressUtils } from "../../libraries/AddressUtils.sol";
import { ERC20Lib } from "../../libraries/ERC20Lib.sol";
import { IRewardRouter } from "./interfaces/IGMXV2.sol";
import { Strategy } from "../Strategy.sol";

/**
 * @title Dollet GMXV2GLPStrategy contract
 * @author Dollet Team
 * @notice An implementation of the GMXV2GLPStrategy contract.
 */
contract GMXV2GLPStrategy is Strategy, IGMXV2GLPStrategy {
    using AddressUtils for address;

    IRewardRouter public gmxGlpHandler;
    IRewardRouter public gmxRewardsHandler;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this contract with initial values.
     * @param _initParams Strategy initialization parameters structure.
     */
    function initialize(InitParams calldata _initParams) external initializer {
        AddressUtils.onlyContract(_initParams.gmxGlpHandler);
        AddressUtils.onlyContract(_initParams.gmxRewardsHandler);

        gmxGlpHandler = IRewardRouter(_initParams.gmxGlpHandler);
        gmxRewardsHandler = IRewardRouter(_initParams.gmxRewardsHandler);

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
    }

    /// @inheritdoc IStrategy
    function balance() public view override returns (uint256) {
        return _getTokenBalance(want);
    }

    /**
     * @notice Performs a deposit operation. Adds `_token` as the liquidity to the GMX V2 protocol.
     * @param _token Address of the token to deposit.
     * @param _amount Amount of the token to deposit.
     * @param _additionalData Encoded data which will be used in the time of deposit.
     */
    function _deposit(address _token, uint256 _amount, bytes calldata _additionalData) internal override {
        uint256 _amountOut;
        (uint256 _minTokenOut) = abi.decode(_additionalData, (uint256));
        IRewardRouter _gmxGlpHandler = gmxGlpHandler;

        ERC20Lib.safeApprove(_token, address(_gmxGlpHandler.glpManager()), _amount);

        _amountOut = _gmxGlpHandler.mintAndStakeGlp(_token, _amount, 0, 0);

        if (_amountOut < _minTokenOut) revert StrategyErrors.InsufficientDepositTokenOut();
    }

    /**
     * @notice Performs a withdrawal operation. Removes the liquidity in `_tokenOut` from the GMX V2 protocol.
     * @param _tokenOut Address of the token to withdraw in.
     * @param _wantToWithdraw The want tokens amount to withdraw.
     * @param _additionalData Encoded data which will be used in the time of withdraw.
     */
    function _withdraw(address _tokenOut, uint256 _wantToWithdraw, bytes calldata _additionalData) internal override {
        uint256 _amountOut;
        (uint256 _minTokenOut) = abi.decode(_additionalData, (uint256));
        IRewardRouter _gmxGlpHandler = gmxGlpHandler;

        ERC20Lib.safeApprove(want, address(_gmxGlpHandler), _wantToWithdraw);

        _amountOut = _gmxGlpHandler.unstakeAndRedeemGlp(_tokenOut, _wantToWithdraw, 0, address(this));

        if (_amountOut < _minTokenOut) revert StrategyErrors.InsufficientWithdrawalTokenOut();
    }

    /**
     * @notice Compounds rewards from GMX V2. Optional param: encoded data containing information about the compound
     *         operation.
     */
    function _compound(bytes memory) internal override {
        IRewardRouter _gmxRewardsHandler = gmxRewardsHandler;
        address _weth = address(weth);
        uint256 _claimableWeth = _gmxRewardsHandler.feeGlpTracker().claimable(address(this)) + _getTokenBalance(_weth);

        if (_claimableWeth != 0 && _claimableWeth >= minimumToCompound[_weth]) {
            _gmxRewardsHandler.handleRewards(true, true, true, true, true, true, false);

            uint256 _wethAmount = _getTokenBalance(_weth);
            IRewardRouter _gmxGlpHandler = gmxGlpHandler;

            ERC20Lib.safeApprove(_weth, address(_gmxGlpHandler.glpManager()), _wethAmount);

            uint256 _amountOut = _gmxGlpHandler.mintAndStakeGlp(_weth, _wethAmount, 0, 0);

            emit Compounded(_amountOut);
        }
    }
}
