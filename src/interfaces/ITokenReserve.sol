// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.0;

interface ITokenReserve {
    function requestTransfer(address _to, uint256 _amount) external;
}
