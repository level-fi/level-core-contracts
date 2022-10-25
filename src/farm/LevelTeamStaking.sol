// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ILevelStaking} from "../interfaces/ILevelStaking.sol";

contract LevelTeamStaking is Ownable {
    using SafeERC20 for IERC20;
    IERC20 public LVL;
    IERC20 public LGO;
    ILevelStaking public LEVEL_STAKING;

    uint256 public constant DURATION = 4 * 365 * 24 * 3600; // 4 years
    uint256 public constant EPOCH = 1 * 365 * 24 * 3600; // 1 year
    uint256 public constant START = 1665734400; // Friday, October 14, 2022 3:00:00 PM GMT+07:00
    uint256 public constant ALLOCATION = 6_000_000 ether; // 6M

    uint256 public totalStake;
    uint256 public lastClaimTimestamp;

    constructor(
        address _lvl,
        address _lgo,
        address _level_staking
    ) {
        LVL = IERC20(_lvl);
        LGO = IERC20(_lgo);
        LEVEL_STAKING = ILevelStaking(_level_staking);
    }

    function claimableLVL() public view returns (uint256 _claimable, uint256 _timestamp) {
        uint256 lvlBalance = LVL.balanceOf(address(this));
        if (block.timestamp <= START) {
            _claimable = 0;
            _timestamp = START;
        } else if (block.timestamp > START + DURATION) {
            _claimable = lvlBalance;
            _timestamp = START + DURATION;
        } else {
            uint256 timeRange = block.timestamp - (lastClaimTimestamp > 0 ? lastClaimTimestamp : START);
            uint256 estimateReward = (timeRange - (timeRange % EPOCH)) * ALLOCATION / DURATION;
            _claimable = estimateReward <= lvlBalance ? estimateReward : 0;
            _timestamp = START + (timeRange - (timeRange % EPOCH));
        }
    }

    function claimLVL(address _receiver, uint256 _amount) external onlyOwner {
        require(_receiver != address(0), "LevelTeamStaking::claimLVL: Invalid address");
        require(_amount > 0, "LevelTeamStaking::claimLVL: Invalid amount");

        (uint256 _claimable, uint256 _timestamp) = claimableLVL();
        require(_amount <= _claimable, "LevelTeamStaking::claimLVL: Insufficient claimable amount");

        lastClaimTimestamp = _timestamp;
        LVL.safeTransfer(_receiver, _amount);

        emit ClaimLVL(msg.sender, _amount);
    }

    function claimLGO(address _receiver) external onlyOwner {
        uint256 reward = LEVEL_STAKING.pendingReward(address(this));
        require(reward > 0, "LevelTeamStaking::claimLGO: Invalid amount");

        LEVEL_STAKING.claimRewards(_receiver);
        emit ClaimLGO(msg.sender, reward);
    }

    function stake() external onlyOwner {
        LVL.safeIncreaseAllowance(address(LEVEL_STAKING), LVL.balanceOf(address(this)));
        LEVEL_STAKING.stake(address(this), LVL.balanceOf(address(this)));
        emit Stake(msg.sender, LVL.balanceOf(address(this)));
    }

    function unstake(uint256 _amount) external onlyOwner {
        require(_amount > 0, "LevelTeamStaking::unstake: Invalid amount");
        require(_amount <= totalStake, "LevelTeamStaking::unstake: Insufficient total stake");
        totalStake -= _amount;
        LEVEL_STAKING.unstake(address(this), _amount);
        emit UnStake(msg.sender, _amount);
    }

    function cooldown() external onlyOwner {
        require(totalStake > 0, "LevelTeamStaking::cooldown: Invalid balance on cooldown");
        LEVEL_STAKING.cooldown();
        emit Cooldown(msg.sender);
    }

    event Stake(address indexed _user, uint256 _amount);
    event UnStake(address indexed _user, uint256 _amount);
    event Cooldown(address indexed _user);

    event ClaimLVL(address indexed _user, uint256 _amount);
    event ClaimLGO(address indexed _user, uint256 _amount);
}
