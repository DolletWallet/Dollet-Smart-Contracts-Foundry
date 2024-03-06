// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IERC20 } from "../../interfaces/IERC20.sol";
import { PendleLpOracleLib, IPMarket } from "@pendle/core-v2/contracts/oracles/PendleLpOracleLib.sol";
import { IPendleCalculations } from "../../calculations/pendle/interfaces/IPendleCalculations.sol";
import { ISYToken } from "./interfaces/ISYToken.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { IPendleStrategy } from "../../strategies/pendle/interfaces/IPendleStrategy.sol";
import { IStrategyHelper } from "../../interfaces/dollet/IStrategyHelper.sol";
import { CalculationsErrors } from "../../libraries/CalculationsErrors.sol";
import { Calculations } from "../../calculations/Calculations.sol";
import { IStrategy } from "../../interfaces/dollet/IStrategy.sol";

/**
 * @title Dollet PendleLSDCalculationsV2 contract
 * @author Dollet Team
 * @notice Contract for doing PendleLSDStrategy calculations.
 */
contract PendleLSDCalculationsV2 is Calculations, IPendleCalculations {
    using PendleLpOracleLib for IPMarket;

    address syToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this PendleLSDCalculationsV2 contract.
     * @param _adminStructure AdminStructure contraxct address.
     */
    function initialize(address _adminStructure, address _syToken) external initializer {
        _calculationsInitUnchained(_adminStructure);

        syToken = _syToken;
    }

    /// @inheritdoc IPendleCalculations
    function getPendingToCompound(bytes memory _rewardData)
        public
        view
        returns (
            uint256[] memory _rewardAmounts,
            address[] memory _rewardTokens,
            bool[] memory _enoughRewards,
            bool _atLeastOne
        )
    {
        (_rewardTokens, _rewardAmounts) = abi.decode(_rewardData, (address[], uint256[]));
        uint256 _rewardTokensLength = _rewardTokens.length;

        if (_rewardTokensLength != _rewardAmounts.length) revert CalculationsErrors.LengthsMismatch();

        address _strategy = strategy;

        _enoughRewards = new bool[](_rewardTokensLength);

        for (uint256 _i; _i < _rewardTokensLength;) {
            _rewardAmounts[_i] += IERC20(_rewardTokens[_i]).balanceOf(_strategy);
            _enoughRewards[_i] = _rewardAmounts[_i] >= IStrategy(_strategy).minimumToCompound(_rewardTokens[_i]);

            if (_enoughRewards[_i]) _atLeastOne = true;

            unchecked {
                ++_i;
            }
        }
    }

    /// @inheritdoc IPendleCalculations
    function convertTargetToWant(uint256 _amountTarget) public view returns (uint256) {
        IPendleStrategy _strategy = IPendleStrategy(strategy);

        uint256 _amountAsset =
            _amountTarget * ISYToken(syToken).exchangeRate() / 10 ** IERC20(address(_strategy.targetAsset())).decimals();

        uint256 _lpToAssetRate = IPMarket(address(_strategy.pendleMarket())).getLpToAssetRate(_strategy.twapPeriod());

        return _lpToAssetRate == 0 ? 0 : _amountAsset * 1e18 / _lpToAssetRate;
    }

    /// @inheritdoc IPendleCalculations
    function convertWantToTarget(uint256 _amountWant) public view returns (uint256) {
        IPendleStrategy _strategy = IPendleStrategy(strategy);

        uint256 _lpToAssetRate = IPMarket(address(_strategy.pendleMarket())).getLpToAssetRate(_strategy.twapPeriod());
        uint256 _amountAsset = _lpToAssetRate * _amountWant / 1e18;

        return
            _amountAsset * 10 ** IERC20(address(_strategy.targetAsset())).decimals() / ISYToken(syToken).exchangeRate();
    }

    /**
     * @notice Calculates the amount of the user deposit in terms of the specified token.
     * @param _user The address of the user to calculate the deposit amount for.
     * @param _token The address of the token to use.
     * @return The amount of the user deposit in the specified token.
     */
    function _userDeposit(address _user, address _token) internal view override returns (uint256) {
        address _strategy = strategy;

        return strategyHelper.convert(
            IPendleStrategy(_strategy).targetAsset(),
            _token,
            convertWantToTarget(IStrategy(_strategy).userWantDeposit(_user))
        );
    }

    /**
     * @notice Calculates the amount of the total deposits in terms of the specified token.
     * @param _token The address of the token to use.
     * @return The amount of total deposit in the specified token.
     */
    function _totalDeposits(address _token) internal view override returns (uint256) {
        address _strategy = strategy;

        return strategyHelper.convert(
            IPendleStrategy(_strategy).targetAsset(),
            _token,
            convertWantToTarget(IStrategy(_strategy).totalWantDeposits())
        );
    }

    /**
     * @notice Estimates the want balance after a compound operation.
     * @param _slippageTolerance The allowed slippage percentage to use.
     * @param _rewardData Encoded bytes with information about the reward tokens.
     * @return Returns the new want tokens amount.
     */
    function _estimateWantAfterCompound(
        uint16 _slippageTolerance,
        bytes memory _rewardData
    )
        internal
        view
        override
        returns (uint256)
    {
        (
            uint256[] memory _rewardAmounts,
            address[] memory _rewardTokens,
            bool[] memory _enoughRewards,
            bool _atLeastOne
        ) = getPendingToCompound(_rewardData);
        address _strategy = strategy;
        uint256 _wantBalance = IStrategy(_strategy).balance();

        if (!_atLeastOne) return _wantBalance;

        uint256 _rewardAmountsLength = _rewardAmounts.length;
        uint256 _totalInTargetToken;
        IStrategyHelper _strategyHelper = strategyHelper;
        address _targetAsset = IPendleStrategy(_strategy).targetAsset();

        for (uint256 _i; _i < _rewardAmountsLength;) {
            _totalInTargetToken +=
                _enoughRewards[_i] ? _strategyHelper.convert(_rewardTokens[_i], _targetAsset, _rewardAmounts[_i]) : 0;

            unchecked {
                ++_i;
            }
        }

        return _wantBalance + getMinimumOutputAmount(convertTargetToWant(_totalInTargetToken), _slippageTolerance);
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
        address _targetAsset = IPendleStrategy(strategy).targetAsset();

        uint256 _amountInTarget = strategyHelper.convert(_token, _targetAsset, _amount);

        return getMinimumOutputAmount(convertTargetToWant(_amountInTarget), _slippageTolerance);
    }

    /**
     * @notice Estimates an `_amount` of want tokens in the `_token`.
     * @param _token A token address to use for the estimation.
     * @param _amount An number of want tokens to use for the estimation.
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
        virtual
        override
        returns (uint256)
    {
        if (_amount == 0 || _token == address(0)) return 0;

        uint256 _targetAmount = convertWantToTarget(_amount);

        return getMinimumOutputAmount(
            strategyHelper.convert(IPendleStrategy(strategy).targetAsset(), _token, _targetAmount), _slippageTolerance
        );
    }
}
