pragma solidity >=0.8.0;

interface ILevelStaking {
    function stake(address _to, uint256 _amount) external;

    function unstake(address _to, uint256 _amount) external;

    function cooldown() external;

    function claimRewards(address _to) external;

    function pendingReward(address _to) external view returns (uint256);
}
