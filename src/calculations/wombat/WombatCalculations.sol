// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IWombatStrategy } from "../../strategies/wombat/interfaces/IWombatStrategy.sol";
import { IMasterWombat } from "../../strategies/wombat/interfaces/IWombat.sol";
import { IStrategyHelper } from "../../interfaces/dollet/IStrategyHelper.sol";
import { IWombatCalculations } from "./interfaces/IWombatCalculations.sol";
import { IStrategy } from "../../interfaces/dollet/IStrategy.sol";
import { Calculations } from "../Calculations.sol";

/**
 * @title Dollet WombatCalculations contract
 * @author Dollet Team
 * @notice Contract for doing WombatCalculations calculations.
 */
contract WombatCalculations is Calculations, IWombatCalculations {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this WombatCalculations contract.
     * @param _adminStructure AdminStructure contract address.
     */
    function initialize(address _adminStructure) external initializer {
        _calculationsInitUnchained(_adminStructure);
    }

    /// @inheritdoc IWombatCalculations
    function getPendingToCompound()
        public
        view
        returns (
            address[] memory _rewardTokens,
            uint256[] memory _rewardAmounts,
            bool[] memory _enoughRewards,
            bool _atLeastOne
        )
    {
        address _strategy = strategy;
        IMasterWombat _masterWombat = IWombatStrategy(_strategy).pool().masterWombat();
        (uint256 _pendingRewards, address[] memory _bonusTokenAddresses,, uint256[] memory _pendingBonusRewards) =
            _masterWombat.pendingTokens(_masterWombat.getAssetPid(IStrategy(_strategy).want()), _strategy);
        uint256 _bonusTokenAddressesLength = _bonusTokenAddresses.length;

        _rewardTokens = new address[](_bonusTokenAddressesLength + 1);
        _rewardAmounts = new uint256[](_bonusTokenAddressesLength + 1);
        _enoughRewards = new bool[](_bonusTokenAddressesLength + 1);

        for (uint256 _i; _i < _bonusTokenAddressesLength; ++_i) {
            _rewardTokens[_i] = _bonusTokenAddresses[_i];
            _rewardAmounts[_i] = _pendingBonusRewards[_i] + IERC20Upgradeable(_rewardTokens[_i]).balanceOf(_strategy);
            _enoughRewards[_i] = _rewardAmounts[_i] != 0
                && _rewardAmounts[_i] >= IStrategy(_strategy).minimumToCompound(_rewardTokens[_i]);

            if (_enoughRewards[_i]) _atLeastOne = true;
        }

        address _wom = IWombatStrategy(_strategy).wom();

        _rewardTokens[_bonusTokenAddressesLength] = _wom;
        _rewardAmounts[_bonusTokenAddressesLength] = _pendingRewards + IERC20Upgradeable(_wom).balanceOf(_strategy);
        _enoughRewards[_bonusTokenAddressesLength] = _rewardAmounts[_bonusTokenAddressesLength] != 0
            && _rewardAmounts[_bonusTokenAddressesLength] >= IStrategy(_strategy).minimumToCompound(_wom);

        if (_enoughRewards[_bonusTokenAddressesLength]) _atLeastOne = true;
    }

    /**
     * @notice Calculates the amount of the user deposit in terms of the specified token.
     * @param _user The address of the user to calculate the deposit amount for.
     * @param _token The address of the token to use.
     * @return The amount of the user deposit in the specified token.
     */
    function _userDeposit(address _user, address _token) internal view override returns (uint256) {
        address _strategy = strategy;
        address _targetAsset = IWombatStrategy(_strategy).targetAsset();

        return strategyHelper.convert(
            _targetAsset,
            _token,
            _convertWantToTargetAsset(IStrategy(_strategy).userWantDeposit(_user), _strategy, _targetAsset)
        );
    }

    /**
     * @notice Calculates the amount of the total deposits in terms of the specified token.
     * @param _token The address of the token to use.
     * @return The amount of total deposit in the specified token.
     */
    function _totalDeposits(address _token) internal view override returns (uint256) {
        address _strategy = strategy;
        address _targetAsset = IWombatStrategy(_strategy).targetAsset();

        return strategyHelper.convert(
            _targetAsset,
            _token,
            _convertWantToTargetAsset(IStrategy(_strategy).totalWantDeposits(), _strategy, _targetAsset)
        );
    }

    /**
     * @notice Estimates the want balance after a compound operation.
     * @param _slippageTolerance The allowed slippage tolerance percentage to use.
     * @return The new want tokens amount.
     */
    function _estimateWantAfterCompound(
        uint16 _slippageTolerance,
        bytes memory
    )
        internal
        view
        override
        returns (uint256)
    {
        (
            address[] memory _rewardTokens,
            uint256[] memory _rewardAmounts,
            bool[] memory _enoughRewards,
            bool _atLeastOne
        ) = getPendingToCompound();
        address _strategy = strategy;
        uint256 _wantBalance = IStrategy(_strategy).balance();

        if (!_atLeastOne) return _wantBalance;

        uint256 _rewardAmountsLength = _rewardAmounts.length;
        uint256 _totalInTargetAsset;
        IStrategyHelper _strategyHelper = strategyHelper;
        address _targetAsset = IWombatStrategy(_strategy).targetAsset();

        for (uint256 _i; _i < _rewardAmountsLength; ++_i) {
            _totalInTargetAsset +=
                _enoughRewards[_i] ? _strategyHelper.convert(_rewardTokens[_i], _targetAsset, _rewardAmounts[_i]) : 0;
        }

        return _wantBalance
            + getMinimumOutputAmount(
                _convertTargetAssetToWant(_totalInTargetAsset, _strategy, _targetAsset), _slippageTolerance
            );
    }

    /**
     * @notice Returns the expected amount of want tokens to be obtained from a deposit.
     * @param _token The token to be used for deposit.
     * @param _amount The amount of tokens to be deposited.
     * @param _slippageTolerance The slippage tolerance for the deposit.
     * @return The minimum LP expected to be obtained from the deposit.
     */
    function _estimateDeposit(
        address _token,
        uint256 _amount,
        uint256 _slippageTolerance,
        bytes calldata
    )
        internal
        view
        override
        returns (uint256)
    {
        address _strategy = strategy;
        address _targetAsset = IWombatStrategy(_strategy).targetAsset();

        return getMinimumOutputAmount(
            _convertTargetAssetToWant(strategyHelper.convert(_token, _targetAsset, _amount), _strategy, _targetAsset),
            _slippageTolerance
        );
    }

    /**
     * @notice Estimates an `_amount` of want tokens in the `_token`.
     * @param _token A token address to use for the estimation.
     * @param _amount A number of want tokens to use for the estimation.
     * @param _slippageTolerance A slippage tolerance to apply at the time of the estimation.
     * @return A number of tokens in the `_token` that is equivalent to the `_amount` in the want token.
     */
    function _estimateWantToToken(
        address _token,
        uint256 _amount,
        uint16 _slippageTolerance
    )
        internal
        view
        override
        returns (uint256)
    {
        if (_amount == 0 || _token == address(0)) return 0;

        address _strategy = strategy;
        address _targetAsset = IWombatStrategy(_strategy).targetAsset();

        return getMinimumOutputAmount(
            strategyHelper.convert(_targetAsset, _token, _convertWantToTargetAsset(_amount, _strategy, _targetAsset)),
            _slippageTolerance
        );
    }

    /**
     * @notice Converts specified amount of target asset tokens to want token.
     * @param _targetAssetAmount An amount of target asset tokens to convert to want token.
     * @param _strategy Strategy contract address.
     * @param _targetAsset Target asset token address.
     * @return The equivalent amount of target asset tokens in want token.
     */
    function _convertTargetAssetToWant(
        uint256 _targetAssetAmount,
        address _strategy,
        address _targetAsset
    )
        private
        view
        returns (uint256)
    {
        uint256 _exchangeRate = IWombatStrategy(_strategy).pool().exchangeRate(_targetAsset);

        if (_exchangeRate == 0) return 0;

        // 1e36 == 1e18 (exchange rate precision) + 1e18 (additional precision)
        return _targetAssetAmount * 1e36 / _exchangeRate / 10 ** ERC20Upgradeable(_targetAsset).decimals();
    }

    /**
     * @notice Converts specified amount of want tokens to target token.
     * @param _wantAmount An amount of want tokens to convert to target token.
     * @param _strategy Strategy contract address.
     * @param _targetAsset Target asset token address.
     * @return The equivalent amount of want tokens in target token.
     */
    function _convertWantToTargetAsset(
        uint256 _wantAmount,
        address _strategy,
        address _targetAsset
    )
        private
        view
        returns (uint256)
    {
        // 1e36 == 1e18 (exchange rate precision) + 1e18 (want token precision)
        return IWombatStrategy(_strategy).pool().exchangeRate(_targetAsset) * _wantAmount
            * 10 ** ERC20Upgradeable(_targetAsset).decimals() / 1e36;
    }
}
