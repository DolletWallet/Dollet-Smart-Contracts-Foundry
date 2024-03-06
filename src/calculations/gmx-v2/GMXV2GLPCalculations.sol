// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IGMXV2GLPStrategy } from "../../strategies/gmx-v2/interfaces/IGMXV2GLPStrategy.sol";
import { IGMXV2GLPCalculations } from "./interfaces/IGMXV2GLPCalculations.sol";
import { Calculations } from "../../calculations/Calculations.sol";
import { IStrategy } from "../../interfaces/dollet/IStrategy.sol";
import { AddressUtils } from "../../libraries/AddressUtils.sol";

/**
 * @title Dollet GMXV2GLPCalculations contract
 * @author Dollet Team
 * @notice Contract for doing GMXV2GLPCalculations calculations.
 */
contract GMXV2GLPCalculations is Calculations, IGMXV2GLPCalculations {
    using AddressUtils for address;

    address public usd;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes this GMXV2GLPCalculations contract.
     * @param _adminStructure AdminStructure contract address.
     * @param _usd USD token contract address (USDC/USDT/DAI/etc.).
     */
    function initialize(address _adminStructure, address _usd) external initializer {
        _calculationsInitUnchained(_adminStructure);
        _setUsd(_usd);
    }

    /// @inheritdoc IGMXV2GLPCalculations
    function setUsd(address _newUsd) external {
        _onlyAdmin();
        _setUsd(_newUsd);
    }

    /// @inheritdoc IGMXV2GLPCalculations
    function getPendingToCompound() public view returns (uint256, bool) {
        address _strategy = strategy;
        address _weth = address(IStrategy(_strategy).weth());
        uint256 _claimableWeth = IGMXV2GLPStrategy(_strategy).gmxRewardsHandler().feeGlpTracker().claimable(_strategy)
            + ERC20Upgradeable(_weth).balanceOf(_strategy);

        return (_claimableWeth, _claimableWeth >= IStrategy(_strategy).minimumToCompound(_weth));
    }

    /**
     * @notice Calculates the amount of the user deposit in terms of the specified token.
     * @param _user The address of the user to calculate the deposit amount for.
     * @param _token The address of the token to use.
     * @return The amount of the user deposit in the specified token.
     */
    function _userDeposit(address _user, address _token) internal view override returns (uint256) {
        return strategyHelper.convert(usd, _token, _convertWantToUsd(IStrategy(strategy).userWantDeposit(_user)));
    }

    /**
     * @notice Calculates the amount of the total deposits in terms of the specified token.
     * @param _token The address of the token to use.
     * @return The amount of total deposit in the specified token.
     */
    function _totalDeposits(address _token) internal view override returns (uint256) {
        return strategyHelper.convert(usd, _token, _convertWantToUsd(IStrategy(strategy).totalWantDeposits()));
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
        address _strategy = strategy;
        (uint256 _claimableWeth, bool _isEnoughRewards) = getPendingToCompound();
        uint256 _strategyBalance = IStrategy(_strategy).balance();

        if (!_isEnoughRewards) return _strategyBalance;

        uint256 _usdAmount = strategyHelper.convert(address(IStrategy(_strategy).weth()), usd, _claimableWeth);

        return _strategyBalance + getMinimumOutputAmount(_convertUsdToWant(_usdAmount), _slippageTolerance);
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
        return
            getMinimumOutputAmount(_convertUsdToWant(strategyHelper.convert(_token, usd, _amount)), _slippageTolerance);
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

        return
            getMinimumOutputAmount(strategyHelper.convert(usd, _token, _convertWantToUsd(_amount)), _slippageTolerance);
    }

    /**
     * @notice Sets a new USD token contract address (USDC/USDT/DAI/etc.).
     * @param _newUsd A new USD token contract address (USDC/USDT/DAI/etc.).
     */
    function _setUsd(address _newUsd) private {
        AddressUtils.onlyContract(_newUsd);

        emit UsdSet(usd, _newUsd);

        usd = _newUsd;
    }

    /**
     * @notice Converts specified amount of USD tokens to want tokens.
     * @param _usdAmount An amount of USD tokens to convert to want tokens.
     * @return The equivalent amount of USD tokens in want tokens.
     */
    function _convertUsdToWant(uint256 _usdAmount) private view returns (uint256) {
        uint256 _glpPrice = IGMXV2GLPStrategy(strategy).gmxGlpHandler().glpManager().getPrice(true);

        if (_glpPrice == 0) return 0;

        // 1e48 = 1e30 (GLP price precision) + 1e18 (want token precision)
        return _usdAmount * 1e48 / _glpPrice / (10 ** ERC20Upgradeable(usd).decimals());
    }

    /**
     * @notice Converts specified amount of want tokens to USD tokens.
     * @param _wantAmount An amount of want tokens to convert to USD tokens.
     * @return The equivalent amount of want tokens in USD tokens.
     */
    function _convertWantToUsd(uint256 _wantAmount) private view returns (uint256) {
        uint256 _glpPrice = IGMXV2GLPStrategy(strategy).gmxGlpHandler().glpManager().getPrice(true);

        // 1e48 = 1e30 (GLP price precision) + 1e18 (want token precision)
        return _glpPrice * _wantAmount * (10 ** ERC20Upgradeable(usd).decimals()) / 1e48;
    }
}
