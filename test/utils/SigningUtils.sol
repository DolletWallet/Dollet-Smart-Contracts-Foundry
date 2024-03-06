// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.21;

import { ECDSAUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import { IERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20PermitUpgradeable.sol";
import { Signature } from "../../src/libraries/ERC20Lib.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { Vm } from "forge-std/Vm.sol";

contract SigningUtils is StdCheats {
    bytes32 public constant EIP721_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    Vm public constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function signHashGetBytes(uint256 _privateKey, bytes32 _hash) external pure returns (bytes memory _signature) {
        (uint8 _v, bytes32 _r, bytes32 _s) = VM.sign(_privateKey, _hash);

        _signature = abi.encodePacked(_r, _s, _v);
    }

    function getEIP712DomainHash(
        string memory _contractName,
        string memory _version,
        uint256 _chainId,
        address _verifyingContract
    )
        external
        pure
        returns (bytes32)
    {
        bytes memory _encoded = abi.encode(
            EIP721_DOMAIN_TYPEHASH,
            keccak256(bytes(_contractName)),
            keccak256(bytes(_version)),
            _chainId,
            _verifyingContract
        );

        return keccak256(_encoded);
    }

    function signHashGetVRS(
        uint256 _privateKey,
        bytes32 _hash
    )
        public
        pure
        returns (uint8 _v, bytes32 _r, bytes32 _s)
    {
        (_v, _r, _s) = VM.sign(_privateKey, _hash);
    }

    function getPermitHash(
        address _token,
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline
    )
        public
        view
        returns (bytes32)
    {
        uint256 _nonce = IERC20PermitUpgradeable(_token).nonces(_owner);

        return keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, _nonce, _deadline));
    }

    function hashTypedDataV4(address _token, bytes32 _structHash) public view virtual returns (bytes32) {
        bytes32 _domainSeparator = IERC20PermitUpgradeable(_token).DOMAIN_SEPARATOR();

        return ECDSAUpgradeable.toTypedDataHash(_domainSeparator, _structHash);
    }

    function signPermit(
        address _token,
        address _from,
        uint256 _fromPrivateKey,
        address _to,
        uint256 _amount,
        uint256 _deadline
    )
        public
        view
        returns (Signature memory)
    {
        bytes32 _structHash = getPermitHash(_token, _from, _to, _amount, _deadline);
        bytes32 _typeHash = hashTypedDataV4(_token, _structHash);
        (uint8 _v, bytes32 _r, bytes32 _s) = signHashGetVRS(_fromPrivateKey, _typeHash);

        return Signature({ deadline: _deadline, v: _v, r: _r, s: _s });
    }
}
