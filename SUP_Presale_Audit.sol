// SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function getAmountsOut(
        uint amountIn, 
        address[] memory path
        ) external view returns (uint[] memory amounts);
    
    function getAmountsIn(uint amountOut, address[] memory path) external view returns (uint[] memory amounts);

}


contract SUPPresale is Ownable(msg.sender) {
    using SafeERC20 for IERC20;

    struct Phase {
        uint256 maxTokens;
        uint256 price;
        uint256 minPerWallet;
        uint256 maxPerWallet;
        
        uint256 startTime;
        uint256 endTime;

        uint256 soldTokens;
    }

    uint256 public activePhase;
    bool public isAutoMovePhase;

    Phase[] public phases;

    IERC20 USDT;
    IERC20 SUPToken;
    IRouter public router;
    
    uint256 private constant TOKEN_DECIMAL = 1e18;
    uint256 private constant USDT_DECIMAL = 1e6;
    address public SALE_WITH_CARD_PAYMENT_MANAGER;

    mapping (address => mapping(uint256 => uint256)) private userPaidUSD;

    event Buy(address _to, uint256 _amount, uint256 _phaseNum);
    event Burn(uint256 _amount, uint256 _phaseNum);
    event SetStartAndEndTime(uint256 _startTime, uint256 _endTime, uint256 _phaseNum);
    event SetEndTime(uint256 _time, uint256 _phaseNum);
    event SetCardPaymentManager(address _address);
    event RefundAmount2CardOrBNBPayer(uint256 _phaseNum, address _user, uint256 _owingAmount);

    receive() payable external {}

    constructor(address _router, address _usdt, address _token) {
        router = IRouter(_router);
        SUPToken = IERC20(_token);
        USDT = IERC20(_usdt);
        SALE_WITH_CARD_PAYMENT_MANAGER = msg.sender;

        addPhase(250_000_000, 4500, 200, 15000);
        addPhase(750_000_000, 5500, 100, 10000);
        addPhase(500_000_000, 6000, 100, 8000);
        addPhase(850_000_000, 7500, 100, 6375000); // 6375000 means no limit.
    }

    function addPhase(uint256 _maxTokens, uint256 _price, uint256 _minPerWallet, uint256 _maxPerWallet) private {
        phases.push(
            Phase({
                maxTokens: _maxTokens * TOKEN_DECIMAL,
                price: _price,
                minPerWallet: _minPerWallet * USDT_DECIMAL,
                maxPerWallet: _maxPerWallet * USDT_DECIMAL,
                startTime: 0,
                endTime: 0,
                soldTokens: 0
            })
        );
    }

    /**
    * @notice Buy tokens with usdt.
    * @param _usdtAmount Amount of usdt to buy token.
    */
    function buyTokensWithUSDT(uint256 _usdtAmount) external {
        uint256 maxTokens = phases[activePhase].maxTokens;
        uint256 price = phases[activePhase].price;
        uint256 minPerWallet = phases[activePhase].minPerWallet;
        uint256 maxPerWallet = phases[activePhase].maxPerWallet;
        uint256 start_time = phases[activePhase].startTime;
        uint256 end_time = phases[activePhase].endTime;
        uint256 soldTokens = phases[activePhase].soldTokens;

        uint256 user_paid = userPaidUSD[msg.sender][activePhase];

        require(block.timestamp >= start_time && block.timestamp <= end_time, "SUPPresale: Not presale period");

        uint256 currentPaid = user_paid;
        require(currentPaid + _usdtAmount >= minPerWallet && currentPaid + _usdtAmount <= maxPerWallet, "SUPPresale: The price is not allowed for presale.");
        
        bool isReachMaxAmount;

        // token amount user want to buy
        uint256 tokenAmount = _usdtAmount * TOKEN_DECIMAL / price;

        // transfer USDT to here
        USDT.safeTransferFrom(msg.sender, address(this), _usdtAmount);

        if (phases[activePhase].maxTokens < tokenAmount + soldTokens && isAutoMovePhase) {
            uint256 tokenAmount2 = maxTokens - soldTokens;
            uint256 returnAmount = _usdtAmount - (_usdtAmount * tokenAmount2 / tokenAmount);
            IERC20(USDT).safeTransfer(msg.sender, returnAmount);

            tokenAmount = tokenAmount2;
            isReachMaxAmount = true;
        }

        // transfer SUP token to user
        SUPToken.safeTransfer(msg.sender, tokenAmount);
        
        phases[activePhase].soldTokens += tokenAmount;
        // add USD user bought
        userPaidUSD[msg.sender][activePhase] += _usdtAmount;

        emit Buy(msg.sender, tokenAmount, activePhase);

        if(isReachMaxAmount){
            activePhase++;
        } 
    }

    /**
    * @notice Buy tokens with eth.
    */
    function buyTokensWithETH() external payable {
        uint256 maxTokens = phases[activePhase].maxTokens;
        uint256 price = phases[activePhase].price;
        uint256 minPerWallet = phases[activePhase].minPerWallet;
        uint256 maxPerWallet = phases[activePhase].maxPerWallet;
        uint256 start_time = phases[activePhase].startTime;
        uint256 end_time = phases[activePhase].endTime;
        uint256 soldTokens = phases[activePhase].soldTokens;

        require(block.timestamp >= start_time && block.timestamp <= end_time, "SUPPresale: Not presale period");
        
        require(msg.value > 0, "Insufficient ETH amount");

        uint256 ethAmount = msg.value;
        uint256 usdtAmount = getLatestETHPrice(ethAmount);
 
        uint256 currentPaid = userPaidUSD[msg.sender][activePhase];
        require(currentPaid + usdtAmount >= minPerWallet && currentPaid + usdtAmount <= maxPerWallet, "SUPPresale: The price is not allowed for presale.");

        bool isReachMaxAmount;

        // token amount user want to buy
        uint256 tokenAmount = usdtAmount * TOKEN_DECIMAL / price;

        if (phases[activePhase].maxTokens < tokenAmount + soldTokens && isAutoMovePhase) {
            uint256 tokenAmount2 = maxTokens - soldTokens;
            uint256 returnAmount = ethAmount - (ethAmount * tokenAmount2 / tokenAmount);
            returnEth(msg.sender, returnAmount);

            usdtAmount = usdtAmount * tokenAmount2 / tokenAmount;
            tokenAmount = tokenAmount2;
            isReachMaxAmount = true;
        }

        // transfer SUP token to user
        SUPToken.safeTransfer(msg.sender, tokenAmount);

        phases[activePhase].soldTokens += tokenAmount;
        // add USD user bought
        userPaidUSD[msg.sender][activePhase] += usdtAmount;

        emit Buy(msg.sender, tokenAmount, activePhase);

        if(isReachMaxAmount){
            activePhase++;
        } 
    }

    /**
    * @notice Purchase tokens with USD using a credit card payment. A manager's wallet will then transfer the tokens to the user who paid with BNB or a credit card.
    * @param _usdtAmount Amount of usdt to buy token.
    * @param _user Address of user
    */
    function giveTokenToBuyer(uint256 _usdtAmount, address _user) external {
        require(msg.sender == SALE_WITH_CARD_PAYMENT_MANAGER, "SUPPresale: Invalid caller");

        uint256 maxTokens = phases[activePhase].maxTokens;
        uint256 price = phases[activePhase].price;
        uint256 minPerWallet = phases[activePhase].minPerWallet;
        uint256 maxPerWallet = phases[activePhase].maxPerWallet;
        uint256 start_time = phases[activePhase].startTime;
        uint256 end_time = phases[activePhase].endTime;
        uint256 soldTokens = phases[activePhase].soldTokens;

        uint256 user_paid = userPaidUSD[_user][activePhase];

        require(block.timestamp >= start_time && block.timestamp <= end_time, "SUPPresale: Not presale period");

        uint256 currentPaid = user_paid;
        require(currentPaid + _usdtAmount >= minPerWallet && currentPaid + _usdtAmount <= maxPerWallet, "SUPPresale: The price is not allowed for presale.");
        
        bool isReachMaxAmount;

        // token amount user want to buy
        uint256 tokenAmount = _usdtAmount * TOKEN_DECIMAL / price;

        if (phases[activePhase].maxTokens < tokenAmount + soldTokens && isAutoMovePhase) {
            uint256 returnAmount = _usdtAmount -  (_usdtAmount * (maxTokens - soldTokens) / tokenAmount);
            if(IERC20(USDT).balanceOf(address(this)) >= returnAmount){
            IERC20(USDT).safeTransfer(_user, returnAmount);
            }else {
                emit RefundAmount2CardOrBNBPayer(activePhase, _user, returnAmount);
            }
            tokenAmount = maxTokens - soldTokens;
            isReachMaxAmount = true;
        }

       // transfer SUP token to user
        SUPToken.safeTransfer(_user, tokenAmount);
        
        phases[activePhase].soldTokens += tokenAmount;
        // add USD user bought
        userPaidUSD[_user][activePhase] += _usdtAmount;

        emit Buy(_user, tokenAmount, activePhase);

        if(isReachMaxAmount){
            activePhase++;
        } 
    }

    /**
    * @dev Get latest ETH price from dex.
    * @param _amount ETH amount.
    */
    function getLatestETHPrice(uint256 _amount) public view returns (uint256) {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(USDT);

        uint256[] memory price_out = router.getAmountsOut(_amount, path);
        uint256 price_round = price_out[1] / USDT_DECIMAL;
        return price_round * USDT_DECIMAL;
    }

    /**
    * @dev Get paid usdt of a user on specified phase.
    * @param _account User address.
    * @param _phaseNum Number of phase.
    */
    function getUserPaidUSDT (address _account, uint256 _phaseNum) public view returns (uint256) {
        return userPaidUSD[_account][_phaseNum];
    }

    /**
    * @dev Set start and end time of a phase.
    * @param _phaseNum Number of phase.
    * @param _startTime Start time of a phase.
    * @param _endTime End time of a phase.
    */
    function setStartAndEndTime(uint256 _phaseNum, uint256 _startTime, uint256 _endTime) external onlyOwner {
        phases[_phaseNum].startTime = _startTime;
        phases[_phaseNum].endTime = _endTime;
        emit SetStartAndEndTime(_startTime, _endTime, _phaseNum);
    }

    /**
    * @dev Set end time of a phase.
    * @param _phaseNum Number of phase.
    * @param _time End time of a phase.
    */
    function setEndTime(uint256 _phaseNum, uint256 _time) external onlyOwner {
        phases[_phaseNum].endTime = _time;

        emit SetEndTime(_time, _phaseNum);
    }

    /**
    * @dev Set wallet address that is used to withdraw SupCoin along card payment amount
    * @param _address A Wallet address.
    */
    function setCardPaymentManager(address _address) external onlyOwner {
        SALE_WITH_CARD_PAYMENT_MANAGER = _address;

        emit SetCardPaymentManager(_address);
    }

    /**
    * @dev Set active phase.
    * @param _phaseNum Number of phase.
    * @param _isAutoPhase Auto move phase, TRUE: Auto move to next phase if a phase end.
    */
    function setActivePhase(uint256 _phaseNum, bool _isAutoPhase) external onlyOwner {
        activePhase = _phaseNum;
        isAutoMovePhase = _isAutoPhase;
    }

    /**
    * @dev Burn unsold tokens at the end of a phase.
    */
    function burnUnsoldTokens() external onlyOwner {
        require(phases[activePhase].endTime != 0 && block.timestamp > phases[activePhase].endTime);
        uint256 unsoldTokens = phases[activePhase].maxTokens - phases[activePhase].soldTokens;
        require(unsoldTokens > 0, "no unsold tokens");

        SUPToken.safeTransfer(address(0), unsoldTokens);

        emit Burn(unsoldTokens, activePhase);
    }

    /**
    * @notice Withdraw ETH.
    * @dev Withdraw eth from this contract.
    * @param _ethAmount Amount of eth to withdraw.
    */
    function withdrawETH(uint256 _ethAmount) external onlyOwner {

        ( bool success,) = owner().call{value: _ethAmount}("");
        require(success, "Withdrawal was not successful");
    }

    function returnEth(address _account, uint256 _amount) internal {
        ( bool success,) = _account.call{value: _amount}("");
        require(success, "Withdrawal was not successful");
    }

    /**
    * @notice Withdraw tokens.
    * @dev Withdraw tokens from this contract.
    * @param _tokenAddress Address of the token.
    * @param _amount Amount of the token to withdraw.
    */
    function withdrawToken(address _tokenAddress,uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).safeTransfer(owner(),_amount);
    }
}