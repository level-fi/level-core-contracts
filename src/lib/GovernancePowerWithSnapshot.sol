// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;
import {GovernancePowerDelegationERC20} from "./GovernancePowerDelegationERC20.sol";
import {ITransferHook} from "../interfaces/ITransferHook.sol";

/**
 * @title ERC20WithSnapshot
 * @notice ERC20 including snapshots of balances on transfer-related actions
 * @author Level
 **/
abstract contract GovernancePowerWithSnapshot is GovernancePowerDelegationERC20 {
    /**
     * @dev The following storage layout points to the prior StakedToken.sol implementation:
     * _snapshots => _votingSnapshots
     * _snapshotsCounts =>  _votingSnapshotsCounts
     * _levelGovernance => _levelGovernance
     */
    mapping(address => mapping(uint256 => Snapshot)) public _votingSnapshots;
    mapping(address => uint256) public _votingSnapshotsCounts;

    /// @dev reference to the Level governance contract to call (if initialized) on _beforeTokenTransfer
    /// !!! IMPORTANT The Level governance is considered a trustable contract, being its responsibility
    /// to control all potential reentrancies by calling back the this contract
    ITransferHook public _levelGovernance;

    function _setLevelGovernance(ITransferHook levelGovernance) internal virtual {
        _levelGovernance = levelGovernance;
    }
}
