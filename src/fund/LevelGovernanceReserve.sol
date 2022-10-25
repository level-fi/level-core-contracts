// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract LevelGovernanceReserve is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public immutable LGO;
    mapping(address => bool) isDistributor;

    constructor(address lgo) {
        require(lgo != address(0), "Invalid address");
        LGO = IERC20(lgo);
    }

    function addDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "LevelGovernanceReserve::addDistributor: Invalid address");
        require(!isDistributor[_distributor], "LevelGovernanceReserve::addDistributor: Address already added");
        isDistributor[_distributor] = true;
        emit DistributorAdded(_distributor);
    }

    function removeDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "LevelGovernanceReserve::removeDistributor: Invalid address");
        require(isDistributor[_distributor], "LevelGovernanceReserve::removeDistributor: Distributor not exists");
        isDistributor[_distributor] = false;
        emit DistributorRemoved(_distributor);
    }

    function requestTransfer(address _to, uint256 _amount) external {
        require(_to != address(0), "LevelGovernanceReserve::requestTransfer: Invalid address");
        require(isDistributor[msg.sender], "LevelGovernanceReserve::requestTransfer: Not allowed");
        LGO.safeTransfer(_to, _amount);
        emit Distributed(_to, _amount);
    }

    event DistributorAdded(address distributor);
    event DistributorRemoved(address distributor);
    event Distributed(address to, uint256 amount);
}
