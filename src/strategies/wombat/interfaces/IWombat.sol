// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

interface IMasterWombat {
    struct UserInfo {
        uint128 amount;
        uint128 factor;
        uint128 rewardDebt;
        uint128 pendingWom;
    }

    function withdraw(
        uint256 _pid,
        uint256 _amount
    )
        external
        returns (uint256 _reward, uint256[] memory _additionalRewards);

    function multiClaim(uint256[] calldata _pids)
        external
        returns (uint256 _reward, uint256[] memory _amounts, uint256[][] memory _additionalRewards);

    function userInfo(uint256 _pid, address _user) external view returns (UserInfo memory);

    function getAssetPid(address _asset) external view returns (uint256);

    function pendingTokens(
        uint256 _pid,
        address _user
    )
        external
        view
        returns (
            uint256 _pendingRewards,
            address[] memory _bonusTokenAddresses,
            string[] memory _bonusTokenSymbols,
            uint256[] memory _pendingBonusRewards
        );

    function rewarderBonusTokenInfo(uint256 _pid)
        external
        view
        returns (address[] memory _bonusTokenAddresses, string[] memory _bonusTokenSymbols);
}

interface IPool {
    function deposit(
        address _token,
        uint256 _amount,
        uint256 _minimumLiquidity,
        address _to,
        uint256 _deadline,
        bool _shouldStake
    )
        external
        returns (uint256 _liquidity);

    function withdraw(
        address _token,
        uint256 _liquidity,
        uint256 _minimumAmount,
        address _to,
        uint256 _deadline
    )
        external
        returns (uint256 _amount);

    function masterWombat() external view returns (IMasterWombat);

    function exchangeRate(address _token) external view returns (uint256 _xr);
}
