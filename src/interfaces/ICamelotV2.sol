// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

/**
 * @title ICamelotV2Router interface
 * @author Dollet Team
 * @notice Camelot V2 Router interface. This interface defines the functions for interacting with the Camelot V2 Router
 *         contract.
 */
interface ICamelotV2Router {
    /**
     * @notice Swaps `_amountIn` of one token for as much as possible of another token.
     * @param _amountIn An amount of input tokens.
     * @param _amountOutMin A minimum acceptable output amount.
     * @param _path A path of the swap.
     * @param _to A recipient of output tokens.
     * @param _referrer A referrer address.
     * @param _deadline A timestamp when swap transaction will become invalid.
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] calldata _path,
        address _to,
        address _referrer,
        uint256 _deadline
    )
        external;
}

/**
 * @title ICamelotV2Pair interface
 * @author Dollet Team
 * @notice Camelot V2 Pair interface. This interface defines the functions for interacting with the Camelot V2 Pair
 *         contract.
 */
interface ICamelotV2Pair {
    /**
     * @notice Returns the address of the first token in the Camelot V2 Pair.
     * @return The address of the first token in the Camelot V2 Pair.
     */
    function token0() external view returns (address);

    /**
     * @notice Returns the information about reserves in the Camelot V2 Pair.
     * @return _reserve0 An amount of the first token in the Camelot V2 Pair.
     * @return _reserve1 An amount of the second token in the Camelot V2 Pair.
     * @return _token0FeePercent A percentage of fee of the first token the Camelot V2 Pair.
     * @return _token1FeePercent A percentage of fee of the second token the Camelot V2 Pair.
     */
    function getReserves()
        external
        view
        returns (uint112 _reserve0, uint112 _reserve1, uint16 _token0FeePercent, uint16 _token1FeePercent);
}
