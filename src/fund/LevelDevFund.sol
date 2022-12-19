// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ILevelStake} from "../interfaces/ILevelStake.sol";

/// @title Level Dev Fund
/// @author Level
/// @notice Hold team's LVL to stake to LevelStake contract. These LVL will be unlock in a period
/// of 4 years with 25% annually released.
contract LevelDevFund is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public LVL;
    IERC20 public LGO;
    ILevelStake public LEVEL_STAKE;

    uint256 public constant EPOCH = 365 days;
    uint256 public constant DURATION = 4 * EPOCH;
    uint256 public constant START = 1672063200; // December 26, 2022 9:00:00 PM GMT+07:00
    uint256 public constant ALLOCATION = 10_000_000 ether; // 10 M

    uint256 public claimedAmount;

    function initialize(address _levelStake) external initializer {
        __Ownable_init();
        LEVEL_STAKE = ILevelStake(_levelStake);
        LVL = LEVEL_STAKE.LVL();
        LGO = LEVEL_STAKE.LGO();
    }

    /* ========== VIEW FUNCTIONS ========== */
    /// @notice calculate amount of LVL unlocked
    function unlockedLVL() public view returns (uint256) {
        if (block.timestamp < START) {
            // vesting not started, unlock all
            return ALLOCATION;
        }
        uint256 _now = block.timestamp;
        // effective duration is rounded to a multiple of epoch
        uint256 effectiveDuration = _now <= START ? 0 : (_now - START) / EPOCH * EPOCH;
        effectiveDuration = effectiveDuration > DURATION ? DURATION : effectiveDuration;
        return effectiveDuration * ALLOCATION / DURATION - claimedAmount;
    }

    function claimableLGO() public view returns (uint256) {
        return LEVEL_STAKE.pendingReward(address(this)) + LGO.balanceOf(address(this));
    }

    function getUnstakeTime() public view returns (uint256 start, uint256 end) {
        (,, uint256 cooldowns) = LEVEL_STAKE.userInfo(address(this));
        if (cooldowns != 0) {
            start = cooldowns + LEVEL_STAKE.COOLDOWN_SECONDS();
            end = cooldowns + LEVEL_STAKE.COOLDOWN_SECONDS() + LEVEL_STAKE.UNSTAKE_WINDOWN();
        }
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    /// @notice withdraw vested LVL
    function withdraw(uint256 _amount, address _receiver) external onlyOwner {
        require(_receiver != address(0), "LevelDevFund::withdraw: invalid address");
        require(
            _amount != 0 && _amount <= LVL.balanceOf(address(this)) && _amount <= unlockedLVL(),
            "LevelDevFund::withdraw: invalid amount"
        );
        claimedAmount += _amount;
        LVL.safeTransfer(_receiver, _amount);
        emit Withdrawn(_receiver, _amount);
    }

    function stake(uint256 _amount) external onlyOwner {
        require(_amount <= LVL.balanceOf(address(this)), "LevelDevFund::stake: insufficient balance");
        LVL.safeIncreaseAllowance(address(LEVEL_STAKE), _amount);
        LEVEL_STAKE.stake(address(this), _amount);
        emit Staked(_amount);
    }

    function unstake(uint256 _amount) external onlyOwner {
        require(0 < _amount && _amount <= totalLVLStaked(), "LevelDevFund::unstake: invalid amount");
        LEVEL_STAKE.unstake(address(this), _amount);
        emit Unstaked(_amount);
    }

    function cooldown() external onlyOwner {
        require(totalLVLStaked() != 0, "LevelDevFund::cooldown: not staked");
        LEVEL_STAKE.cooldown();
        emit Cooldown(msg.sender);
    }

    function claimLGO(address _receiver, uint256 _amount) external onlyOwner {
        require(_receiver != address(0), "LevelDevFund::claimLGO: invalid address");
        if (LEVEL_STAKE.pendingReward(address(this)) != 0) {
            LEVEL_STAKE.claimRewards(address(this));
        }
        uint256 lgoBalance = LGO.balanceOf(address(this));
        _amount = _amount > lgoBalance ? lgoBalance : _amount;
        LGO.safeTransfer(_receiver, _amount);
        emit LGOClaimed(_receiver, _amount);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function totalLVLStaked() internal view returns (uint256) {
        (uint256 amount,,) = LEVEL_STAKE.userInfo(address(this));
        return amount;
    }

    /* ========== EVENTS ========== */

    event Staked(uint256 _amount);
    event Unstaked(uint256 _amount);
    event Cooldown(address indexed _user);
    event Withdrawn(address indexed _receiver, uint256 _amount);
    event LGOClaimed(address indexed _receiver, uint256 _amount);
}
