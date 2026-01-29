// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { LiquidityPoolToken } from "./LiquidityPoolToken.sol";
import { SD59x18, exp } from "prb-math/src/SD59x18.sol";
import { ProtocolParameters } from "./ProtocolParameters.sol";

contract Maelstrom {
    struct PoolParams {
        uint256 lastBuyPrice;
        uint256 lastSellPrice;
        uint256 lastExchangeTimestamp;
        uint256 initialSellPrice;
        uint256 initialBuyPrice;
        uint256 finalBuyPrice;
        uint256 finalSellPrice;
        uint256 lastBuyTimestamp;
        uint256 lastSellTimestamp;
        uint256 decayedBuyTime;
        uint256 decayedSellTime;
        uint256 decayedBuyVolume;
        uint256 decayedSellVolume;
    }

    struct PoolFees {
        uint256 fee;
        uint256 timestamp;
    }
    event PoolInitialized(address indexed token, uint256 amountToken, uint256 amountEther, uint256 initialPriceBuy, uint256 initialPriceSell);
    event BuyTrade(address indexed token, address indexed trader, uint256 amountEther, uint256 amountToken, uint256 tradeBuyPrice, uint256 updatedBuyPrice, uint256 sellPrice);
    event SellTrade(address indexed token, address indexed trader, uint256 amountToken, uint256 amountEther, uint256 tradeSellPrice, uint256 updatedSellPrice, uint256 buyPrice);
    event SwapTrade(address indexed tokenSold, address indexed tokenBought, address indexed trader, uint256 amountTokenSold, uint256 amountTokenBought, uint256 tradeSellPrice, uint256 updatedSellPrice, uint256 tradeBuyPrice, uint256 updatedBuyPrice);
    event Deposit(address indexed token, address indexed user, uint256 amountEther, uint256 amountToken, uint256 lpTokensMinted);
    event Withdraw(address indexed token, address indexed user, uint256 amountEther, uint256 amountToken, uint256 lpTokensBurned);
    uint256 public auctionResetPercentage = 5;
    uint256 public totalFees = 0;
    address[] public poolList;
    mapping(address => uint256) public totalPoolFees;
    mapping(address => PoolFees[]) public poolFeesEvents;
    mapping(address => mapping(address => uint256)) public userPoolIndex; //index+1 is stored
    mapping(address => address[]) public userPools;
    mapping(address => LiquidityPoolToken) public poolToken;
    mapping(address => uint256) public ethBalance;
    mapping(address => PoolParams) public pools;
    ProtocolParameters protocolParameters;

    modifier validAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than zero");
        _;
    }

    modifier validAddress(address _addr) {
        require(_addr != address(0), "Invalid address");
        _;
    }
    modifier validETHValue(string memory errorMessage) {
        require(msg.value > 0, errorMessage);
        _;
    }

    constructor(address _protocolParametersAddress) validAddress(_protocolParametersAddress) {
        protocolParameters = ProtocolParameters(_protocolParametersAddress);
    }

    function sendERC20(address token, address to, uint256 amountToken) internal {
        SafeERC20.safeTransfer(IERC20(token), to, amountToken);
    }

    function receiveERC20(address token, address from, uint256 amountToken) internal {
        SafeERC20.safeTransferFrom(IERC20(token), from, address(this), amountToken);
    }

    function _getSubArray(address[] memory array, uint256 start, uint256 end) internal pure returns (address[] memory) {
        if (array.length == 0 || start >= array.length) {
            return new address[](0);
        }
        end = end >= array.length ? array.length - 1 : end;
        require(start <= end, "Invalid start or end index");
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

    function getPoolFeeList(address token, uint256 start, uint256 end) external view returns (PoolFees[] memory) {
        require(start <= end, "Invalid start or end index");
        PoolFees[] memory array = poolFeesEvents[token];
        end = end >= array.length ? array.length - 1 : end;
        PoolFees[] memory subArray = new PoolFees[](end - start + 1);
        for (uint256 i = start; i <= end; i++) {
            subArray[i - start] = array[i];
        }
        return subArray;
    }

    function _addTokenToUserPools(address user, address token) internal {
        userPools[user].push(token);
        userPoolIndex[user][token] = userPools[user].length;
    }

    function getTotalPools() external view returns (uint256) {
        return poolList.length;
    }

    function getUserTotalPools(address user) external view returns (uint256) {
        return userPools[user].length;
    }

    function getPoolFeeEventsCount(address token) external view returns (uint256) {
        return poolFeesEvents[token].length;
    }

    function calculateFinalPrice(uint256 decayedSellVolume, uint256 sellPrice, uint256 decayedBuyVolume, uint256 buyPrice) internal pure returns (uint256) {
        if (decayedSellVolume + decayedBuyVolume == 0) return (sellPrice + buyPrice) / 2;
        return (decayedSellVolume * sellPrice + decayedBuyVolume * buyPrice) / (decayedSellVolume + decayedBuyVolume);
    }

    function _getDecayValue(uint256 initialVolume, int256 timeElapsed) internal pure returns (uint256) {
        int256 decayedAmount = SD59x18.unwrap(SD59x18.wrap((int256)(initialVolume)) * exp(SD59x18.wrap(-timeElapsed)));
        return (uint256)(decayedAmount);
    }

    function processProtocolFees(address token, uint256 totalFee) internal {
        totalFees += totalFee;
        totalPoolFees[token] += totalFee;
        PoolFees memory newFee = PoolFees({ fee: totalFee, timestamp: block.timestamp });
        poolFeesEvents[token].push(newFee);
        uint256 stableFees = (totalFee * protocolParameters.fee()) / 10000;
        address feeRecipient = protocolParameters.treasury();
        (bool success, ) = feeRecipient.call{ value: stableFees }("");
        require(success, "Transfer failed");
    }

    function updatePriceSellParams(address token, uint256 amountToken, uint256 newPrice) internal {
        PoolParams storage pool = pools[token];
        int256 timeElapsed = (int256)(block.timestamp - pool.lastExchangeTimestamp);
        uint256 decayedSellVolume = _getDecayValue(pool.decayedSellVolume, timeElapsed);
        uint256 decayedBuyVolume = _getDecayValue(pool.decayedBuyVolume, timeElapsed);
        uint256 newDecayedSellVolume = decayedSellVolume + amountToken;
        uint256 newInitialSellPrice = (pool.initialSellPrice * (100 - auctionResetPercentage)) / 100;
        pool.lastSellPrice = newPrice;
        pool.initialSellPrice = newInitialSellPrice;
        pool.initialBuyPrice = priceBuy(token);
        pool.decayedSellVolume = newDecayedSellVolume;
        pool.decayedBuyVolume = decayedBuyVolume;
        pool.finalBuyPrice = calculateFinalPrice(newDecayedSellVolume, newInitialSellPrice, decayedBuyVolume, pool.initialBuyPrice);
        pool.finalSellPrice = pool.finalBuyPrice;
        pool.decayedSellTime = (((block.timestamp - pool.lastSellTimestamp) * amountToken) + (pool.decayedSellTime * decayedSellVolume)) / (amountToken + decayedSellVolume);
        pool.lastSellTimestamp = block.timestamp;
        pool.lastExchangeTimestamp = block.timestamp;
    }

    function updatePriceBuyParams(address token, uint256 amountToken, uint256 newPrice) internal {
        PoolParams storage pool = pools[token];
        int256 timeElapsed = (int256)(block.timestamp - pool.lastExchangeTimestamp);
        uint256 decayedSellVolume = _getDecayValue(pool.decayedSellVolume, timeElapsed);
        uint256 decayedBuyVolume = _getDecayValue(pool.decayedBuyVolume, timeElapsed);
        uint256 newDecayedBuyVolume = decayedBuyVolume + amountToken;
        uint256 newInitialBuyPrice = (pool.initialBuyPrice * (100 + auctionResetPercentage)) / 100;
        pool.lastBuyPrice = newPrice;
        pool.initialBuyPrice = newInitialBuyPrice;
        pool.initialSellPrice = priceSell(token);
        pool.decayedBuyVolume = newDecayedBuyVolume;
        pool.decayedSellVolume = decayedSellVolume;
        pool.finalBuyPrice = calculateFinalPrice(decayedSellVolume, pool.initialSellPrice, newDecayedBuyVolume, newInitialBuyPrice);
        pool.finalSellPrice = pool.finalBuyPrice;
        pool.decayedBuyTime = (((block.timestamp - pool.lastBuyTimestamp) * amountToken) + (pool.decayedBuyTime * decayedBuyVolume)) / (amountToken + decayedBuyVolume);
        pool.lastBuyTimestamp = block.timestamp;
        pool.lastExchangeTimestamp = block.timestamp;
    }

    function _postSell(address token, uint256 amountToken) internal returns (uint256, uint256) {
        uint256 sellPrice = priceSell(token);
        uint256 amountEther = (amountToken * sellPrice) / 1e18;
        require((ethBalance[token] * 10) / 100 >= amountEther, "Not more than 10% of eth in pool can be used for swap");
        ethBalance[token] -= amountEther;
        uint256 totalFee = ((pools[token].finalSellPrice - sellPrice) * amountToken) / 1e18;
        if (totalFee != 0) processProtocolFees(token, totalFee);
        updatePriceSellParams(token, amountToken, sellPrice);
        processProtocolFees(token, totalFee);
        return (amountEther, sellPrice);
    }

    function _preBuy(address token, uint256 amountEther) internal returns (uint256, uint256) {
        ethBalance[token] += amountEther;
        uint256 buyPrice = priceBuy(token);
        uint256 amountToken = (amountEther * 1e18) / buyPrice;
        require((ERC20(token).balanceOf(address(this)) * 10) / 100 >= amountToken, "Not more than 10% of tokens in pool can be used for swap");
        uint256 totalFee = ((buyPrice - pools[token].finalBuyPrice) * amountToken) / 1e18;
        if (totalFee != 0) processProtocolFees(token, totalFee);
        updatePriceBuyParams(token, amountToken, buyPrice);
        return (amountToken, buyPrice);
    }

    function priceBuy(address token) public view returns (uint256) {
        PoolParams memory pool = pools[token];
        uint256 initialBuyPrice = pool.initialBuyPrice;
        uint256 finalBuyPrice = pool.finalBuyPrice;
        uint256 timeElapsed = block.timestamp - pool.lastExchangeTimestamp;
        if (timeElapsed >= pool.decayedBuyTime) return finalBuyPrice;
        return initialBuyPrice - (((initialBuyPrice - finalBuyPrice) * timeElapsed) / (pool.decayedBuyTime));
    }

    function priceSell(address token) public view returns (uint256) {
        PoolParams memory pool = pools[token];
        uint256 initialSellPrice = pool.initialSellPrice;
        uint256 finalSellPrice = pool.finalSellPrice;
        uint256 timeElapsed = block.timestamp - pool.lastExchangeTimestamp;
        if (timeElapsed >= pool.decayedSellTime) return finalSellPrice;
        return initialSellPrice + (((finalSellPrice - initialSellPrice) * timeElapsed) / (pool.decayedSellTime));
    }

    function initializePool(address token, uint256 amountToken, uint256 initialPriceBuy, uint256 initialPriceSell) public payable validAddress(token) validETHValue("Initial liquidity required") {
        require(amountToken > 0, "Initial token liquidity required");
        require(initialPriceBuy > 0 && initialPriceSell > 0, "Initial prices must be > 0");
        require(address(poolToken[token]) == address(0), "pool already initialized");
        string memory tokenName = string.concat(ERC20(token).name(), " Maelstrom Liquidity Pool Token");
        string memory tokenSymbol = string.concat("m", ERC20(token).symbol());
        receiveERC20(token, msg.sender, amountToken);
        LiquidityPoolToken lpt = new LiquidityPoolToken(tokenName, tokenSymbol);
        poolToken[token] = lpt;
        uint256 avgPrice = (initialPriceBuy + initialPriceSell) / 2;
        pools[token] = PoolParams({ lastBuyPrice: initialPriceBuy, lastSellPrice: initialPriceSell, lastExchangeTimestamp: block.timestamp, finalBuyPrice: avgPrice, finalSellPrice: avgPrice, initialSellPrice: initialPriceSell, initialBuyPrice: initialPriceBuy, lastBuyTimestamp: block.timestamp, lastSellTimestamp: block.timestamp, decayedBuyTime: 0, decayedSellTime: 0, decayedBuyVolume: 0, decayedSellVolume: 0 });
        ethBalance[token] = msg.value;
        poolToken[token].mint(msg.sender, amountToken);
        poolList.push(token);
        _addTokenToUserPools(msg.sender, token);
        emit PoolInitialized(token, amountToken, msg.value, initialPriceBuy, initialPriceSell);
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

    function buy(address token, uint256 minimumAmountToken) public payable {
        (uint256 amountToken, uint256 buyPrice) = _preBuy(token, msg.value);
        require(minimumAmountToken <= amountToken, "Insufficient output amount");
        sendERC20(token, msg.sender, amountToken);
        emit BuyTrade(token, msg.sender, msg.value, amountToken, buyPrice, priceBuy(token), priceSell(token));
    }

    function sell(address token, uint256 amount, uint256 minimumAmountEther) public validAmount(amount) validAddress(token) {
        receiveERC20(token, msg.sender, amount);
        (uint256 amountEther, uint256 sellPrice) = _postSell(token, amount);
        require(minimumAmountEther < amountEther, "Insufficient output amount");
        (bool success, ) = msg.sender.call{ value: amountEther }("");
        require(success, "Transfer failed");
        emit SellTrade(token, msg.sender, amount, amountEther, sellPrice, priceSell(token), priceBuy(token));
    }

    function deposit(address token) external payable {
        require(msg.value > 0, "Must send ETH to deposit");
        if (userPoolIndex[msg.sender][token] == 0) _addTokenToUserPools(msg.sender, token);
        uint256 ethBalanceBefore = ethBalance[token];
        uint256 amountToken = msg.value * tokenPerETHRatio(token);
        ethBalance[token] += msg.value;
        receiveERC20(token, msg.sender, amountToken);
        LiquidityPoolToken pt = poolToken[token];
        uint256 mintAmount = (pt.totalSupply() * msg.value) / ethBalanceBefore;
        pt.mint(msg.sender, mintAmount);
        emit Deposit(token, msg.sender, msg.value, amountToken, mintAmount);
    }

    function withdraw(address token, uint256 amountPoolToken) external validAddress(token) {
        require(amountPoolToken > 0, "Amount must be greater than zero");
        LiquidityPoolToken pt = poolToken[token];
        require(pt.balanceOf(msg.sender) >= amountPoolToken, "Not enough LP tokens");
        (uint256 rETH, uint256 rToken) = reserves(token);
        uint256 ts = pt.totalSupply();
        uint256 amountToken = (rToken * amountPoolToken) / ts;
        uint256 amountTokenAfterFees = (amountToken * 995) / 1000;
        pt.burn(msg.sender, amountPoolToken);
        sendERC20(token, msg.sender, amountTokenAfterFees);
        uint256 amountEther = (rETH * amountPoolToken) / ts;
        uint256 amountEtherAfterFees = (amountEther * 995) / 1000;
        ethBalance[token] -= amountEtherAfterFees;
        (bool success, ) = msg.sender.call{ value: amountEtherAfterFees }("");
        if (pt.balanceOf(msg.sender) == 0) {
            address[] storage currentPools = userPools[msg.sender];
            mapping(address => uint256) storage poolIndex = userPoolIndex[msg.sender];
            uint256 indexToRemove = poolIndex[token] - 1;
            uint256 lastIndex = currentPools.length - 1;
            if (indexToRemove != lastIndex) {
                address lastToken = currentPools[lastIndex];
                currentPools[indexToRemove] = lastToken;
                // Update the index of the moved token (remembering it is 1-based)
                poolIndex[lastToken] = indexToRemove + 1;
            }
            currentPools.pop();
            poolIndex[token] = 0;
        }
        require(success, "ETH Transfer Failed!");
        emit Withdraw(token, msg.sender, amountEtherAfterFees, amountTokenAfterFees, amountPoolToken);
    }

    function swap(address tokenSell, address tokenBuy, uint256 amountToSell, uint256 minimumAmountToken) external {
        (uint256 amountEther, uint256 sellPrice) = _postSell(tokenSell, amountToSell);
        (uint256 amountToken, uint256 buyPrice) = _preBuy(tokenBuy, amountEther);
        require(amountToken >= minimumAmountToken, "Insufficient output amount");
        receiveERC20(tokenSell, msg.sender, amountToSell);
        sendERC20(tokenBuy, msg.sender, amountToken);
        emit SwapTrade(tokenSell, tokenBuy, msg.sender, amountToSell, amountToken, sellPrice, priceSell(tokenSell), buyPrice, priceBuy(tokenBuy));
    }
}
