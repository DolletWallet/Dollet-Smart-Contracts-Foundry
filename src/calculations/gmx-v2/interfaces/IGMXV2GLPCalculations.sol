// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

/**
 * @title Dollet GMXV2GLPCalculations interface
 * @author Dollet Team
 * @notice An interface for GMXV2GLPCalculations contract.
 */
interface IGMXV2GLPCalculations {
    /**
     * @notice Event emmited when a new USD is set.
     * @param _oldUsd Old USD token address.
     * @param _newUsd New USD token address.
     */
    event UsdSet(address _oldUsd, address _newUsd);

    /**
     * @notice Returns an address of a USD token that is used for calculations.
     * @return An address of a USD token that is used for calculations.
     */
    function usd() external view returns (address);

    /**
     * @notice Sets a new USD token contract address (USDC/USDT/DAI/etc.) by an admin.
     * @param _newUsd A new USD token contract address (USDC/USDT/DAI/etc.).
     */
    function setUsd(address _newUsd) external;

    /**
     * @notice Returns the pending to compound amount in WETH tokens.
     * @return The pending to compound amount in WETH tokens and the flag if there are enough rewards to execute a
     *         compound.
     */
    function getPendingToCompound() external view returns (uint256, bool);
}
