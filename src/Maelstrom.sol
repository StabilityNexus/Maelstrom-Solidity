// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "node_modules/openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from 'node_modules/openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeERC20} from 'node_modules/openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {SafeMath} from "node_modules/openzeppelin/contracts/utils/math/SafeMath.sol";
import {LiquidityPoolToken} from "./LiquidityPoolToken.sol";
import {SD59x18,exp} from "node_modules/@prb/math/src/SD59x18.sol";

contract Maelstrom {
    using SafeMath for uint256;
    struct PoolParams {
        uint256 lastBuyPrice;
        uint256 lastSellPrice;
        uint256 lastExchangeTimestamp;
        uint256 finalBuyPrice;
        uint256 finalSellPrice;
        uint256 lastBuyTimestamp;
        uint256 lastSellTimestamp;
        uint256 decayedBuyTime;
        uint256 decayedSellTime;
        uint256 decayedBuyVolume;
        uint256 decayedSellVolume;
    }
    event PoolInitialized(address indexed token, uint256 tokenAmount, uint256 ethAmount, uint256 initialPriceBuy, uint256 initialPriceSell);
    event BuyTrade(address indexed token,address indexed trader,uint256 ethAmount,uint256 tokenAmount,uint256 buyPrice);
    event SellTrade(address indexed token,address indexed trader,uint256 tokenAmount,uint256 ethAmount,uint256 sellPrice);
    event SwapTrade(address indexed tokenSold,address indexed tokenBought,address indexed trader,uint256 tokenAmountSold,uint256 tokenAmountBought);
    event Deposit(address indexed token,address indexed user,uint256 ethAmount,uint256 tokenAmount,uint256 lpTokensMinted);
    event Withdraw(address indexed token,address indexed user,uint256 ethAmount,uint256 tokenAmount,uint256 lpTokensBurned);
    uint256 multiplicationFactor = 5;
    address[] public poolList;
    mapping(address => mapping(address => uint256)) public userPoolIndex;  //index+1 is stored
    mapping(address => address[]) public userPools;
    mapping(address => LiquidityPoolToken) public poolToken; 
    mapping(address => uint256) public ethBalance;
    mapping(address => PoolParams) public pools;
    

    function sendERC20(address token, address to, uint256 tokenAmount) internal {
        SafeERC20.safeTransfer(IERC20(token), to, tokenAmount);
    }

    function receiveERC20(address token, address from, uint256 tokenAmount) internal {
        SafeERC20.safeTransferFrom(IERC20(token), from, address(this), tokenAmount);
    }

    function calculateFinalPrice(uint256 decayedSellVolume,uint256 sellPrice,uint256 decayedBuyVolume,uint256 buyPrice) internal pure returns (uint256){
        if(decayedSellVolume + decayedBuyVolume == 0) return (sellPrice + buyPrice) / 2;
        return (decayedSellVolume * sellPrice + decayedBuyVolume * buyPrice) / (decayedSellVolume + decayedBuyVolume);
    }

    function _getDecayValue(uint256 initialValue,int256 timeElapsed) internal pure returns (uint256){
        int256 decayedAmount = SD59x18.unwrap(SD59x18.wrap((int256)(initialValue)) * exp(SD59x18.wrap(-timeElapsed)));  
        if(decayedAmount < 0) return 0;
        return (uint256)(decayedAmount);
    }

    function updatePriceSellParams(address token,uint256 tokenAmount, uint256 newPrice) internal {
        PoolParams storage pool = pools[token];
        int256 timeElapsed = (int256)(block.timestamp - pool.lastExchangeTimestamp);
        uint256 decayedSellVolume = _getDecayValue(pool.decayedSellVolume,timeElapsed);
        uint256 decayedBuyVolume = _getDecayValue(pool.decayedBuyVolume,timeElapsed);
        uint256 newDecayedSellVolume = decayedSellVolume + tokenAmount;
        pool.lastSellPrice = newPrice;
        pool.lastBuyPrice = priceBuy(token);
        pool.decayedSellVolume = newDecayedSellVolume;
        pool.finalBuyPrice = calculateFinalPrice(newDecayedSellVolume, newPrice, decayedBuyVolume, pool.lastBuyPrice);
        pool.finalSellPrice = pool.finalBuyPrice;
        pool.decayedSellTime = (((block.timestamp - pool.lastSellTimestamp) * tokenAmount) + (pool.decayedSellTime * decayedSellVolume)) / (tokenAmount + decayedSellVolume);
        pool.lastSellTimestamp = block.timestamp;
        pool.lastExchangeTimestamp = block.timestamp;
    }

    function updatePriceBuyParams(address token,uint256 tokenAmount, uint256 newPrice) internal {
        PoolParams storage pool = pools[token];
        int256 timeElapsed = (int256)(block.timestamp - pool.lastExchangeTimestamp);
        uint256 decayedSellVolume = _getDecayValue(pool.decayedSellVolume,timeElapsed);
        uint256 decayedBuyVolume = _getDecayValue(pool.decayedBuyVolume,timeElapsed);
        uint256 newDecayedBuyVolume = decayedBuyVolume + tokenAmount;
        pool.lastSellPrice = priceSell(token);
        pool.lastBuyPrice = newPrice;
        pool.decayedBuyVolume = newDecayedBuyVolume;
        pool.finalBuyPrice = calculateFinalPrice(decayedSellVolume, pool.lastSellPrice, newDecayedBuyVolume, newPrice);
        pool.finalSellPrice = pool.finalBuyPrice;
        pool.decayedBuyTime = (((block.timestamp - pool.lastBuyTimestamp) * tokenAmount) + (pool.decayedBuyTime * decayedBuyVolume)) / (tokenAmount + decayedBuyVolume);
        pool.lastBuyTimestamp = block.timestamp;
        pool.lastExchangeTimestamp = block.timestamp;
    }

    function _postSell(address token, uint256 amount) internal returns (uint256,uint256) {
        uint256 sellPrice = priceSell(token);
        uint256 ethAmount = amount * sellPrice;
        require((ethBalance[token] * 10) / 100 >= ethAmount, "Not more than 10% of eth in pool can be used for swap");
        ethBalance[token] -= ethAmount;
        updatePriceSellParams(token,amount,sellPrice);
        return (ethAmount,sellPrice);
    }

    function _preBuy(address token, uint256 ethAmount) internal returns (uint256,uint256) {
        ethBalance[token] += ethAmount;
        uint256 buyPrice = priceBuy(token);
        uint256 tokenAmount = ethAmount / buyPrice;
        require((ERC20(token).balanceOf(address(this)) * 10) / 100 >= tokenAmount, "Not more than 10% of tokens in pool can be used for swap");
        updatePriceBuyParams(token,tokenAmount, buyPrice);
        return (tokenAmount,buyPrice);
    }

    function priceBuy(address token) public view returns (uint256){
        PoolParams memory pool = pools[token];
        uint256 lastBuyPrice = pool.lastBuyPrice;
        uint256 finalBuyPrice = pool.finalBuyPrice;
        uint256 timeElapsed = block.timestamp - pool.lastExchangeTimestamp;
        if(timeElapsed >= pool.decayedBuyTime) return finalBuyPrice; 
        uint256 currentPrice = lastBuyPrice - (((lastBuyPrice - finalBuyPrice) * timeElapsed) / (pool.decayedBuyTime)); 
        return (currentPrice * (100 + multiplicationFactor)) / 100;
    }

    function priceSell(address token) public view returns(uint256){
        PoolParams memory pool = pools[token];
        uint256 lastSellPrice = pool.lastSellPrice;
        uint256 finalSellPrice = pool.finalSellPrice;
        uint256 timeElapsed = block.timestamp - pool.lastExchangeTimestamp;
        if(timeElapsed >= pool.decayedSellTime) return finalSellPrice;
        uint256 currentPrice = lastSellPrice + (((finalSellPrice - lastSellPrice) * timeElapsed) / (pool.decayedSellTime));
        return (currentPrice * (100 - multiplicationFactor)) / 100;
    }

    function initializePool(address token, uint256 amount, uint256 initialPriceBuy, uint256 initialPriceSell) public payable {
        require(address(poolToken[token]) == address(0), "pool already initialized");
        string memory tokenName = string.concat(ERC20(token).name(), " Maelstrom Liquidity Pool Token");
        string memory tokenSymbol = string.concat("m",ERC20(token).symbol());
        receiveERC20(token, msg.sender, amount);
        LiquidityPoolToken lpt = new LiquidityPoolToken(tokenName, tokenSymbol);
        poolToken[token] = lpt;
        pools[token] = PoolParams({
            lastBuyPrice: initialPriceBuy,
            lastSellPrice: initialPriceSell,
            lastExchangeTimestamp: block.timestamp,
            finalBuyPrice: initialPriceBuy,
            finalSellPrice: initialPriceSell,
            lastBuyTimestamp: block.timestamp,
            lastSellTimestamp: block.timestamp,
            decayedBuyTime: 0, 
            decayedSellTime: 0,
            decayedBuyVolume: 0,
            decayedSellVolume: 0
        });
        ethBalance[token] = msg.value;
        poolToken[token].mint(msg.sender, amount);
        poolList.push(token);
        emit PoolInitialized(token,amount,msg.value,initialPriceBuy,initialPriceSell);
    }

    function reserves(address token) public view returns (uint256, uint256) {
        return (ethBalance[token], ERC20(token).balanceOf(address(this)));
    }

    function poolUserBalances(address token, address user) public view returns (uint256, uint256) {
        (uint256 rETH, uint256 rToken) = reserves(token);
        LiquidityPoolToken pt = poolToken[token];
        uint256 ub = pt.balanceOf(user);
        uint256 ts = pt.totalSupply();
        return ((rETH * ub) / ts, (rToken * ub) / ts);
    }

    function tokenPerETHRatio(address token) public view returns (uint256) {
        (uint256 poolETHBalance, uint256 poolTokenBalance) = reserves(token);
        return poolTokenBalance / poolETHBalance;
    }

    function buy(address token) public payable {
        (uint256 tokenAmount,uint256 buyPrice) = _preBuy(token, msg.value);
        sendERC20(token, msg.sender, tokenAmount);
        emit BuyTrade(token, msg.sender, msg.value, tokenAmount, buyPrice);
    }

    function sell(address token, uint256 amount) public {
        receiveERC20(token, msg.sender, amount);
        (uint256 ethAmount,uint256 sellPrice) = _postSell(token, amount);
        (bool success, ) = msg.sender.call{value: ethAmount}(''); 
        require(success, 'Transfer failed');
        emit SellTrade(token, msg.sender, amount, ethAmount, sellPrice);
    }

    function deposit(address token) external payable {
        require(msg.value > 0, "Must send ETH to deposit");
        if(userPoolIndex[msg.sender][token] == 0) {
            userPools[msg.sender].push(token);
            userPoolIndex[msg.sender][token] = userPools[msg.sender].length; 
        }
        uint256 ethBalanceBefore = ethBalance[token];
        ethBalance[token] += msg.value;
        uint256 tokenAmount = msg.value * tokenPerETHRatio(token);
        receiveERC20(token, msg.sender, tokenAmount);
        LiquidityPoolToken pt = poolToken[token];
        uint256 mintAmount = (pt.totalSupply() * msg.value) / ethBalanceBefore;
        pt.mint(msg.sender, mintAmount);
        emit Deposit(token, msg.sender, msg.value, tokenAmount, mintAmount);
    }

    function withdraw(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than zero");
        LiquidityPoolToken pt = poolToken[token];
        require(pt.balanceOf(msg.sender) >= amount, "Not enough LP tokens");
        pt.burn(msg.sender, amount);
        (uint256 rETH, uint256 rToken) = reserves(token);
        uint256 ts = pt.totalSupply();
        uint256 tokenAmount = (rToken * amount) / ts;
        sendERC20(token, msg.sender, tokenAmount);
        uint256 ethAmount = (rETH * amount) / ts;
        ethBalance[token] -= ethAmount;
        (bool success, ) = msg.sender.call{value: (ethAmount)}('');
        if(pt.balanceOf(msg.sender) == 0){
            address[] storage currentPools = userPools[msg.sender];
            mapping(address => uint256) storage userPoolIdx = userPoolIndex[msg.sender];
            uint256 index = userPoolIndex[msg.sender][token] - 1;
            userPoolIdx[token] = 0;
            uint256 lastIndex = userPools[msg.sender].length - 1;
            if(index != 0){
                address lastToken = currentPools[lastIndex];
                currentPools[index] = lastToken;
                userPoolIdx[lastToken] = index + 1; 
            }
            currentPools.pop();
        }
        require(success, "ETH Transfer Failed!");
        emit Withdraw(token, msg.sender, ethAmount, tokenAmount, amount);
    }

    function swap(address tokenSell, address tokenBuy, uint256 amountToSell, uint256 minimumAmountToBuy) external {
        (uint256 ethAmount, )  = _postSell(tokenSell, amountToSell);
        (uint256 tokenAmount, ) = _preBuy(tokenBuy, ethAmount);
        require(tokenAmount >= minimumAmountToBuy, "Insufficient output amount");
        receiveERC20(tokenSell, msg.sender, amountToSell);
        sendERC20(tokenBuy, msg.sender, tokenAmount);
        emit SwapTrade(tokenSell, tokenBuy, msg.sender, amountToSell, tokenAmount);
    }

    function _getSubArray(address[] memory array, uint256 start, uint256 end) internal pure returns (address[] memory) {
        require(start <= end && end < array.length, "Invalid start or end index");
        address[] memory subArray = new address[](end - start + 1);
        for (uint256 i = start; i <= end; i++) {
            subArray[i - start] = array[i];
        }
        return subArray;
    }

    function getPoolList(uint256 start, uint256 end) external view returns (address[] memory) {
        return _getSubArray(poolList, start, end);
    }

    function getUserPools(address user, uint256 start, uint256 end) external view returns (address[] memory) {
        return _getSubArray(userPools[user], start, end);
    }

}
