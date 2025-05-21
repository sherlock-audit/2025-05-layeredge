//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {WETH9} from "@src/WETH9.sol";

contract DeployWETH9 is Script {
    function run() public returns (WETH9 weth) {
        vm.startBroadcast();
        weth = new WETH9();
        vm.stopBroadcast();
    }
}
