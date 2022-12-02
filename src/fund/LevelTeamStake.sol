// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {ILevelStake} from "../interfaces/ILevelStake.sol";

/// @title Team staking fund
/// @author Level
/// @notice Hold team's LVL to stake to LevelStake contract. These LVL will be unlock in a period
/// of 4 years with 25% annually released.
contract LevelTeamStake is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 public LVL;
    IERC20 public LGO;
    ILevelStake public LEVEL_STAKE;

    uint256 public constant EPOCH = 365 days;
    uint256 public constant DURATION = 4 * EPOCH;
    uint256 public START;
    uint256 public ALLOCATION;
    uint256 public claimedAmount;

    function initialize(address _levelStake) external initializer {
        __Ownable_init();
        LEVEL_STAKE = ILevelStake(_levelStake);
        LVL = LEVEL_STAKE.LVL();
        LGO = LEVEL_STAKE.LGO();
        ALLOCATION = LVL.balanceOf(address(this));
        LVL.safeIncreaseAllowance(address(LEVEL_STAKE), ALLOCATION);
        LEVEL_STAKE.stake(address(this), ALLOCATION);
        START = block.timestamp;
        emit Lock(msg.sender, ALLOCATION);
    }

    /* ========== VIEW FUNCTIONS ========== */
    /// @notice calculate amount of LVL unlocked
    function unlockedLVL() public view returns (uint256) {
        uint256 _now = block.timestamp;
        // effective duration is rounded to a multiple of epoch
        uint256 effectiveDuration = _now <= START ? 0 : (_now - START) / EPOCH * EPOCH;
        effectiveDuration = effectiveDuration > DURATION ? DURATION : effectiveDuration;
        return effectiveDuration * ALLOCATION / DURATION - claimedAmount;
    }

    function claimableLGO() public view returns (uint256) {
        return LEVEL_STAKE.pendingReward(address(this)) + LGO.balanceOf(address(this));
    }

    /* ========== RESTRICTIVE FUNCTIONS ========== */

    function claimLGO(address _receiver) external onlyOwner {
        uint256 _claimableLGO = claimableLGO();
        require(_claimableLGO > 0, "LevelTeamStake::claimLGO: Invalid amount");

        LEVEL_STAKE.claimRewards(address(this));
        LGO.safeTransfer(_receiver, _claimableLGO);
        emit ClaimLGO(msg.sender, _claimableLGO);
    }

    function unlock(uint256 _amount, address _receiver) external onlyOwner {
        require(_receiver != address(0), "LevelTeamStake::unstake: Invalid address");
        uint256 _unlockedLVL = unlockedLVL();
        require(0 < _amount && _amount <= _unlockedLVL, "LevelTeamStake::unstake: Invalid unlocked amount");
        claimedAmount += _amount;
        LEVEL_STAKE.unstake(address(this), _unlockedLVL);
        LVL.safeTransfer(_receiver, _unlockedLVL);
        emit Unlock(msg.sender, _unlockedLVL);
    }

    function cooldown() external onlyOwner {
        require(totalLVLStaked() > 0, "LevelTeamStake::cooldown: Not staked");
        LEVEL_STAKE.cooldown();
        emit Cooldown(msg.sender);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function totalLVLStaked() internal view returns (uint256) {
        (uint256 amount,,) = LEVEL_STAKE.userInfo(address(this));
        return amount;
    }

    /* ========== EVENTS ========== */

    event Lock(address indexed _user, uint256 _amount);
    event Unlock(address indexed _user, uint256 _amount);
    event Cooldown(address indexed _user);
    event ClaimLGO(address indexed _user, uint256 _amount);
}
