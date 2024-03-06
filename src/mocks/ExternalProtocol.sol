// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IStrategyHelper } from "../interfaces/dollet/IStrategyHelper.sol";
import "forge-std/Test.sol";

contract ExternalProtocol is ERC20Upgradeable, Test {
    using SafeERC20Upgradeable for ERC20Upgradeable;

    IStrategyHelper public strategyHelper;
    uint256 public claimAmount;

    constructor(address _strategyHelper) {
        strategyHelper = IStrategyHelper(_strategyHelper);
    }

    function depositProtocol(address _token, uint256 _amount) external returns (uint256 _amountOut) {
        ERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);

        _amountOut = strategyHelper.convert(_token, address(this), _amount);

        _mint(msg.sender, _amountOut);
    }

    function withdrawProtocol(address _token, uint256 _amount) external returns (uint256 _amountOut) {
        _burn(msg.sender, _amount);

        _amountOut = strategyHelper.convert(address(this), _token, _amount);

        deal(_token, address(this), _amountOut);

        ERC20Upgradeable(_token).safeTransfer(msg.sender, _amountOut);
    }

    function claimProtocol() external returns (uint256 _amountOut) {
        _amountOut = claimAmount;

        _mint(msg.sender, _amountOut);
    }

    function setClaimAmount(uint256 _claimAmount) external {
        claimAmount = _claimAmount;
    }
}
