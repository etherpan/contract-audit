// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SUP_AIRDROP is Ownable(msg.sender) {
    using SafeERC20 for IERC20;

    IERC20 SupToken;    
    address public SupTokenAddress;
    uint256 public startTime;
    uint256 public endTime;
    mapping (address => uint256) public userClaimedAmount;
    mapping (address => uint256) public userClaimableAmount;

    event Claim(address _user, uint256 _amount);

    receive() payable external {}

    constructor(address _SupTokenAddress, uint256 _startTime, uint256 _endTime) {

        SupToken = IERC20(_SupTokenAddress);
        SupTokenAddress = _SupTokenAddress;
        startTime = _startTime;
        endTime = _endTime;
    } 

    function setTokenAddress(address _TokenAddress) external onlyOwner {
        SupToken = IERC20(_TokenAddress);
        SupTokenAddress = _TokenAddress;
    }

    function setStartEndTimes(uint256 _startTime, uint256 _endTime) external onlyOwner
    {
        require(_startTime > 0 && _endTime>0, "SUP AIRDROP: Invalid times.");
        require(_endTime > _startTime, "SUP AIRDROP: End time should lager then start time.");
        startTime = _startTime;
        endTime = _endTime;
    }

    function addUserClaimAmount(address _address, uint256 _amount) public {
        if(userClaimableAmount[_address] > 0)
        {
            userClaimableAmount[_address] += _amount;
        }else userClaimableAmount[_address] = _amount;
    }

    function claim(uint256 _amount) public  {
        require(block.timestamp >= startTime, "SUP AIRDROP: Not started yet.");
        require(block.timestamp <= endTime, "SUP AIRDROP: Aready ended.");
        require(_amount>0, "SUP AIRDROP: Amount should be bigger than zero.");
        require(userClaimableAmount[msg.sender] > 0, "Caller is not in the whitelist.");
       
        SupToken.transfer(msg.sender, _amount);

        userClaimedAmount[msg.sender] += _amount;

        emit Claim(msg.sender, _amount);        
    }

    function withdrawToken(address _tokenAddress,uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(owner(),_amount);
    }
    
}