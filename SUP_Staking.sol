// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;


abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
    * @dev Initializes the contract setting the deployer as the initial owner.
    */
    constructor () {
      address msgSender = _msgSender();
      _owner = msgSender;
      emit OwnershipTransferred(address(0), msgSender);
    }

    /**
    * @dev Returns the address of the current owner.
    */
    function owner() public view returns (address) {
      return _owner;
    }

    
    modifier onlyOwner() {
      require(_owner == _msgSender(), "Ownable: caller is not the owner");
      _;
    }

    function renounceOwnership() public onlyOwner {
      emit OwnershipTransferred(_owner, address(0));
      _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
      _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
      require(newOwner != address(0), "Ownable: new owner is the zero address");
      emit OwnershipTransferred(_owner, newOwner);
      _owner = newOwner;
    }
}

interface ERC20 {
    function totalSupply() external view returns (uint);

    function balanceOf(address account) external view returns (uint);

    function transfer(address recipient, uint amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}


contract SUP_Staking is Context, Ownable {
    address public SUP = 0x1cE7ad20818310CaDb2d6974732b2f625baBC130; // for testnet
    uint256 public SUP_DECIMAL = 6;

    address public feeWallet;
    uint256 constant feePercent = 20;

    bool private initialized = false;

    struct PoolConfig {
        uint256 lockPeriod;
        uint256 apy;
        uint256 totalAmount;
    }

    PoolConfig[] public poolData;

    struct UserPool {
        uint256 stakeAmount;
        uint256 startTime;
        uint256 claimTime;
        uint256 claimNum;

        uint256 lastClaimTime;
        uint256 lastClaimAmount;
    }

    struct User {
        mapping (uint256 => UserPool) pools;
        uint256 remainedAmount;
        uint256 withdrawnAmount;
	}

    mapping (address => User) private users;

    event Stake(address indexed _addr, uint256 _amount, uint256 _poolIndex, uint256 _time);
    event Unstake(address indexed _addr, uint256 _amount, uint256 _poolIndex, uint256 _time);
    event Withdraw(address indexed _addr, uint256 _amount, uint256 _poolIndex, uint256 _time);


    constructor() {
        createInitialPools();
        feeWallet = msg.sender;
    }
    
    /**
    * @notice Create 4 types of pools.
    * @dev Create 4 types of pools, function is called in contructor.
    */
    function createInitialPools() internal {
        addPool(0, 13);
        addPool(1, 15);
        addPool(3, 30);
        addPool(5, 40);
        addPool(8, 55);
        addPool(12, 70);
        addPool(24, 85);
    }

    /**
    * @notice Add pool with price and reward percent.
    * @dev Add pool config.
    * @param _lockPeriod Pool lock period.
    * @param _apy Annual percentage yield of pool.
    */
    function addPool(uint32 _lockPeriod, uint256 _apy) public onlyOwner {
        require(
            _apy > 0,
            "annual percentage yield must be greater than zero"
        );

        poolData.push(
            PoolConfig({
                lockPeriod: _lockPeriod * 30 * 24 * 3600,
                apy: _apy,
                totalAmount: 0
            })
        );
    }
    
    /**
    * @dev Withdraw rewards.
    * @param _index Pool index.
    * @param _amount Amount to withdraw.
    */
    function withdraw(uint256 _index, uint256 _amount) public {
        checkState();

        uint256 rewards = getRewards(msg.sender, _index);
        require(rewards > 0, "not staked");
        require(_amount < rewards, "exceed balance");

        uint256 claimNum = users[msg.sender].pools[_index].claimNum;
        uint256 claimTime = users[msg.sender].pools[_index].claimTime;
        uint256 withdrawnAmount = users[msg.sender].withdrawnAmount;

        users[msg.sender].remainedAmount = rewards - _amount;
        poolData[_index].totalAmount -= _amount;

        if (poolData[_index].lockPeriod != 0 && block.timestamp - claimTime < 30 * 86400 && claimNum > 3) {
            uint256 feeAmount = _amount * feePercent / 100;
            ERC20(SUP).transfer(feeWallet, feeAmount);
            _amount -= feeAmount;
        }
        
        ERC20(SUP).transfer(address(msg.sender), _amount);

        emit Withdraw(msg.sender, _amount, _index, block.timestamp);

        if (withdrawnAmount == 0 || block.timestamp - claimTime > 30 * 86400) {
            users[msg.sender].pools[_index].claimTime = block.timestamp;
            claimNum = 0;
        }

        users[msg.sender].pools[_index].lastClaimTime = block.timestamp;
        users[msg.sender].pools[_index].lastClaimAmount = _amount;
        users[msg.sender].withdrawnAmount = withdrawnAmount + _amount;
        users[msg.sender].pools[_index].claimNum = claimNum + 1;
    }
    
    /**
    * @dev Unstake.
    * @param _index Pool index.
    */
    function unstake(uint256 _index) public {
        checkState();

        uint256 lockPeriod = poolData[_index].lockPeriod;
        
        uint256 stakeAmount = users[msg.sender].pools[_index].stakeAmount;
        uint256 startTime = users[msg.sender].pools[_index].startTime;

        require(stakeAmount > 0, "not staked");
        require(block.timestamp - startTime > lockPeriod, "lock period");
        
        ERC20(SUP).transfer(address(msg.sender), stakeAmount);
        
        emit Unstake(msg.sender, stakeAmount, _index, block.timestamp);

        users[msg.sender].pools[_index] = (
                                            UserPool({
                                                stakeAmount: 0,
                                                startTime: 0,
                                                claimTime: 0,
                                                claimNum: 0,
                                                lastClaimTime: 0,
                                                lastClaimAmount: 0

                                            })
                                        );

        poolData[_index].totalAmount -= stakeAmount;
    }

    /**
    * @dev Stake on pools.
    */
    function stake(uint256 _amount, uint256 _index) public {
        require(initialized, "err: not started");

        ERC20(SUP).transferFrom(address(msg.sender), address(this), _amount);
        
        emit Stake(msg.sender, _amount, _index, block.timestamp);
        
        users[msg.sender].remainedAmount = getRewards(msg.sender, _index);

        uint256 oldStakeAmount = users[msg.sender].pools[_index].stakeAmount;
        uint256 lastClaimAmount_ = users[msg.sender].pools[_index].lastClaimAmount;

        users[msg.sender].pools[_index] = (
                                                UserPool({
                                                    stakeAmount: _amount + oldStakeAmount,
                                                    startTime: block.timestamp,
                                                    claimTime: block.timestamp,
                                                    claimNum: 0,
                                                    lastClaimTime: block.timestamp,
                                                    lastClaimAmount: lastClaimAmount_
                                                })
                                            );

        poolData[_index].totalAmount += _amount;
    }

    /**
    * @dev Check it is on going or not.
    */
    function checkState() internal view {
        require(initialized, "err: not started");
    }

    /**
    * @dev Start platform.
    */
    function start() public onlyOwner {
        require(initialized == false, "err: already started");
        initialized=true;
    }


    /**
    * @dev Get user pool info.
    * @param _addr User address.
    * @param _index Pool index.
    */
	function getUserPoolInfo(address _addr, uint256 _index) public view returns(UserPool memory) {
		return users[_addr].pools[_index];
	}

    /**
    * @dev Get withdrawn amount.
    * @param _addr User address.
    */
	function getUserWithdrawnAmount(address _addr) public view returns(uint256) {
		return users[_addr].withdrawnAmount;
	}

    /**
    * @dev Get remained amount.
    * @param _addr User address.
    */
	function getUserRemainedAmount(address _addr) public view returns(uint256) {
		return users[_addr].remainedAmount;
	}

    /**
    * @dev Get rewards.
    * @param _addr User address.
    * @param _index Pool index.
    */
    function getRewards(address _addr, uint256 _index) public view returns(uint256) {
        uint256 lastClaimTime = users[_addr].pools[_index].lastClaimTime;

        uint256 stakeAmount = users[_addr].pools[_index].stakeAmount;
        uint256 apy = poolData[_index].apy;
        
        uint256 rewards = (stakeAmount * apy / 100) * (block.timestamp - lastClaimTime) / (365 * 86400);

        return users[_addr].remainedAmount + rewards;
    }

    /**
    * @dev Set staking token.
    * @param _addr Token address
    * @param _decimal Token decimal
    */
    function setToken(address _addr, uint256 _decimal) public onlyOwner {
        require(_addr != address(0), "invalid address");
        require(_decimal > 0, "decimal must be greater than zero");

        SUP = _addr;
        SUP_DECIMAL = _decimal;
    }

    /**
    * @dev Set fee wallet.
    * @param _addr Wallet address
    */
    function setFeeWallet(address _addr) public onlyOwner {
        feeWallet = _addr;
    }
}