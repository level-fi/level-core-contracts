// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

contract DevFund is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public LVL;

    uint256 public constant DURATION = 4 * 365 * 24 * 3600; // 4 years
    uint256 public constant EPOCH = 28 * 24 * 3600; // 28 days
    uint256 public constant START = 1665734400; // Friday, October 14, 2022 3:00:00 PM GMT+07:00
    uint256 public constant ALLOCATION = 1_500_000 ether; // 1.5M

    uint256 public lastClaimTimestamp;

    constructor(address _lvl) {
        LVL = IERC20(_lvl);
    }

    function claimable() public view returns (uint256 _claimable, uint256 _timestamp) {
        if (block.timestamp <= START) {
            _claimable = 0;
            _timestamp = START;
        } else if (block.timestamp > START + DURATION) {
            _claimable = LVL.balanceOf(address(this));
            _timestamp = START + DURATION;
        } else {
            uint256 timeRange = block.timestamp - (lastClaimTimestamp > 0 ? lastClaimTimestamp : START);
            _claimable = (timeRange - (timeRange % EPOCH)) * ALLOCATION / DURATION;
            _timestamp = START + (timeRange - (timeRange % EPOCH));
        }
    }

    function transfer(address _receiver, uint256 _amount) external onlyOwner {
        require(_receiver != address(0), "DevFund::transfer: Invalid address");
        require(_amount > 0, "DevFund::transfer: Invalid amount");
        require(_amount <= LVL.balanceOf(address(this)), "DevFund::transfer: Insufficient balance");

        (uint256 _claimable, uint256 _timestamp) = claimable();

        require(_amount <= _claimable, "DevFund::transfer: Insufficient claimable amount");

        lastClaimTimestamp = _timestamp;
        LVL.safeTransfer(_receiver, _amount);
    }
}
