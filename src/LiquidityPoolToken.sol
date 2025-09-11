// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from 'node_modules/openzeppelin/contracts/token/ERC20/ERC20.sol';
import {Ownable} from 'node_modules/openzeppelin/contracts/access/Ownable.sol';


contract LiquidityPoolToken is ERC20,Ownable {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}