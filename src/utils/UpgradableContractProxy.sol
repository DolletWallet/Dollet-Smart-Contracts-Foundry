// SPDX-License-Identifier: MIT

pragma solidity 0.8.21;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Dollet UpgradableContractProxy contract
 * @author Dollet Team
 * @notice This contract implements a proxy pattern for upgradable contracts, using the ERC1967 standard.
 */
contract UpgradableContractProxy is ERC1967Proxy {
    /**
     * @notice Initializes the upgradable proxy with an initial underlying logic contract and initialization data.
     * @param _logic Address of the initial logic contract.
     * @param _data Encoded function call to be made to the logic contract for initialization.
     */
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) { }
}
