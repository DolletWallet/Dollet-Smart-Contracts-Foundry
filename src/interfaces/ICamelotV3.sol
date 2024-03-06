// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

/**
 * @title ICamelotV3Router interface
 * @author Dollet Team
 * @notice Camelot V3 Router interface. This interface defines the functions for interacting with the Camelot V3 Router
 *         contract.
 */
interface ICamelotV3Router {
    /**
     * @notice ExactInputSingle parameters structure.
     * @param tokenIn A token address to swap from.
     * @param tokenOut A token address to swap to.
     * @param recipient A recipient of output tokens.
     * @param deadline A timestamp when swap transaction will become invalid.
     * @param amountIn An amount of input tokens.
     * @param amountOutMinimum Minimum acceptable output amount.
     * @param limitSqrtPrice Squared price limit.
     */
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 limitSqrtPrice;
    }

    /**
     * @notice Swaps `amountIn` of one token for as much as possible of another token.
     * @param _params The parameters necessary for the swap, encoded as `ExactInputSingleParams` in calldata.
     * @return _amountOut The amount of the received token.
     */
    function exactInputSingle(ExactInputSingleParams calldata _params) external payable returns (uint256 _amountOut);
}

/**
 * @title ICamelotV3Pool interface
 * @author Dollet Team
 * @notice Camelot V3 pool interface. This interface defines the functions for interacting with the Camelot V3 pool
 *         contract.
 */
interface ICamelotV3Pool {
    /**
     * @notice Returns the first of the two tokens of the pool.
     * @return The first of the two tokens of the pool.
     */
    function token0() external view returns (address);

    /**
     * @notice Returns the second of the two tokens of the pool.
     * @return The second of the two tokens of the pool.
     */
    function token1() external view returns (address);

    /**
     * @notice Returns the cumulative tick and liquidity as of each timestamp `_secondsAgos` from the current block
     *         timestamp.
     * @dev To get a time weighted average tick or liquidity-in-range, you must call this with two values, one
     *      representing the beginning of the period and another for the end of the period. E.g., to get the last hour
     *      time-weighted average tick, you must call it with `_secondsAgos` = [3600, 0].
     * @dev The time weighted average tick represents the geometric time weighted average price of the pool, in log base
     *      sqrt(1.0001) of token1/token0. The TickMath library can be used to go from a tick value to a ratio.
     * @param _secondsAgos From how long ago each cumulative tick and liquidity value should be returned.
     * @return _tickCumulatives Cumulative tick values as of each `_secondsAgos` from the current block timestamp.
     * @return _secondsPerLiquidityCumulatives Cumulative seconds per liquidity-in-range value as of each `_secondsAgos`
     *                                         from the current block timestamp
     * @return _volatilityCumulatives Cumulative standard deviation as of each `_secondsAgos`.
     * @return _volumePerAvgLiquiditys Cumulative swap volume per liquidity as of each `_secondsAgos`.
     */
    function getTimepoints(uint32[] calldata _secondsAgos)
        external
        view
        returns (
            int56[] memory _tickCumulatives,
            uint160[] memory _secondsPerLiquidityCumulatives,
            uint112[] memory _volatilityCumulatives,
            uint256[] memory _volumePerAvgLiquiditys
        );
}
