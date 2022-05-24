// SPDX-License-Identifier: Unlicensed

pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IRFA.sol";

contract Staking is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
//------
// EVENT
//------
    event rewardPerMinute(uint rfaPerMinute);

    event PoolCreated(
        uint poolId,
        address lpToken,
        uint allocPoint,
        uint stakeTimestamp,
        uint accRfaPerShare
    );

    event PoolUpdated(
        uint allocPoint,
        uint stakeTimestamp
    );

    event Deposit(
        address user,
        uint poolId,
        uint amount,
        uint stakeTime
    );

    event WithdrawToken(
        address user,
        uint poolId,
        uint amount,
        uint withdrawTime
    );

    event EmergencyWithdraw(
        address user,
        uint poolId,
        uint amount
    );


//-------------------
// STRUCT AND STORAGE
//-------------------

    // Info of each user.
    struct UserInfo {
        uint amount; // How many LP tokens the user has provided.
        uint rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SUSHIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accRfaPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accRfaPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        uint poolId;
        uint tokenSupply;
        IERC20Upgradeable lpToken; // Address of LP token contract.
        uint allocPoint; // How many allocation points assigned to this pool. rfas to distribute per block.
        uint lastRewardTimeStamp; // Last timestamp that rfas distribution occurs.
        uint accRfaPerShare; // Accumulated rfas per share, times 1e18. See below.
    }

    uint constant RFA_MINTED_DURATION = 1 minutes;
    uint public bonusMultiplier;
    uint public rfaPerMinute;

    IRFA public rfa;

    PoolInfo[] public poolInfo;
    mapping(uint => mapping(address => UserInfo)) public userInfo;
    mapping(IERC20Upgradeable => bool) public poolExist;

    uint totalAllocPoint;
    // SUM of all allocPoints per pool created
    uint totalAllocPoints;

    uint public bonusStart;
    uint public bonusEnd;

    address dev;

    // Pausable
    bool public paused;

    modifier whenNotPaused() {
        require(!paused, "Pausable: paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Pausable: not paused");
        _;
    }

    function setPaused(bool _set) external onlyOwner returns(bool) {
        return (paused = _set);
    }



// ------------
// CONSTRUCTOR
// ------------
    function initialize(address _rfa) public initializer {
        __Ownable_init();
        // Deploy the reward token
        rfa = IRFA(_rfa);

        // Default dev == owner
        dev = msg.sender;

        //Default setting
        bonusMultiplier = 1;
        rfaPerMinute = 1e18; 
        // Push native token pool to poolInfo[0]
        add(
            10,
            IERC20Upgradeable(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF),
            false
        );
        emit rewardPerMinute(1e18);
    }

// ----------------
//  OWNER FUNCTIONS
// ----------------

    // Add pool
    function add(
        uint _allocPoint,
        IERC20Upgradeable _lpToken,
        bool _withUpdate
    ) public onlyOwner returns(uint _pid){
        if (_withUpdate) {
            massUpdatePools();
        }
        require(!poolExist[_lpToken], "token pool already exist");

        _pid = getPoolLength();
        totalAllocPoint += _allocPoint;
        poolInfo.push(
            PoolInfo({
                poolId: _pid,
                tokenSupply: 0,
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardTimeStamp: block.timestamp,
                accRfaPerShare: 0
            })
        );
        poolExist[_lpToken] = true;
         // get the poolId
        emit PoolCreated(_pid, address(_lpToken), _allocPoint, block.timestamp, 0);
    }

    function set(
        uint _pid, //pool Id
        uint _newAllocPoint, // it set new allocPoint per pool
        bool _withUpdate // call massUpdatePool() or not
    ) external onlyOwner {
        require(poolInfo[_pid].poolId == _pid, "Pool doesn't exist");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _newAllocPoint;
        poolInfo[_pid].allocPoint = _newAllocPoint;
        emit PoolUpdated(_newAllocPoint, block.timestamp);
    }

    function setRfaPerMinute(uint _rfaPerMinute) external onlyOwner {
        require(_rfaPerMinute != 0, "Value can't be 0");
        rfaPerMinute = _rfaPerMinute;

    }

    function setBonus(uint _timeStart, uint _bonusDuration, uint _multiplier) external onlyOwner{
        require(_multiplier != 0, "Multiplier can't be 0");
        bonusStart = _timeStart;
        bonusEnd = _timeStart + _bonusDuration;
        bonusMultiplier = _multiplier;
    }

    function setDev(address _newDev) external onlyOwner{
        require(_newDev != address(0), "Dev can't be address 0");
        dev = _newDev;
    }
// -----
// UTILS
// -----

    // set to public so user can see how many available pool is
    function getPoolLength() public view returns (uint) {
        return poolInfo.length;
    }

    function durationPerMinted(uint _from, uint _to) private pure returns(uint) {
        uint modulus = (_to - _from) % RFA_MINTED_DURATION;
        return (_to - _from - modulus) / RFA_MINTED_DURATION; 
    }

    function getMultiplier(uint _from, uint _to)
        private
        view
        returns (uint)
    {
        uint _bonusStart = bonusStart;
        uint _bonusEnd = bonusEnd;
        
        // No bonus if bonusTime == 0
        if(_bonusStart != 0 && _bonusEnd != 0){
        // Condition whether stake happens at bonusDuration or not
            if (_from >= _bonusStart) {
                if(_to > _bonusEnd){
                    return
                        durationPerMinted(_from, _bonusEnd) * bonusMultiplier 
                        + durationPerMinted(_bonusEnd, _to);
                }
                return durationPerMinted(_from, _to) * bonusMultiplier;
            } else if (_to <= _bonusEnd) {
                return 
                    durationPerMinted(_from, _bonusStart) 
                        + durationPerMinted(_bonusStart, _to) * bonusMultiplier;
            }
        }

        return durationPerMinted(_from, _to);
    }

    // Harvest the staking reward
    function safeRfaTransfer(address _to, uint _amount) internal {
        uint rfaBal = rfa.balanceOf(address(this));
        if (_amount > rfaBal) {
            rfa.transfer(_to, rfaBal);
        } else {
            rfa.transfer(_to, _amount);
        }
    }
    function getRfaReward(uint _multiplier, uint _alloc) private view returns(uint) {
        return _multiplier * rfaPerMinute * _alloc / totalAllocPoint;
    }

//------- 
// UPDATE
//------- 
    function massUpdatePools() public {
        uint length = poolInfo.length;
        for (uint pid; pid < length; ) {
            updatePool(pid);
            unchecked{++pid;}
        }
    }

    function updatePool(uint _pid) public {
        PoolInfo storage pool = poolInfo[_pid];

        uint lpSupply = pool.tokenSupply;

        // return if no lpSupply for gas opt
        if (lpSupply == 0) {
                pool.lastRewardTimeStamp = block.timestamp;
                return;
            }
        uint multiplier = getMultiplier(pool.lastRewardTimeStamp, block.timestamp);
        uint rfaReward = multiplier * rfaPerMinute * pool.allocPoint / totalAllocPoint;
        pool.accRfaPerShare += rfaReward / lpSupply;
        pool.lastRewardTimeStamp = block.timestamp;
        rfa.mint(address(this), rfaReward);
        rfa.mint(owner(), rfaReward / 10); 
    }


//-----------------
// PUBLIC FUNCTIONS
//-----------------

    function stakeETH() public payable whenNotPaused {
        require(msg.value != 0, "Value can't be 0");
        stake(0, msg.value);
    }

    function stake(uint _pid, uint _amount) public whenNotPaused {
        require(_pid < poolInfo.length, "Pool doesn't exist");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        // Transfer user rfa reward if 
        if (user.amount != 0) {
            uint256 pending = user.amount * pool.accRfaPerShare - user.rewardDebt;
            safeRfaTransfer(msg.sender, pending);
        }

        user.amount += _amount;
        user.rewardDebt  = user.amount * pool.accRfaPerShare;
        pool.tokenSupply += _amount;
        if(_pid != 0){
            IERC20Upgradeable(pool.lpToken).safeTransferFrom(
                msg.sender,
                address(this),
                _amount
            );
        }
        
        emit Deposit(msg.sender, _pid, _amount, block.timestamp);
    }

    function withdraw(uint _pid, uint _amount) external whenNotPaused {
        require(_pid < poolInfo.length, "Pool doesn't exist");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Amount exceed the balance");
        updatePool(_pid);
        uint pending = user.amount * pool.accRfaPerShare - user.rewardDebt;
        safeRfaTransfer(msg.sender, pending);

        unchecked{user.amount -= _amount;}
        pool.tokenSupply -= _amount;

        if(_pid == 0){
            (bool success,) = payable(msg.sender).call{value: _amount} ("");
            require(success,"tx failed");
        }else{
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        emit WithdrawToken(msg.sender, _pid, _amount, block.timestamp);
        
    }

    function pendingRfa(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRfaPerShare = pool.accRfaPerShare;

        uint lpSupply = pool.tokenSupply;

        if (block.timestamp > pool.lastRewardTimeStamp && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTimeStamp, block.timestamp);
            uint256 rfaReward = multiplier * rfaPerMinute * pool.allocPoint / totalAllocPoint;
            accRfaPerShare = accRfaPerShare + rfaReward / lpSupply;
        }
        return user.amount * accRfaPerShare - user.rewardDebt;
    }

    function emergencyWithdraw(uint256 _pid) public whenNotPaused {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

    receive() external payable {
        stakeETH();
    }

//xxxxxxxxxxxxxxxxxxx 
// Under Dev
//xxxxxxxxxxxxxxxxxxx    
}