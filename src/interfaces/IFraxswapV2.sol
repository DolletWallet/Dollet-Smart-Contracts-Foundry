// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

/**
 * @title FraxswapV2Router interface
 * @author Dollet Team
 * @notice Fraxswap V2 Router interface. This interface defines the functions for interacting with the Fraxswap V2
 *         Router contract.
 */
interface IFraxswapV2Router {
    /**
     * @notice Swaps `_amountIn` of one token for as much as possible of another token.
     * @param _amountIn An amount of input tokens.
     * @param _amountOutMin A minimum acceptable output amount.
     * @param _path A path of the swap.
     * @param _to A recipient of output tokens.
     * @param _deadline A timestamp when swap transaction will become invalid.
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        uint256 _deadline
    )
        external;
}
