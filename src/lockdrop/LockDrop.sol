// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {IPool} from "../interfaces/IPool.sol";
import {ILevelMaster} from "../interfaces/ILevelMaster.sol";
import {UniERC20} from "../lib/UniERC20.sol";

contract LockDrop is Ownable, ReentrancyGuard {
    using UniERC20 for IERC20;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 boostedAmount;
        uint256 rewardDebt;
    }

    uint256 private constant PRECISION = 1e6;
    uint256 private constant MAX_CAP = 1_000_000 ether;
    uint256 private constant TOTAL_REWARDS = 100_000 ether;
    /// @notice share of rewards distributed for early depositor
    uint256 private constant BONUS_REWARD_RATIO = 10000; // 1%

    IERC20 public immutable rewardToken;

    // Level Pool
    IERC20 public immutable lp;
    IPool public immutable pool;
    /// @notice the time contract start to accept deposit
    uint256 private immutable startTime;
    /// @notice from that time user cannot deposit nor withdraw, rewards start to emit
    uint256 private immutable lockTime;
    /// @notice rewards emission completed, user can withdraw
    uint256 private immutable unlockTime;
    /// @notice total amount of locked token
    uint256 private totalAmount;
    /// @notice early deposit user take some bonus point when calculate reward
    uint256 private totalBoostedAmount;

    bool public enableEmergency;

    // Level Master
    ILevelMaster public levelMaster;
    uint256 levelMasterId;

    mapping(address => UserInfo) public userInfo;

    constructor(
        address _lp,
        address _pool,
        address _levelMaster,
        uint256 _levelMasterId,
        address _rewardToken,
        uint256 _startTime,
        uint256 _lockTime,
        uint256 _unlockTime
    ) {
        require(
            block.timestamp <= _startTime && _startTime < _lockTime && _lockTime < _unlockTime,
            "LockDrop::constructor: Time not valid"
        );

        lp = IERC20(_lp);
        pool = IPool(_pool);
        levelMaster = ILevelMaster(_levelMaster);
        levelMasterId = _levelMasterId;
        rewardToken = IERC20(_rewardToken);
        startTime = _startTime;
        lockTime = _lockTime;
        unlockTime = _unlockTime;
    }

    // =============== VIEWS ===============

    function claimableRewards(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 _now = block.timestamp;
        if (totalAmount == 0 || user.amount == 0 || _now < lockTime) {
            return 0;
        }

        uint256 time = _now <= unlockTime ? _now - lockTime : unlockTime - lockTime;
        uint256 lockDuration = unlockTime - lockTime;

        uint256 reward =
            (user.amount * time * TOTAL_REWARDS * (PRECISION - BONUS_REWARD_RATIO)) / lockDuration / totalAmount / PRECISION;

        uint256 bonusReward = (user.boostedAmount * time * TOTAL_REWARDS * BONUS_REWARD_RATIO) / lockDuration
            / (totalBoostedAmount) / PRECISION;
        return reward + bonusReward - user.rewardDebt;
    }

    function info()
        public
        view
        returns (
            uint256 _maxCap,
            uint256 _startTime,
            uint256 _lockTime,
            uint256 _unlockTime,
            uint256 _totalReward,
            uint256 _totalAmount
        )
    {
        _maxCap = MAX_CAP;
        _startTime = startTime;
        _lockTime = lockTime;
        _unlockTime = unlockTime;
        _totalReward = TOTAL_REWARDS;
        _totalAmount = totalAmount;
    }

    // =============== USER FUNCTIONS ===============

    /// @notice Deposited token will be add to Level Pool, then the LP is locked to this contract
    function deposit(address _token, uint256 _amount, uint256 _minLpAmount, address _to)
        external
        payable
        nonReentrant
    {
        uint256 _now = block.timestamp;
        require(lockTime > _now, "LockDrop::deposit: locked");
        require(startTime <= _now, "LockDrop::deposit: not start");

        uint256 lockAmount = addLiquidity(_token, _amount, _minLpAmount);
        require(MAX_CAP >= totalAmount + lockAmount, "LockDrop::deposit: max cap exceeded");

        uint256 boostedAmount = (lockTime - _now) * lockAmount;

        UserInfo storage user = userInfo[_to];
        user.boostedAmount += boostedAmount;
        user.amount += lockAmount;

        totalBoostedAmount += boostedAmount;
        totalAmount += lockAmount;

        emit Deposited(msg.sender, _to, _token, _amount, lockAmount);
    }

    /// @notice withdraw LP token then stake to farm contract
    /// @param _unstake if true LP will be sent to user instead of depositing to level master
    function withdraw(address _to, bool _unstake) public {
        require(unlockTime <= block.timestamp, "LockDrop::withdraw: locked");

        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        if (amount == 0) {
            return;
        }

        uint256 rewards = claimableRewards(msg.sender);
        delete userInfo[msg.sender];

        if (rewards > 0) {
            rewardToken.safeTransfer(_to, rewards);
        }

        if (_unstake) {
            lp.safeTransfer(_to, amount);
        } else {
            lp.safeIncreaseAllowance(address(levelMaster), amount);
            levelMaster.deposit(levelMasterId, amount, _to);
        }
        emit Withdrawn(msg.sender, _to, amount, rewards);
    }

    function claimRewards(address _to) public {
        require(lockTime <= block.timestamp, "LockDrop::claimRewards: Cannot claim before lock time");
        UserInfo storage user = userInfo[msg.sender];
        uint256 rewards = claimableRewards(msg.sender);
        user.rewardDebt = user.rewardDebt + rewards;
        rewardToken.safeTransfer(_to, rewards);

        emit ClaimRewards(msg.sender, _to, rewards);
    }

    function emergencyWithdraw(address _to) external {
        require(enableEmergency, "LockDrop::emergencyWithdraw: not in emergency");

        uint256 amount = userInfo[msg.sender].amount;
        if (amount > 0) {
            delete userInfo[msg.sender];
            lp.safeTransfer(_to, amount);
            emit EmergencyWithdrawn(msg.sender, _to);
        }
    }

    // ===============  RESTRICTED ===============

    function setEmergency(bool _enableEmergency) external onlyOwner {
        if (enableEmergency != _enableEmergency) {
            enableEmergency = _enableEmergency;
            emit EmergencySet(_enableEmergency);
        }
    }

    // ===============  INTERNAL ===============

    function addLiquidity(address _token, uint256 _amount, uint256 _minLpAmount) internal returns (uint256) {
        uint256 currentBalance = lp.balanceOf(address(this));

        if (_token != UniERC20.ETH) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
            pool.addLiquidity(address(lp), _token, _amount, _minLpAmount, address(this));
        } else {
            require(msg.value == _amount, "LockDrop::deposit: invalid transfer in amount");
            pool.addLiquidity{value: _amount}(address(lp), _token, _amount, _minLpAmount, address(this));
        }

        return lp.balanceOf(address(this)) - currentBalance;
    }

    // ===============  EVENTS ===============
    event EmergencySet(bool enableEmergency);
    event Deposited(address indexed sender, address indexed to, address token, uint256 amount, uint256 lockAmount);
    event EmergencyWithdrawn(address indexed sender, address indexed to);
    event Withdrawn(address indexed sender, address indexed to, uint256 amount, uint256 rewards);
    event ClaimRewards(address indexed sender, address indexed to, uint256 rewards);
}
