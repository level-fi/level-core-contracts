// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import "../interfaces/ITokenReserve.sol";

/// @title Erc20 reserve
/// @author LevelFinance developer
/// @notice reserve protocol token and distribute to authorized party when needed
contract Erc20Reserve is Ownable, ITokenReserve {
    using SafeERC20 for IERC20;

    IERC20 public immutable TOKEN;

    mapping(address => bool) public isDistributor;
    address[] private allDistributors;

    constructor(address _token) {
        if (_token == address(0)) {
            revert InvalidAddress(_token);
        }
        TOKEN = IERC20(_token);
    }

    function getAllDistributors() external view returns (address[] memory list) {
        return allDistributors;
    }

    function addDistributor(address _distributor) external onlyOwner {
        if (_distributor == address(0)) {
            revert InvalidAddress(_distributor);
        }
        if (isDistributor[_distributor]) {
            revert DistributorAlreadyAdded(_distributor);
        }
        isDistributor[_distributor] = true;
        allDistributors.push(_distributor);
        emit DistributorAdded(_distributor);
    }

    function removeDistributor(address _distributor) external onlyOwner {
        if (!isDistributor[_distributor]) {
            revert NotDistributor(_distributor);
        }
        isDistributor[_distributor] = false;
        for (uint256 i = 0; i < allDistributors.length; i++) {
            if (allDistributors[i] == _distributor) {
                allDistributors[i] = allDistributors[allDistributors.length - 1];
                break;
            }
        }
        allDistributors.pop();
        emit DistributorRemoved(_distributor);
    }

    function requestTransfer(address _to, uint256 _amount) external {
        if (!isDistributor[msg.sender]) {
            revert NotDistributor(msg.sender);
        }
        if (_to == address(0)) {
            revert InvalidAddress(_to);
        }

        TOKEN.safeTransfer(_to, _amount);
        emit Distributed(_to, _amount);
    }

    event DistributorAdded(address distributor);
    event DistributorRemoved(address distributor);
    event Distributed(address to, uint256 amount);

    error InvalidAddress(address);
    error DistributorAlreadyAdded(address);
    error NotDistributor(address);
}
