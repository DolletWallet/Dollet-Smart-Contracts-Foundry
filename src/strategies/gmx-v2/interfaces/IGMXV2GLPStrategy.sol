// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { IRewardRouter } from "./IGMXV2.sol";

/**
 * @title Dollet GMXV2GLPStrategy interface
 * @author Dollet Team
 * @notice An interface of the GMXV2GLPStrategy contract.
 */
interface IGMXV2GLPStrategy {
    /**
     * @notice Strategy initialization parameters structure.
     * @param adminStructure AdminStructure contract address.
     * @param strategyHelper StrategyHelper contract address.
     * @param feeManager FeeManager contract address.
     * @param weth WETH token contract address.
     * @param want Want token contract address.
     * @param calculations Calculations contract address.
     * @param gmxGlpHandler GMX's GLP handler contract address.
     * @param gmxRewardsHandler GMX's rewards handler contract address.
     * @param tokensToCompound An array of the tokens to set the minimum to compound.
     * @param minimumsToCompound An array of the minimum amounts to compound.
     */
    struct InitParams {
        address adminStructure;
        address strategyHelper;
        address feeManager;
        address weth;
        address want;
        address calculations;
        address gmxGlpHandler;
        address gmxRewardsHandler;
        address[] tokensToCompound;
        uint256[] minimumsToCompound;
    }

    /**
     * @notice Returns an address of the GMX's GLP handler contract.
     * @return An address of the GMX's GLP handler contract.
     */
    function gmxGlpHandler() external view returns (IRewardRouter);

    /**
     * @notice Returns an address of the GMX's rewards handler contract.
     * @return An address of the GMX's rewards handler contract.
     */
    function gmxRewardsHandler() external view returns (IRewardRouter);
}
