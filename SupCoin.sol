// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


interface IRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address uniswapV2Pair);
}

contract SupCoin is ERC20, Ownable(msg.sender) {
    string constant TOKEN_NAME = "SupCoin";
    string constant TOKEN_SYMBOL = "SUP";

    uint8 internal constant DECIMAL_PLACES = 18;
    uint256 constant TOTAL_SUPPLY = 10 ** 10 * 10**DECIMAL_PLACES;

    mapping (address => bool) private _isExcludedFromFee;

    uint256 constant BUY_TAX = 1;
    uint256 constant SELL_TAX = 3;

    uint256 constant BURN_FEE = 50;
    uint256 constant ECOSYSTEM_FEE = 20;
    uint256 constant POOL_LIQUIDITY_FEE = 30;

    address public _ecosystemAddress;
    address public _stakingAddress;

    IRouter public _router;
    address public _pair;

    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    uint256 public swapThreshold = TOTAL_SUPPLY / 5000;
    
    bool public tradingEnabled = false;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SwapAndLiquifyEnabledUpdated(bool enabled);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    constructor(address router) ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        super._mint(address(this), TOTAL_SUPPLY);

        // Create a uniswap pair for this new token
        _router = IRouter(router);
        _pair = IFactory(_router.factory())
            .createPair(address(this), _router.WETH());

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[address(0)] = true;
    }

    function decimals() public pure override returns (uint8) {
        return DECIMAL_PLACES;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (inSwapAndLiquify) {
            return super._update(from, to, value);
        }
        
        bool isBuy = from == _pair || from == address(_router);
        bool isSell = to == _pair || to == address(_router);

        if (isSell) {
            // is the token balance of this contract address over the min number of
            // tokens that we need to initiate a swap + liquidity lock?
            // also, don't get caught in a circular liquidity event.
            // also, don't swap & liquify if sender is uniswap pair.
            uint256 contractTokenBalance = balanceOf(address(this));
            
            bool overMinTokenBalance = contractTokenBalance >= swapThreshold;
            if (
                overMinTokenBalance &&
                !inSwapAndLiquify &&
                from != _pair &&
                swapAndLiquifyEnabled
            ) {
                contractTokenBalance = swapThreshold;
                //add liquidity
                swapAndLiquify(contractTokenBalance);
            }
        }

        if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to] && tx.origin != owner()) {
            if (!tradingEnabled) {
                revert("Trading not yet enabled!");
            }

            if (isBuy) {
                uint256 tax = value * BUY_TAX / 100;
                super._update(from, address(this), tax);
                super._update(address(this), address(0), tax * BURN_FEE / 100);
                super._update(address(this), _ecosystemAddress, tax * ECOSYSTEM_FEE / 100);
                super._update(address(this), _stakingAddress, tax * POOL_LIQUIDITY_FEE / 100);

                value = value - tax;
            }

            if (isSell) {
                uint256 tax = value * SELL_TAX / 100;
                super._update(from, address(this), tax);
                super._update(address(this), address(0), tax * BURN_FEE / 100);
                super._update(address(this), _ecosystemAddress, tax * ECOSYSTEM_FEE / 100);

                value = value - tax;
            }
        }

        super._update(from, to, value);
    }

    /**
    * @notice Enable trading.
    * @dev Set trading enabled.
    */
    function enableTrading() public onlyOwner {
        require(!tradingEnabled, "Trading already enabled!");

        tradingEnabled = true;
    }

    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance / 2;
        uint256 otherHalf = contractTokenBalance - half;

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance - initialBalance;

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }


    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();

        _approve(address(this), address(_router), tokenAmount);

        // make the swap
        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(_router), tokenAmount);

        // add the liquidity
        _router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );
    }

    /**
    * @notice Set ecosystem address.
    * @dev Set ecosystem wallet address.
    * @param ecoAddress Address of ecosystem wallet.
    */
    function setEcosystemAddress(address ecoAddress) external onlyOwner() {
        _ecosystemAddress = ecoAddress;
    }

    /**
    * @notice Set staking contract address.
    * @dev Set staking contract address.
    * @param stakingAddress Address of staking contract.
    */
    function setStakingAddress(address stakingAddress) external onlyOwner() {
        _stakingAddress = stakingAddress;
    }

    /**
    * @notice Exclude address from fee.
    * @dev Set address to exclude from fee.
    * @param account Address to exclude.
    */
    function excludeFromFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = true;
    }
    
    /**
    * @notice Include address in fee.
    * @dev Set address to include in fee.
    * @param account Address to include.
    */
    function includeInFee(address account) public onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    /**
    * @notice Set flag to swap and liquify enabled.
    * @dev Set swapAndLiquifyEnabled to auto add liquidity.
    * @param enabled Address of ecosystem wallet.
    */
    function setSwapAndLiquifyEnabled(bool enabled) public onlyOwner {
        swapAndLiquifyEnabled = enabled;
        emit SwapAndLiquifyEnabledUpdated(enabled);
    }

    /**
    * @notice Withdraw tokens.
    * @dev Withdraw tokens from this contract.
    * @param _tokenAddress Address of the token.
    * @param _amount Amount of the token to withdraw.
    */
    function withdrawToken(address _tokenAddress,uint256 _amount) external onlyOwner {
        IERC20(_tokenAddress).transfer(owner(),_amount);
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

    /**
    * @notice Allocate tokens.

    * 23% of tokens will be sent to presale contract (seed: 2.5%, round1: 7.5%, round2: 5%, public: 8%)
    * 12% of tokens will be sent staking contract for rewards.
    * 10% for team
    * 22.8% for ecosystem
    * 10% for marketing
    * 5.5% for supelle treasury
    * 1.5% of tokens will be sent to owner for initial liquidity
    * 0.2% for airdrop
    * 15% for development
    */
    function allocateTokens(
        address presale, address staking, address team, address ecosystem, 
        address marketing, address treasury, address airdrop, address dev
    ) external onlyOwner() {
    
        require(balanceOf(address(this)) == TOTAL_SUPPLY, "Already allocated");

        transfer(presale, TOTAL_SUPPLY * 230 / 1000);
        transfer(staking, TOTAL_SUPPLY * 120 / 1000);

        transfer(team, TOTAL_SUPPLY * 100 / 1000);
        transfer(ecosystem, TOTAL_SUPPLY * 228 / 1000);
        transfer(marketing, TOTAL_SUPPLY * 100 / 1000);

        transfer(treasury, TOTAL_SUPPLY * 55 / 1000);

        transfer(owner(), TOTAL_SUPPLY * 15 / 100);

        transfer(airdrop, TOTAL_SUPPLY * 2 / 1000);
        transfer(dev, TOTAL_SUPPLY * 150 / 1000);
    }
    
    //to recieve ETH from uniswapV2Router when swaping
    receive() external payable {}
}