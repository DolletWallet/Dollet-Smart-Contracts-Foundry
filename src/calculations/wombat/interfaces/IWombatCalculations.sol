// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

/**
 * @title Dollet WombatCalculations interface
 * @author Dollet Team
 * @notice An interface for WombatCalculations contract.
 */
interface IWombatCalculations {
    /**
     * @notice Returns information about pending rewards to compound.
     * @return _rewardTokens Addresses of the reward tokens.
     * @return _rewardAmounts Rewards amounts representing pending rewards.
     * @return _enoughRewards List indicating if the reward token is enough to compound.
     * @return _atLeastOne Indicates if there is at least one reward to compound.
     */
    function getPendingToCompound()
        external
        view
        returns (
            address[] memory _rewardTokens,
            uint256[] memory _rewardAmounts,
            bool[] memory _enoughRewards,
            bool _atLeastOne
        );
}
