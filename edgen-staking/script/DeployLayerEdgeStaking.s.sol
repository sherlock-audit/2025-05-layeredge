//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {LayerEdgeStaking} from "@src/stake/LayerEdgeStaking.sol";
import {HelperConfig, NetworkConfig} from "@script/HelperConfig.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployLayerEdgeStaking is Script {
    function run() public returns (LayerEdgeStaking layerEdgeStaking, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        NetworkConfig memory networkConfig = helperConfig.getActiveNetworkConfig();

        vm.startBroadcast();
        LayerEdgeStaking layerEdgeStakingImpl = new LayerEdgeStaking();

        layerEdgeStaking = LayerEdgeStaking(
            payable(
                address(
                    new ERC1967Proxy(
                        address(layerEdgeStakingImpl),
                        abi.encodeWithSelector(
                            layerEdgeStakingImpl.initialize.selector, networkConfig.stakingToken, networkConfig.owner
                        )
                    )
                )
            )
        );
        vm.stopBroadcast();
    }
}

contract DeployLayerEdgeStakingNative is Script {
    function run() public returns (LayerEdgeStaking layerEdgeStaking, HelperConfig helperConfig) {
        helperConfig = new HelperConfig();
        NetworkConfig memory networkConfig = helperConfig.getActiveNetworkConfigNative();

        vm.startBroadcast();
        LayerEdgeStaking layerEdgeStakingImpl = new LayerEdgeStaking();

        layerEdgeStaking = LayerEdgeStaking(
            payable(
                address(
                    new ERC1967Proxy(
                        address(layerEdgeStakingImpl),
                        abi.encodeWithSelector(
                            layerEdgeStakingImpl.initialize.selector, networkConfig.stakingToken, networkConfig.owner
                        )
                    )
                )
            )
        );
        vm.stopBroadcast();
    }
}
