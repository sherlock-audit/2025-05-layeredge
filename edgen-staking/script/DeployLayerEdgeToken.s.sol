//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LayerEdgeToken} from "@test/mock/LayerEdgeToken.sol";

contract DeployLayerEdgeToken is Script {
    function run() public returns (LayerEdgeToken) {
        vm.startBroadcast();
        (string memory name, string memory symbol, uint256 totalSupply, address to) = getConstructorParams();
        LayerEdgeToken token = new LayerEdgeToken(name, symbol, totalSupply, to);
        vm.stopBroadcast();
        return token;
    }

    function getConstructorParams()
        public
        pure
        returns (string memory name, string memory symbol, uint256 totalSupply, address to)
    {
        name = "LayerEdge";
        symbol = "EDGEN";
        totalSupply = 1000000000 * 10 ** 18;
        to = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    }
}
