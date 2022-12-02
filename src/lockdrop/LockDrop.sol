// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {SafeERC20, IERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {IPool} from "../interfaces/IPool.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {ILevelMaster} from "../interfaces/ILevelMaster.sol";

contract LockDrop is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeERC20 for IWETH;

    struct UserInfo {
        uint256 amount;
        uint256 boostedAmount;
        uint256 rewardDebt;
    }

    uint256 private constant PRECISION = 1e6;
    uint256 private immutable BASE_REWARDS;
    /// @notice share of rewards distributed for early depositor
    uint256 private immutable BONUS_REWARDS;

    IERC20 public immutable rewardToken;
    IWETH public immutable weth;

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
        address _weth,
        address _lp,
        address _pool,
        address _levelMaster,
        uint256 _levelMasterId,
        address _rewardToken,
        uint256 _startTime,
        uint256 _lockTime,
        uint256 _unlockTime,
        uint256 baseRewards,
        uint256 bonusRewards
    ) {
        require(
            block.timestamp <= _startTime && _startTime < _lockTime && _lockTime < _unlockTime,
            "LockDrop::constructor: Time not valid"
        );
        weth = IWETH(_weth);
        lp = IERC20(_lp);
        pool = IPool(_pool);
        levelMaster = ILevelMaster(_levelMaster);
        levelMasterId = _levelMasterId;
        rewardToken = IERC20(_rewardToken);
        startTime = _startTime;
        lockTime = _lockTime;
        unlockTime = _unlockTime;
        BASE_REWARDS = baseRewards;
        BONUS_REWARDS = bonusRewards;
    }

    modifier onlyActive() {
        uint256 _now = block.timestamp;
        require(lockTime > _now, "LockDrop::deposit: locked");
        require(startTime <= _now, "LockDrop::deposit: not start");
        _;
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

        uint256 reward = (user.amount * time * BASE_REWARDS) / lockDuration / totalAmount;
        uint256 bonusReward = (user.boostedAmount * time * BONUS_REWARDS) / lockDuration / (totalBoostedAmount);

        return reward + bonusReward - user.rewardDebt;
    }

    function info()
        public
        view
        returns (
            uint256 _startTime,
            uint256 _lockTime,
            uint256 _unlockTime,
            uint256 _baseRewards,
            uint256 _bonusRewards,
            uint256 _totalAmount,
            uint256 _totalBoostedAmount
        )
    {
        _startTime = startTime;
        _lockTime = lockTime;
        _unlockTime = unlockTime;
        _baseRewards = BASE_REWARDS;
        _bonusRewards = BONUS_REWARDS;
        _totalAmount = totalAmount;
        _totalBoostedAmount = totalBoostedAmount;
    }

    // =============== USER FUNCTIONS ===============

    /// @notice Deposit ERC20 token. Deposited token will be add to Level Pool, then the LP is locked to this contract
    function deposit(address _token, uint256 _amount, uint256 _minLpAmount, address _to)
        external
        nonReentrant
        onlyActive
    {
        uint256 lockAmount = _addLiquidity(_token, _amount, _minLpAmount);
        _update(_to, lockAmount);
        emit Deposited(msg.sender, _to, _token, _amount, lockAmount);
    }

    /// @notice Deposit ETH token. Deposited token will be add to Level Pool, then the LP is locked to this contract
    function depositETH(uint256 _minLpAmount, address _to) external payable nonReentrant onlyActive {
        uint256 _amount = msg.value;
        uint256 lockAmount = _addLiquidityETH(_amount, _minLpAmount);

        _update(_to, lockAmount);

        emit ETHDeposited(msg.sender, _to, _amount, lockAmount);
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

    function _update(address _to, uint256 _lockAmount) internal {
        uint256 _now = block.timestamp;
        uint256 boostedAmount = (lockTime - _now) * _lockAmount;

        UserInfo storage user = userInfo[_to];
        user.boostedAmount += boostedAmount;
        user.amount += _lockAmount;

        totalBoostedAmount += boostedAmount;
        totalAmount += _lockAmount;
    }

    function _addLiquidity(address _token, uint256 _amount, uint256 _minLpAmount) internal returns (uint256) {
        uint256 currentBalance = lp.balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        IERC20(_token).safeIncreaseAllowance(address(pool), _amount);
        pool.addLiquidity(address(lp), _token, _amount, _minLpAmount, address(this));
        return lp.balanceOf(address(this)) - currentBalance;
    }

    function _addLiquidityETH(uint256 _amount, uint256 _minLpAmount) internal returns (uint256) {
        uint256 currentBalance = lp.balanceOf(address(this));
        weth.deposit{value: _amount}();
        weth.safeIncreaseAllowance(address(pool), _amount);
        pool.addLiquidity(address(lp), address(weth), _amount, _minLpAmount, address(this));
        return lp.balanceOf(address(this)) - currentBalance;
    }

    // ===============  EVENTS ===============
    event EmergencySet(bool enableEmergency);
    event Deposited(address indexed sender, address indexed to, address token, uint256 amount, uint256 lockAmount);
    event ETHDeposited(address indexed sender, address indexed to, uint256 amount, uint256 lockAmount);
    event EmergencyWithdrawn(address indexed sender, address indexed to);
    event Withdrawn(address indexed sender, address indexed to, uint256 amount, uint256 rewards);
    event ClaimRewards(address indexed sender, address indexed to, uint256 rewards);
}
