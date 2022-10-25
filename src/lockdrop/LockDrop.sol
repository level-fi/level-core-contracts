// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {IPool} from "../interfaces/IPool.sol";
import {ILevelMaster} from "../interfaces/ILevelMaster.sol";
import {UniERC20} from "../lib/UniERC20.sol";

contract LockDrop is Ownable {
    using UniERC20 for IERC20;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 bonusPoint;
    }

    uint256 private constant PRECISION = 1e6;

    uint256 private constant MAX_CAP = 100e18;
    uint256 private constant TOTAL_REWARDS = 1e17;
    uint256 private constant BONUS_REWARD_RATIO = 10000; // 1%

    IERC20 public rewardToken;

    // Level Pool
    IERC20 lp;
    IPool pool;
    address tranche;

    // Level Master
    ILevelMaster public levelMaster;
    uint256 levelMasterId;

    uint256 startTime;
    uint256 lockTime;
    uint256 unlockTime;

    uint256 totalAmount;
    uint256 totalBonusPoint;

    bool enableEmergency;

    mapping(address => UserInfo) public userInfo;

    constructor(
        address _lp,
        address _pool,
        address _tranche,
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
        tranche = _tranche;
        levelMaster = ILevelMaster(_levelMaster);
        levelMasterId = _levelMasterId;
        rewardToken = IERC20(_rewardToken);
        startTime = _startTime;
        lockTime = _lockTime;
        unlockTime = _unlockTime;
    }

    // ===============  VIEWS ===============

    function claimableRewards(address _to) public view returns (uint256 claimable) {
        if (totalAmount > 0 && lockTime <= block.timestamp) {
            UserInfo storage user = userInfo[_to];
            uint256 time = (block.timestamp <= unlockTime ? block.timestamp : unlockTime) - lockTime;
            uint256 lockDuration = unlockTime - lockTime;
            uint256 reward = (user.amount * time * TOTAL_REWARDS * (PRECISION - BONUS_REWARD_RATIO)) /
                    lockDuration /
                    totalAmount /
                    PRECISION;
            uint256 rewardWithBonus = (user.bonusPoint * time * TOTAL_REWARDS * BONUS_REWARD_RATIO) /
                    lockDuration /
                    (totalBonusPoint) /
                    PRECISION;
            claimable = reward + rewardWithBonus - user.rewardDebt;
        }
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

    // ===============  USER FUNCTIONS ===============

    function deposit(
        address _token,
        uint256 _amount,
        uint256 _minLpAmount,
        address _to
    ) external payable {
        require(lockTime > block.timestamp, "LockDrop::deposit: Pool was locked for deposit");

        uint256 lockAmount = addLiquidity(_token, _amount, _minLpAmount);
        require(MAX_CAP >= totalAmount + lockAmount, "LockDrop::deposit: Exceed the max cap");

        uint256 time = block.timestamp - startTime;
        uint256 depositDuration = lockTime - startTime;

        UserInfo storage user = userInfo[_to];

        uint256 _bonusPoint = (depositDuration - time) * lockAmount;

        user.bonusPoint += _bonusPoint;
        user.amount += lockAmount;

        totalBonusPoint += _bonusPoint;
        totalAmount += lockAmount;

        emit Deposited(msg.sender, _to, _token, _amount, lockAmount);
    }

    function withdraw(address _to) public {
        require(unlockTime <= block.timestamp, "LockDrop::withdraw: Cannot withdraw before unlock time");

        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        uint256 rewards;

        if (amount > 0) {
            rewards = claimableRewards(msg.sender);
            user.rewardDebt = user.rewardDebt + rewards;
            rewardToken.safeTransfer(_to, rewards);

            user.amount = 0;
            user.bonusPoint = 0;
            IERC20(lp).safeIncreaseAllowance(address(levelMaster), amount);
            levelMaster.deposit(levelMasterId, amount, _to);

            emit Withdrawn(msg.sender, _to, amount, rewards);
        }
    }

    function claimRewards(address _to) public {
        require(address(rewardToken) != address(0), "LockDrop::claimRewards: Reward token not set");
        require(lockTime <= block.timestamp, "LockDrop::claimRewards: Cannot claim before lock time");
        UserInfo storage user = userInfo[msg.sender];

        uint256 rewards = claimableRewards(msg.sender);
        user.rewardDebt = user.rewardDebt + rewards;
        rewardToken.safeTransfer(_to, rewards);

        emit ClaimRewards(msg.sender, _to, rewards);
    }

    function emergencyWithdraw(address _to) external {
        require(enableEmergency, "LockDrop::emergencyWithdraw: Only can be triggered when admin set Emergency");

        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;

        if (amount > 0) {
            user.amount = 0;
            user.bonusPoint = 0;
            lp.safeTransfer(_to, amount);
            emit EmergencyWithdrawn(msg.sender, _to);
        }
    }

    // ===============  RESTRICTED ===============

    function setEmergency(bool _enableEmergency) external onlyOwner {
        enableEmergency = _enableEmergency;
        emit EmergencySet(_enableEmergency);
    }

    // ===============  INTERNAL ===============

    function addLiquidity(
        address _token,
        uint256 _amount,
        uint256 _minLpAmount
    ) internal returns (uint256) {
        uint256 currentBalance = lp.balanceOf(address(this));

        if (_token != UniERC20.ETH) {
            IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
            IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
            pool.addLiquidity(tranche, _token, _amount, _minLpAmount, address(this));
        } else {
            require(msg.value == _amount, "LockDrop::deposit: Invalid transfer amount in");
            pool.addLiquidity{value: _amount}(tranche, _token, _amount, _minLpAmount, address(this));
        }

        uint256 lockAmount = lp.balanceOf(address(this)) - currentBalance;

        return lockAmount;
    }

    // ===============  EVENTS ===============
    event EmergencySet(bool enableEmergency);
    event Deposited(address indexed sender, address indexed to, address token, uint256 amount, uint256 lockAmount);
    event EmergencyWithdrawn(address indexed sender, address indexed to);
    event Withdrawn(address indexed sender, address indexed to, uint256 amount, uint256 rewards);
    event ClaimRewards(address indexed sender, address indexed to, uint256 rewards);
}
