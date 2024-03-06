// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IStrategyHelper } from "../../interfaces/dollet/IStrategyHelper.sol";
import { StrategyErrors } from "../../libraries/StrategyErrors.sol";
import { IWombatStrategy } from "./interfaces/IWombatStrategy.sol";
import { IStrategy } from "../../interfaces/dollet/IStrategy.sol";
import { AddressUtils } from "../../libraries/AddressUtils.sol";
import { IMasterWombat, IPool } from "./interfaces/IWombat.sol";
import { ERC20Lib } from "../../libraries/ERC20Lib.sol";
import { Strategy } from "../Strategy.sol";

/**
 * @title Dollet WombatStrategy contract
 * @author Dollet Team
 * @notice An implementation of the WombatStrategy contract.
 */
contract WombatStrategy is Strategy, IWombatStrategy {
    using AddressUtils for address;

    IPool public pool;
    address public wom;
    address public targetAsset;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this contract with initial values.
     * @param _initParams Strategy initialization parameters structure.
     */
    function initialize(InitParams calldata _initParams) external initializer {
        AddressUtils.onlyContract(_initParams.pool);
        AddressUtils.onlyContract(_initParams.wom);
        AddressUtils.onlyContract(_initParams.targetAsset);

        pool = IPool(_initParams.pool);
        wom = _initParams.wom;
        targetAsset = _initParams.targetAsset;

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
        IMasterWombat _masterWombat = pool.masterWombat();

        return _masterWombat.userInfo(_masterWombat.getAssetPid(want), address(this)).amount;
    }

    /**
     * @notice Performs a deposit operation. Adds `targetAsset` as the liquidity to the Wombat protocol.
     * @param _amount Amount of the token to deposit.
     * @param _additionalData Encoded data which will be used in the time of deposit.
     */
    function _deposit(address, uint256 _amount, bytes calldata _additionalData) internal override {
        uint256 _amountOut = _depositAndStake(targetAsset, _amount);
        (uint256 _minTokenOut) = abi.decode(_additionalData, (uint256));

        if (_amountOut < _minTokenOut) revert StrategyErrors.InsufficientDepositTokenOut();
    }

    /**
     * @notice Performs a withdrawal operation. Removes the liquidity in `targetAsset` from the Wombat protocol.
     * @param _wantToWithdraw The want tokens amount to withdraw.
     * @param _additionalData Encoded data which will be used in the time of withdraw.
     */
    function _withdraw(address, uint256 _wantToWithdraw, bytes calldata _additionalData) internal override {
        IPool _pool = pool;
        IMasterWombat _masterWombat = _pool.masterWombat();
        address _want = want;

        _masterWombat.withdraw(_masterWombat.getAssetPid(_want), _wantToWithdraw);

        ERC20Lib.safeApprove(_want, address(_pool), _wantToWithdraw);

        uint256 _amountOut = _pool.withdraw(targetAsset, _wantToWithdraw, 0, address(this), block.timestamp);
        (uint256 _minTokenOut) = abi.decode(_additionalData, (uint256));

        if (_amountOut < _minTokenOut) revert StrategyErrors.InsufficientWithdrawalTokenOut();
    }

    /**
     * @notice Compounds rewards from Wombat. Optional param: encoded data containing information about the compound
     *         operation.
     */
    function _compound(bytes memory) internal override {
        IStrategyHelper _strategyHelper = strategyHelper;
        address _weth = address(weth);
        uint16 _slippageTolerance = slippageTolerance;

        _swapRewardsToWeth(_claimRewards(), _strategyHelper, _weth, _slippageTolerance);
        _executeCompound(_strategyHelper, _weth, _slippageTolerance);
    }

    /**
     * @notice Deposits and stakes an amount of tokens to the Wombat protocol.
     * @param _token A token address to deposit and stake.
     * @param _amount An amount of tokens to deposit and stake.
     * @return _amountOut An amount of output liquidity tokens staked.
     */
    function _depositAndStake(address _token, uint256 _amount) private returns (uint256 _amountOut) {
        IPool _pool = pool;

        ERC20Lib.safeApprove(_token, address(_pool), _amount);

        _amountOut = _pool.deposit(_token, _amount, 0, address(this), block.timestamp, true);
    }

    /**
     * @notice Claims rewards from the Wombat protocol and returns the list of bonus token addresses.
     * @return _bonusTokenAddresses The list of bonus token addresses.
     */
    function _claimRewards() private returns (address[] memory _bonusTokenAddresses) {
        IMasterWombat _masterWombat = pool.masterWombat();
        uint256 _pid = _masterWombat.getAssetPid(want);

        // Withdraw 0 amount == claim all rewards
        _masterWombat.withdraw(_pid, 0);

        (_bonusTokenAddresses,) = _masterWombat.rewarderBonusTokenInfo(_pid);
    }

    /**
     * @notice Swaps rewards in reward token to WETH.
     * @param _rewardToken Reward token address to swap to WETH.
     * @param _strategyHelper StrategyHelper contract address.
     * @param _weth WETH token address.
     * @param _slippageTolerance A slippage tolerance to apply at the time of swap.
     */
    function _swapRewardToWeth(
        address _rewardToken,
        IStrategyHelper _strategyHelper,
        address _weth,
        uint16 _slippageTolerance
    )
        private
    {
        uint256 _bonusTokenBalance = _getTokenBalance(_rewardToken);

        if (_bonusTokenBalance == 0 || _bonusTokenBalance < minimumToCompound[_rewardToken]) return;

        ERC20Lib.safeApprove(_rewardToken, address(_strategyHelper), _bonusTokenBalance);
        _strategyHelper.swap(_rewardToken, _weth, _bonusTokenBalance, _slippageTolerance, address(this));
    }

    /**
     * @notice Swaps claimed from Wombat protocol rewards to WETH if there is enough rewards to compound in each
     *         specific reward token.
     * @param _bonusTokenAddresses A list of addresses of Wombat pool reward tokens.
     * @param _strategyHelper StrategyHelper contract address.
     * @param _weth WETH token address.
     * @param _slippageTolerance A slippage tolerance to apply at the time of swaps.
     */
    function _swapRewardsToWeth(
        address[] memory _bonusTokenAddresses,
        IStrategyHelper _strategyHelper,
        address _weth,
        uint16 _slippageTolerance
    )
        private
    {
        uint256 _bonusTokensLength = _bonusTokenAddresses.length;

        for (uint256 _i; _i < _bonusTokensLength; ++_i) {
            _swapRewardToWeth(_bonusTokenAddresses[_i], _strategyHelper, _weth, _slippageTolerance);
        }

        _swapRewardToWeth(wom, _strategyHelper, _weth, _slippageTolerance);
    }

    /**
     * @notice Swaps WETH to target asset and deposits target asset to the Wombat protocol.
     * @param _strategyHelper StrategyHelper contract address.
     * @param _weth WETH token address.
     * @param _slippageTolerance A slippage tolerance to apply at the time of the swap operation.
     */
    function _executeCompound(IStrategyHelper _strategyHelper, address _weth, uint16 _slippageTolerance) private {
        uint256 _wethAmount = _getTokenBalance(_weth);

        if (_wethAmount != 0) {
            ERC20Lib.safeApprove(_weth, address(_strategyHelper), _wethAmount);

            address _targetAsset = targetAsset;
            uint256 _targetAssetAmountOut =
                _strategyHelper.swap(_weth, _targetAsset, _wethAmount, _slippageTolerance, address(this));
            uint256 _amountOut = _depositAndStake(_targetAsset, _targetAssetAmountOut);

            emit Compounded(_amountOut);
        }
    }
}
