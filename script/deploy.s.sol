// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import "forge-std/Script.sol";
import "../src/Maelstrom.sol";
import "../src/MockERC20.sol";

contract DeployScript is Script {
  function run() external {
    uint256 deployerPrivateKey = uint256(vm.envBytes32("PRIVATE_KEY"));
    vm.startBroadcast(deployerPrivateKey);
    ProtocolParameters pc = new ProtocolParameters(
      0x762B75ec9e050555679191B764A736c823a25fEd, //treasury
      0x762B75ec9e050555679191B764A736c823a25fEd, //manager
      500 //fee 1%
    );
    Maelstrom mc = new Maelstrom(address(pc));
    // MockERC20 token1 = new MockERC20("Nebula", "NEB");
    // MockERC20 token2 = new MockERC20("Meta", "MET");
    vm.stopBroadcast();
  }
}
