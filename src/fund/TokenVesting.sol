// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

/// @title TokenVesting
/// @author LevelFinance developer
/// @notice Release an amount of token in a period of time
abstract contract TokenVesting {
    uint256 public epoch;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public totalAllocation;
    uint256 public claimedAmount;

    function _initialize(uint256 _startTime, uint256 _endTime, uint256 _epoch, uint256 _totalAlloction) internal {
        if (_epoch == 0) {
            revert InvalidEpoch();
        }
        if (_endTime <= _startTime || _startTime < block.timestamp) {
            revert InvalidVestingPeriod(_startTime, _endTime);
        }
        epoch = _epoch;
        startTime = _startTime;
        endTime = _endTime;
        totalAllocation = _totalAlloction;
    }

    function claimable() external view returns (uint256) {
        return _claimable();
    }

    function claimVested(uint256 _amount, address _recipient) external virtual {
        if (_amount == 0) {
            revert InvalidAmount();
        }
        uint256 vestedAmount = _claimable();
        if (_amount > vestedAmount) {
            revert ClaimExceedVested();
        }
        if (_amount > 0) {
            claimedAmount += _amount;
            _transferOut(_recipient, _amount);
            emit Claimed(_amount, _recipient);
        }
    }

    function _transferOut(address _recipient, uint256 _amount) internal virtual;

    function _claimable() internal view returns (uint256) {
        uint256 _now = block.timestamp;
        if (_now < startTime) {
            return 0;
        }

        uint256 effectedTimestamp = startTime + (_now - startTime) / epoch * epoch;
        effectedTimestamp = effectedTimestamp > endTime ? endTime : effectedTimestamp;
        return (effectedTimestamp - startTime) * totalAllocation / (endTime - startTime) - claimedAmount;
    }

    event Claimed(uint256 amount, address recipient);

    error InvalidEpoch();
    error InvalidVestingPeriod(uint256 startTime, uint256 endTime);
    error ClaimExceedVested();
    error InvalidAmount();
}
