// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {Maelstrom} from "../src/Maelstrom.sol";
import {LiquidityPoolToken} from "../src/LiquidityPoolToken.sol";
import {ProtocolParameters} from "../src/ProtocolParameters.sol";
import {MockERC20} from "../src/MockERC20.sol";

contract MaelstromTest is Test {
    Maelstrom public maelstrom;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    
    uint256 public constant INITIAL_ETH_BALANCE = 1000 ether;
    uint256 public constant INITIAL_TOKEN_AMOUNT = 1000 * 10**18;
    uint256 public constant INITIAL_BUY_PRICE = 2 * 10**18; // 2 ETH per token
    uint256 public constant INITIAL_SELL_PRICE = 1.8 * 10**18; // 1.8 ETH per token
    
    event PoolInitialized(address indexed token, uint256 tokenAmount, uint256 ethAmount, uint256 initialPriceBuy, uint256 initialPriceSell);
    event BuyTrade(address indexed token, address indexed trader, uint256 ethAmount, uint256 tokenAmount, uint256 buyPrice);
    event SellTrade(address indexed token, address indexed trader, uint256 tokenAmount, uint256 ethAmount, uint256 sellPrice);
    event SwapTrade(address indexed tokenSold, address indexed tokenBought, address indexed trader, uint256 tokenAmountSold, uint256 tokenAmountBought, uint256 sellPrice, uint256 buyPrice);
    event Deposit(address indexed token, address indexed user, uint256 ethAmount, uint256 tokenAmount, uint256 lpTokensMinted);
    event Withdraw(address indexed token, address indexed user, uint256 ethAmount, uint256 tokenAmount, uint256 lpTokensBurned);

    function setUp() public {

        address treasury = makeAddr("treasury");
        address manager  = makeAddr("manager");

        ProtocolParameters protocol = new ProtocolParameters(
            treasury,
            manager,
            0 // 0% fee (max 500 = 5%)
        );
        maelstrom = new Maelstrom(address(protocol));
        tokenA = new MockERC20("Token A", "TKNA");
        tokenB = new MockERC20("Token B", "TKNB");
        // Give test accounts ETH
        vm.deal(alice, INITIAL_ETH_BALANCE);
        vm.deal(bob, INITIAL_ETH_BALANCE);
        vm.deal(charlie, INITIAL_ETH_BALANCE);
        // Give test accounts tokens
        tokenA.transfer(alice, INITIAL_TOKEN_AMOUNT);
        tokenA.transfer(bob, INITIAL_TOKEN_AMOUNT);
        tokenA.transfer(charlie, INITIAL_TOKEN_AMOUNT);
        tokenB.transfer(alice, INITIAL_TOKEN_AMOUNT);
        tokenB.transfer(bob, INITIAL_TOKEN_AMOUNT);
        tokenB.transfer(charlie, INITIAL_TOKEN_AMOUNT);
    }

    function testInitializePool() public {
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        vm.expectEmit(true, true, true, true);
        emit PoolInitialized(address(tokenA), INITIAL_TOKEN_AMOUNT, 10 ether, INITIAL_BUY_PRICE, INITIAL_SELL_PRICE);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Check pool was initialized correctly
        assertEq(maelstrom.getTotalPools(), 1);
        assertEq(maelstrom.getUserTotalPools(alice), 1);
        (uint256 ethBalance, uint256 tokenBalance) = maelstrom.reserves(address(tokenA));
        assertEq(ethBalance, 10 ether);
        assertEq(tokenBalance, INITIAL_TOKEN_AMOUNT);
        // Check LP token was created and minted
        LiquidityPoolToken lpToken = maelstrom.poolToken(address(tokenA));
        assertEq(lpToken.balanceOf(alice), INITIAL_TOKEN_AMOUNT);
        assertEq(lpToken.totalSupply(), INITIAL_TOKEN_AMOUNT);
        // Check prices
        uint256 avgPrice = (INITIAL_BUY_PRICE + INITIAL_SELL_PRICE) / 2;
        assertEq(maelstrom.priceBuy(address(tokenA)), avgPrice);
        assertEq(maelstrom.priceSell(address(tokenA)), avgPrice);
    }

    function testCannotInitializePoolTwice() public {
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT * 2);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.expectRevert("pool already initialized");
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
    }

    function testBuyTokens() public {
        // Initialize pool first
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Bob buys tokens
        uint256 avgPrice = (INITIAL_BUY_PRICE + INITIAL_SELL_PRICE) / 2;
        uint256 ethAmount = 1 ether;
        uint256 expectedTokenAmount = (ethAmount * 1e18) / avgPrice;
        vm.startPrank(bob);
        uint256 bobTokensBefore = tokenA.balanceOf(bob);
        // vm.expectEmit(true, true, true, true);
        // emit BuyTrade(address(tokenA), address(bob), ethAmount, expectedTokenAmount, avgPrice);
        maelstrom.buy{value: ethAmount}(address(tokenA),expectedTokenAmount);
        uint256 bobTokensAfter = tokenA.balanceOf(bob);
        console.log("Bob's tokens after:", bobTokensAfter);
        console.log("Actual tokens received:", bobTokensAfter - bobTokensBefore);
        assertEq(bobTokensAfter - bobTokensBefore, expectedTokenAmount);
        vm.stopPrank();
        // Check pool balances updated
        (uint256 ethBalance, uint256 tokenBalance) = maelstrom.reserves(address(tokenA));
        assertEq(ethBalance, 11 ether);
        assertEq(tokenBalance, INITIAL_TOKEN_AMOUNT - expectedTokenAmount);
    }

    function testSellTokens() public {
        // Initialize pool and buy some tokens first
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 20 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Bob sells tokens
        uint256 avgPrice = (INITIAL_BUY_PRICE + INITIAL_SELL_PRICE) / 2;
        uint256 tokenAmount = 1 * 10**18;
        uint256 expectedEthAmount = (tokenAmount * avgPrice) / 1e18;
        uint256 minEthOut = (expectedEthAmount * 99) / 100; // 1% slippage
        vm.startPrank(bob);
        tokenA.approve(address(maelstrom), tokenAmount);
        uint256 bobEthBefore = bob.balance;
        // vm.expectEmit(true, true, true, true);
        // emit SellTrade(address(tokenA), address(bob), tokenAmount, expectedEthAmount, avgPrice);
        maelstrom.sell(address(tokenA), tokenAmount, minEthOut);
        uint256 bobEthAfter = bob.balance;
        assertEq(bobEthAfter - bobEthBefore, expectedEthAmount);
        vm.stopPrank();
        // Check pool balances updated
        (uint256 ethBalance, uint256 tokenBalance) = maelstrom.reserves(address(tokenA));
        assertEq(ethBalance, 20 ether - expectedEthAmount);
        assertEq(tokenBalance, INITIAL_TOKEN_AMOUNT + tokenAmount);
    }

    function testPriceDecayOverTime() public {
        // Initialize pool
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Make a trade to set up price decay
        vm.warp(block.timestamp + 3600); 
        vm.startPrank(bob);
        uint256 buyPrice = maelstrom.priceBuy(address(tokenA));
        uint256 quotedTokens = (1 ether * 1e18) / buyPrice;
        uint256 minTokensOut = (quotedTokens * 99) / 100;
        maelstrom.buy{value: 1 ether}(address(tokenA), minTokensOut);
        tokenA.approve(address(maelstrom), 1 * 10**18);

        uint256 sellAmount = 1e17;
        tokenA.approve(address(maelstrom), sellAmount);

        uint256 price = maelstrom.priceSell(address(tokenA));
        uint256 quoted = (sellAmount * price) / 1e18;
        uint256 minOut = (quoted * 99) / 100;
        
        maelstrom.sell(address(tokenA), sellAmount, minOut);
        vm.stopPrank();
        uint256 priceAfterTrade = maelstrom.priceBuy(address(tokenA));
        // Skip forward in time
        vm.warp(block.timestamp + 1000); 
        uint256 priceAfterTime = maelstrom.priceBuy(address(tokenA));
        // Price should have changed due to time decay
        assertTrue(priceAfterTime != priceAfterTrade);
    }

    function testDeposit() public {
        // Initialize pool
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Bob deposits liquidity
        uint256 ethAmount = 2 ether;
        uint256 expectedTokenAmount = ethAmount * maelstrom.tokenPerETHRatio(address(tokenA));
        vm.startPrank(bob);
        tokenA.approve(address(maelstrom), expectedTokenAmount);
        LiquidityPoolToken lpToken = maelstrom.poolToken(address(tokenA));
        uint256 lpTokensBefore = lpToken.balanceOf(bob);
        uint256 totalSupplyBefore = lpToken.totalSupply();
        vm.expectEmit(true, true, true, true);
        emit Deposit(address(tokenA), bob, ethAmount, expectedTokenAmount, (totalSupplyBefore * ethAmount) / 10 ether);
        maelstrom.deposit{value: ethAmount}(address(tokenA));
        uint256 lpTokensAfter = lpToken.balanceOf(bob);
        assertTrue(lpTokensAfter > lpTokensBefore);
        vm.stopPrank();
        // Check user was added to user pools
        assertEq(maelstrom.getUserTotalPools(bob), 1);
    }

    function testWithdraw() public {
        // Initialize pool and deposit
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 ethAmount = 2 ether;
        uint256 expectedTokenAmount = ethAmount * maelstrom.tokenPerETHRatio(address(tokenA));
        tokenA.approve(address(maelstrom), expectedTokenAmount);
        maelstrom.deposit{value: ethAmount}(address(tokenA));
        // Now withdraw
        LiquidityPoolToken lpToken = maelstrom.poolToken(address(tokenA));
        uint256 lpTokensToWithdraw = lpToken.balanceOf(bob) / 2; // Withdraw half
        uint256 bobEthBefore = bob.balance;
        uint256 bobTokensBefore = tokenA.balanceOf(bob);
        maelstrom.withdraw(address(tokenA), lpTokensToWithdraw);
        uint256 bobEthAfter = bob.balance;
        uint256 bobTokensAfter = tokenA.balanceOf(bob);
        assertTrue(bobEthAfter > bobEthBefore);
        assertTrue(bobTokensAfter > bobTokensBefore);
        vm.stopPrank();
    }

    function testFullWithdrawRemovesUserFromPools() public {
        // Initialize pool and deposit
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        vm.startPrank(bob);
        uint256 ethAmount = 2 ether;
        uint256 expectedTokenAmount = ethAmount * maelstrom.tokenPerETHRatio(address(tokenA));
        tokenA.approve(address(maelstrom), expectedTokenAmount);
        maelstrom.deposit{value: ethAmount}(address(tokenA));
        assertEq(maelstrom.getUserTotalPools(bob), 1);
        // Withdraw all LP tokens
        LiquidityPoolToken lpToken = maelstrom.poolToken(address(tokenA));
        uint256 allLpTokens = lpToken.balanceOf(bob);
        maelstrom.withdraw(address(tokenA), allLpTokens);
        // Bob should be removed from user pools
        assertEq(maelstrom.getUserTotalPools(bob), 0);
        vm.stopPrank();
    }

    function testSwap() public {
        // Initialize both pools
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        tokenB.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 100 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        maelstrom.initializePool{value: 100 ether}(
            address(tokenB),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Bob swaps tokenA for tokenB
        uint256 tokenAAmount = 1 * 10**17;
        uint256 avgPrice = (INITIAL_SELL_PRICE + INITIAL_BUY_PRICE) / 2;
        uint256 expectedEthFromSell = (tokenAAmount * avgPrice) / 1e18;
        uint256 expectedTokenBAmount = (expectedEthFromSell * 1e18) / avgPrice;
        vm.startPrank(bob);
        tokenA.approve(address(maelstrom), tokenAAmount);
        uint256 bobTokenBBefore = tokenB.balanceOf(bob);
        // vm.expectEmit(true, true, true, true);
        // emit SwapTrade(address(tokenA), address(tokenB), bob, tokenAAmount, expectedTokenBAmount, avgPrice, avgPrice);
        maelstrom.swap(address(tokenA), address(tokenB), tokenAAmount, expectedTokenBAmount);
        uint256 bobTokenBAfter = tokenB.balanceOf(bob);
        assertEq(bobTokenBAfter - bobTokenBBefore, expectedTokenBAmount);
        vm.stopPrank();
    }

    function testSwapFailsWithInsufficientOutput() public {
        // Initialize both pools
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        tokenB.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 100 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        maelstrom.initializePool{value: 100 ether}(
            address(tokenB),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Bob tries to swap with too high minimum amount
        uint256 tokenAAmount = 1 * 10**17;
        uint256 tooHighMinimum = 1000 * 10**18; // Unrealistically high
        vm.startPrank(bob);
        tokenA.approve(address(maelstrom), tokenAAmount);
        vm.expectRevert("Insufficient output amount");
        maelstrom.swap(address(tokenA), address(tokenB), tokenAAmount, tooHighMinimum);
        vm.stopPrank();
    }

    function testTradeVolumeConstraints() public {
        // Initialize pool with small amounts
        uint256 smallTokenAmount = 10 * 10**18;
        uint256 smallEthAmount = 1 ether;
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), smallTokenAmount);
        maelstrom.initializePool{value: smallEthAmount}(
            address(tokenA),
            smallTokenAmount,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Try to buy more than 10% of tokens in pool
        uint256 largeEthAmount = 10 ether; // This would try to buy more than available
        vm.prank(bob);
        vm.expectRevert("Not more than 10% of tokens in pool can be used for swap");
        maelstrom.buy{value: largeEthAmount}(address(tokenA),10 * 10**18);
        // Try to sell more than 10% of ETH in pool
        uint256 largeTokenAmount = 10 * 10**18; // This would try to drain more than 10% of ETH
        vm.startPrank(bob);
        tokenA.approve(address(maelstrom), largeTokenAmount);
        vm.expectRevert("Not more than 10% of eth in pool can be used for swap");
        maelstrom.sell(address(tokenA), largeTokenAmount,1 ether);
        vm.stopPrank();
    }

    function testGetPoolAndUserPoolLists() public {
        // Initialize multiple pools
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        tokenB.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        maelstrom.initializePool{value: 10 ether}(
            address(tokenB),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Check total pools
        assertEq(maelstrom.getTotalPools(), 2);
        // Check pool list
        address[] memory pools = maelstrom.getPoolList(0, 1);
        assertEq(pools.length, 2);
        assertEq(pools[0], address(tokenA));
        assertEq(pools[1], address(tokenB));
        // Check user pools for alice
        assertEq(maelstrom.getUserTotalPools(alice), 2);
        address[] memory userPools = maelstrom.getUserPools(alice, 0, 1);
        assertEq(userPools.length, 2);
    }

    function testPoolUserBalances() public {
        // Initialize pool
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Check alice's pool balances
        (uint256 aliceEthBalance, uint256 aliceTokenBalance) = maelstrom.poolUserBalances(address(tokenA), alice);
        assertEq(aliceEthBalance, 10 ether);
        assertEq(aliceTokenBalance, INITIAL_TOKEN_AMOUNT);
        // Bob deposits and check his balances
        vm.startPrank(bob);
        uint256 ethAmount = 5 ether;
        uint256 expectedTokenAmount = ethAmount * maelstrom.tokenPerETHRatio(address(tokenA));
        tokenA.approve(address(maelstrom), expectedTokenAmount);
        maelstrom.deposit{value: ethAmount}(address(tokenA));
        (uint256 bobEthBalance, uint256 bobTokenBalance) = maelstrom.poolUserBalances(address(tokenA), bob);
        assertTrue(bobEthBalance > 0);
        assertTrue(bobTokenBalance > 0);
        vm.stopPrank();
    }

    function testMustSendEthToDeposit() public {
        // Initialize pool
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Try to deposit without sending ETH
        vm.prank(bob);
        vm.expectRevert("Must send ETH to deposit");
        maelstrom.deposit{value: 0}(address(tokenA));
    }

    function testWithdrawRequiresPositiveAmount() public {
        // Initialize pool
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert("Amount must be greater than zero");
        maelstrom.withdraw(address(tokenA), 0);
    }

    function testWithdrawRequiresSufficientLPTokens() public {
        // Initialize pool
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        vm.prank(bob);
        vm.expectRevert("Not enough LP tokens");
        maelstrom.withdraw(address(tokenA), 1000 * 10**18);
    }

    function testFuzzBuyTrade(uint256 ethAmount) public {
        // Bound the fuzz input to reasonable values
        ethAmount = bound(ethAmount, 0.01 ether, 1 ether);
        // Initialize pool
        vm.startPrank(alice);
        tokenA.approve(address(maelstrom), INITIAL_TOKEN_AMOUNT);
        maelstrom.initializePool{value: 10 ether}(
            address(tokenA),
            INITIAL_TOKEN_AMOUNT,
            INITIAL_BUY_PRICE,
            INITIAL_SELL_PRICE
        );
        vm.stopPrank();
        // Ensure bob has enough ETH
        vm.deal(bob, ethAmount);
        uint256 buyPrice = maelstrom.priceBuy(address(tokenA));
        uint256 expectedTokenAmount = (ethAmount * 1e18) / buyPrice;
        vm.startPrank(bob);
        uint256 bobTokensBefore = tokenA.balanceOf(bob);
        maelstrom.buy{value: ethAmount}(address(tokenA),expectedTokenAmount);
        uint256 bobTokensAfter = tokenA.balanceOf(bob);
        assertEq(bobTokensAfter - bobTokensBefore, expectedTokenAmount);
        vm.stopPrank();
    }
}
