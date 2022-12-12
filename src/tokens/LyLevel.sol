// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.15;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Initializable} from "openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";
import {ITokenReserve} from "../interfaces/ITokenReserve.sol";

contract LyLevel is Initializable, OwnableUpgradeable, IERC20 {
    struct RedeemProgramInfo {
        uint256 rewardPerShare;
        uint256 totalBalance;
        uint256 allocatedTime;
    }

    string public constant name = "Level Finance loyalty token";

    string public constant symbol = "lyLVL";

    uint256 public constant decimals = 18;

    uint256 public constant PRECISION = 1e6;

    address public minter;

    ITokenReserve public rewardFund;

    uint256 public currentBatchId;

    mapping(uint256 => RedeemProgramInfo) public redeemPrograms;

    mapping(uint256 => mapping(address => uint256)) public userBalance;

    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(uint256 => mapping(address => uint256)) public userClaimed;

    mapping(uint256 => uint256) private totalSupply_;

    function initialize() external initializer {
        __Ownable_init();
    }

    /* ========== VIEW FUNCTIONS ========== */
    function totalSupply() public view override returns (uint256) {
        return totalSupply_[currentBatchId];
    }

    function balanceOf(address _account) public view override returns (uint256) {
        return userBalance[currentBatchId][_account];
    }

    function claimable(uint256 _batchId, address _account) public view returns (uint256) {
        require(_batchId <= currentBatchId, "LyLevel: program not exist");
        return userBalance[_batchId][_account] * redeemPrograms[_batchId].rewardPerShare / PRECISION
            - userClaimed[_batchId][_account];
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function transfer(address _to, uint256 _amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, _to, _amount);
        return true;
    }

    function allowance(address _owner, address _spender) public view virtual override returns (uint256) {
        return _allowances[_owner][_spender];
    }

    function approve(address _spender, uint256 _amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, _spender, _amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, _spender, allowance(owner, _spender) + _addedValue);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, _spender);
        require(currentAllowance >= _subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, _spender, currentAllowance - _subtractedValue);
        }

        return true;
    }

    function mint(address _to, uint256 _amount) external {
        require(_msgSender() == minter, "LyLevel:!minter");
        _mint(_to, _amount);
    }

    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }

    function claim(uint256 _batchId, address _receiver) external {
        require(address(rewardFund) != address(0), "LyLevel: reward fund not set");
        address sender = _msgSender();
        uint256 amount = claimable(_batchId, sender);
        require(amount != 0, "LyLevel: nothing to claim");
        userClaimed[_batchId][sender] += amount;
        rewardFund.requestTransfer(_receiver, amount);
        emit Claimed(sender, _batchId, amount, _receiver);
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    function _transfer(address _from, address _to, uint256 _amount) internal {
        require(_from != address(0), "ERC20: transfer from the zero address");
        require(_to != address(0), "ERC20: transfer to the zero address");

        uint256 fromBalance = userBalance[currentBatchId][_from];
        require(fromBalance >= _amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            userBalance[currentBatchId][_from] = fromBalance - _amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            userBalance[currentBatchId][_to] += _amount;
        }

        emit Transfer(_from, _to, _amount);
    }

    function _mint(address _account, uint256 _amount) internal {
        require(_account != address(0), "ERC20: mint to the zero address");

        totalSupply_[currentBatchId] += _amount;
        unchecked {
            // Overflow not possible: balance + _amount is at most totalSupply + _amount, which is checked above.
            userBalance[currentBatchId][_account] += _amount;
        }
        emit Transfer(address(0), _account, _amount);
    }

    function _burn(address _account, uint256 _amount) internal {
        require(_account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = userBalance[currentBatchId][_account];
        require(accountBalance >= _amount, "ERC20: burn _amount exceeds balance");
        unchecked {
            userBalance[currentBatchId][_account] = accountBalance - _amount;
            // Overflow not possible: _amount <= accountBalance <= totalSupply.
            totalSupply_[currentBatchId] -= _amount;
        }

        emit Transfer(_account, address(0), _amount);
    }

    function _approve(address _owner, address _spender, uint256 _amount) internal virtual {
        require(_owner != address(0), "ERC20: approve from the zero address");
        require(_spender != address(0), "ERC20: approve to the zero address");

        _allowances[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
    }

    function _spendAllowance(address _owner, address _spender, uint256 _amount) internal virtual {
        uint256 currentAllowance = allowance(_owner, _spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= _amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(_owner, _spender, currentAllowance - _amount);
            }
        }
    }

    /* ========== RESTRICTIVE FUNCTIONS ========== */
    function setRewardFund(address _rewardFund) external onlyOwner {
        rewardFund = ITokenReserve(_rewardFund);
        emit RewardFundSet(_rewardFund);
    }

    function setMinter(address _minter) external onlyOwner {
        require(_minter != address(0), "LyLevel:zero address");
        minter = _minter;
        emit MinterSet(_minter);
    }

    /// @notice allocate reward for current batch and start a new batch
    function allocateReward(uint256 _totalAmount) external onlyOwner {
        require(totalSupply() > 0, "LyLevel:no supply");
        RedeemProgramInfo memory info = RedeemProgramInfo({
            totalBalance: totalSupply(),
            rewardPerShare: _totalAmount * PRECISION / totalSupply(),
            allocatedTime: block.timestamp
        });
        redeemPrograms[currentBatchId] = info;
        emit RewardAllocated(currentBatchId, _totalAmount);
        currentBatchId++;
        emit BatchStarted(currentBatchId);
    }

    /* ========== EVENT ========== */
    event MinterSet(address minter);
    event Claimed(address indexed user, uint256 indexed batchId, uint256 amount, address to);
    event RewardAllocated(uint256 indexed batchId, uint256 amount);
    event BatchStarted(uint256 id);
    event RewardFundSet(address fund);
}
