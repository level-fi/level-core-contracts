// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract LevelReserve is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable LVL;
    mapping(address => bool) isDistributor;

    constructor(address lvl) {
        require(lvl != address(0), "Invalid address");
        LVL = IERC20(lvl);
    }

    function addDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "LevelReserve::addDistributor: Invalid address");
        require(!isDistributor[_distributor], "LevelReserve::addDistributor: Address already added");
        isDistributor[_distributor] = true;
        emit DistributorAdded(_distributor);
    }

    function removeDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "LevelReserve::removeDistributor: Invalid address");
        require(isDistributor[_distributor], "LevelReserve::removeDistributor: Distributor not exists");
        isDistributor[_distributor] = false;
        emit DistributorRemoved(_distributor);
    }

    function requestTransfer(address _to, uint256 _amount) external {
        require(_to != address(0), "LevelReserve::requestTransfer: Invalid address");
        require(isDistributor[msg.sender], "LevelReserve::requestTransfer: Not allowed");
        LVL.safeTransfer(_to, _amount);
        emit Distributed(_to, _amount);
    }

    event DistributorAdded(address distributor);
    event DistributorRemoved(address distributor);
    event Distributed(address to, uint256 amount);
}
