// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { Calculations } from "../calculations/Calculations.sol";
import { IStrategy } from "../interfaces/dollet/IStrategy.sol";
import { StrategyMock } from "./StrategyMock.sol";

contract CalculationsMock is Calculations {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _adminStructure) external initializer {
        _calculationsInitUnchained(_adminStructure);
    }

    function getPendingToCompound(bytes memory _rewardData)
        public
        view
        returns (uint256 _rewardAmount, bool _enoughReward)
    {
        (, uint256[] memory _rewardAmounts) = abi.decode(_rewardData, (address[], uint256[]));

        _rewardAmount = _rewardAmounts[0];
        _enoughReward = _rewardAmount >= IStrategy(strategy).minimumToCompound(StrategyMock(strategy).rewardAsset());
    }

    function convertTargetToWant(uint256 _targetAmount) public pure returns (uint256) {
        uint256 _rate = _getRate();

        return _targetAmount * _rate;
    }

    function convertWantToTarget(uint256 _wantAmount) public pure returns (uint256) {
        uint256 _rate = _getRate();

        return _rate == 0 ? 0 : _wantAmount / _rate;
    }

    function _userDeposit(address _user, address _token) internal view override returns (uint256) {
        return strategyHelper.convert(
            StrategyMock(strategy).targetAsset(),
            _token,
            convertWantToTarget(IStrategy(strategy).userWantDeposit(_user))
        );
    }

    function _totalDeposits(address _token) internal view override returns (uint256) {
        return strategyHelper.convert(
            StrategyMock(strategy).targetAsset(), _token, convertWantToTarget(IStrategy(strategy).totalWantDeposits())
        );
    }

    function _estimateWantAfterCompound(
        uint16 _slippageTolerance,
        bytes memory _rewardData
    )
        internal
        view
        override
        returns (uint256)
    {
        {
            (uint256 _rewardAmount, bool _enoughReward) = getPendingToCompound(_rewardData);
            address payable _strategy = strategy;
            uint256 _targetAmount = _enoughReward
                ? strategyHelper.convert(
                    StrategyMock(_strategy).rewardAsset(), StrategyMock(_strategy).targetAsset(), _rewardAmount
                )
                : 0;

            return IStrategy(_strategy).balance()
                + getMinimumOutputAmount(convertTargetToWant(_targetAmount), _slippageTolerance);
        }
    }

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
        return getMinimumOutputAmount(
            convertTargetToWant(strategyHelper.convert(_token, StrategyMock(strategy).targetAsset(), _amount)),
            _slippageTolerance
        );
    }

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
        return getMinimumOutputAmount(
            strategyHelper.convert(StrategyMock(strategy).targetAsset(), _token, convertWantToTarget(_amount)),
            _slippageTolerance
        );
    }

    function _getRate() private pure returns (uint256) {
        return 1;
    }
}
