// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

interface IGLPManager {
    function getPrice(bool _maximise) external view returns (uint256);
}

interface IRewardTracker {
    function claimable(address _account) external view returns (uint256);
}

interface IRewardRouter {
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    )
        external
        returns (uint256);

    function unstakeAndRedeemGlp(
        address _tokenOut,
        uint256 _glpAmount,
        uint256 _minOut,
        address _receiver
    )
        external
        returns (uint256);

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    )
        external;

    function glpManager() external view returns (IGLPManager);

    function feeGlpTracker() external view returns (IRewardTracker);
}
