// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./SafeMath.sol";
import "./IBEP20.sol";
import "./SafeBEP20.sol";
import "./Ownable.sol";

import "./TazorToken.sol";

// MasterChef is the master of Tazor. He can make Tazor and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once TAZOR is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of TAZORs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTazorPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTazorPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. TAZORs to distribute per block.
        uint256 lastRewardBlock;  // Last block number that TAZORs distribution occurs.
        uint256 accTazorPerShare;   // Accumulated TAZORs per share, times 1e12. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The TAZOR TOKEN!
    TazorToken public tazor;
    // Dev address.
    address public devaddr;
    // TAZOR tokens created per block.
    uint256 public tazorPerBlock;
    // Bonus muliplier for early tazor makers.
    uint256 public constant BONUS_MULTIPLIER = 1;
    // Deposit Fee address
    address public feeAddress;

    uint256 public feeburnPercent = 3;

    uint256 StarttimeBurn;
    // uint256 day = 86400;
    uint256 day = 180;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when TAZOR mining starts.
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event ChangeFeeBurnPercentEvent(uint256 indexed oldFee, uint256 newFee);


    constructor(
        TazorToken _tazor,
        address _devaddr,
        address _feeAddress,
        uint256 _tazorPerBlock,
        uint256 _startBlock
    ) public {
        tazor = _tazor;
        devaddr = _devaddr;
        feeAddress = _feeAddress;
        tazorPerBlock = _tazorPerBlock;
        startBlock = _startBlock;
        StarttimeBurn = block.timestamp;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accTazorPerShare: 0,
            depositFeeBP: _depositFeeBP
        }));
    }

    // Update the given pool's TAZOR allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) public onlyOwner {
        require(_depositFeeBP <= 10000, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending TAZORs on frontend.
    function pendingTazor(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTazorPerShare = pool.accTazorPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tazorReward = multiplier.mul(tazorPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTazorPerShare = accTazorPerShare.add(tazorReward.mul(1e12).div(lpSupply));
        }
        uint256 pendingView = user.amount.div(20000).mul(accTazorPerShare).div(1e12).sub(user.rewardDebt);
        return pendingView;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 tazorReward = multiplier.mul(tazorPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        uint256 FeeTokenForBurn = tazorReward.mul(feeburnPercent).div(100);
        // tazor.mint(devaddr, tazorReward.div(10));
        tazor.mint(address(this), tazorReward);
        // tazor.burn(address(this), FeeTokenForBurn);
        pool.accTazorPerShare = pool.accTazorPerShare.add(tazorReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for TAZOR allocation.
    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.div(20000).mul(pool.accTazorPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTazorTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            if(pool.depositFeeBP > 0){
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            }else{
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.div(20000).mul(pool.accTazorPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.div(20000).mul(pool.accTazorPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTazorTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.div(20000).mul(pool.accTazorPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe tazor transfer function, just in case if rounding error causes pool to not have enough TAZORs.
    function safeTazorTransfer(address _to, uint256 _amount) internal {
        uint256 tazorBal = tazor.balanceOf(address(this));
        if (_amount > tazorBal) {
            tazor.transfer(_to, tazorBal);
        } else {
            tazor.transfer(_to, _amount);
        }
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }

    function setFeeAddress(address _feeAddress) public{
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        feeAddress = _feeAddress;
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _tazorPerBlock) public onlyOwner {
        massUpdatePools();
        tazorPerBlock = _tazorPerBlock;
    }

    function ChangeFeeburnPercent(uint256 _amountfee) public onlyOwner{
        emit ChangeFeeBurnPercentEvent(feeburnPercent, _amountfee);
        feeburnPercent = _amountfee;
    }

    function BurnFromFarm() public onlyOwner{
        require(block.timestamp > StarttimeBurn + (day), "TAZOR::Time not End");
        uint256 FarmSupplyx = tazor.balanceOf(address(this));

        tazor.burn(address(this), FarmSupplyx.mul(feeburnPercent).div(100));
        StarttimeBurn = block.timestamp;
    }
}