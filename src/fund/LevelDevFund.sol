// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";
import {Initializable} from "openzeppelin/proxy/utils/Initializable.sol";
import {TokenVesting} from "./TokenVesting.sol";

contract LevelDevFund is Initializable, Ownable, TokenVesting {
    using SafeERC20 for IERC20;

    IERC20 public LVL;

    function initialize(address _lvl, uint256 _startTime, uint256 _endTime, uint256 _epoch) external initializer {
        if (_lvl == address(0)) {
            revert InvalidAddress();
        }
        LVL = IERC20(_lvl);
        _initialize(_startTime, _endTime, _epoch, LVL.balanceOf(address(this)));
    }

    function _transferOut(address _recipient, uint256 _amount) internal override {
        LVL.safeTransfer(_recipient, _amount);
    }

    error InvalidAddress();
}
