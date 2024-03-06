// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { StrategyErrors } from "../libraries/StrategyErrors.sol";
import { ExternalProtocol } from "./ExternalProtocol.sol";
import { Strategy } from "../strategies/Strategy.sol";

contract StrategyMock is Strategy {
    address public targetAsset;
    address public rewardAsset;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _adminStructure,
        address _strategyHelper,
        address _feeManager,
        address _weth,
        address _want,
        address _calculations,
        address[] calldata _tokensToCompound,
        uint256[] calldata _minimumsToCompound,
        address _targetAsset
    )
        external
        initializer
    {
        _strategyInitUnchained(
            _adminStructure,
            _strategyHelper,
            _feeManager,
            _weth,
            _want,
            _calculations,
            _tokensToCompound,
            _minimumsToCompound
        );

        targetAsset = _targetAsset;
        rewardAsset = _tokensToCompound[0];
    }

    function editUserWantDeposit(address _user, uint256 _amount) external {
        userWantDeposit[_user] = _amount;
    }

    function editTotalWantDeposit(uint256 _amount) external {
        totalWantDeposits = _amount;
    }

    function balance() public view virtual override(Strategy) returns (uint256) {
        return _getTokenBalance(want);
    }

    function _deposit(address _token, uint256 _amount, bytes calldata _additionalData) internal override {
        (uint256 _minTokenOut,) = abi.decode(_additionalData, (uint256, uint16));
        uint256 _amountOut = _depositStrategy(_tokenToTarget(_token, _amount));

        if (_amountOut < _minTokenOut) revert StrategyErrors.InsufficientDepositTokenOut();
    }

    function _withdraw(address token, uint256 _wantToWithdraw, bytes calldata _additionalData) internal override {
        (uint256 _minTokenOut,) = abi.decode(_additionalData, (uint256, uint16));
        uint256 _amountOut = _targetToToken(token, _withdrawStrategy(_wantToWithdraw));

        if (_amountOut < _minTokenOut) revert StrategyErrors.InsufficientWithdrawalTokenOut();
    }

    function _compound(bytes memory) internal virtual override {
        uint256 _amountReward = _claimStrategy();
        uint256 _amountOut = _depositStrategy(_tokenToTarget(rewardAsset, _amountReward));

        emit Compounded(_amountOut);
    }

    function _depositStrategy(uint256 _amountTarget) private returns (uint256 _amountWant) {
        IERC20Upgradeable(targetAsset).approve(want, _amountTarget);

        _amountWant = ExternalProtocol(want).depositProtocol(targetAsset, _amountTarget);
    }

    function _withdrawStrategy(uint256 _amountWant) private returns (uint256 _amountTarget) {
        IERC20Upgradeable(want).approve(want, _amountWant);

        _amountTarget = ExternalProtocol(want).withdrawProtocol(targetAsset, _amountWant);
    }

    function _claimStrategy() private returns (uint256 _amountReward) {
        _amountReward = ExternalProtocol(rewardAsset).claimProtocol();
    }

    function _tokenToTarget(address _tokenIn, uint256 _amount) private returns (uint256 _amountOut) {
        IERC20Upgradeable(_tokenIn).approve(targetAsset, _amount);

        _amountOut = ExternalProtocol(targetAsset).depositProtocol(_tokenIn, _amount);
    }

    function _targetToToken(address _tokenOut, uint256 _amount) private returns (uint256 _amountOut) {
        IERC20Upgradeable(targetAsset).approve(targetAsset, _amount);

        _amountOut = ExternalProtocol(targetAsset).withdrawProtocol(_tokenOut, _amount);
    }
}
