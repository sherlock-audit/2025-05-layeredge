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
        weth = WETH9(payable(address(stakingToken)));

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

        layerEdgeStaking.unstake(UNSTAKE_AMOUNT);
        vm.warp(block.timestamp + layerEdgeStaking.UNSTAKE_WINDOW() + 1);
        layerEdgeStaking.completeUnstakeNative(0);
        assertEq(user.balance, UNSTAKE_AMOUNT);
        vm.stopPrank();
    }

    function test_claimInterestNative() public {
        vm.deal(user, STAKE_AMOUNT);
        vm.startPrank(user);
        layerEdgeStaking.stakeNative{value: STAKE_AMOUNT}();

        vm.warp(block.timestamp + 30 days);
        (,,, uint256 claimable) = layerEdgeStaking.getUserInfo(user);
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

    function test_LayerEdgeStaking_CompleteUnstake_Native() public {
        // Initial setup - user stakes native ETH
        vm.deal(user, STAKE_AMOUNT);
        uint256 initialAliceETH = address(user).balance;
        uint256 initialContractBalance = weth.balanceOf(address(layerEdgeStaking));

        vm.prank(user);
        layerEdgeStaking.stakeNative{value: STAKE_AMOUNT}();

        // Check balances after staking
        assertEq(
            address(user).balance, initialAliceETH - STAKE_AMOUNT, "user ETH balance should decrease after staking"
        );
        assertEq(
            weth.balanceOf(address(layerEdgeStaking)),
            initialContractBalance + STAKE_AMOUNT,
            "Contract WETH balance should increase after staking"
        );

        // Queue unstake
        vm.prank(user);
        layerEdgeStaking.unstake(STAKE_AMOUNT);

        // Check balances after unstake request (tokens still in contract)
        assertEq(
            address(user).balance,
            initialAliceETH - STAKE_AMOUNT,
            "user ETH balance should remain the same after unstake request"
        );
        assertEq(
            weth.balanceOf(address(layerEdgeStaking)),
            initialContractBalance + STAKE_AMOUNT,
            "Contract WETH balance should remain the same after unstake request"
        );

        // Verify unstake request is created
        (uint256 amount, uint256 timestamp, bool completed) = layerEdgeStaking.unstakeRequests(user, 0);
        assertEq(amount, STAKE_AMOUNT, "Unstake request amount should match");
        assertFalse(completed, "Unstake request should not be completed yet");

        // Advance time past unstaking window
        vm.warp(timestamp + 7 days + 1);

        // Complete unstake as native ETH
        vm.prank(user);
        layerEdgeStaking.completeUnstakeNative(0);

        // Check balances after completing unstake
        assertEq(address(user).balance, initialAliceETH, "user ETH balance should be restored after completing unstake");
        assertEq(
            weth.balanceOf(address(layerEdgeStaking)),
            initialContractBalance,
            "Contract WETH balance should be restored after completing unstake"
        );

        // Verify unstake request is completed
        (amount, timestamp, completed) = layerEdgeStaking.unstakeRequests(user, 0);
        assertTrue(completed, "Unstake request should be marked as completed");
    }
}
