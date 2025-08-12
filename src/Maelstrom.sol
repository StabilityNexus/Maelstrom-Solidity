// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Maelstrom { 
    using SafeMath for uint256;
    mapping(address => uint256) public lastPriceBuy;
    mapping(address => uint256) public lastPriceSell;
    mapping(address => uint256) public lastBuyTimestamp;
    mapping(address => uint256) public lastSellTimestamp;

    mapping(address => address) public poolToken; // token => LP token of the token/ETH pool
    mapping(address => uint256) public ethBalance; // token => balance of ETH in the token's pool

    function priceBuy(address token) public view {
        return lastPriceBuy[token]; // TODO
    }

    function priceSell(address token) public view { 
        return lastPriceSell[token]; // TODO
    }

    function initializePool(address token, uint256 amount, uint256 initialPriceBuy, uint256 initialPriceSell) public payable {
       require(poolToken[token] == address(0), "pool already initialized");
       // TODO: create LP token (ERC20) for the pool
       // poolToken[token] = IERC20(lpToken);
       lastPriceBuy[token] = initialPriceBuy;
       lastPriceSell[token] = initialPriceSell;
       lastBuyTimestamp[token] = block.timestamp;
       lastSellTimestamp[token] = block.timestamp;
       ethBalance[token] = msg.value;
       poolToken[token].mint(msg.sender, amount);
    } 

    function reserves(address token) public view returns (uint256, uint256) { // (ETH amount in the pool, token amount in the pool)
        return (ethBalance[token], IERC20(token).balanceOf(address(this)));
    }


    function poolUserBalances(address token, address user) public view returns (uint256, uint256) { // (User's ETH amount in the pool, User's token amount in the pool)
        (uint256 rETH, uint256 rToken) = reserves(token);
        IERC20 pt = IERC20(poolToken[token]);
        uint256 ub = pt.balanceOf(user);
        uint256 ts = pt.totalSupply();
        return (rETH * ub / ts, rToken * ub / ts);
    }

    function tokenPerETHRatio(address token) public view returns (uint256) {
        (uint256 poolETHBalance, uint256 poolTokenBalance) = poolTotalBalances(token);
        return poolTokenBalance / poolETHBalance;
    }

    function buy(address token) public payable {
        IERC20(token).transfer(msg.sender, msg.value / priceBuy(token));
    }

    function sell(address token, uint256 amount) public {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        // TODO: transfer `amount * priceSell(token)` ETH from this contract to msg.sender
    }

    function deposit() external payable {
        uint256 ethBalanceBefore = ethBalance[token];
        ethBalance[token] += msg.value;
        IERC20(token).transferFrom(msg.sender, address(this), msg.value * tokenPerETHRatio(token));
        IERC20 pt = IERC20(poolToken[token]);
        pt.mint(msg.sender, pt.totalSupply() * msg.value / ethBalanceBefore);
    }

    function withdraw(uint256 amount) external {
        // TODO: burn LP tokens and transfer eth and token to msg.sender
    }

    function swap(address tokenSell, address tokenBuy, uint256 amountToSell, uint256 minimumAmountToBuy) external {
        // TODO: sell tokenSell and then buy TokenBuy with the ETH from the tokenSell you just sold
    }
}
