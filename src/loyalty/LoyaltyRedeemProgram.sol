// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {Pausable} from "openzeppelin/security/Pausable.sol";
import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ILyLevelToken} from "../interfaces/ILyLevelToken.sol";
import {ITokenReserve} from "../interfaces/ITokenReserve.sol";

contract LoyaltyRedeemProgram is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ILyLevelToken public immutable lyLevel;
    ITokenReserve public immutable rewardsReserve;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public conversionRate;
    uint256 public constant PRECISION = 1e6;
    uint256 public maxReward;
    uint256 public totalRedeemed;

    constructor(address _lyLevel, address _rewardsReserve) {
        require(_lyLevel != address(0), "LoyatyProgramRedeem:Invalid Address");
        lyLevel = ILyLevelToken(_lyLevel);
        rewardsReserve = ITokenReserve(_rewardsReserve);
    }

    function config(uint256 _startTime, uint256 _endTime, uint256 _conversionRate, uint256 _maxReward)
        external
        onlyOwner
    {
        require(_endTime > _startTime && _startTime > block.timestamp, "LoyatyProgramRedeem: Invalid time");
        require(_conversionRate > 0, "LoyatyProgramRedeem: Invalid rate");
        startTime = _startTime;
        endTime = _endTime;
        conversionRate = _conversionRate;
        maxReward = _maxReward;
        totalRedeemed = 0;
        emit ConfigUpdated(startTime, endTime, conversionRate, maxReward);
    }

    /// @notice burn lyLVL to get an amount of LVL
    /// the conversion rate is fixed when config
    function redeem(address _to, uint256 _amount) external whenNotPaused nonReentrant {
        require(_amount > 0, "LoyatyProgramRedeem: Invalid amount");
        require(startTime <= block.timestamp && block.timestamp < endTime, "LoyatyProgramRedeem: Invalid time");
        uint256 levelAmount = _amount * conversionRate / PRECISION;
        if (levelAmount > 0) {
            totalRedeemed += levelAmount;
            require(totalRedeemed <= maxReward, "LoyatyProgramRedeem: Max available reward");
            lyLevel.burnFrom(msg.sender, _amount);
            rewardsReserve.requestTransfer(_to, levelAmount);
            emit Redeemed(_to, _amount, levelAmount);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    event Redeemed(address to, uint256 amount, uint256 amountLevel);
    event ConfigUpdated(uint256 startTime, uint256 endTime, uint256 conversionRate, uint256 maxReward);
}
