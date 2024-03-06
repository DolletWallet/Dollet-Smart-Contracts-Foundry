// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

interface IWeETH {
    function getWeETHByeETH(uint256 _eETHAmount) external view returns (uint256);

    function wrap(uint256 _eETHAmount) external returns (uint256);
}
