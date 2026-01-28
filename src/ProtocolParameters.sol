// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ProtocolParameters
 * @notice This contract defines the protocol fees and address in which that fees will be received.
 */
contract ProtocolParameters {
    address public treasury;
    address public manager;
    uint256 public fee;

    modifier onlyManager() {
        require(msg.sender == manager, "Caller is not the manager");
        _;
    }

    modifier lessThan5Percent(uint256 feeRate) {
        require(feeRate <= 500, "Fee rate must be between 0 and 500"); //0 to 5% , rate = 0.0001 * _fee;
        _;
    }

    modifier nonZeroAddress(address addr) {
        require(addr != address(0), "Address cannot be zero");
        _;
    }

    constructor(address _treasury, address _manager, uint256 _fee) nonZeroAddress(_treasury) nonZeroAddress(_manager) lessThan5Percent(_fee) {
        treasury = _treasury;
        manager = _manager;
        fee = _fee;
    }

    function updateFee(uint256 newFee) external onlyManager lessThan5Percent(newFee) {
        fee = newFee;
    }

    function updateTreasury(address newTreasury) external onlyManager nonZeroAddress(newTreasury) {
        treasury = newTreasury;
    }
}
