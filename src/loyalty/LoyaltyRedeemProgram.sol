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

    struct ProgramInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 conversionRate;
        uint256 maxReward;
        uint256 totalRedeemed;
    }

    mapping(uint256 => ProgramInfo) public programs;
    uint256 public activeProgramId;
    uint256 public nextProgramId;

    ILyLevelToken public immutable lyLevel;
    ITokenReserve public immutable rewardsReserve;

    uint256 public constant PRECISION = 1e6;
    uint256 private constant MAX_CONVERSION_RATE = PRECISION;

    constructor(address _lyLevel, address _rewardsReserve) {
        require(_lyLevel != address(0), "LoyatyProgramRedeem:Invalid Address");
        lyLevel = ILyLevelToken(_lyLevel);
        rewardsReserve = ITokenReserve(_rewardsReserve);
        nextProgramId = 1;
    }

    function addProgram(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _conversionRate,
        uint256 _maxReward,
        bool isActive
    ) external onlyOwner {
        require(_endTime > _startTime && _startTime > block.timestamp, "LoyatyProgramRedeem: Invalid time");
        require(0 < _conversionRate && _conversionRate <= MAX_CONVERSION_RATE, "LoyatyProgramRedeem: Invalid rate");
        programs[nextProgramId] = ProgramInfo({
            startTime: _startTime,
            endTime: _endTime,
            conversionRate: _conversionRate,
            maxReward: _maxReward,
            totalRedeemed: 0
        });
        if (isActive) {
            activeProgramId = nextProgramId;
        }
        nextProgramId += 1;
        emit ProgramAdded(nextProgramId - 1, _startTime, _endTime, _conversionRate, _maxReward);
    }

    /// @notice burn lyLVL to get an amount of LVL
    /// the conversion rate is fixed when config
    function redeem(address _to, uint256 _amount) external whenNotPaused nonReentrant {
        ProgramInfo storage program = programs[activeProgramId];
        require(_amount > 0, "LoyatyProgramRedeem: Invalid amount");
        require(program.conversionRate > 0, "LoyatyProgramRedeem: Invalid conversion rate");
        require(
            program.startTime <= block.timestamp && block.timestamp < program.endTime,
            "LoyatyProgramRedeem: Invalid time"
        );
        uint256 levelAmount = _amount * program.conversionRate / PRECISION;
        program.totalRedeemed += levelAmount;
        require(program.totalRedeemed <= program.maxReward, "LoyatyProgramRedeem: Max available reward");
        lyLevel.burnFrom(msg.sender, _amount);
        rewardsReserve.requestTransfer(_to, levelAmount);
        emit Redeemed(_to, _amount, levelAmount);
    }

    function activeProgram(uint256 _pid) external onlyOwner {
        activeProgramId = _pid;
        emit ProgramActived(_pid);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    event Redeemed(address to, uint256 amount, uint256 amountLevel);
    event ProgramAdded(uint256 pid, uint256 startTime, uint256 endTime, uint256 conversionRate, uint256 maxReward);
    event ProgramActived(uint256 pid);
}
