// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {EduLedgerNFT} from "../src/EduLedgerNFT.sol";

contract Deploy is Script {
    function run() external returns (EduLedgerNFT deployed) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("Deploying EduLedgerNFT");
        console2.log("  Deployer  :", deployer);
        console2.log("  Chain ID  :", block.chainid);

        vm.startBroadcast(deployerKey);

        deployed = new EduLedgerNFT("EduLedger", "EDU");

        vm.stopBroadcast();

        console2.log("  Contract  :", address(deployed));
        console2.log("  Owner     :", deployed.owner());
    }
}
