//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {DeployLayerEdgeToken} from "@script/DeployLayerEdgeToken.s.sol";
import {DeployWETH9} from "@script/DeployWETH9.s.sol";
import {WETH9} from "@src/WETH9.sol";
import {LayerEdgeToken} from "@test/mock/LayerEdgeToken.sol";

struct NetworkConfig {
    address stakingToken;
    address owner;
}

contract HelperConfig is Script {
    NetworkConfig private activeNetworkConfig;
    NetworkConfig private activeNetworkConfigNative;

    constructor() {
        if (block.chainid == 84532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else if (block.chainid == 3456) {
            activeNetworkConfig = getEdgenTestnetConfig();
        } else {
            activeNetworkConfig = getAnvilConfig();
            activeNetworkConfigNative = getAnvilConfigNative();
        }
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    function getActiveNetworkConfigNative() public view returns (NetworkConfig memory) {
        return activeNetworkConfigNative;
    }

    function getBaseSepoliaConfig() private pure returns (NetworkConfig memory) {
        NetworkConfig memory baseSepoliaConfig = NetworkConfig({
            stakingToken: 0x9601aAA6889c7E930EAf1d0B92311B46285d10D6,
            owner: 0x8CB4783e150Fd71915Ea1D2277f264550e8784f4
        });
        return baseSepoliaConfig;
    }

    function getEdgenTestnetConfig() private pure returns (NetworkConfig memory) {
        NetworkConfig memory edgenTestnetConfig = NetworkConfig({
            stakingToken: 0x79F1A446046F4003a01577d9ad56a20F4Bcf960D,
            owner: 0xa62162A652dE844510a694AE1F666930B3224CCA
        });
        return edgenTestnetConfig;
    }

    function getAnvilConfig() private returns (NetworkConfig memory) {
        DeployLayerEdgeToken deployer = new DeployLayerEdgeToken();
        LayerEdgeToken layerEdgeToken = deployer.run();

        NetworkConfig memory anvilConfig =
            NetworkConfig({stakingToken: address(layerEdgeToken), owner: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266});
        return anvilConfig;
    }

    function getAnvilConfigNative() private returns (NetworkConfig memory) {
        DeployWETH9 deployer = new DeployWETH9();
        WETH9 weth = deployer.run();

        NetworkConfig memory anvilConfigNative =
            NetworkConfig({stakingToken: address(weth), owner: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266});

        return anvilConfigNative;
    }
}
