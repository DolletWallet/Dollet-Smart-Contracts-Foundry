// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

/**
 * @title ITraderJoeV1 interface
 * @author Dollet Team
 * @notice TraderJoe V1 Router interface. This interface defines the functions for interacting with the TraderJoe V1
 *         Router contract.
 */
interface ITraderJoeV1Router {
    /**
     * @notice Swaps `_amountIn` of one token for as much as possible of another token.
     * @param _amountIn An amount of input tokens.
     * @param _amountOutMin A minimum acceptable output amount.
     * @param _tokenPath An array of tokens.
     * @param _to A recipient of output tokens.
     * @param _deadline A timestamp when swap transaction will become invalid.
     */
    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _tokenPath,
        address _to,
        uint256 _deadline
    )
        external
        returns (uint256 amountOut);

    /**
     * @notice Gives amount out in case of a swap.
     * @param _amountIn An amount of input tokens.
     * @param _path An array of tokens on pool.
     */
    function getAmountsOut(
        uint256 _amountIn,
        address[] calldata _path
    )
        external
        view
        returns (uint256[] memory amounts);
}
