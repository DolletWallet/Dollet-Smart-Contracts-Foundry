// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IPool } from "./IWombat.sol";

/**
 * @title Dollet WombatStrategy interface
 * @author Dollet Team
 * @notice An interface of the WombatStrategy contract.
 */
interface IWombatStrategy {
    /**
     * @notice Strategy initialization parameters structure.
     * @param adminStructure AdminStructure contract address.
     * @param strategyHelper StrategyHelper contract address.
     * @param feeManager FeeManager contract address.
     * @param weth WETH token contract address.
     * @param want Want token contract address.
     * @param pool Wombat pool contract address.
     * @param wom WOM token contract address.
     * @param targetAsset Target asset contract address that is used during the compound operation.
     * @param calculations Calculations contract address.
     * @param tokensToCompound An array of the tokens to set the minimum to compound.
     * @param minimumsToCompound An array of the minimum amounts to compound.
     */
    struct InitParams {
        address adminStructure;
        address strategyHelper;
        address feeManager;
        address weth;
        address want;
        address pool;
        address wom;
        address targetAsset;
        address calculations;
        address[] tokensToCompound;
        uint256[] minimumsToCompound;
    }

    /**
     * @notice Returns an address of the Wombat pool contract.
     * @return An address of the Wombat pool contract.
     */
    function pool() external view returns (IPool);

    /**
     * @notice Returns an address of the target asset contract that is used during the compound operation.
     * @return An address of the target asset contract that is used during the compound operation.
     */
    function targetAsset() external view returns (address);

    /**
     * @notice Returns an address of the WOM token.
     * @return An address of the WOM token.
     */
    function wom() external view returns (address);
}
