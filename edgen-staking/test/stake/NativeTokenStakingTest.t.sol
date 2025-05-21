//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {LayerEdgeStaking} from "@src/stake/LayerEdgeStaking.sol";
import {DeployLayerEdgeStakingNative} from "@script/DeployLayerEdgeStaking.s.sol";
import {NetworkConfig, HelperConfig} from "@script/HelperConfig.s.sol";
import {WETH9} from "@src/WETH9.sol";
import {IWETH} from "@src/interfaces/IWETH.sol";

contract NativeTokenStakingTest is Test {
    LayerEdgeStaking public layerEdgeStaking;
    WETH9 public weth;
    HelperConfig public helperConfig;
    DeployLayerEdgeStakingNative public deployer;
    address public stakingToken;

    uint256 public constant STAKE_AMOUNT = 3000 ether;
    uint256 public constant UNSTAKE_AMOUNT = 1500 ether;
    uint256 public constant REWARDS_AMOUNT = 1_000_000 ether;
    address public user = makeAddr("user");
    address public admin;

    function setUp() public {
        deployer = new DeployLayerEdgeStakingNative();
        (layerEdgeStaking, helperConfig) = deployer.run();

        NetworkConfig memory config = helperConfig.getActiveNetworkConfigNative();
        admin = config.owner;
        stakingToken = config.stakingToken;

        vm.startPrank(admin);
        vm.deal(admin, REWARDS_AMOUNT);
        IWETH(address(stakingToken)).deposit{value: REWARDS_AMOUNT}();
        IWETH(address(stakingToken)).approve(address(layerEdgeStaking), REWARDS_AMOUNT);
        layerEdgeStaking.depositRewards(REWARDS_AMOUNT);
        vm.stopPrank();
    }

    function test_stakeNative() public {
        vm.deal(user, STAKE_AMOUNT);
        vm.prank(user);
        layerEdgeStaking.stakeNative{value: STAKE_AMOUNT}();
    }

    function test_unstakeNative() public {
        vm.deal(user, STAKE_AMOUNT);
        vm.startPrank(user);
        layerEdgeStaking.stakeNative{value: STAKE_AMOUNT}();

        vm.warp(block.timestamp + layerEdgeStaking.UNSTAKE_WINDOW() + 1);
        layerEdgeStaking.unstakeNative(UNSTAKE_AMOUNT);
        assertEq(user.balance, UNSTAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_claimInterestNative() public {
        vm.deal(user, STAKE_AMOUNT);
        vm.startPrank(user);
        layerEdgeStaking.stakeNative{value: STAKE_AMOUNT}();

        vm.warp(block.timestamp + 30 days);
        (,,,, uint256 claimable) = layerEdgeStaking.getUserInfo(user);
        layerEdgeStaking.claimInterestNative();
        assertEq(user.balance, claimable);
        vm.stopPrank();
    }

    function test_receiveFunction() public {
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Try to send ETH directly to contract
        vm.expectRevert("Only staking token can send ETH");
        (bool success,) = address(layerEdgeStaking).call{value: 1 ether}("");
        // success is true because the EVM successfully executed the call
        // even though the contract reverted it
        assertEq(success, true);
        vm.stopPrank();
    }

    function test_fallbackFunction() public {
        vm.deal(user, 1 ether);
        vm.startPrank(user);

        // Try to call fallback function
        vm.expectRevert("Fallback not allowed");
        (bool success,) = address(layerEdgeStaking).call{value: 1 ether}("0x");
        // success is true because the EVM successfully executed the call
        // even though the contract reverted it
        assertEq(success, true);

        vm.stopPrank();
    }
}
