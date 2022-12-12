// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {Side, IPool} from "../interfaces/IPool.sol";

contract ReferralController is Initializable, OwnableUpgradeable {
    /// @notice trader => referrer
    mapping(address => address) public referedBy;
    mapping(address => uint256) public point;
    uint256 public totalPoint;
    /// @notice these address is allowed to update point and referer
    mapping(address => bool) public updaters;

    function initialize() external initializer {
        __Ownable_init();
    }

    /**
     * @notice set referer for a trader
     * Can be set by updater or trader themself
     */
    function setReferrer(address _trader, address _referrer) external {
        if (!updaters[msg.sender] && msg.sender != _trader) revert NotAllowed(msg.sender);

        if (_trader == _referrer) {
            return;
        }
        if (referedBy[_trader] != address(0)) {
            return;
        }

        if (_referrer != address(0)) {
            referedBy[_trader] = _referrer;
            emit ReferrerSet(_referrer, _trader);
        }
    }

    function handlePositionDecreased(
        address trader,
        address, /* indexToken */
        address, /* collateralToken */
        Side, /* side */
        uint256 sizeChange
    ) external {
        if (!updaters[msg.sender]) revert NotAllowed(msg.sender);
        address referrer = referedBy[trader];
        if (referrer == address(0)) {
            return;
        }

        uint256 traderPoint = sizeChange / 2;
        uint256 referrerPoint = sizeChange / 2;
        point[trader] += traderPoint;
        point[referrer] += referrerPoint;
        totalPoint += traderPoint + referrerPoint;
        emit PointUpdated(trader, traderPoint);
        emit PointUpdated(referrer, referrerPoint);
    }

    function addUpdater(address _updater) external onlyOwner {
        if (_updater == address(0)) revert InvalidAddress();
        if (updaters[_updater]) revert UpdaterAlreadyAdded(_updater);
        updaters[_updater] = true;
        emit UpdaterAdded(_updater);
    }

    function removeUpdater(address _updater) external onlyOwner {
        if (!updaters[_updater]) revert NotAnUpdater(_updater);
        updaters[_updater] = false;
        emit UpdaterRemoved(_updater);
    }

    // ======== ERRORS ========

    error NotAnUpdater(address _address);
    error UpdaterAlreadyAdded(address _address);
    error InvalidAddress();
    error NotAllowed(address sender);

    // ======== EVENTS ========

    event ReferrerSet(address referrer, address referee);
    event PointUpdated(address user, uint256 point);
    event UpdaterAdded(address updater);
    event UpdaterRemoved(address updater);
}
