// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "node_modules/openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from 'node_modules/openzeppelin/contracts/token/ERC20/ERC20.sol';
import {SafeERC20} from 'node_modules/openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {SafeMath} from "node_modules/openzeppelin/contracts/utils/math/SafeMath.sol";
import {LiquidityPoolToken} from "./LiquidityPoolToken.sol";

contract Maelstrom {
    using SafeMath for uint256;
    mapping(address => uint256) public lastPriceBuy;
    mapping(address => uint256) public lastPriceSell;
    mapping(address => uint256) public lastPriceMid;
    // mapping(address => uint256) public lastBuyTimestamp;
    // mapping(address => uint256) public lastSellTimestamp;
    mapping(address => uint256) public lastExchangeTimestamp;
    mapping(address => LiquidityPoolToken) public poolToken; // token => LP token of the token/ETH pool
    mapping(address => uint256) public ethBalance; // token => balance of ETH in the token's pool

    function sendERC20(address token, address to, uint256 tokenAmount) internal {
        SafeERC20.safeTransfer(IERC20(token), to, tokenAmount);
    }

    function receiveERC20(address token, address from, uint256 tokenAmount) internal {
        SafeERC20.safeTransferFrom(IERC20(token), from, address(this), tokenAmount);
    }

    function updateTimeStamp(address token) internal {
        lastExchangeTimestamp[token] = block.timestamp;
    }

    function updatePriceMid(address token) internal {
        lastPriceMid[token] = (lastPriceBuy[token] + lastPriceSell[token]) / 2;
    }

    function updatePriceSellParams(address token, uint256 newPrice) internal {
        lastPriceSell[token] = newPrice;
        updatePriceMid(token);
        updateTimeStamp(token);
    }

    function updatePriceBuyParams(address token, uint256 newPrice) internal {
        lastPriceBuy[token] = newPrice;
        updatePriceMid(token);
        updateTimeStamp(token);
    }

    function _postSell(address token, uint256 amount) internal returns (uint256) {
        uint256 sellPrice = priceSell(token);
        uint256 ethAmount = amount * sellPrice;
        require((ethBalance[token] * 10) / 100 >= ethAmount, "Not more than 10% of eth in pool can be used for swap");
        ethBalance[token] -= ethAmount;
        updatePriceSellParams(token, sellPrice);
        return ethAmount;
    }

    function _preBuy(address token, uint256 ethAmount) internal returns (uint256) {
        ethBalance[token] += ethAmount;
        uint256 buyPrice = priceBuy(token);
        uint256 tokenAmount = msg.value / buyPrice;
        require((ERC20(token).balanceOf(address(this)) * 10) / 100 >= tokenAmount, "Not more than 10% of tokens in pool can be used for swap");
        updatePriceBuyParams(token, buyPrice);
        return tokenAmount;
    }

    function priceBuy(address token) public view returns (uint256){
        uint256 timeElapsed = block.timestamp - lastExchangeTimestamp[token];
        if(timeElapsed >= 24 hours) return (lastPriceMid[token] * 120) / 100; 
        uint256 currentPrice = lastPriceBuy[token] + (lastPriceMid[token] - lastPriceBuy[token]) * timeElapsed / (24 hours); 
        return (currentPrice * 120) / 100;
    }

    function priceSell(address token) public view returns(uint256){
        uint256 timeElapsed = block.timestamp - lastExchangeTimestamp[token];
        if(timeElapsed >= 24 hours) return (lastPriceMid[token] * 80) / 100;
        uint256 currentPrice = lastPriceSell[token] + (lastPriceMid[token] - lastPriceSell[token]) * timeElapsed / (24 hours);
        return (currentPrice * 80) / 100;
    }

    function initializePool(address token, uint256 amount, uint256 initialPriceBuy, uint256 initialPriceSell) public payable {
        require(address(poolToken[token]) == address(0), "pool already initialized");
        string memory tokenName = string.concat(ERC20(token).name(), " Maelstrom Liquidity Pool Token");
        string memory tokenSymbol = string.concat("m",ERC20(token).symbol());
        LiquidityPoolToken lpt = new LiquidityPoolToken(tokenName, tokenSymbol);
        poolToken[token] = lpt;
        updatePriceBuyParams(token, initialPriceBuy);
        updatePriceSellParams(token, initialPriceSell);
        ethBalance[token] = msg.value;
        poolToken[token].mint(msg.sender, amount);
    }

    function reserves(address token) public view returns (uint256, uint256) {
        // (ETH amount in the pool, token amount in the pool)
        return (ethBalance[token], ERC20(token).balanceOf(address(this)));
    }

    function poolUserBalances(address token, address user) public view returns (uint256, uint256) {
        // (User's ETH amount in the pool, User's token amount in the pool)
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
        // Transfer `msg.value / priceBuy(token)` token from this contract to msg.sender
        sendERC20(token, msg.sender, _preBuy(token, msg.value));
    }

    function sell(address token, uint256 amount) public {
        // Transfer `amount * priceSell(token)` ETH from this contract to msg.sender
        receiveERC20(token, msg.sender, amount);
        (bool success, ) = msg.sender.call{value: _postSell(token,amount)}(''); 
        require(success, 'Transfer failed');
    }

    function deposit(address token) external payable {
        uint256 ethBalanceBefore = ethBalance[token];
        ethBalance[token] += msg.value;
        receiveERC20(token, msg.sender, msg.value * tokenPerETHRatio(token));
        LiquidityPoolToken pt = poolToken[token];
        pt.mint(msg.sender, (pt.totalSupply() * msg.value) / ethBalanceBefore);
    }

    function withdraw(address token, uint256 amount) external {
        // burn LP tokens and transfer eth and token to msg.sender
        LiquidityPoolToken pt = poolToken[token];
        require(pt.balanceOf(msg.sender) >= amount, "Not enough LP tokens");
        pt.burn(msg.sender, amount);
        (uint256 rETH, uint256 rToken) = reserves(token);
        uint256 ts = pt.totalSupply();
        sendERC20(token, msg.sender, (rToken * amount) / ts);
        uint256 ethAmount = (rETH * amount) / ts;
        ethBalance[token] -= ethAmount;
        (bool success, ) = msg.sender.call{value: (ethAmount)}('');
        require(success, "ETH Transfer Failed!");
    }

    function swap(address tokenSell, address tokenBuy, uint256 amountToSell, uint256 minimumAmountToBuy) external {
        // sell tokenSell and then buy TokenBuy with the ETH from the tokenSell you just sold
        uint256 ethAmount = _postSell(tokenSell, amountToSell);
        uint256 tokenAmount = _preBuy(tokenBuy, ethAmount);
        require(tokenAmount >= minimumAmountToBuy, "Insufficient output amount");
        receiveERC20(tokenSell, msg.sender, amountToSell);
        sendERC20(tokenBuy, msg.sender, tokenAmount);
    }
}
