// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {LayerEdgeStaking} from "@src/stake/LayerEdgeStaking.sol";
import {LayerEdgeToken} from "@test/mock/LayerEdgeToken.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {DeployLayerEdgeStaking} from "@script/DeployLayerEdgeStaking.s.sol";
import {NetworkConfig, HelperConfig} from "@script/HelperConfig.s.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

contract LayerEdgeStakingTest is Test {
    LayerEdgeStaking public staking;
    LayerEdgeToken public token;
    HelperConfig public helperConfig;
    DeployLayerEdgeStaking public deployer;

    // Test users
    address public admin;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public david = makeAddr("david");
    address public eve = makeAddr("eve");
    address public frank = makeAddr("frank");
    address public grace = makeAddr("grace");
    address public harry = makeAddr("harry");
    address public ian = makeAddr("ian");
    address public judy = makeAddr("judy");

    // Constants for testing
    uint256 public constant MIN_STAKE = 3000 * 1e18; // Minimum stake amount
    uint256 public constant LARGE_STAKE = 10000 * 1e18; // Larger stake amount for testing
    uint256 public constant PRECISION = 1e18;
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 1e18; // 1B tokens

    function setUp() public {
        deployer = new DeployLayerEdgeStaking();
        (staking, helperConfig) = deployer.run();

        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        token = LayerEdgeToken(config.stakingToken);
        admin = config.owner;
        vm.startPrank(admin);

        // Distribute tokens to users
        uint256 userAmount = 100_000 * 1e18; // 100k tokens per test user
        token.transfer(alice, userAmount);
        token.transfer(bob, userAmount);
        token.transfer(charlie, userAmount);
        token.transfer(david, userAmount);
        token.transfer(eve, userAmount);
        token.transfer(frank, userAmount);
        token.transfer(grace, userAmount);
        token.transfer(harry, userAmount);
        token.transfer(ian, userAmount);
        token.transfer(judy, userAmount);

        // Fund staking contract with reward tokens
        uint256 rewardAmount = 100_000 * 1e18; // 100k tokens for rewards
        token.approve(address(staking), rewardAmount);
        staking.depositRewards(rewardAmount);
        staking.setCompoundingStatus(true);
        staking.setMinStakeAmount(MIN_STAKE);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                           TIER SYSTEM TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_TierSystem_Initial() public view {
        // Check initial APY rates
        assertEq(staking.tier1APY(), 50 * PRECISION); // 50%
        assertEq(staking.tier2APY(), 35 * PRECISION); // 35%
        assertEq(staking.tier3APY(), 20 * PRECISION); // 20%

        // Check tier counts with no stakers
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 0);
        assertEq(tier2Count, 0);
        assertEq(tier3Count, 0);
    }

    function test_LayerEdgeStaking_TierSystem_OneStaker() public {
        // Alice stakes minimum amount
        vm.startPrank(alice);

        // Approve tokens
        token.approve(address(staking), MIN_STAKE);

        vm.expectEmit(true, false, false, false);
        emit LayerEdgeStaking.Staked(alice, MIN_STAKE, LayerEdgeStaking.Tier.Tier1); // First staker should be tier 1
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Check tier counts with one staker
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1);
        assertEq(tier2Count, 0);
        assertEq(tier3Count, 0);

        // Check Alice's tier and APY
        (, LayerEdgeStaking.Tier tier, uint256 apy,,) = staking.getUserInfo(alice);
        assertEq(uint256(tier), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(apy, 50 * PRECISION);

        // Check token balances
        assertEq(token.balanceOf(address(staking)), 100_000 * 1e18 + MIN_STAKE); // Rewards + stake
        assertEq(token.balanceOf(alice), 100_000 * 1e18 - MIN_STAKE);
    }

    function test_LayerEdgeStaking_TierSystem_MultipleStakers() public {
        // Set up initial token balances for tracking
        uint256[] memory initialBalances = new uint256[](10);
        address[10] memory stakers = [alice, bob, charlie, david, eve, frank, grace, harry, ian, judy];

        for (uint256 i = 0; i < stakers.length; i++) {
            initialBalances[i] = token.balanceOf(stakers[i]);
        }

        // Set up 10 stakers
        setupMultipleStakers(10);

        // Check token balances after setup
        for (uint256 i = 0; i < stakers.length; i++) {
            assertEq(token.balanceOf(stakers[i]), initialBalances[i] - MIN_STAKE);
        }

        // Check tier counts
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 2); // 20% of 10 = 2
        assertEq(tier2Count, 3); // 30% of 10 = 3
        assertEq(tier3Count, 5); // Remaining 5

        // Check specific users' tiers
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(david)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(frank)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Check token balance of staking contract
        uint256 expectedContractBalance = 100_000 * 1e18 + (10 * MIN_STAKE); // Initial rewards + 10 stakers
        assertEq(token.balanceOf(address(staking)), expectedContractBalance);
    }

    function test_LayerEdgeStaking_TierSystem_UnstakingDowngrade() public {
        // Setup multiple stakers
        setupMultipleStakers(5);

        // Check Alice's initial tier (should be tier 1)
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        (,,,,,,, bool outOfTree,,) = staking.users(alice);
        assertFalse(outOfTree, "User should be in the tree");

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Alice unstakes partial amount
        vm.prank(alice);
        staking.unstake(MIN_STAKE / 2);

        // Check Alice's tier after unstaking (should be permanently tier 3)
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier3));
        (,,,,,,, bool outOfTreeAfterUnstake,,) = staking.users(alice);
        assertTrue(outOfTreeAfterUnstake, "User should be out of tree");

        // Alice tries to stake more to get back to tier 1
        vm.startPrank(alice);
        token.approve(address(staking), LARGE_STAKE);
        staking.stake(LARGE_STAKE);
        vm.stopPrank();

        // Check Alice's tier after staking (should be tier 3)
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier3));
        (,,,,,,, bool outOfTreeAfterStake,,) = staking.users(alice);
        assertTrue(outOfTreeAfterStake, "User should be out of tree");
    }

    /*//////////////////////////////////////////////////////////////
                      INTEREST CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_Interest_BasicAccrual() public {
        // Alice stakes
        dealToken(alice, 3000 ether);
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Advance time by 30 days
        vm.warp(block.timestamp + 365 days);

        // Check accrued interest
        (,,,, uint256 pendingRewards) = staking.getUserInfo(alice);

        // Calculate expected rewards for 30 days at tier 1 (50%)
        uint256 expectedRewards = (MIN_STAKE * 50 * PRECISION * 365 days) / (365 days * PRECISION) / 100;
        // Allow for minimal rounding errors
        assertApproxEqAbs(pendingRewards, expectedRewards, 2);
    }

    function test_LayerEdgeStaking_Interest_TierBasedRewards() public {
        // Setup 10 stakers to create tier distribution
        setupMultipleStakers(10); //1,2 tier1, 2,3,5 tier2, 6,7,8,9,10 tier3

        // Advance time by 30 days
        vm.warp(block.timestamp + 30 days);

        // Get rewards for different tiers
        (,,,, uint256 tier1Rewards) = staking.getUserInfo(alice); // Tier 1 - 50%
        (,,,, uint256 tier2Rewards) = staking.getUserInfo(charlie); // Tier 2 - 35%
        (,,,, uint256 tier3Rewards) = staking.getUserInfo(frank); // Tier 3 - 20%

        // Verify reward hierarchy
        assertTrue(tier1Rewards > tier2Rewards, "Tier 1 should earn more than Tier 2");
        assertTrue(tier2Rewards > tier3Rewards, "Tier 2 should earn more than Tier 3");

        // Verify approximate ratios
        uint256 ratio1to2 = (tier1Rewards * 100) / tier2Rewards;
        uint256 ratio2to3 = (tier2Rewards * 100) / tier3Rewards;

        // 50/35 ≈ 1.43
        assertApproxEqAbs(ratio1to2, 143, 5);

        // 35/20 = 1.75
        assertApproxEqAbs(ratio2to3, 175, 5);
    }

    function test_LayerEdgeStaking_Interest_APYUpdatesAndZeroRate() public {
        // Alice stakes
        dealToken(alice, 100_000 * 1e18);
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Advance time by 30 days
        vm.warp(block.timestamp + 30 days);

        // Get rewards accrued at 50% APY
        (,,,, uint256 rewardsBefore) = staking.getUserInfo(alice);

        // Admin updates APY to 0 for all tiers
        vm.prank(admin);
        staking.updateAllAPYs(0, 0, 0);

        // Advance time by another 30 days
        vm.warp(block.timestamp + 30 days);

        // Get rewards after update
        (,,,, uint256 rewardsAfter) = staking.getUserInfo(alice);
        // Rewards should be unchanged since APY is now 0
        assertEq(rewardsAfter, rewardsBefore, "No new rewards should accrue with 0% APY");

        // Admin updates APY to new values
        vm.prank(admin);
        staking.updateAllAPYs(25 * PRECISION, 15 * PRECISION, 10 * PRECISION);

        // Advance time by another 30 days
        vm.warp(block.timestamp + 30 days);
        // Get rewards after second update
        (,,,, uint256 rewardsFinal) = staking.getUserInfo(alice);

        // New rewards should be accrued at 25% rate
        assertTrue(rewardsFinal > rewardsAfter, "Rewards should accrue after APY is increased");

        // Calculate expected new rewards
        uint256 expectedNewRewards = (MIN_STAKE * 25 * PRECISION * 30 days) / (365 days * PRECISION) / 100;
        uint256 expectedTotal = rewardsAfter + expectedNewRewards;

        // Allow for minimal rounding errors
        assertApproxEqAbs(rewardsFinal, expectedTotal, 2);
    }

    function test_LayerEdgeStaking_Interest_ClaimingRewards() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Advance time by 30 days
        vm.warp(block.timestamp + 30 days);

        // Get pending rewards
        (,,,, uint256 pendingRewards) = staking.getUserInfo(alice);
        assertTrue(pendingRewards > 0, "Should have pending rewards");

        // Record balances before claiming
        uint256 contractBalanceBefore = token.balanceOf(address(staking));
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        uint256 reserveBefore = staking.rewardsReserve();

        // Alice claims rewards
        vm.startPrank(alice);
        vm.expectEmit(true, false, false, false);
        emit LayerEdgeStaking.RewardClaimed(alice, pendingRewards);
        staking.claimInterest();
        vm.stopPrank();

        // Check rewards are reset
        (,,,, uint256 pendingAfterClaim) = staking.getUserInfo(alice);
        assertEq(pendingAfterClaim, 0, "Pending rewards should be reset after claim");

        // Check token balances are updated
        assertEq(
            token.balanceOf(address(staking)),
            contractBalanceBefore - pendingRewards,
            "Contract balance should decrease"
        );
        assertEq(token.balanceOf(alice), aliceBalanceBefore + pendingRewards, "User balance should increase");

        // Check rewards reserve is updated
        assertEq(staking.rewardsReserve(), reserveBefore - pendingRewards, "Rewards reserve should decrease");
    }

    function test_LayerEdgeStaking_Interest_CompoundingRewards() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Advance time by 30 days
        vm.warp(block.timestamp + 30 days);

        // Get pending rewards and initial balance
        (uint256 initialBalance,,,, uint256 pendingRewards) = staking.getUserInfo(alice);
        assertTrue(pendingRewards > 0, "Should have pending rewards");

        // Record rewards reserve before compounding
        uint256 reserveBefore = staking.rewardsReserve();

        // Alice compounds rewards
        vm.startPrank(alice);
        vm.expectEmit(true, false, false, false);
        emit LayerEdgeStaking.RewardClaimed(alice, pendingRewards);
        vm.expectEmit(true, false, false, false);
        emit LayerEdgeStaking.Staked(alice, pendingRewards, LayerEdgeStaking.Tier.Tier1);
        staking.compoundInterest();
        vm.stopPrank();

        // Check rewards are reset and balance increased
        (uint256 newBalance,,,, uint256 pendingAfterCompound) = staking.getUserInfo(alice);
        assertEq(pendingAfterCompound, 0, "Pending rewards should be reset after compounding");
        assertEq(staking.calculateUnclaimedInterest(alice), 0, "Unclaimed interest should be equal to 0");
        assertEq(newBalance, initialBalance + pendingRewards, "Balance should increase by reward amount");

        // Check rewards reserve is updated
        assertEq(staking.rewardsReserve(), reserveBefore - pendingRewards, "Rewards reserve should decrease");

        // Token balance of contract should remain unchanged
        // (rewards are kept in contract, just moved from reserve to staked)

        // Advance time by another 30 days
        vm.warp(block.timestamp + 30 days);

        // New rewards should be calculated based on higher balance
        (,,,, uint256 newPendingRewards) = staking.getUserInfo(alice);

        // Calculate expected rewards for second period with higher balance
        uint256 expectedNewRewards = (newBalance * 50 * PRECISION * 30 days) / (365 days * PRECISION) / 100;

        // Allow for minimal rounding errors
        assertApproxEqAbs(newPendingRewards, expectedNewRewards, 2);
    }

    function test_LayerEdgeStaking_Interest_CompoundingAfterUnstake() public {
        // Setup and get Alice to Tier 1
        setupMultipleStakers(5);

        // Advance time by 30 days to accrue rewards
        vm.warp(block.timestamp + 30 days);

        //Assert interest accured for alice
        (,,,, uint256 pendingRewardsBeforeUnstake) = staking.getUserInfo(alice);
        assertEq(pendingRewardsBeforeUnstake, (MIN_STAKE * 50 * PRECISION * 30 days) / (365 days * PRECISION) / 100);

        vm.prank(alice);
        staking.unstake(MIN_STAKE / 2);

        //Assert out or tree and tier 3
        (,,,,,,, bool outOfTreeAfterUnstake,,) = staking.users(alice);
        assertTrue(outOfTreeAfterUnstake);
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Advance time to accrue more rewards (now at tier 3)
        vm.warp(block.timestamp + 30 days);

        //Assert interest accured for alice
        (,,,, uint256 pendingRewardsAfterUnstake) = staking.getUserInfo(alice);
        assertEq(
            pendingRewardsAfterUnstake,
            pendingRewardsBeforeUnstake + (MIN_STAKE / 2 * 20 * PRECISION * 30 days) / (365 days * PRECISION) / 100
        );

        vm.prank(alice);
        staking.compoundInterest();

        //Assert interest accured for alice
        (uint256 newBalance,,,, uint256 pendingRewardsAfterCompound) = staking.getUserInfo(alice);
        assertEq(pendingRewardsAfterCompound, 0);
        assertEq(newBalance, MIN_STAKE / 2 + pendingRewardsAfterUnstake);

        vm.warp(block.timestamp + 30 days);

        //Assert interest accured for alice
        (,,,, uint256 pendingRewardsAfterCompound2) = staking.getUserInfo(alice);
        assertEq(
            pendingRewardsAfterCompound2,
            (MIN_STAKE / 2 + pendingRewardsAfterUnstake) * 20 * PRECISION * 30 days / (365 days * PRECISION) / 100
        );

        uint256 balanceBeforeClaim = token.balanceOf(alice);

        // Alice should still be able to claim rewards normally
        vm.prank(alice);
        staking.claimInterest();

        //Assert interest accured for alice
        (,,,, uint256 pendingRewardsAfterClaim) = staking.getUserInfo(alice);
        assertEq(pendingRewardsAfterClaim, 0);
        assertEq(token.balanceOf(alice), balanceBeforeClaim + pendingRewardsAfterCompound2);
    }

    /*//////////////////////////////////////////////////////////////
                           UNSTAKING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_Unstake_Basic() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Record balances before unstaking
        uint256 contractBalanceBefore = token.balanceOf(address(staking));
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Check initial stake balance
        (uint256 initialBalance,,,,) = staking.getUserInfo(alice);
        assertEq(initialBalance, MIN_STAKE);

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Alice unstakes half
        vm.startPrank(alice);
        vm.expectEmit(true, false, false, false);
        emit LayerEdgeStaking.TierChanged(alice, LayerEdgeStaking.Tier.Tier3);
        vm.expectEmit(true, false, false, false);
        emit LayerEdgeStaking.Unstaked(alice, MIN_STAKE / 2);
        staking.unstake(MIN_STAKE / 2);
        vm.stopPrank();

        // Check balance after unstake
        (uint256 finalBalance,,,,) = staking.getUserInfo(alice);
        assertEq(finalBalance, MIN_STAKE / 2);

        // Total staked should decrease
        assertEq(staking.totalStaked(), MIN_STAKE / 2);

        // Token balances should be updated
        assertEq(token.balanceOf(address(staking)), contractBalanceBefore - MIN_STAKE / 2);
        assertEq(token.balanceOf(alice), aliceBalanceBefore + MIN_STAKE / 2);
    }

    function test_LayerEdgeStaking_Unstake_CompleteUnstake() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Record initial balances
        uint256 contractBalanceBefore = token.balanceOf(address(staking));
        uint256 aliceBalanceBefore = token.balanceOf(alice);

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Alice unstakes everything
        vm.startPrank(alice);
        staking.unstake(MIN_STAKE);
        vm.stopPrank();

        // Check balance after unstake (should be 0)
        (uint256 finalBalance,,,,) = staking.getUserInfo(alice);
        assertEq(finalBalance, 0);

        // Get user info directly from contract
        (uint256 balance,,,,,,, bool outOfTree, bool isActive,) = staking.users(alice);

        // Check user state
        assertEq(balance, 0);
        assertTrue(outOfTree);
        assertTrue(isActive); //User already participated and unstaked so this wallet will remain in Tier 3

        // Total staked should be 0
        assertEq(staking.totalStaked(), 0);

        // Active staker count should decrease
        assertEq(staking.stakerCountInTree(), 0);
        assertEq(staking.stakerCountOutOfTree(), 1);

        // Check token balances
        assertEq(token.balanceOf(address(staking)), contractBalanceBefore - MIN_STAKE);
        assertEq(token.balanceOf(alice), aliceBalanceBefore + MIN_STAKE);

        //Alice stakes again should be out of tree and in tier 3
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        (,,,,,,, bool outOfTreeAfterStake,,) = staking.users(alice);
        assertTrue(outOfTreeAfterStake, "User should be out of tree");
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier3));
    }

    function test_LayerEdgeStaking_Unstake_BeforeUnstakingWindow() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Try to unstake before unstaking window
        vm.warp(block.timestamp + 3 days); // Only 3 days passed (less than 7)
        vm.startPrank(alice);
        vm.expectRevert("Unstaking window not reached");
        staking.unstake(MIN_STAKE / 2);
        vm.stopPrank();
    }

    function test_LayerEdgeStaking_Unstake_InterestAccrualBeforeAndAfter() public {
        // Alice stakes
        dealToken(alice, MIN_STAKE);
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Advance time by 30 days to accrue interest at Tier 1 (50%)
        vm.warp(block.timestamp + 30 days);

        // Alice unstakes half
        vm.prank(alice);
        staking.unstake(MIN_STAKE / 2);

        // Check tier after unstaking (should be tier 3)
        (, LayerEdgeStaking.Tier tier, uint256 apy,,) = staking.getUserInfo(alice);
        assertEq(uint256(tier), uint256(LayerEdgeStaking.Tier.Tier3));
        assertEq(apy, 20 * PRECISION);

        // Record rewards right after unstaking
        (,,,, uint256 rewardsAfterUnstake) = staking.getUserInfo(alice);

        // Advance time for another 30 days to accrue interest at Tier 3 (20%)
        vm.warp(block.timestamp + 30 days);

        // Get final rewards
        (,,,, uint256 finalRewards) = staking.getUserInfo(alice);

        // Calculate expected tier 3 rewards for remaining balance
        uint256 expectedNewRewards = ((MIN_STAKE / 2) * 20 * PRECISION * 30 days) / (365 days * PRECISION) / 100;
        uint256 expectedTotalRewards = rewardsAfterUnstake + expectedNewRewards;

        // Allow for minimal rounding errors
        assertApproxEqAbs(finalRewards, expectedTotalRewards, 2);
    }

    function test_LayerEdgeStaking_Unstake_TierShifting() public {
        // Setup 5 stakers
        setupMultipleStakers(5);

        // Initial tiers should be:
        // - alice: Tier 1 (20%)
        // - bob: Tier 2 (30%)
        // - charlie, david, eve: Tier 3
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3));
        assertEq(uint256(staking.getCurrentTier(david)), uint256(LayerEdgeStaking.Tier.Tier3));
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Bob unstakes (should downgrade to tier 3 permanently)
        vm.prank(bob);
        staking.unstake(MIN_STAKE / 2);
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Active staker count should decrease
        assertEq(staking.stakerCountInTree(), 4);

        // Tiers should adjust:
        // - alice: still Tier 1
        // - charlie, david: Tier 2
        // - eve: Tier 3
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(david)), uint256(LayerEdgeStaking.Tier.Tier3));
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Bob unstakes completely
        vm.prank(bob);
        staking.unstake(MIN_STAKE / 2);

        // Active staker count should decrease
        assertEq(staking.stakerCountInTree(), 4);

        // Get tier counts
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1); // 20% of 4 = 0.8 rounds to 1
        assertEq(tier2Count, 1); // 30% of 4 = 1.2 rounds to 1
        assertEq(tier3Count, 2); // remaining 2
    }

    function test_LayerEdgeStaking_Unstake_MultipleInterestRates() public {
        // Alice stakes
        dealToken(alice, MIN_STAKE);
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Advance time by 30 days at 50% APY
        vm.warp(block.timestamp + 30 days);

        // Admin changes APY rates
        vm.prank(admin);
        staking.updateAllAPYs(40 * PRECISION, 30 * PRECISION, 15 * PRECISION);

        // Advance time for another 30 days at new rates
        vm.warp(block.timestamp + 30 days);

        // Alice unstakes after unstaking window
        vm.warp(block.timestamp + 7 days);
        vm.prank(alice);
        staking.unstake(MIN_STAKE / 2);

        // At this point Alice should have accrued interest at:
        // - 30 days at Tier 1 (50%)
        // - 30 days at Tier 1 (40%)
        // Now she should be downgraded to Tier 3 (15%)

        // Record rewards after unstaking
        (,,,, uint256 rewardsAfterUnstake) = staking.getUserInfo(alice);

        // Admin changes APY rates again
        vm.prank(admin);
        staking.updateAllAPYs(30 * PRECISION, 20 * PRECISION, 10 * PRECISION);

        // Advance time for another 30 days at newer rates
        vm.warp(block.timestamp + 30 days);

        // Alice now has accrued interest at:
        // - 30 days at Tier 1 (50%)
        // - 30 days at Tier 1 (40%)
        // - 30 days at Tier 3 (10%) - current rate for Tier 3

        // Get final rewards
        (,,,, uint256 finalRewards) = staking.getUserInfo(alice);

        // Calculate expected Tier 3 rewards for the final period
        uint256 expectedNewRewards = ((MIN_STAKE / 2) * 10 * PRECISION * 30 days) / (365 days * PRECISION) / 100;
        uint256 expectedTotalRewards = rewardsAfterUnstake + expectedNewRewards;

        // Allow for minimal rounding errors
        assertApproxEqAbs(finalRewards, expectedTotalRewards, 2);
    }

    /*//////////////////////////////////////////////////////////////
                        REWARDS MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_DepositRewards() public {
        // Admin deposits additional rewards
        uint256 depositAmount = 50_000 * 1e18;

        uint256 initialReserve = staking.rewardsReserve();
        uint256 initialContractBalance = token.balanceOf(address(staking));

        vm.startPrank(admin);
        token.approve(address(staking), depositAmount);

        vm.expectEmit(true, false, false, false);
        emit LayerEdgeStaking.RewardsDeposited(admin, depositAmount);
        staking.depositRewards(depositAmount);
        vm.stopPrank();

        // Check reserve and balances
        assertEq(staking.rewardsReserve(), initialReserve + depositAmount, "Rewards reserve should increase");
        assertEq(
            token.balanceOf(address(staking)),
            initialContractBalance + depositAmount,
            "Contract balance should increase"
        );
    }

    function test_LayerEdgeStaking_AnyoneCanDepositRewards() public {
        // Even non-admin users can deposit rewards
        uint256 depositAmount = 5_000 * 1e18;

        uint256 initialReserve = staking.rewardsReserve();
        uint256 initialContractBalance = token.balanceOf(address(staking));
        uint256 initialAliceBalance = token.balanceOf(alice);

        vm.startPrank(alice);
        token.approve(address(staking), depositAmount);

        vm.expectEmit(true, false, false, false);
        emit LayerEdgeStaking.RewardsDeposited(alice, depositAmount);
        staking.depositRewards(depositAmount);
        vm.stopPrank();

        // Check reserve and balances
        assertEq(staking.rewardsReserve(), initialReserve + depositAmount, "Rewards reserve should increase");
        assertEq(
            token.balanceOf(address(staking)),
            initialContractBalance + depositAmount,
            "Contract balance should increase"
        );
        assertEq(token.balanceOf(alice), initialAliceBalance - depositAmount, "Alice's balance should decrease");
    }

    function test_LayerEdgeStaking_WithdrawRewards() public {
        // Only admin can withdraw rewards
        uint256 withdrawAmount = 10_000 * 1e18;

        uint256 initialReserve = staking.rewardsReserve();
        uint256 initialContractBalance = token.balanceOf(address(staking));
        uint256 initialAdminBalance = token.balanceOf(admin);

        // Non-admin should not be able to withdraw
        vm.startPrank(alice);
        vm.expectRevert();
        staking.withdrawRewards(withdrawAmount);
        vm.stopPrank();

        // Admin can withdraw
        vm.startPrank(admin);
        staking.withdrawRewards(withdrawAmount);
        vm.stopPrank();

        // Check reserve and balances
        assertEq(staking.rewardsReserve(), initialReserve - withdrawAmount, "Rewards reserve should decrease");
        assertEq(
            token.balanceOf(address(staking)),
            initialContractBalance - withdrawAmount,
            "Contract balance should decrease"
        );
        assertEq(token.balanceOf(admin), initialAdminBalance + withdrawAmount, "Admin balance should increase");
    }

    function test_LayerEdgeStaking_InsufficientRewardsForClaiming() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 30 days);

        // Get pending rewards
        (,,,, uint256 pendingRewards) = staking.getUserInfo(alice);
        assertTrue(pendingRewards > 0, "Should have pending rewards");

        // Admin withdraws all rewards, leaving insufficient balance
        vm.startPrank(admin);
        staking.withdrawRewards(staking.rewardsReserve());
        vm.stopPrank();

        // Alice tries to claim but should fail
        vm.startPrank(alice);
        vm.expectRevert("Insufficient rewards in contract");
        staking.claimInterest();
        vm.stopPrank();

        // Alice tries to compound but should fail
        vm.startPrank(alice);
        vm.expectRevert("Insufficient rewards in contract");
        staking.compoundInterest();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_StakingWithoutApproval() public {
        // Alice tries to stake without approving tokens first
        vm.startPrank(alice);
        vm.expectRevert(); // Should revert with transfer failure
        staking.stake(MIN_STAKE);
        vm.stopPrank();
    }

    function test_LayerEdgeStaking_StakingWithInsufficientBalance() public {
        // Bob tries to stake more than his balance
        uint256 excessiveAmount = 200_000 * 1e18; // 200k tokens (more than the 100k distributed)

        vm.startPrank(bob);
        token.approve(address(staking), excessiveAmount);
        vm.expectRevert(); // Should revert with transfer failure
        staking.stake(excessiveAmount);
        vm.stopPrank();
    }

    function test_LayerEdgeStaking_TokenBalanceTracking() public {
        // Test that token balances are correctly tracked during multiple operations

        // Initial balances
        uint256 initialContractBalance = token.balanceOf(address(staking));
        uint256 initialAliceBalance = token.balanceOf(alice);

        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Check balances after staking
        assertEq(token.balanceOf(address(staking)), initialContractBalance + MIN_STAKE);
        assertEq(token.balanceOf(alice), initialAliceBalance - MIN_STAKE);

        // Advance time to accrue rewards
        vm.warp(block.timestamp + 30 days);

        // Get pending rewards
        (,,,, uint256 pendingRewards) = staking.getUserInfo(alice);
        assertTrue(pendingRewards > 0);

        // Alice claims rewards
        vm.startPrank(alice);
        staking.claimInterest();
        vm.stopPrank();

        // Check balances after claiming
        assertEq(token.balanceOf(address(staking)), initialContractBalance + MIN_STAKE - pendingRewards);
        assertEq(token.balanceOf(alice), initialAliceBalance - MIN_STAKE + pendingRewards);

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days);

        // Alice unstakes all
        vm.startPrank(alice);
        staking.unstake(MIN_STAKE);
        vm.stopPrank();

        // Check final balances - should be back to initial minus the claimed rewards
        assertEq(token.balanceOf(address(staking)), initialContractBalance - pendingRewards);
        assertEq(token.balanceOf(alice), initialAliceBalance + pendingRewards);
    }

    function test_LayerEdgeStaking_RewardPoolExhaustion() public {
        // Test behavior when reward pool is exhausted

        // Stake with multiple users to accrue significant rewards
        setupMultipleStakers(5);

        // Advance time significantly to accrue large rewards
        vm.warp(block.timestamp + 365 days);

        // Admin withdraws most of the reward pool, leaving minimal amount
        vm.startPrank(admin);
        uint256 rewardsToLeave = 1 * 1e18; // Leave just 1 token
        uint256 currentRewards = staking.rewardsReserve();
        uint256 withdrawAmount = currentRewards - rewardsToLeave;
        staking.withdrawRewards(withdrawAmount);
        vm.stopPrank();

        // Charlie's rewards should exceed the available pool
        (,,,, uint256 charlieRewards) = staking.getUserInfo(charlie);
        assertTrue(charlieRewards > rewardsToLeave, "Charlie should have more rewards than available");

        // Charlie tries to claim but should only get partial rewards
        vm.startPrank(charlie);
        vm.expectRevert("Insufficient rewards in contract");
        staking.claimInterest();
        vm.stopPrank();

        // Admin replenishes the reward pool
        vm.startPrank(admin);
        token.approve(address(staking), charlieRewards);
        staking.depositRewards(charlieRewards);
        vm.stopPrank();

        // Now Charlie can claim
        vm.startPrank(charlie);
        staking.claimInterest();
        vm.stopPrank();

        // Rewards should be claimed successfully
        (,,,, uint256 charlieRemainingRewards) = staking.getUserInfo(charlie);
        assertEq(charlieRemainingRewards, 0, "All rewards should be claimed");
    }

    /*//////////////////////////////////////////////////////////////
                      BALANCE TRACKING TESTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Comprehensive test for tracking balances during staking
     */
    function test_LayerEdgeStaking_BalanceTracking_Stake() public {
        // Record initial balances
        uint256 userInitialBalance = token.balanceOf(alice);
        uint256 contractInitialBalance = token.balanceOf(address(staking));
        uint256 stakeAmount = MIN_STAKE;

        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // Check balances after staking
        uint256 userFinalBalance = token.balanceOf(alice);
        uint256 contractFinalBalance = token.balanceOf(address(staking));

        // User balance should decrease by stake amount
        assertEq(
            userFinalBalance, userInitialBalance - stakeAmount, "User balance should decrease by exact stake amount"
        );

        // Contract balance should increase by stake amount
        assertEq(
            contractFinalBalance,
            contractInitialBalance + stakeAmount,
            "Contract balance should increase by exact stake amount"
        );

        // Check that the staked amount is properly recorded for the user
        (uint256 stakedBalance,,,,) = staking.getUserInfo(alice);
        assertEq(stakedBalance, stakeAmount, "User's staked balance should match the stake amount");
    }

    /**
     * @notice Comprehensive test for tracking balances during unstaking
     */
    function test_LayerEdgeStaking_BalanceTracking_Unstake() public {
        // Setup - Alice stakes
        uint256 stakeAmount = MIN_STAKE;
        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // Record balances before unstaking
        uint256 userBalanceBeforeUnstake = token.balanceOf(alice);
        uint256 contractBalanceBeforeUnstake = token.balanceOf(address(staking));

        // Advance time past unstake window
        vm.warp(block.timestamp + 7 days + 1);

        // Unstake half the amount
        uint256 unstakeAmount = stakeAmount / 2;
        vm.prank(alice);
        staking.unstake(unstakeAmount);

        // Check balances after unstaking
        uint256 userBalanceAfterUnstake = token.balanceOf(alice);
        uint256 contractBalanceAfterUnstake = token.balanceOf(address(staking));

        // User balance should increase by unstake amount
        assertEq(
            userBalanceAfterUnstake,
            userBalanceBeforeUnstake + unstakeAmount,
            "User balance should increase by exact unstake amount"
        );

        // Contract balance should decrease by unstake amount
        assertEq(
            contractBalanceAfterUnstake,
            contractBalanceBeforeUnstake - unstakeAmount,
            "Contract balance should decrease by exact unstake amount"
        );

        // Check that the staked amount is properly updated
        (uint256 remainingStakedBalance,,,,) = staking.getUserInfo(alice);
        assertEq(
            remainingStakedBalance,
            stakeAmount - unstakeAmount,
            "User's staked balance should be reduced by unstake amount"
        );
    }

    /**
     * @notice Comprehensive test for tracking balances during interest claim
     */
    function test_LayerEdgeStaking_BalanceTracking_ClaimInterest() public {
        // Setup - Alice stakes
        uint256 stakeAmount = MIN_STAKE;
        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // Advance time for interest to accrue
        vm.warp(block.timestamp + 30 days);

        // Record balances before claiming
        uint256 userBalanceBeforeClaim = token.balanceOf(alice);
        uint256 contractBalanceBeforeClaim = token.balanceOf(address(staking));

        // Get expected interest amount
        (,,,, uint256 pendingInterest) = staking.getUserInfo(alice);

        // Claim interest
        vm.prank(alice);
        staking.claimInterest();

        // Check balances after claiming
        uint256 userBalanceAfterClaim = token.balanceOf(alice);
        uint256 contractBalanceAfterClaim = token.balanceOf(address(staking));

        // User balance should increase by interest amount
        assertEq(
            userBalanceAfterClaim,
            userBalanceBeforeClaim + pendingInterest,
            "User balance should increase by exact interest amount"
        );

        // Contract balance should decrease by interest amount
        assertEq(
            contractBalanceAfterClaim,
            contractBalanceBeforeClaim - pendingInterest,
            "Contract balance should decrease by exact interest amount"
        );

        // Pending interest should be reset to 0
        (,,,, uint256 remainingInterest) = staking.getUserInfo(alice);
        assertEq(remainingInterest, 0, "Pending interest should be reset to 0 after claiming");
    }

    /**
     * @notice Comprehensive test for tracking balances during interest compounding
     */
    function test_LayerEdgeStaking_BalanceTracking_CompoundInterest() public {
        // Setup - Alice stakes
        uint256 stakeAmount = MIN_STAKE;
        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // Advance time for interest to accrue
        vm.warp(block.timestamp + 30 days);

        // Record balances before compounding
        uint256 userBalanceBeforeCompound = token.balanceOf(alice);
        uint256 contractBalanceBeforeCompound = token.balanceOf(address(staking));

        // Get expected interest amount
        (uint256 stakedBalanceBeforeCompound,,,, uint256 pendingInterest) = staking.getUserInfo(alice);

        // Compound interest
        vm.prank(alice);
        staking.compoundInterest();

        // Check balances after compounding
        uint256 userBalanceAfterCompound = token.balanceOf(alice);
        uint256 contractBalanceAfterCompound = token.balanceOf(address(staking));

        // User token balance should remain unchanged
        assertEq(
            userBalanceAfterCompound,
            userBalanceBeforeCompound,
            "User external balance should remain unchanged after compounding"
        );

        // Contract token balance should remain unchanged
        assertEq(
            contractBalanceAfterCompound,
            contractBalanceBeforeCompound,
            "Contract token balance should remain unchanged after compounding"
        );

        // Staked balance should increase by the interest amount
        (uint256 stakedBalanceAfterCompound,,,,) = staking.getUserInfo(alice);
        assertEq(
            stakedBalanceAfterCompound,
            stakedBalanceBeforeCompound + pendingInterest,
            "Staked balance should increase by interest amount"
        );

        // Pending interest should be reset to 0
        (,,,, uint256 remainingInterest) = staking.getUserInfo(alice);
        assertEq(remainingInterest, 0, "Pending interest should be reset to 0 after compounding");
    }

    /**
     * @notice Test for tracking balances when multiple users interact with different tiers
     */
    function test_LayerEdgeStaking_BalanceTracking_MultipleTiers() public {
        // Setup multiple users in different tiers
        setupMultipleStakers(10);

        // Advance time for interest to accrue
        vm.warp(block.timestamp + 60 days);

        // Record balances before claiming for different tier users
        uint256 tier1UserBalanceBefore = token.balanceOf(alice); // Tier 1
        uint256 tier2UserBalanceBefore = token.balanceOf(charlie); // Tier 2
        uint256 tier3UserBalanceBefore = token.balanceOf(frank); // Tier 3
        uint256 contractBalanceBefore = token.balanceOf(address(staking));

        // Get expected interest amounts
        (,,,, uint256 tier1Interest) = staking.getUserInfo(alice);
        (,,,, uint256 tier2Interest) = staking.getUserInfo(charlie);
        (,,,, uint256 tier3Interest) = staking.getUserInfo(frank);

        // All users claim interest
        vm.prank(alice);
        staking.claimInterest();

        vm.prank(charlie);
        staking.claimInterest();

        vm.prank(frank);
        staking.claimInterest();

        // Check balances after claiming
        uint256 tier1UserBalanceAfter = token.balanceOf(alice);
        uint256 tier2UserBalanceAfter = token.balanceOf(charlie);
        uint256 tier3UserBalanceAfter = token.balanceOf(frank);
        uint256 contractBalanceAfter = token.balanceOf(address(staking));

        // Verify each user's balance increased by their interest amount
        assertEq(
            tier1UserBalanceAfter,
            tier1UserBalanceBefore + tier1Interest,
            "Tier 1 user balance should increase by their interest amount"
        );

        assertEq(
            tier2UserBalanceAfter,
            tier2UserBalanceBefore + tier2Interest,
            "Tier 2 user balance should increase by their interest amount"
        );

        assertEq(
            tier3UserBalanceAfter,
            tier3UserBalanceBefore + tier3Interest,
            "Tier 3 user balance should increase by their interest amount"
        );

        // Contract balance should decrease by total interest paid
        uint256 totalInterestPaid = tier1Interest + tier2Interest + tier3Interest;
        assertEq(
            contractBalanceAfter,
            contractBalanceBefore - totalInterestPaid,
            "Contract balance should decrease by total interest paid"
        );

        // Verify interest hierarchy (Tier 1 > Tier 2 > Tier 3)
        assertTrue(tier1Interest > tier2Interest, "Tier 1 interest should be greater than Tier 2");
        assertTrue(tier2Interest > tier3Interest, "Tier 2 interest should be greater than Tier 3");
    }

    /**
     * @notice Test for tracking contract rewards balance during deposit and rewards claiming
     */
    function test_LayerEdgeStaking_RewardsBalance_Tracking() public {
        // Record initial state
        uint256 initialRewardsReserve = staking.rewardsReserve();
        uint256 initialContractBalance = token.balanceOf(address(staking));

        // Setup - Alice stakes
        uint256 stakeAmount = MIN_STAKE;
        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // Verify contract balance increased by stake amount
        assertEq(
            token.balanceOf(address(staking)),
            initialContractBalance + stakeAmount,
            "Contract balance should increase by stake amount"
        );

        // But rewards reserve remains unchanged
        assertEq(
            staking.rewardsReserve(), initialRewardsReserve, "Rewards reserve should remain unchanged after staking"
        );

        // Admin adds more rewards
        uint256 additionalRewards = 50_000 * 1e18;
        vm.startPrank(admin);
        token.approve(address(staking), additionalRewards);
        staking.depositRewards(additionalRewards);
        vm.stopPrank();

        // Verify rewards reserve increased
        assertEq(
            staking.rewardsReserve(),
            initialRewardsReserve + additionalRewards,
            "Rewards reserve should increase by deposited amount"
        );

        // Verify contract token balance also increased
        assertEq(
            token.balanceOf(address(staking)),
            initialContractBalance + stakeAmount + additionalRewards,
            "Contract balance should increase by both stake and rewards amount"
        );

        // Advance time for interest to accrue
        vm.warp(block.timestamp + 30 days);

        // Get expected interest
        (,,,, uint256 pendingInterest) = staking.getUserInfo(alice);

        // Alice claims interest
        uint256 rewardsReserveBeforeClaim = staking.rewardsReserve();
        vm.prank(alice);
        staking.claimInterest();
        uint256 rewardsReserveAfterClaim = staking.rewardsReserve();

        // Verify rewards reserve decreased by interest amount
        assertEq(
            rewardsReserveAfterClaim,
            rewardsReserveBeforeClaim - pendingInterest,
            "Rewards reserve should decrease by claimed interest amount"
        );
    }

    /**
     * @notice Test for tracking balances with full staking lifecycle (stake, earn, claim, unstake)
     */
    function test_LayerEdgeStaking_FullLifecycle_BalanceTracking() public {
        // Setup - Alice stakes
        uint256 stakeAmount = MIN_STAKE;
        uint256 initialUserBalance = token.balanceOf(alice);
        uint256 initialContractBalance = token.balanceOf(address(staking));

        vm.startPrank(alice);
        token.approve(address(staking), stakeAmount);
        staking.stake(stakeAmount);
        vm.stopPrank();

        // Verify initial stake balances
        assertEq(
            token.balanceOf(alice), initialUserBalance - stakeAmount, "User balance should decrease by stake amount"
        );
        assertEq(
            token.balanceOf(address(staking)),
            initialContractBalance + stakeAmount,
            "Contract balance should increase by stake amount"
        );

        // Advance time for interest to accrue
        vm.warp(block.timestamp + 180 days);

        // Get expected interest amount
        (,,,, uint256 pendingInterest) = staking.getUserInfo(alice);

        // Alice claims interest
        vm.prank(alice);
        staking.claimInterest();

        // Verify balances after claim
        assertEq(
            token.balanceOf(alice),
            initialUserBalance - stakeAmount + pendingInterest,
            "User balance should increase by interest amount after claim"
        );

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Alice unstakes full amount
        vm.prank(alice);
        staking.unstake(stakeAmount);

        // Verify final balances
        assertEq(
            token.balanceOf(alice),
            initialUserBalance + pendingInterest,
            "User should recover full stake amount plus interest by end of lifecycle"
        );
        assertEq(
            token.balanceOf(address(staking)),
            initialContractBalance - pendingInterest,
            "Contract balance should decrease by interest amount only"
        );

        // Verify user staking state
        (uint256 finalStakedBalance, LayerEdgeStaking.Tier tier,,,) = staking.getUserInfo(alice);
        assertEq(finalStakedBalance, 0, "User should have no staked balance after full unstake");
        assertEq(
            uint256(tier), uint256(LayerEdgeStaking.Tier.Tier3), "User should be downgraded to Tier 3 after unstaking"
        );
    }

    /*//////////////////////////////////////////////////////////////
                          HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setupMultipleStakers(uint256 count) internal {
        address[10] memory stakers = [alice, bob, charlie, david, eve, frank, grace, harry, ian, judy];

        for (uint256 i = 0; i < count && i < stakers.length; i++) {
            vm.startPrank(stakers[i]);
            token.approve(address(staking), MIN_STAKE);
            staking.stake(MIN_STAKE);
            vm.stopPrank();
        }
    }

    function dealToken(address to, uint256 amount) internal {
        vm.deal(to, amount);
        vm.prank(to);
        token.approve(address(staking), amount);
    }

    /*//////////////////////////////////////////////////////////////
                        APY UPDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_UpdateTierAPY_Individual() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Initial APY rates
        assertEq(staking.tier1APY(), 50 * PRECISION);
        assertEq(staking.tier2APY(), 35 * PRECISION);
        assertEq(staking.tier3APY(), 20 * PRECISION);

        // Update only tier 1
        vm.startPrank(admin);

        // Record block timestamp
        uint256 tier1UpdateTime = block.timestamp;

        // Update tier 1 APY to 60%
        vm.expectEmit(true, true, false, true);
        emit LayerEdgeStaking.APYUpdated(LayerEdgeStaking.Tier.Tier1, 60 * PRECISION, tier1UpdateTime);
        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier1, 60 * PRECISION);

        // Wait some time before updating tier 2
        vm.warp(block.timestamp + 1 days);
        uint256 tier2UpdateTime = block.timestamp;

        // Update tier 2 APY to 45%
        vm.expectEmit(true, true, false, true);
        emit LayerEdgeStaking.APYUpdated(LayerEdgeStaking.Tier.Tier2, 45 * PRECISION, tier2UpdateTime);
        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier2, 45 * PRECISION);

        // Wait more time before updating tier 3
        vm.warp(block.timestamp + 2 days);
        uint256 tier3UpdateTime = block.timestamp;

        // Update tier 3 APY to 25%
        vm.expectEmit(true, true, false, true);
        emit LayerEdgeStaking.APYUpdated(LayerEdgeStaking.Tier.Tier3, 25 * PRECISION, tier3UpdateTime);
        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier3, 25 * PRECISION);

        vm.stopPrank();

        // Check the updated APY rates
        assertEq(staking.tier1APY(), 60 * PRECISION);
        assertEq(staking.tier2APY(), 45 * PRECISION);
        assertEq(staking.tier3APY(), 25 * PRECISION);

        // Check APY history for each tier
        // Tier 1 should have 2 entries (initial + update)
        (uint256 tier1Rate, uint256 tier1Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier1, 0);
        assertEq(tier1Rate, 50 * PRECISION);

        (tier1Rate, tier1Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier1, 1);
        assertEq(tier1Rate, 60 * PRECISION);
        assertEq(tier1Time, tier1UpdateTime);

        // Tier 2 should have 2 entries (initial + update)
        (uint256 tier2Rate, uint256 tier2Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier2, 0);
        assertEq(tier2Rate, 35 * PRECISION);

        (tier2Rate, tier2Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier2, 1);
        assertEq(tier2Rate, 45 * PRECISION);
        assertEq(tier2Time, tier2UpdateTime);

        // Tier 3 should have 2 entries (initial + update)
        (uint256 tier3Rate, uint256 tier3Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier3, 0);
        assertEq(tier3Rate, 20 * PRECISION);

        (tier3Rate, tier3Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier3, 1);
        assertEq(tier3Rate, 25 * PRECISION);
        assertEq(tier3Time, tier3UpdateTime);
    }

    function test_LayerEdgeStaking_UpdateAllAPYs() public {
        // Initial APY rates
        assertEq(staking.tier1APY(), 50 * PRECISION);
        assertEq(staking.tier2APY(), 35 * PRECISION);
        assertEq(staking.tier3APY(), 20 * PRECISION);

        // Update all tiers at once
        vm.startPrank(admin);

        uint256 updateTime = block.timestamp;

        // Update all APYs
        vm.expectEmit(true, true, false, true);
        emit LayerEdgeStaking.APYUpdated(LayerEdgeStaking.Tier.Tier1, 70 * PRECISION, updateTime);
        vm.expectEmit(true, true, false, true);
        emit LayerEdgeStaking.APYUpdated(LayerEdgeStaking.Tier.Tier2, 50 * PRECISION, updateTime);
        vm.expectEmit(true, true, false, true);
        emit LayerEdgeStaking.APYUpdated(LayerEdgeStaking.Tier.Tier3, 30 * PRECISION, updateTime);
        staking.updateAllAPYs(70 * PRECISION, 50 * PRECISION, 30 * PRECISION);

        vm.stopPrank();

        // Check the updated APY rates
        assertEq(staking.tier1APY(), 70 * PRECISION);
        assertEq(staking.tier2APY(), 50 * PRECISION);
        assertEq(staking.tier3APY(), 30 * PRECISION);

        // Check APY history for each tier
        // All tiers should have 2 entries (initial + update) with the same timestamp
        (uint256 tier1Rate, uint256 tier1Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier1, 1);
        assertEq(tier1Rate, 70 * PRECISION);
        assertEq(tier1Time, updateTime);

        (uint256 tier2Rate, uint256 tier2Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier2, 1);
        assertEq(tier2Rate, 50 * PRECISION);
        assertEq(tier2Time, updateTime);

        (uint256 tier3Rate, uint256 tier3Time) = staking.tierAPYHistory(LayerEdgeStaking.Tier.Tier3, 1);
        assertEq(tier3Rate, 30 * PRECISION);
        assertEq(tier3Time, updateTime);
    }

    function test_LayerEdgeStaking_UpdateTierAPY_OnlyOwner() public {
        // Non-owner should not be able to update APY
        vm.startPrank(alice);
        vm.expectRevert(); // Only owner can call
        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier1, 60 * PRECISION);
        vm.stopPrank();

        // Owner should be able to update APY
        vm.startPrank(admin);
        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier1, 60 * PRECISION);
        vm.stopPrank();

        // Check the updated APY rate
        assertEq(staking.tier1APY(), 60 * PRECISION);
    }

    function test_LayerEdgeStaking_InterestCalculation_WithDifferentTierChanges() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Advance time by 10 days - accruing interest at original 50% rate
        vm.warp(block.timestamp + 10 days);

        // Admin updates APY for tier 1 only
        vm.startPrank(admin);
        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier1, 60 * PRECISION); // 60% for tier 1
        vm.stopPrank();

        // Advance time by another 10 days - accruing interest at new 60% rate
        vm.warp(block.timestamp + 10 days);

        // Get Alice's interest accrual
        (,,,, uint256 pendingRewards) = staking.getUserInfo(alice);
        // Calculate expected rewards:
        // 10 days at 50% APY
        uint256 firstPeriodRewards = (MIN_STAKE * 50 * PRECISION * 10 days) / (365 days * PRECISION) / 100;

        // 10 days at 60% APY
        uint256 secondPeriodRewards = (MIN_STAKE * 60 * PRECISION * 10 days) / (365 days * PRECISION) / 100;

        uint256 expectedTotal = firstPeriodRewards + secondPeriodRewards;

        // Allow for minimal rounding errors
        assertApproxEqAbs(pendingRewards, expectedTotal, 2);
    }

    function test_LayerEdgeStaking_InterestCalculation_WithTierShift() public {
        // Set up multiple stakers so we have different tiers
        setupMultipleStakers(10);

        // Check initial tiers
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1)); // Alice should be tier 1
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier2)); // Charlie should be tier 2
        assertEq(uint256(staking.getCurrentTier(frank)), uint256(LayerEdgeStaking.Tier.Tier3)); // Frank should be tier 3

        // Advance time to accrue some interest at initial rates
        vm.warp(block.timestamp + 10 days);

        // Update APY rates for all tiers differently
        vm.startPrank(admin);
        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier1, 60 * PRECISION); // Tier 1: 50% -> 60%

        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier2, 40 * PRECISION); // Tier 2: 35% -> 40%

        staking.updateTierAPY(LayerEdgeStaking.Tier.Tier3, 25 * PRECISION); // Tier 3: 20% -> 25%
        vm.stopPrank();

        // Advance time to accrue more interest at new rates
        vm.warp(block.timestamp + 10 days);

        // Get rewards for different tiers
        (,,,, uint256 tier1Rewards) = staking.getUserInfo(alice);
        (,,,, uint256 tier2Rewards) = staking.getUserInfo(charlie);
        (,,,, uint256 tier3Rewards) = staking.getUserInfo(frank);

        // Calculate expected rewards for each tier
        // Tier 1: 10 days at 50% + 10 days at 60%
        uint256 expectedTier1 = (MIN_STAKE * 50 * PRECISION * 10 days) / (365 days * PRECISION) / 100
            + (MIN_STAKE * 60 * PRECISION * 10 days) / (365 days * PRECISION) / 100;

        // Tier 2: 10 days at 35% + 10 days at 40%
        uint256 expectedTier2 = (MIN_STAKE * 35 * PRECISION * 10 days) / (365 days * PRECISION) / 100
            + (MIN_STAKE * 40 * PRECISION * 10 days) / (365 days * PRECISION) / 100;

        // Tier 3: 10 days at 20% + 10 days at 25%
        uint256 expectedTier3 = (MIN_STAKE * 20 * PRECISION * 10 days) / (365 days * PRECISION) / 100
            + (MIN_STAKE * 25 * PRECISION * 10 days) / (365 days * PRECISION) / 100;

        // Allow for minimal rounding errors
        assertApproxEqAbs(tier1Rewards, expectedTier1, 2);
        assertApproxEqAbs(tier2Rewards, expectedTier2, 2);
        assertApproxEqAbs(tier3Rewards, expectedTier3, 2);

        // Verify the reward hierarchy still holds
        assertTrue(tier1Rewards > tier2Rewards, "Tier 1 should earn more than Tier 2");
        assertTrue(tier2Rewards > tier3Rewards, "Tier 2 should earn more than Tier 3");
    }

    /*//////////////////////////////////////////////////////////////
                         PAUSE AND UNPAUSE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_Pause_UnpauseAccess() public {
        // Only owner should be able to pause/unpause the contract
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        staking.pause();

        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        staking.unPause();
        vm.stopPrank();

        // Admin should be able to pause/unpause
        vm.startPrank(admin);
        staking.pause();

        // Verify contract is paused
        assertTrue(staking.paused(), "Contract should be paused");

        staking.unPause();

        // Verify contract is unpaused
        assertFalse(staking.paused(), "Contract should be unpaused");
        vm.stopPrank();
    }

    function test_LayerEdgeStaking_Pause_BlocksOperations() public {
        // Setup initial state
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Advance time to accrue some interest
        vm.warp(block.timestamp + 30 days);

        // Admin pauses the contract
        vm.prank(admin);
        staking.pause();

        // All state-changing operations should be blocked while paused

        // Stake
        vm.startPrank(bob);
        token.approve(address(staking), MIN_STAKE);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Unstake
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        staking.unstake(MIN_STAKE / 2);
        vm.stopPrank();

        // Claim interest
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        staking.claimInterest();
        vm.stopPrank();

        // Compound interest
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(PausableUpgradeable.EnforcedPause.selector));
        staking.compoundInterest();
        vm.stopPrank();

        // Unpause and verify operations work again
        vm.prank(admin);
        staking.unPause();

        // Stake should work again
        vm.startPrank(bob);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Unstake should work again
        vm.startPrank(alice);
        staking.unstake(MIN_STAKE / 2);
        vm.stopPrank();

        // Interest claims should work again
        vm.startPrank(alice);
        staking.claimInterest();
        vm.stopPrank();
    }

    function test_LayerEdgeStaking_Pause_ViewFunctionsWork() public {
        // Setup initial state
        setupMultipleStakers(5);

        // Admin pauses the contract
        vm.prank(admin);
        staking.pause();

        // View functions should still work while paused

        // Get user info
        (uint256 balance, LayerEdgeStaking.Tier tier, uint256 apy, uint256 depositTime, uint256 pendingRewards) =
            staking.getUserInfo(alice);

        // Check that values are accessible
        assertEq(balance, MIN_STAKE);
        assertEq(uint256(tier), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(apy, 50 * PRECISION);
        assertTrue(depositTime > 0);
        assertEq(pendingRewards, 0); // No time passed yet

        // Get tier counts should work
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1);
        assertEq(tier2Count, 1);
        assertEq(tier3Count, 3);

        // Get current tier should work
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3));
    }

    /*//////////////////////////////////////////////////////////////
                    MINIMUM STAKE AMOUNT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_SetMinStakeAmount_OnlyOwner() public {
        // Non-owner should not be able to set minimum stake amount
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        staking.setMinStakeAmount(5000 * 1e18);
        vm.stopPrank();

        // Admin should be able to set minimum stake amount
        uint256 newMinStake = 5000 * 1e18;
        vm.startPrank(admin);
        staking.setMinStakeAmount(newMinStake);
        vm.stopPrank();

        // Verify the minimum stake amount has been updated
        assertEq(staking.minStakeAmount(), newMinStake);
    }

    function test_LayerEdgeStaking_SetMinStakeAmount_AffectsNewStakes() public {
        // Increase minimum stake amount
        uint256 newMinStake = 5000 * 1e18;
        vm.prank(admin);
        staking.setMinStakeAmount(newMinStake);

        // Alice tries to stake the old minimum (should now be considered below minimum)
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Alice should be assigned to Tier 3 due to staking below the new minimum
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Bob stakes at the new minimum
        vm.startPrank(bob);
        token.approve(address(staking), newMinStake);
        staking.stake(newMinStake);
        vm.stopPrank();

        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1));

        vm.startPrank(charlie);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3));
    }

    function test_LayerEdgeStaking_ShouldEarnCorectInterestRateWhenBelowMinimumStake() public {
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE - 1);
        staking.stake(MIN_STAKE - 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        (,,,, uint256 pendingRewards) = staking.getUserInfo(alice);
        //Tier 3 APY is 20%
        assertEq(pendingRewards, (MIN_STAKE - 1) * 20 * PRECISION * 30 days / (365 days * PRECISION) / 100);
    }

    function test_LayerEdgeStaking_ShouldRemainInTier3IfBelowMinimumStakeAfterStakingAgain() public {
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE - 1);
        staking.stake(MIN_STAKE - 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 30 days);

        (,,,,,,, bool outOfTree,,) = staking.users(alice);
        assertTrue(outOfTree, "User should be marked as out of tree");

        (LayerEdgeStaking.Tier tier) = staking.getCurrentTier(alice);
        assertEq(uint256(tier), uint256(LayerEdgeStaking.Tier.Tier3));

        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE * 4);
        staking.stake(MIN_STAKE * 4);
        vm.stopPrank();

        (LayerEdgeStaking.Tier tierAfterStake) = staking.getCurrentTier(alice);
        assertEq(uint256(tierAfterStake), uint256(LayerEdgeStaking.Tier.Tier3));
        (,,,,,,, bool outOfTreeAfterStake,,) = staking.users(alice);
        assertTrue(outOfTreeAfterStake, "User should be out of tree");
    }

    function test_LayerEdgeStaking_SetMinStakeAmount_DoesNotAffectExistingStakers() public {
        // Alice stakes at the original minimum
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Alice should be in Tier 1
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));

        // Increase minimum stake amount
        uint256 newMinStake = 5000 * 1e18;
        vm.prank(admin);
        staking.setMinStakeAmount(newMinStake);

        // Alice should still be in Tier 1 despite being below the new minimum
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
    }

    /*//////////////////////////////////////////////////////////////
                    COMPOUNDING FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_LayerEdgeStaking_SetCompoundingStatus_OnlyOwner() public {
        // Non-owner should not be able to set compounding status
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, alice));
        staking.setCompoundingStatus(false);
        vm.stopPrank();

        // Admin should be able to set compounding status
        vm.startPrank(admin);
        staking.setCompoundingStatus(false);
        vm.stopPrank();

        // Verify compounding status has been updated
        assertFalse(staking.compoundingEnabled());
    }

    function test_LayerEdgeStaking_Compounding_Disabled() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Advance time to accrue interest
        vm.warp(block.timestamp + 30 days);

        // Admin disables compounding
        vm.prank(admin);
        staking.setCompoundingStatus(false);

        // Alice tries to compound interest but should fail
        vm.startPrank(alice);
        vm.expectRevert("Compounding is disabled");
        staking.compoundInterest();
        vm.stopPrank();

        // Alice should still be able to claim interest normally
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        staking.claimInterest();
        uint256 aliceBalanceAfter = token.balanceOf(alice);

        // Verify Alice received interest via claim
        assertTrue(
            aliceBalanceAfter > aliceBalanceBefore,
            "Alice should be able to claim interest even when compounding is disabled"
        );
    }

    function test_LayerEdgeStaking_Compounding_ReEnabled() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Admin disables compounding
        vm.prank(admin);
        staking.setCompoundingStatus(false);

        // Advance time to accrue interest
        vm.warp(block.timestamp + 30 days);

        // Alice tries to compound interest but should fail
        vm.startPrank(alice);
        vm.expectRevert("Compounding is disabled");
        staking.compoundInterest();
        vm.stopPrank();

        // Admin re-enables compounding
        vm.prank(admin);
        staking.setCompoundingStatus(true);

        // Record staked balance before compounding
        (uint256 balanceBefore,,,,) = staking.getUserInfo(alice);

        // Alice should now be able to compound
        vm.prank(alice);
        staking.compoundInterest();

        // Verify Alice's staked balance increased
        (uint256 balanceAfter,,,,) = staking.getUserInfo(alice);
        assertTrue(balanceAfter > balanceBefore, "Alice's staked balance should increase after compounding");
    }

    function test_LayerEdgeStaking_FenwickTree_PartialUnstaking() public {
        // Setup initial stakers with minimum stake to establish base state
        setupMultipleStakers(3); // Setup charlie, bob, and alice with MIN_STAKE each

        // Record initial state
        uint256 initialstakerCountInTree = staking.stakerCountInTree();

        // Setup users with larger stakes
        uint256 largeStake = MIN_STAKE * 4; // 4x minimum stake
        setupLargerStake(david, largeStake);
        setupLargerStake(eve, largeStake);

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Test case 1: Partial unstake that keeps balance above minimum
        // David unstakes 25% of his balance
        vm.startPrank(david);
        uint256 davidInitialBalance = largeStake;
        uint256 unstakeAmount1 = largeStake / 4; // 25% of stake

        staking.unstake(unstakeAmount1);

        // Check David's state - should still be active in tree
        (uint256 davidBalanceAfterUnstake1,,,,) = staking.getUserInfo(david);
        assertEq(
            davidBalanceAfterUnstake1, davidInitialBalance - unstakeAmount1, "Balance should decrease by unstake amount"
        );
        assertTrue(davidBalanceAfterUnstake1 > staking.minStakeAmount(), "Balance should remain above minimum stake");

        // Check active staker count - should remain unchanged
        assertEq(
            staking.stakerCountInTree(),
            initialstakerCountInTree + 2,
            "Active staker count should not change after partial unstake"
        );

        // David unstakes another 25% but still above minimum
        uint256 unstakeAmount2 = largeStake / 4;
        staking.unstake(unstakeAmount2);

        // Check David's state again - should still be active
        (uint256 davidBalanceAfterUnstake2,,,,) = staking.getUserInfo(david);
        assertEq(
            davidBalanceAfterUnstake2,
            davidBalanceAfterUnstake1 - unstakeAmount2,
            "Balance should decrease by second unstake amount"
        );
        assertTrue(
            davidBalanceAfterUnstake2 > staking.minStakeAmount(), "Balance should still remain above minimum stake"
        );

        // Check active staker count - should still remain unchanged
        assertEq(
            staking.stakerCountInTree(),
            initialstakerCountInTree + 2,
            "Active staker count should not change after second partial unstake"
        );
        vm.stopPrank();

        // Test case 2: Multiple unstakes ending with unstake that drops below minimum
        vm.startPrank(eve);
        uint256 eveInitialBalance = largeStake;

        // First unstake - 60% of stake but still above minimum
        uint256 eveUnstakeAmount1 = (largeStake * 60) / 100;
        staking.unstake(eveUnstakeAmount1);

        // Check Eve's state - should still be active
        (uint256 eveBalanceAfterUnstake1,,,,) = staking.getUserInfo(eve);
        assertEq(
            eveBalanceAfterUnstake1, eveInitialBalance - eveUnstakeAmount1, "Balance should decrease by unstake amount"
        );
        assertTrue(eveBalanceAfterUnstake1 > staking.minStakeAmount(), "Balance should remain above minimum stake");

        // Check active staker count - should remain unchanged
        assertEq(
            staking.stakerCountInTree(),
            initialstakerCountInTree + 2,
            "Active staker count should not change after partial unstake"
        );

        // Second unstake - pushes balance below minimum
        uint256 eveUnstakeAmount2 = eveBalanceAfterUnstake1 - (staking.minStakeAmount() / 2);
        staking.unstake(eveUnstakeAmount2);

        // Check Eve's state - should be removed from tree
        (uint256 eveBalanceAfterUnstake2,,,,) = staking.getUserInfo(eve);
        assertEq(
            eveBalanceAfterUnstake2,
            eveBalanceAfterUnstake1 - eveUnstakeAmount2,
            "Balance should decrease by second unstake amount"
        );
        assertTrue(eveBalanceAfterUnstake2 < staking.minStakeAmount(), "Balance should now be below minimum stake");

        // Check active staker count - should decrease by 1
        assertEq(
            staking.stakerCountInTree(),
            initialstakerCountInTree + 1,
            "Active staker count should decrease after unstaking below minimum"
        );

        // Verify Eve has been assigned to Tier 3 and is marked as inactive
        (,, uint256 eveTierAPY,,) = staking.getUserInfo(eve);
        assertEq(eveTierAPY, 20 * PRECISION, "User should be assigned Tier 3 APY after unstaking below minimum");

        (,,,,,,, bool outOfTree,,) = staking.users(eve);
        assertTrue(outOfTree, "User should be marked as out of tree after unstaking below minimum");
        vm.stopPrank();
    }

    // Create a new function to stake with larger amounts
    function setupLargerStake(address user, uint256 amount) internal {
        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();
    }

    function test_LayerEdgeStaking_FenwickTree_ShouldNotOverflowUnderflow() public {
        // Setup initial stakers with 4x minimum stake
        uint256 largeStake = MIN_STAKE * 4;
        setupLargerStake(alice, largeStake);
        setupLargerStake(bob, largeStake);
        setupLargerStake(charlie, largeStake);

        // Record initial state
        uint256 initialstakerCountInTree = staking.stakerCountInTree();

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Bob unstakes 1 wei three times
        vm.startPrank(bob);

        // First 1 wei unstake
        staking.unstake(1);

        // Check Bob's state - should still be active
        (uint256 bobBalanceAfterUnstake1,,,,) = staking.getUserInfo(bob);
        assertEq(bobBalanceAfterUnstake1, largeStake - 1, "Balance should decrease by 1 wei");
        assertTrue(bobBalanceAfterUnstake1 > staking.minStakeAmount(), "Balance should remain above minimum stake");
        assertEq(staking.stakerCountInTree(), initialstakerCountInTree, "Active staker count should not change");

        // Second 1 wei unstake
        staking.unstake(1);

        // Check Bob's state - should still be active
        (uint256 bobBalanceAfterUnstake2,,,,) = staking.getUserInfo(bob);
        assertEq(bobBalanceAfterUnstake2, largeStake - 2, "Balance should decrease by another 1 wei");
        assertTrue(bobBalanceAfterUnstake2 > staking.minStakeAmount(), "Balance should remain above minimum stake");
        assertEq(staking.stakerCountInTree(), initialstakerCountInTree, "Active staker count should not change");

        // Third 1 wei unstake
        staking.unstake(1);

        // Check Bob's state - should still be active
        (uint256 bobBalanceAfterUnstake3,,,,) = staking.getUserInfo(bob);
        assertEq(bobBalanceAfterUnstake3, largeStake - 3, "Balance should decrease by another 1 wei");
        assertTrue(bobBalanceAfterUnstake3 > staking.minStakeAmount(), "Balance should remain above minimum stake");
        assertEq(staking.stakerCountInTree(), initialstakerCountInTree, "Active staker count should not change");

        vm.stopPrank();

        // Charlie stakes again - should pass
        vm.startPrank(charlie);

        uint256 additionalStake = MIN_STAKE;
        token.approve(address(staking), additionalStake);
        staking.stake(additionalStake);

        // Check Charlie's state - should have increased balance
        (uint256 charlieBalance,,,,) = staking.getUserInfo(charlie);
        assertEq(charlieBalance, largeStake + additionalStake, "Balance should increase by additional stake amount");

        vm.stopPrank();

        // Verify the total staked amount is correct
        uint256 expectedTotalStaked = largeStake // Alice
            + (largeStake - 3) // Bob after 3 wei unstake
            + (largeStake + additionalStake); // Charlie after additional stake

        assertEq(staking.totalStaked(), expectedTotalStaked, "Total staked amount should be correct");
    }

    function test_LayerEdgeStaking_StakeAndUnstakeVariations() public {
        // Alice stakes
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Assert in tree
        (,,,,,,, bool outOfTree,,) = staking.users(alice);
        assertFalse(outOfTree, "Alice should be in the tree");
        // Assert tier is tier 1
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        //Assert stakers count is 1
        assertEq(staking.stakerCountInTree(), 1);

        // Alice stakes again
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Assert in tree
        (,,,,,,, outOfTree,,) = staking.users(alice);
        assertFalse(outOfTree, "Alice should be in the tree");
        // Assert tier is tier 1
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        //Assert stakers count is 1
        assertEq(staking.stakerCountInTree(), 1);

        vm.warp(block.timestamp + 7 days + 1);
        // Alice unstakes
        vm.startPrank(alice);
        staking.unstake(MIN_STAKE + 1);
        vm.stopPrank();

        // Assert out of tree
        (,,,,,,, outOfTree,,) = staking.users(alice);
        assertTrue(outOfTree, "Alice should be out of tree");
        // Assert tier is tier 3
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier3));
        //Assert stakers count is 0
        assertEq(staking.stakerCountInTree(), 0);
        assertEq(staking.stakerCountOutOfTree(), 1);

        // Alice stakes again
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Assert out of tree
        (,,,,,,, outOfTree,,) = staking.users(alice);
        assertTrue(outOfTree, "Alice should be out of tree");
        // Assert tier is tier 3
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier3));
        //Assert stakers count is 0
        assertEq(staking.stakerCountInTree(), 0);
        assertEq(staking.stakerCountOutOfTree(), 1);
    }

    function test_LayerEdgeStaking_TierPromotionDemotion() public {
        // This test will verify the behavior of tier promotions and demotions
        // according to the audit finding

        console2.log("alice", address(alice));
        console2.log("bob", address(bob));
        console2.log("charlie", address(charlie));
        console2.log("david", address(david));
        console2.log("eve", address(eve));
        console2.log("frank", address(frank));
        console2.log("grace", address(grace));

        // 1. Setup 6 stakers to create specific tier distribution (1 in Tier1, 1 in Tier2, 4 in Tier3)
        setupMultipleStakers(6);

        // Verify initial tier distribution
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1, "Should have 1 staker in Tier1");
        assertEq(tier2Count, 1, "Should have 1 staker in Tier2");
        assertEq(tier3Count, 4, "Should have 4 stakers in Tier3");

        // Check tiers of each user
        assertEq(
            uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1), "Alice should be in Tier1"
        );
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2), "Bob should be in Tier2");
        assertEq(
            uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3), "Charlie should be in Tier3"
        );

        // Advance time to accumulate some interest at initial tiers
        vm.warp(block.timestamp + 30 days);

        // Check Charlie's interest accrual at Tier3
        (,,,, uint256 charlieInterestBeforePromotion) = staking.getUserInfo(charlie);
        uint256 expectedTier3Interest = (MIN_STAKE * 20 * PRECISION * 30 days) / (365 days * PRECISION) / 100;
        assertApproxEqAbs(
            charlieInterestBeforePromotion, expectedTier3Interest, 2, "Charlie should have accrued Tier3 interest"
        );

        // 2. Add one more staker (Grace) to test promotion
        // According to the audit, this should trigger a promotion from Tier3 to Tier2
        vm.startPrank(grace);
        token.approve(address(staking), MIN_STAKE);
        staking.stake(MIN_STAKE);
        vm.stopPrank();

        // Verify updated tier distribution - should now be 1 in Tier1, 2 in Tier2, 4 in Tier3
        (tier1Count, tier2Count, tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1, "Should have 1 staker in Tier1");
        assertEq(tier2Count, 2, "Should have 2 stakers in Tier2");
        assertEq(tier3Count, 4, "Should have 4 stakers in Tier3");

        //Get staker tier history of bob and charlie
        uint256 bobTierHistoryLength = staking.stakerTierHistoryLength(bob);
        uint256 charlieTierHistoryLength = staking.stakerTierHistoryLength(charlie);
        console2.log("bobTierHistoryLength", bobTierHistoryLength);
        console2.log("charlieTierHistoryLength", charlieTierHistoryLength);

        for (uint256 i = 0; i < bobTierHistoryLength; i++) {
            (LayerEdgeStaking.Tier from, LayerEdgeStaking.Tier to, uint256 timestamp) =
                staking.stakerTierHistory(bob, i);
            console2.log("bobTierHistory", uint256(from), uint256(to), timestamp);
        }

        for (uint256 i = 0; i < charlieTierHistoryLength; i++) {
            (LayerEdgeStaking.Tier from, LayerEdgeStaking.Tier to, uint256 timestamp) =
                staking.stakerTierHistory(charlie, i);
            console2.log("charlieTierHistory", uint256(from), uint256(to), timestamp);
        }

        // Check if Charlie was promoted to Tier2 (should be first in Tier3 previously)
        // The audit suggests this might not happen correctly, so we're verifying
        assertEq(
            uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1), "Alice should remain in Tier1"
        );
        assertEq(
            uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2), "Bob should remain in Tier2"
        );
        assertEq(
            uint256(staking.getCurrentTier(charlie)),
            uint256(LayerEdgeStaking.Tier.Tier2),
            "Charlie should be promoted to Tier2"
        );

        vm.warp(block.timestamp + 30 days);

        // Check Charlie's interest accrual after promotion to Tier2
        (,,,, uint256 charlieInterestAfterPromotion) = staking.getUserInfo(charlie);

        // Expected interest should include:
        // 1. Interest already earned at Tier3 (charlieInterestBeforePromotion)
        // 2. New interest earned at Tier2 rate (35%)
        uint256 expectedTier2Interest = (MIN_STAKE * 35 * PRECISION * 30 days) / (365 days * PRECISION) / 100;
        uint256 expectedTotalInterest = charlieInterestBeforePromotion + expectedTier2Interest;

        assertApproxEqAbs(
            charlieInterestAfterPromotion,
            expectedTotalInterest,
            2,
            "Charlie should have accrued additional interest at Tier2 rate"
        );
    }

    function test_LayerEdgeStaking_TierReassignmentOnRemoval() public {
        // This test specifically checks the issue mentioned in the audit report:
        // "For example, suppose there are currently 7 activeStakers: 1 in Tier1, 2 in Tier2, and 4 in Tier3.
        // After removing one user, there will be 1 Tier1, 1 Tier2 and 4 Tier3."

        // Setup 7 stakers to create the specific distribution mentioned in the audit
        setupMultipleStakers(7);

        // Verify initial tier distribution
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();

        // Expected distribution with 7 stakers:
        // Tier1: 20% of 7 = 1.4 => 1 staker (floored)
        // Tier2: 30% of 7 = 2.1 => 2 stakers (floored)
        // Tier3: Remaining 4 stakers
        assertEq(tier1Count, 1, "Should have 1 staker in Tier1");
        assertEq(tier2Count, 2, "Should have 2 stakers in Tier2");
        assertEq(tier3Count, 4, "Should have 4 stakers in Tier3");

        // Verify initial tier assignments
        assertEq(
            uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1), "Alice should be in Tier1"
        );
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2), "Bob should be in Tier2");
        assertEq(
            uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier2), "Charlie should be in Tier2"
        );
        assertEq(
            uint256(staking.getCurrentTier(david)), uint256(LayerEdgeStaking.Tier.Tier3), "David should be in Tier3"
        );

        console2.log("--- Initial Tier Distribution ---");
        console2.log("Alice (first staker):", uint256(staking.getCurrentTier(alice)));
        console2.log("Bob (second staker):", uint256(staking.getCurrentTier(bob)));
        console2.log("Charlie (third staker):", uint256(staking.getCurrentTier(charlie)));
        console2.log("David (fourth staker):", uint256(staking.getCurrentTier(david)));
        console2.log("Eve (fifth staker):", uint256(staking.getCurrentTier(eve)));
        console2.log("Frank (sixth staker):", uint256(staking.getCurrentTier(frank)));
        console2.log("Grace (seventh staker):", uint256(staking.getCurrentTier(grace)));

        // Get tier history lengths before removals
        uint256 bobTierHistoryLengthBefore = staking.stakerTierHistoryLength(bob);
        uint256 charlieTierHistoryLengthBefore = staking.stakerTierHistoryLength(charlie);

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // CASE 1: Remove Alice (Tier1 user)
        // According to the audit report, the correct behavior should be:
        // "If the user in Tier1 was removed, then the first user in Tier2 should be moved to Tier1."
        vm.startPrank(alice);
        staking.unstake(MIN_STAKE);
        vm.stopPrank();

        // After Alice is removed, we should see:
        // 1. Bob (originally first in Tier2) should move to Tier1
        // 2. Charlie should remain in Tier2
        // 3. No changes to Tier3 users

        console2.log("--- After Alice Removal ---");
        console2.log("Bob:", uint256(staking.getCurrentTier(bob)));
        console2.log("Charlie:", uint256(staking.getCurrentTier(charlie)));
        console2.log("David:", uint256(staking.getCurrentTier(david)));

        assertEq(
            uint256(staking.getCurrentTier(bob)),
            uint256(LayerEdgeStaking.Tier.Tier1),
            "Bob should be promoted to Tier1 when Alice leaves"
        );
        assertEq(
            uint256(staking.getCurrentTier(charlie)),
            uint256(LayerEdgeStaking.Tier.Tier2),
            "Charlie should remain in Tier2"
        );

        // Verify Bob's tier history was updated
        uint256 bobTierHistoryLengthAfter = staking.stakerTierHistoryLength(bob);
        assertTrue(
            bobTierHistoryLengthAfter > bobTierHistoryLengthBefore,
            "Bob's tier history should be updated after Alice's removal"
        );

        //Log all history
        for (uint256 i = 0; i < bobTierHistoryLengthAfter; i++) {
            (LayerEdgeStaking.Tier fromTier, LayerEdgeStaking.Tier toTier,) = staking.stakerTierHistory(bob, i);
            console2.log("bobTierHistory", uint256(fromTier), uint256(toTier));
        }

        if (bobTierHistoryLengthAfter > 0) {
            (LayerEdgeStaking.Tier fromTier, LayerEdgeStaking.Tier toTier,) =
                staking.stakerTierHistory(bob, bobTierHistoryLengthAfter - 1);

            //TODO: fix this test
            assertEq(
                uint256(fromTier),
                uint256(LayerEdgeStaking.Tier.Tier2),
                "Bob's recorded tier change should be from Tier2"
            );
            assertEq(
                uint256(toTier), uint256(LayerEdgeStaking.Tier.Tier1), "Bob's recorded tier change should be to Tier1"
            );
        }
        console2.log("before reset");

        // Reset the test to re-check with a fresh set of stakers
        vm.warp(0);
        vm.roll(0);
        setUp();
        setupMultipleStakers(7);

        // Verify initial tier distribution again
        (tier1Count, tier2Count, tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1, "Should have 1 staker in Tier1");
        assertEq(tier2Count, 2, "Should have 2 stakers in Tier2");
        assertEq(tier3Count, 4, "Should have 4 stakers in Tier3");

        // CASE 2: Remove Bob (first user in Tier2)
        // According to the audit report:
        // "If the first user in Tier2 was removed, then no users need to be moved."

        // Get Charlie's tier history length before Bob's removal
        charlieTierHistoryLengthBefore = staking.stakerTierHistoryLength(charlie);

        // Advance time past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Bob unstakes
        vm.startPrank(bob);
        staking.unstake(MIN_STAKE);
        vm.stopPrank();

        console2.log("--- After Bob Removal ---");
        console2.log("Alice:", uint256(staking.getCurrentTier(alice)));
        console2.log("Charlie:", uint256(staking.getCurrentTier(charlie)));
        console2.log("David:", uint256(staking.getCurrentTier(david)));

        // After Bob is removed, we should see:
        // 1. Alice should remain in Tier1
        // 2. Charlie should remain in Tier2 as the only Tier2 user
        // 3. No other tier changes

        assertEq(
            uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1), "Alice should remain in Tier1"
        );
        assertEq(
            uint256(staking.getCurrentTier(charlie)),
            uint256(LayerEdgeStaking.Tier.Tier2),
            "Charlie should remain the only Tier2 user"
        );

        // Charlie's tier history should not change according to the audit report's expected behavior
        uint256 charlieTierHistoryLengthAfter = staking.stakerTierHistoryLength(charlie);
        assertEq(charlieTierHistoryLengthAfter, 2);

        // The audit report suggests that the bug would cause Charlie to be incorrectly demoted
        // So we're checking if Charlie's tier history shows any tier changes it shouldn't have
        if (charlieTierHistoryLengthAfter > charlieTierHistoryLengthBefore) {
            console2.log("Charlie tier history changed when it shouldn't have!");
            for (uint256 i = charlieTierHistoryLengthBefore; i < charlieTierHistoryLengthAfter; i++) {
                (LayerEdgeStaking.Tier from, LayerEdgeStaking.Tier to, uint256 timestamp) =
                    staking.stakerTierHistory(charlie, i);
                console2.log("charlieTierHistory", uint256(from), uint256(to), timestamp);
            }
        }

        // Check tier counts after Bob's removal
        (tier1Count, tier2Count, tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1, "Should still have 1 staker in Tier1");
        assertEq(tier2Count, 1, "Should now have 1 staker in Tier2");
        assertEq(tier3Count, 4, "Should still have 4 stakers in Tier3");
    }

    //Multiple partial stake and unstake
    function test_LayerEdgeStaking_MultiplePartialStakeAndUnstake() public {
        //Alice stakes minstake
        vm.startPrank(alice);
        token.approve(address(staking), MIN_STAKE * 10);
        staking.stake(MIN_STAKE);

        (uint256 balance,,,,,,,,,) = staking.users(alice);
        assertEq(balance, MIN_STAKE);
        assertEq(staking.totalStaked(), MIN_STAKE);
        assertEq(staking.stakerCountInTree(), 1);
        assertEq(staking.stakerCountOutOfTree(), 0);

        staking.stake(MIN_STAKE);

        (balance,,,,,,,,,) = staking.users(alice);
        assertEq(balance, MIN_STAKE * 2);
        assertEq(staking.totalStaked(), MIN_STAKE * 2);
        assertEq(staking.stakerCountInTree(), 1);
        assertEq(staking.stakerCountOutOfTree(), 0);

        staking.stake(MIN_STAKE);

        (balance,,,,,,,,,) = staking.users(alice);
        assertEq(balance, MIN_STAKE * 3);
        assertEq(staking.totalStaked(), MIN_STAKE * 3);
        assertEq(staking.stakerCountInTree(), 1);
        assertEq(staking.stakerCountOutOfTree(), 0);

        vm.warp(block.timestamp + 7 days + 1);
        staking.unstake(MIN_STAKE);

        (balance,,,,,,,,,) = staking.users(alice);
        assertEq(balance, MIN_STAKE * 2);
        assertEq(staking.totalStaked(), MIN_STAKE * 2);
        assertEq(staking.stakerCountInTree(), 1);
        assertEq(staking.stakerCountOutOfTree(), 0);

        staking.unstake(MIN_STAKE);

        (balance,,,,,,,,,) = staking.users(alice);
        assertEq(balance, MIN_STAKE);
        assertEq(staking.totalStaked(), MIN_STAKE);
        assertEq(staking.stakerCountInTree(), 1);
        assertEq(staking.stakerCountOutOfTree(), 0);

        staking.unstake(1);

        (balance,,,,,,,,,) = staking.users(alice);
        assertEq(balance, MIN_STAKE - 1);
        assertEq(staking.totalStaked(), MIN_STAKE - 1);
        assertEq(staking.stakerCountInTree(), 0);
        assertEq(staking.stakerCountOutOfTree(), 1);
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier3));
        vm.stopPrank();
    }
}
