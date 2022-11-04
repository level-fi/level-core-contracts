// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {ERC20Upgradeable} from "openzeppelin-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";

contract LyLevel is Initializable, OwnableUpgradeable, ERC20Upgradeable {
    string public constant NAME = "Level Finance loyalty token";
    string public constant SYMBOL = "lyLEVEL";

    address public minter;

    function initialize() external initializer {
        __Ownable_init();
        __ERC20_init(NAME, SYMBOL);
    }

    function mint(address _to, uint256 _amount) external {
        require(msg.sender == minter, "lyLEVEL:!minter");
        _mint(_to, _amount);
    }

    function burnFrom(address _account, uint256 _amount) external {
        _spendAllowance(_account, _msgSender(), _amount);
        _burn(_account, _amount);
    }

    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "zeroAddress");
        minter = _minter;
        emit MinterChanged(_minter);
    }

    event MinterChanged(address);
}
