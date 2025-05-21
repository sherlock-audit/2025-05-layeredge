// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {LayerEdgeStaking} from "@src/stake/LayerEdgeStaking.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {DeployLayerEdgeStaking} from "@script/DeployLayerEdgeStaking.s.sol";
import {NetworkConfig, HelperConfig} from "@script/HelperConfig.s.sol";
import {LayerEdgeToken} from "@test/mock/LayerEdgeToken.sol";

contract TierBoundaryAndInterestTest is Test {
    LayerEdgeStaking public implementation;
    LayerEdgeStaking public staking;
    LayerEdgeToken public token;
    HelperConfig public helperConfig;
    DeployLayerEdgeStaking public deployer;

    // Users
    address public admin = makeAddr("admin");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public dave = makeAddr("dave");
    address public eve = makeAddr("eve");
    address public frank = makeAddr("frank");
    address public grace = makeAddr("grace");
    address public heidi = makeAddr("heidi");
    address public ivan = makeAddr("ivan");
    address public judy = makeAddr("judy");

    // Constants
    uint256 public constant PRECISION = 1e18;
    uint256 public constant MIN_STAKE = 3000 * 1e18;
    uint256 public constant LARGE_STAKE = 10000 * 1e18;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint256 public constant REWARDS_AMOUNT = 100_000 * 1e18;

    function setUp() public {
        // Deploy token
        deployer = new DeployLayerEdgeStaking();
        (staking, helperConfig) = deployer.run();

        NetworkConfig memory config = helperConfig.getActiveNetworkConfig();

        token = LayerEdgeToken(config.stakingToken);
        admin = config.owner;

        // Fund admin and deposit rewards
        vm.startPrank(admin);
        token.approve(address(staking), REWARDS_AMOUNT);
        staking.depositRewards(REWARDS_AMOUNT);
        vm.stopPrank();

        // Fund users
        dealToken(alice, LARGE_STAKE);
        dealToken(bob, LARGE_STAKE);
        dealToken(charlie, LARGE_STAKE);
        dealToken(dave, LARGE_STAKE);
        dealToken(eve, LARGE_STAKE);
        dealToken(frank, LARGE_STAKE);
        dealToken(grace, LARGE_STAKE);
        dealToken(heidi, LARGE_STAKE);
        dealToken(ivan, LARGE_STAKE);
        dealToken(judy, LARGE_STAKE);
    }

    function dealToken(address to, uint256 amount) internal {
        vm.prank(admin);
        token.transfer(to, amount);
        vm.prank(to);
        token.approve(address(staking), amount);
    }

    // Test tier distribution with 5 users
    function test_StakingTierBoundry_TierDistribution_5Users() public {
        // Alice stakes
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Verify tier counts with 1 user
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1);
        assertEq(tier2Count, 0);
        assertEq(tier3Count, 0);

        // Verify Alice's tier (should be tier 1)
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));

        // Bob stakes
        vm.prank(bob);
        staking.stake(MIN_STAKE);

        // Verify tier counts with 2 users
        (tier1Count, tier2Count, tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1); // 20% of 2 rounded up = 1
        assertEq(tier2Count, 1); // 30% of 2 rounded down = 0, but we have 1 remaining
        assertEq(tier3Count, 0);

        // Verify Bob's tier (should be tier 2)
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));

        // Charlie stakes
        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        // Verify tier counts with 3 users
        (tier1Count, tier2Count, tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1); // 20% of 3 rounded down = 0, but min is 1
        assertEq(tier2Count, 1); // 30% of 3 rounded down = 0, but remaining after tier1 is 2
        assertEq(tier3Count, 1);

        // Dave stakes
        vm.prank(dave);
        staking.stake(MIN_STAKE);

        // Eve stakes
        vm.prank(eve);
        staking.stake(MIN_STAKE);

        // Verify tier counts with 5 users
        (tier1Count, tier2Count, tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 1); // 20% of 5 = 1
        assertEq(tier2Count, 1); // 30% of 5 = 1.5 = 1
        assertEq(tier3Count, 3);

        // Verify all users' tiers
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3));
        assertEq(uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier3));
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier3));
    }

    // Test tier shifts when more users join
    function test_StakingTierBoundry_TierShifts_WhenMoreUsersJoin() public {
        // First set up 5 users
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(MIN_STAKE);

        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        vm.prank(dave);
        staking.stake(MIN_STAKE);

        vm.prank(eve);
        staking.stake(MIN_STAKE);

        // Verify initial tiers
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Add 5 more users
        vm.prank(frank);
        staking.stake(MIN_STAKE);

        vm.prank(grace);
        staking.stake(MIN_STAKE);

        vm.prank(heidi);
        staking.stake(MIN_STAKE);

        vm.prank(ivan);
        staking.stake(MIN_STAKE);

        vm.prank(judy);
        staking.stake(MIN_STAKE);

        // Now we have 10 users, verify tier counts
        (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
        assertEq(tier1Count, 2); // 20% of 10 = 2
        assertEq(tier2Count, 3); // 30% of 10 = 3
        assertEq(tier3Count, 5); // remaining 5

        // Verify tiers after the expansion
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(frank)), uint256(LayerEdgeStaking.Tier.Tier3));
    }

    // Test tier history recording with proper FCFS logic
    function test_StakingTierBoundry_TierHistoryRecording() public {
        // Alice stakes first and should always remain in Tier 1
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Bob stakes second and should start in Tier 2
        vm.prank(bob);
        staking.stake(MIN_STAKE);

        // Store initial timestamp
        uint256 startTime = block.timestamp;

        // Wait some time - Bob earns Tier 2 interest during this period
        vm.warp(startTime + 30 days);

        // Now add 8 more users to make a total of 10
        // This should push Bob to Tier 1 (as 20% of 10 = 2 users in Tier 1)
        for (uint256 i = 0; i < 8; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
            vm.deal(user, 1 ether);
            dealToken(user, MIN_STAKE);
            vm.prank(user);
            staking.stake(MIN_STAKE);
        }

        // Bob should now be in Tier 1
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1));

        // Bob stays in Tier 1 for another period
        vm.warp(startTime + 60 days);

        // Get tier history for Bob
        LayerEdgeStaking.TierEvent[] memory bobHistory = getTierHistory(bob);

        // Bob should have 2 tier events: initial Tier2 and promotion to Tier1
        assertEq(bobHistory.length, 2);
        assertEq(uint256(bobHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier2)); // Initial tier
        assertEq(uint256(bobHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier1)); // Promotion to Tier 1

        // Calculate expected interest:
        // First 30 days: Tier 2 (35% APY)
        // Next 30 days: Tier 1 (50% APY)
        uint256 tier2Days = 30;
        uint256 tier1Days = 30;
        uint256 tier2Interest = (MIN_STAKE * 35 * PRECISION * tier2Days) / (365 * 100 * PRECISION);
        uint256 tier1Interest = (MIN_STAKE * 50 * PRECISION * tier1Days) / (365 * 100 * PRECISION);
        uint256 expectedInterest = tier2Interest + tier1Interest;

        // Get actual interest from contract
        (,,,, uint256 actualInterest) = staking.getUserInfo(bob);

        // Allow for small rounding differences due to block timestamps
        assertApproxEqRel(actualInterest, expectedInterest, 0.01e18); // 1% tolerance
    }

    // Test interest calculation with tier changes
    function test_StakingTierBoundry_InterestCalculation_WithTierChanges() public {
        // Set up initial state with Alice in tier 1
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Store initial timestamp
        uint256 initialTimestamp = block.timestamp;

        // Advance time by 30 days - Alice earns tier 1 interest during this time (50% APY)
        vm.warp(initialTimestamp + 30 days);

        // Bob stakes and should be in tier 2
        vm.prank(bob);
        staking.stake(MIN_STAKE);

        // Advance time by another 30 days
        vm.warp(initialTimestamp + 60 days);

        // Charlie stakes - should be in tier 3 (with 3 users: 1 tier 1, 1 tier 2, 1 tier 3)
        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        // Verify tiers are assigned correctly
        assertEq(
            uint256(staking.getCurrentTier(alice)),
            uint256(LayerEdgeStaking.Tier.Tier1),
            "Alice should remain in Tier 1"
        );
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2), "Bob should be in Tier 2");
        assertEq(
            uint256(staking.getCurrentTier(charlie)),
            uint256(LayerEdgeStaking.Tier.Tier3),
            "Charlie should be in Tier 3"
        );

        // Advance time by another 30 days - Alice still in tier 1
        vm.warp(initialTimestamp + 90 days);

        // Calculate expected interest for Alice: All 90 days in Tier 1 (50% APY)
        uint256 tier1Days = 90;
        uint256 tier1Interest = (MIN_STAKE * 50 * PRECISION * tier1Days) / (365 * 100 * PRECISION);
        uint256 expectedInterest = tier1Interest;

        // Get actual interest from contract
        (,,,, uint256 actualInterest) = staking.getUserInfo(alice);

        // Allow for small rounding differences due to block timestamps
        assertApproxEqRel(actualInterest, expectedInterest, 0.01e18); // 1% tolerance

        // Alice claims interest, verify correct amount is transferred
        uint256 balanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        staking.claimInterest();
        uint256 balanceAfter = token.balanceOf(alice);

        assertApproxEqRel(balanceAfter - balanceBefore, expectedInterest, 0.01e18);
    }

    // Test tier boundary changes when users unstake
    function test_StakingTierBoundry_TierBoundaryChanges_WhenUsersUnstake() public {
        // Setup 10 users in the staking system
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(MIN_STAKE);

        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        vm.prank(dave);
        staking.stake(MIN_STAKE);

        vm.prank(eve);
        staking.stake(MIN_STAKE);

        //Assert eve record history
        LayerEdgeStaking.TierEvent[] memory eveHistory = getTierHistory(eve);
        assertEq(eveHistory.length, 1);
        assertEq(uint256(eveHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier3));

        vm.prank(frank);
        staking.stake(MIN_STAKE);

        //Assert eve record history
        eveHistory = getTierHistory(eve);
        console2.log("eveHistory.length", eveHistory.length);
        console2.log("eves tier", uint256(staking.getCurrentTier(eve)));

        vm.prank(grace);
        staking.stake(MIN_STAKE);

        //Assert eve record history
        eveHistory = getTierHistory(eve);
        console2.log("eveHistory.length", eveHistory.length);
        console2.log("eves tier", uint256(staking.getCurrentTier(eve)));

        vm.prank(heidi);
        staking.stake(MIN_STAKE);

        //Assert eve record history
        eveHistory = getTierHistory(eve);
        console2.log("eveHistory.length", eveHistory.length);
        console2.log("eves tier", uint256(staking.getCurrentTier(eve)));
        vm.prank(ivan);
        staking.stake(MIN_STAKE);

        //Assert eve record history
        eveHistory = getTierHistory(eve);
        console2.log("eveHistory.length", eveHistory.length);
        console2.log("eves tier", uint256(staking.getCurrentTier(eve)));

        vm.prank(judy);
        staking.stake(MIN_STAKE);

        //Assert eve record history
        eveHistory = getTierHistory(eve);
        console2.log("eveHistory.length", eveHistory.length);
        console2.log("eves tier", uint256(staking.getCurrentTier(eve)));
        // Initial distribution should be:
        // Tier 1: Alice, Bob (first 2)
        // Tier 2: Charlie, Dave, Eve (next 3)
        // Tier 3: Frank, Grace, Heidi, Ivan, Judy (remaining 5)
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(frank)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Fast forward past unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Now have Bob unstake, this should push Charlie up to tier 1
        vm.prank(bob);
        staking.unstake(MIN_STAKE);

        //Assert bob out of tree
        (,,,,,,, bool outOfTree,,) = staking.users(bob);
        assertEq(outOfTree, true);
        console2.log("bob out of tree", outOfTree);

        //Assert eve record history
        console2.log("after bob unstake.............");
        eveHistory = getTierHistory(eve);
        console2.log("eveHistory.length", eveHistory.length);
        console2.log("eves tier", uint256(staking.getCurrentTier(eve)));
        console2.log("eves address", eve);
        console2.log("daves address", dave);
        console2.log("franks address", frank);

        // Verify tier changes
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier2)); // Charlie moved up to tier 1
        assertEq(uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier3));
        assertEq(uint256(staking.getCurrentTier(frank)), uint256(LayerEdgeStaking.Tier.Tier3)); // Frank moved up to tier 2
        assertEq(uint256(staking.getCurrentTier(grace)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Bob should be unstaked and inactive
        (uint256 bobBalance,,,,) = staking.getUserInfo(bob);
        assertEq(bobBalance, 0);

        // Check tier history for Eve
        eveHistory = getTierHistory(eve);
        assertEq(eveHistory.length, 3, "Length should be 3");
        console2.log("eveHistory[0].to", uint256(eveHistory[0].to));
        console2.log("eveHistory[1].to", uint256(eveHistory[1].to));
        assertEq(uint256(eveHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier3)); // Initial tier
        assertEq(uint256(eveHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier2)); // Demoted tier
        assertEq(uint256(eveHistory[2].to), uint256(LayerEdgeStaking.Tier.Tier3)); // Promoted tier
    }

    // Test multiple boundary shifts with interest calculation
    function test_StakingTierBoundry_MultipleBoundaryShifts_WithInterestCalculation() public {
        // Initial setup - let's start with Alice
        vm.prank(alice);
        staking.stake(MIN_STAKE);
        uint256 startTime = block.timestamp;

        // Advance time - Alice is in tier 1
        vm.warp(startTime + 10 days);

        // Bob joins - Alice tier 1, Bob tier 2
        vm.prank(bob);
        staking.stake(MIN_STAKE);

        // Advance time - Alice and Bob earning at their respective rates
        vm.warp(startTime + 20 days);

        // Charlie joins - Alice tier 1, Bob tier 2, Charlie tier 3
        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        // Advance time
        vm.warp(startTime + 30 days);

        // Dave, Eve, Frank join in succession (creating a 6-user system)
        vm.prank(dave);
        staking.stake(MIN_STAKE);

        vm.warp(startTime + 40 days);

        vm.prank(eve);
        staking.stake(MIN_STAKE);

        vm.warp(startTime + 50 days);

        vm.prank(frank);
        staking.stake(MIN_STAKE);

        // With 6 users, correct tier distribution is:
        // Tier 1: Alice (20% of 6 = 1.2 = 1 user, since we use integer division)
        // Tier 2: Bob (30% of 6 = 1.8 = 1 user, since we use integer division)
        // Tier 3: Charlie, Dave, Eve, Frank (remaining 4 users)

        // Verify tiers
        assertEq(
            uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1), "Alice should be in Tier 1"
        );
        assertEq(
            uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2), "Bob should remain in Tier 2"
        );
        assertEq(
            uint256(staking.getCurrentTier(charlie)),
            uint256(LayerEdgeStaking.Tier.Tier3),
            "Charlie should be in Tier 3"
        );
        assertEq(
            uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier3), "Dave should be in Tier 3"
        );

        // Advance time for final interest accrual
        vm.warp(startTime + 60 days);

        // Calculate expected interest for Bob:
        // Days 0-10: Not staked
        // Days 10-60: Tier 2 (50 days) - Bob never moves to Tier 1 in this scenario
        uint256 bob_tier2Days = 50;
        uint256 bob_tier2Interest = (MIN_STAKE * 35 * PRECISION * bob_tier2Days) / (365 * 100 * PRECISION);
        uint256 bob_expectedInterest = bob_tier2Interest;

        // Get Bob's actual interest
        (,,,, uint256 bob_actualInterest) = staking.getUserInfo(bob);

        // Verify Bob's interest calculation
        assertApproxEqRel(bob_actualInterest, bob_expectedInterest, 0.01e18);

        // Also check Bob's current tier is correct (should be Tier 2)
        (, LayerEdgeStaking.Tier bobTier,,,) = staking.getUserInfo(bob);
        assertEq(uint256(bobTier), uint256(LayerEdgeStaking.Tier.Tier2));

        // Save Bob's accrued interest before tier change
        uint256 bobInterestBeforeTierChange = bob_actualInterest;

        // Now let's test a different scenario where Bob would move to Tier 1
        // Add 4 more users to bring the total to 10
        address[] memory extraUsers = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            extraUsers[i] = address(uint160(uint256(keccak256(abi.encodePacked("extraUser", i)))));
            vm.deal(extraUsers[i], 1 ether);
            dealToken(extraUsers[i], MIN_STAKE);
            vm.prank(extraUsers[i]);
            staking.stake(MIN_STAKE);
        }

        // With 10 users, tier distribution is:
        // Tier 1: Alice, Bob (20% of 10 = 2 users)
        // Tier 2: Charlie, Dave, Eve (30% of 10 = 3 users)
        // Tier 3: Frank and the 4 new users (remaining 5)

        // Verify the tier changes
        assertEq(
            uint256(staking.getCurrentTier(alice)),
            uint256(LayerEdgeStaking.Tier.Tier1),
            "Alice should remain in Tier 1"
        );
        assertEq(
            uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1), "Bob should now be in Tier 1"
        );
        assertEq(
            uint256(staking.getCurrentTier(charlie)),
            uint256(LayerEdgeStaking.Tier.Tier2),
            "Charlie should be in Tier 2"
        );

        // Let's verify Bob's tier history
        LayerEdgeStaking.TierEvent[] memory bobHistory = getTierHistory(bob);
        assertEq(bobHistory.length, 2);
        assertEq(uint256(bobHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier2), "Bob's initial tier should be Tier 2");
        assertEq(
            uint256(bobHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier1), "Bob should have been promoted to Tier 1"
        );

        // Now advance time by 30 more days - Bob should now earn at Tier 1 rate
        uint256 tierChangeTime = block.timestamp;
        vm.warp(tierChangeTime + 30 days);

        // Calculate Bob's additional interest after tier change:
        // 30 days at Tier 1 rate (50% APY)
        uint256 bob_additional_tier1Days = 30;
        uint256 bob_additional_tier1Interest =
            (MIN_STAKE * 50 * PRECISION * bob_additional_tier1Days) / (365 * 100 * PRECISION);

        // Total expected interest is previous interest + new Tier 1 interest
        uint256 bob_total_expected_interest = bobInterestBeforeTierChange + bob_additional_tier1Interest;

        // Get Bob's actual interest after this additional period
        (,,,, uint256 bob_new_actualInterest) = staking.getUserInfo(bob);

        // Verify Bob's total interest calculation
        assertApproxEqRel(
            bob_new_actualInterest,
            bob_total_expected_interest,
            0.01e18,
            "Bob's interest should include both Tier 2 and Tier 1 periods"
        );

        // Calculate how much interest Bob earned in just the last 30 days
        uint256 lastPeriodInterest = bob_new_actualInterest - bobInterestBeforeTierChange;

        // Verify the last period interest matches expected Tier 1 interest rate
        assertApproxEqRel(
            lastPeriodInterest,
            bob_additional_tier1Interest,
            0.01e18,
            "Bob's interest for last 30 days should be at Tier 1 rate"
        );
    }

    // Test FCFS tier assignments and tier boundary shifts
    function test_StakingTierBoundry_FCFS_TierAssignments_WithBoundaryShifts() public {
        // Alice stakes first - should always be Tier 1
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Bob stakes second
        vm.prank(bob);
        staking.stake(MIN_STAKE);

        // Charlie stakes third
        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        // With 3 users, verify initial tiers
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Add 7 more users to have 10 total stakers
        vm.prank(dave);
        staking.stake(MIN_STAKE);

        vm.prank(eve);
        staking.stake(MIN_STAKE);

        vm.prank(frank);
        staking.stake(MIN_STAKE);

        vm.prank(grace);
        staking.stake(MIN_STAKE);

        vm.prank(heidi);
        staking.stake(MIN_STAKE);

        vm.prank(ivan);
        staking.stake(MIN_STAKE);

        vm.prank(judy);
        staking.stake(MIN_STAKE);

        // With 10 users, tier distribution should be:
        // Tier 1: Alice, Bob (first 20% = 2 users)
        // Tier 2: Charlie, Dave, Eve (next 30% = 3 users)
        // Tier 3: Frank, Grace, Heidi, Ivan, Judy (remaining 50% = 5 users)

        // Verify Alice and Bob remain in Tier 1
        assertEq(
            uint256(staking.getCurrentTier(alice)),
            uint256(LayerEdgeStaking.Tier.Tier1),
            "Alice should remain in Tier 1"
        );
        assertEq(
            uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1), "Bob should now be in Tier 1"
        );

        // Verify the next 3 users are in Tier 2
        assertEq(
            uint256(staking.getCurrentTier(charlie)),
            uint256(LayerEdgeStaking.Tier.Tier2),
            "Charlie should be in Tier 2"
        );
        assertEq(
            uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier2), "Dave should be in Tier 2"
        );
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier2), "Eve should be in Tier 2");

        // Verify the rest are in Tier 3
        assertEq(
            uint256(staking.getCurrentTier(frank)), uint256(LayerEdgeStaking.Tier.Tier3), "Frank should be in Tier 3"
        );

        // Now have three users unstake, dropping total stakers to 7
        vm.warp(block.timestamp + 7 days + 1); // Past unstaking window

        vm.prank(judy);
        staking.unstake(MIN_STAKE);

        vm.prank(ivan);
        staking.unstake(MIN_STAKE);

        vm.prank(heidi);
        staking.unstake(MIN_STAKE);

        // With 7 users left, tiers should shift:
        // Tier 1: Alice (first 20% = 1.4 = 1 user)
        // Tier 2: Bob, Charlie (next 30% = 2.1 = 2 users)
        // Tier 3: Dave, Eve, Frank, Grace (remaining 50% = 4 users)

        // Verify adjustments
        assertEq(
            uint256(staking.getCurrentTier(alice)),
            uint256(LayerEdgeStaking.Tier.Tier1),
            "Alice should still be in Tier 1"
        );
        assertEq(
            uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2), "Bob should move back to Tier 2"
        );
        assertEq(
            uint256(staking.getCurrentTier(charlie)),
            uint256(LayerEdgeStaking.Tier.Tier2),
            "Charlie should remain in Tier 2"
        );
        assertEq(
            uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier3), "Dave should move to Tier 3"
        );

        // Check tier history for Bob, who has moved tiers twice
        LayerEdgeStaking.TierEvent[] memory bobHistory = getTierHistory(bob);
        assertEq(bobHistory.length, 3);
        assertEq(uint256(bobHistory[0].from), uint256(LayerEdgeStaking.Tier.Tier3)); // Initial tier
        assertEq(uint256(bobHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(bobHistory[1].from), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(bobHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier1)); // Promoted when more users joined
        assertEq(uint256(bobHistory[2].from), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(bobHistory[2].to), uint256(LayerEdgeStaking.Tier.Tier2)); // Demoted when users left
    }

    // Enable --via-ir to run this test
    // Test APY changes, dynamic tier boundaries, and interest calculation accuracy
    // function test_StakingTierBoundry_APYChanges_With_RandomUserMovement() public {
    //     // // This test verifies that the tiered staking system correctly:
    //     // // 1. Assigns users to tiers based on staking order and tier percentages
    //     // // 2. Tracks tier changes when users join or leave the system
    //     // // 3. Applies APY changes properly for calculating interest
    //     // // 4. Calculates interest correctly across tier and APY changes
    //     // // 5. Allows claiming of accumulated interest
    //     // //
    //     // // Flow diagram of the test:
    //     // // ┌────────────────────────────┐
    //     // // │ Initial Setup              │
    //     // // │ - Alice stakes (Tier 1)    │
    //     // // └────────────┬───────────────┘
    //     // //              ▼
    //     // // ┌────────────────────────────┐   ┌────────────────────────────┐
    //     // // │ Phase 1 (10 days)          │   │ APY Rates:                 │
    //     // // │ - Alice earns at 50% APY   │   │ - Tier 1: 50%              │
    //     // // │ - Bob joins (Tier 2)       │   │ - Tier 2: 35%              │
    //     // // └────────────┬───────────────┘   │ - Tier 3: 20%              │
    //     // //              │                   └────────────────────────────┘
    //     // //              ▼
    //     // // ┌────────────────────────────┐   ┌────────────────────────────┐
    //     // // │ Phase 2 (10 days)          │   │ APY Rates Updated:         │
    //     // // │ - APY rates change         │   │ - Tier 1: 60%              │
    //     // // │ - Alice earns at 60% APY   │   │ - Tier 2: 40%              │
    //     // // │ - Bob earns at 40% APY     │   │ - Tier 3: 25%              │
    //     // // └────────────┬───────────────┘   └────────────────────────────┘
    //     // //              │
    //     // //              ▼
    //     // // ┌────────────────────────────┐
    //     // // │ Phase 3 (10 days)          │
    //     // // │ - 3 more users join        │
    //     // // │ - Total: 5 users           │
    //     // // │ - Alice T1, Bob T2, others T3│
    //     // // └────────────┬───────────────┘
    //     // //              │
    //     // //              ▼
    //     // // ┌────────────────────────────┐   ┌────────────────────────────┐
    //     // // │ Phase 4 (22 days)          │   │ APY Rates Updated:         │
    //     // // │ - APY rates change again   │   │ - Tier 1: 70%              │
    //     // // │ - Charlie unstakes         │   │ - Tier 2: 45%              │
    //     // // │ - Total: 4 users           │   │ - Tier 3: 30%              │
    //     // // └────────────┬───────────────┘   └────────────────────────────┘
    //     // //              │
    //     // //              ▼
    //     // // ┌────────────────────────────┐
    //     // // │ Phase 5 (5 days)           │
    //     // // │ - 6 more users join        │
    //     // // │ - Total: 10 users          │
    //     // // │ - Bob moves to Tier 1      │
    //     // // └────────────┬───────────────┘
    //     // //              │
    //     // //              ▼
    //     // // ┌────────────────────────────┐   ┌────────────────────────────┐
    //     // // │ Phase 6 (5 days)           │   │ APY Rates Updated:         │
    //     // // │ - Final APY rate change    │   │ - Tier 1: 80%              │
    //     // // │ - Alice claims interest    │   │ - Tier 2: 50%              │
    //     // // └────────────┬───────────────┘   │ - Tier 3: 35%              │
    //     // //              │                   └────────────────────────────┘
    //     // //              ▼
    //     // // ┌────────────────────────────┐
    //     // // │ Phase 7 (10 days)          │
    //     // // │ - 6 users unstake          │
    //     // // │ - Total: 4 users           │
    //     // // │ - Bob moves to Tier 2      │
    //     // // │ - Bob claims all interest  │
    //     // // └────────────────────────────┘
    //     // //
    //     // // Key assertions in this test:
    //     // // 1. Tier assignments are correct at each phase
    //     // // 2. User tier history correctly tracks changes
    //     // // 3. Interest calculation is accurate across tier changes
    //     // // 4. Interest calculation is accurate across APY changes
    //     // // 5. Interest can be claimed and matches expected amounts
    //     // // 6. APY rate transitions are weighted correctly in calculations

    //     // Initial setup with Alice and track timestamps
    //     vm.prank(alice);
    //     staking.stake(MIN_STAKE);
    //     uint256 startTime = block.timestamp;

    //     // Track expected interest totals for verification
    //     uint256 expectedInterestAlice = 0;
    //     uint256 expectedInterestBob = 0;

    //     // Advance time by 10 days - Alice in Tier 1 with 50% APY
    //     vm.warp(startTime + 10 days);

    //     // Bob joins - Alice in Tier 1, Bob in Tier 2
    //     vm.prank(bob);
    //     staking.stake(MIN_STAKE);

    //     // Calculate Alice's interest for first 10 days (Tier 1 - 50% APY)
    //     uint256 alicePhase1Days = 10;
    //     uint256 alicePhase1Interest = (MIN_STAKE * 50 * PRECISION * alicePhase1Days) / (365 * 100 * PRECISION);
    //     expectedInterestAlice += alicePhase1Interest;

    //     // Admin changes APY rates for all tiers
    //     vm.prank(admin);
    //     staking.updateAllAPYs(60 * PRECISION, 40 * PRECISION, 25 * PRECISION); // 60%, 40%, 25%

    //     // Advance time by 10 more days with new APY rates
    //     uint256 phase2Start = block.timestamp;
    //     vm.warp(phase2Start + 10 days);

    //     // Calculate Alice's interest for second 10 days (Tier 1 - 60% APY)
    //     uint256 alicePhase2Days = 10;
    //     uint256 alicePhase2Interest = (MIN_STAKE * 60 * PRECISION * alicePhase2Days) / (365 * 100 * PRECISION);
    //     expectedInterestAlice += alicePhase2Interest;

    //     // Calculate Bob's interest for 10 days (Tier 2 - 40% APY)
    //     uint256 bobPhase1Days = 10;
    //     uint256 bobPhase1Interest = (MIN_STAKE * 40 * PRECISION * bobPhase1Days) / (365 * 100 * PRECISION);
    //     expectedInterestBob += bobPhase1Interest;

    //     // Add 3 more users to create a 5-user system
    //     vm.prank(charlie);
    //     staking.stake(MIN_STAKE);

    //     vm.prank(dave);
    //     staking.stake(MIN_STAKE);

    //     vm.prank(eve);
    //     staking.stake(MIN_STAKE);

    //     // Advance time by another 10 days
    //     uint256 phase3Start = block.timestamp;
    //     vm.warp(phase3Start + 10 days);

    //     // Calculate Alice's interest for third 10 days (still Tier 1 - 60% APY)
    //     uint256 alicePhase3Days = 10;
    //     uint256 alicePhase3Interest = (MIN_STAKE * 60 * PRECISION * alicePhase3Days) / (365 * 100 * PRECISION);
    //     expectedInterestAlice += alicePhase3Interest;

    //     // Calculate Bob's interest for this phase (should still be Tier 2 - 40% APY)
    //     uint256 bobPhase2Days = 10;
    //     uint256 bobPhase2Interest = (MIN_STAKE * 40 * PRECISION * bobPhase2Days) / (365 * 100 * PRECISION);
    //     expectedInterestBob += bobPhase2Interest;

    //     // Admin changes APY rates again
    //     vm.prank(admin);
    //     staking.updateAllAPYs(70 * PRECISION, 45 * PRECISION, 30 * PRECISION); // 70%, 45%, 30%

    //     // Verify tier distribution with 5 users
    //     (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) = staking.getTierCounts();
    //     assertEq(tier1Count, 1); // 20% of 5 = 1
    //     assertEq(tier2Count, 1); // 30% of 5 = 1.5 = 1
    //     assertEq(tier3Count, 3); // remaining 3

    //     // Verify specific user tiers
    //     assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
    //     assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));
    //     assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3));

    //     // Advance time past unstaking window
    //     vm.warp(block.timestamp + 7 days + 1);

    //     // Charlie unstakes, shifting tier boundaries
    //     vm.prank(charlie);
    //     staking.unstake(MIN_STAKE);

    //     // Verify tier counts after Charlie's unstake (4 users)
    //     (tier1Count, tier2Count, tier3Count) = staking.getTierCounts();
    //     assertEq(tier1Count, 1); // 20% of 4 rounded up = 1
    //     assertEq(tier2Count, 1); // 30% of 4 = 1.2 = 1
    //     assertEq(tier3Count, 2); // remaining 2

    //     // Advance time by 15 days with the new configuration
    //     uint256 phase4Start = block.timestamp;
    //     vm.warp(phase4Start + 15 days);

    //     // Calculate Alice's interest for fourth phase (Tier 1 - 70% APY)
    //     uint256 alicePhase4Days = 15 + 7; // Including unstaking window + 1
    //     uint256 alicePhase4Interest = (MIN_STAKE * 70 * PRECISION * alicePhase4Days) / (365 * 100 * PRECISION);
    //     expectedInterestAlice += alicePhase4Interest;

    //     // Calculate Bob's interest for fourth phase (still Tier 2 - 45% APY)
    //     uint256 bobPhase3Days = 15 + 7; // Including unstaking window + 1
    //     uint256 bobPhase3Interest = (MIN_STAKE * 45 * PRECISION * bobPhase3Days) / (365 * 100 * PRECISION);
    //     expectedInterestBob += bobPhase3Interest;

    //     // Add 6 more users to have 10 total stakers
    //     for (uint256 i = 0; i < 6; i++) {
    //         address user = address(uint160(uint256(keccak256(abi.encodePacked("extraUser", i)))));
    //         vm.deal(user, 1 ether);
    //         dealToken(user, MIN_STAKE);
    //         vm.prank(user);
    //         staking.stake(MIN_STAKE);
    //     }

    //     // With 10 users, tier distribution should change:
    //     // Tier 1: Alice, Bob (20% of 10 = 2)
    //     // Tier 2: Charlie, Dave, Eve (30% of 10 = 3)
    //     // Tier 3: Remaining 5 users

    //     // Verify Bob has moved to Tier 1
    //     assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1));

    //     // Advance time by 5 more days
    //     uint256 phase5Start = block.timestamp;
    //     vm.warp(phase5Start + 5 days);

    //     // Calculate Bob's interest for final phase with promotion to Tier 1 (70% APY)
    //     uint256 bobPhase4Days = 5;
    //     uint256 bobPhase4Interest = (MIN_STAKE * 70 * PRECISION * bobPhase4Days) / (365 * 100 * PRECISION);
    //     expectedInterestBob += bobPhase4Interest;

    //     uint256 alicePhase5Days = 5;
    //     uint256 alicePhase5Interest = (MIN_STAKE * 70 * PRECISION * alicePhase5Days) / (365 * 100 * PRECISION);
    //     expectedInterestAlice += alicePhase5Interest;

    //     // Admin makes one more APY change
    //     vm.prank(admin);
    //     staking.updateAllAPYs(80 * PRECISION, 50 * PRECISION, 35 * PRECISION); // 80%, 50%, 35%

    //     // Advance time 5 more days
    //     uint256 phase6Start = block.timestamp;
    //     vm.warp(phase6Start + 5 days);

    //     // Calculate final phase interest
    //     uint256 alicePhase6Days = 5;
    //     uint256 alicePhase6Interest = (MIN_STAKE * 80 * PRECISION * alicePhase6Days) / (365 * 100 * PRECISION);
    //     expectedInterestAlice += alicePhase6Interest;

    //     uint256 bobPhase5Days = 5;
    //     uint256 bobPhase5Interest = (MIN_STAKE * 80 * PRECISION * bobPhase5Days) / (365 * 100 * PRECISION);
    //     expectedInterestBob += bobPhase5Interest;

    //     // Verify final interest calculations
    //     (,,,, uint256 aliceActualInterest) = staking.getUserInfo(alice);
    //     assertApproxEqRel(
    //         aliceActualInterest,
    //         expectedInterestAlice,
    //         0.01e18,
    //         "Alice's interest calculation should be accurate across APY changes"
    //     );

    //     (,,,, uint256 bobActualInterest) = staking.getUserInfo(bob);
    //     assertApproxEqRel(
    //         bobActualInterest,
    //         expectedInterestBob,
    //         0.01e18,
    //         "Bob's interest calculation should be accurate across tier changes and APY updates"
    //     );

    //     // Verify tier history for Bob (should show Tier2 -> Tier1)
    //     LayerEdgeStaking.TierEvent[] memory bobHistory = getTierHistory(bob);
    //     assertEq(bobHistory.length, 2);
    //     assertEq(uint256(bobHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier2));
    //     assertEq(uint256(bobHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier1));

    //     // Verify Alice and Bob can claim interest
    //     uint256 aliceBalanceBefore = token.balanceOf(alice);
    //     vm.prank(alice);
    //     staking.claimInterest();
    //     uint256 aliceBalanceAfter = token.balanceOf(alice);

    //     assertApproxEqRel(
    //         aliceBalanceAfter - aliceBalanceBefore,
    //         expectedInterestAlice,
    //         0.01e18,
    //         "Alice should receive correct interest amount"
    //     );

    //     // Store Bob's interest at this point
    //     uint256 bobInterestBeforeTierChange = staking.calculateUnclaimedInterest(bob);

    //     // Have the last 6 users unstake (the extra users we added earlier)
    //     for (uint256 i = 0; i < 6; i++) {
    //         address user = address(uint160(uint256(keccak256(abi.encodePacked("extraUser", i)))));
    //         vm.prank(user);
    //         staking.unstake(MIN_STAKE);
    //     }

    //     // Now we're back to 4 users (Alice, Bob, Dave, Eve)
    //     // With 4 users, tier distribution should shift:
    //     // Tier 1: Alice (20% of 4 = 0.8 = 1 due to minimum)
    //     // Tier 2: Bob (30% of 4 = 1.2 = 1)
    //     // Tier 3: Dave, Eve (remaining 2)

    //     // Verify Bob's tier changed to Tier 2 naturally due to user count reduction
    //     assertEq(
    //         uint256(staking.getCurrentTier(bob)),
    //         uint256(LayerEdgeStaking.Tier.Tier2),
    //         "Bob should have naturally moved down to Tier 2"
    //     );

    //     // Verify Bob's tier history now includes the natural downgrade to Tier 2
    //     bobHistory = getTierHistory(bob);
    //     assertEq(bobHistory.length, 3);
    //     assertEq(uint256(bobHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier2));
    //     assertEq(uint256(bobHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier1));
    //     assertEq(uint256(bobHistory[2].to), uint256(LayerEdgeStaking.Tier.Tier2));

    //     // Advance time by 10 more days to accrue interest at the Tier 2 rate after the downgrade
    //     uint256 phase7Start = block.timestamp;
    //     vm.warp(phase7Start + 10 days);

    //     // Calculate Bob's interest for period after downgrade (now Tier 2 - 50% APY)
    //     uint256 bobPhase6Days = 10;
    //     uint256 bobPhase6Interest = (MIN_STAKE * 50 * PRECISION * bobPhase6Days) / (365 * 100 * PRECISION);
    //     expectedInterestBob += bobPhase6Interest;

    //     // Verify Bob's interest calculation is correct after the natural tier downgrade
    //     (,,,, uint256 bobFinalInterest) = staking.getUserInfo(bob);
    //     assertApproxEqRel(
    //         bobFinalInterest,
    //         expectedInterestBob,
    //         0.01e18,
    //         "Bob's final interest calculation should include periods in Tier 1 and Tier 2 after natural downgrade"
    //     );

    //     // Calculate how much interest Bob earned just in the final period after downgrade
    //     uint256 finalPeriodInterest = bobFinalInterest - bobInterestBeforeTierChange;
    //     assertApproxEqRel(
    //         finalPeriodInterest,
    //         bobPhase6Interest,
    //         0.01e18,
    //         "Bob's interest for the final period should be at Tier 2 rate (50%)"
    //     );

    //     // Verify Bob can claim the additional interest earned after the tier downgrade
    //     uint256 bobFinalBalanceBefore = token.balanceOf(bob);
    //     vm.prank(bob);
    //     staking.claimInterest();
    //     uint256 bobFinalBalanceAfter = token.balanceOf(bob);

    //     assertApproxEqRel(
    //         bobFinalBalanceAfter - bobFinalBalanceBefore,
    //         expectedInterestBob,
    //         0.01e18,
    //         "Bob should receive interest earned after the tier downgrade"
    //     );
    // }

    // Helper function to get tier history
    function getTierHistory(address user) internal view returns (LayerEdgeStaking.TierEvent[] memory) {
        uint256 length = staking.stakerTierHistoryLength(user);

        // Then build the array
        LayerEdgeStaking.TierEvent[] memory history = new LayerEdgeStaking.TierEvent[](length);
        for (uint256 i = 0; i < length; i++) {
            (LayerEdgeStaking.Tier from, LayerEdgeStaking.Tier to, uint256 timestamp) =
                staking.stakerTierHistory(user, i);
            history[i] = LayerEdgeStaking.TierEvent(from, to, timestamp);
        }
        return history;
    }

    function test_TierBoundary_TierCountsUnchanged_WhenUserRemoved() public {
        // This test verifies that when a user is removed and tier counts remain the same,
        // the correct user's tier is still updated in the tier history

        // Setup 4 users with specific tier distribution
        // This will create: 1 in Tier1, 1 in Tier2, 2 in Tier3
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(MIN_STAKE);

        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        vm.prank(dave);
        staking.stake(MIN_STAKE);

        // Verify initial tier distribution
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier3));
        assertEq(uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Record initial tier counts
        (uint256 old_t1, uint256 old_t2, uint256 old_t3) = staking.getTierCounts();
        assertEq(old_t1, 1);
        assertEq(old_t2, 1);
        assertEq(old_t3, 2);

        // Wait past the unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Now have Charlie (a Tier3 user) unstake
        vm.prank(charlie);
        staking.unstake(MIN_STAKE);

        // Check if tier counts actually remained the same
        (uint256 new_t1, uint256 new_t2, uint256 new_t3) = staking.getTierCounts();
        assertEq(new_t1, 1);
        assertEq(new_t2, 1);
        assertEq(new_t3, 1);

        // Assert tier count condition: tier counts remain the same
        assertEq(old_t1, new_t1, "Tier 1 count should remain the same");
        assertEq(old_t2, new_t2, "Tier 2 count should remain the same");
        assertEq(old_t3 - 1, new_t3, "Tier 3 count should decrease by 1");

        // Verify alice and bob's tiers didn't change
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier3));

        // But the more important check: verify Dave's tier history shows proper tracking
        // even though tier counts didn't change
        LayerEdgeStaking.TierEvent[] memory daveHistory = getTierHistory(dave);

        // Dave's tier shouldn't have changed since counts remained the same, so history length should be 1
        assertEq(daveHistory.length, 1);
        assertEq(uint256(daveHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier3));
    }

    function test_TierBoundary_Tier1UserRemoved_TierCountsUnchanged() public {
        // This test verifies that when a Tier 1 user is removed and tier counts remain the same,
        // the correct tier promotion for Tier 2 user is recorded

        // Setup 32 users exactly to create a specific tier distribution
        // This will create: 6 in Tier1, 9 in Tier2, 17 in Tier3
        // 32 * 0.2 = 6.4 → 6 users in Tier1
        // 32 * 0.3 = 9.6 → 9 users in Tier2
        // 32 - 6 - 9 = 17 users in Tier3

        // First stake with our named users
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(MIN_STAKE);

        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        vm.prank(dave);
        staking.stake(MIN_STAKE);

        vm.prank(eve);
        staking.stake(MIN_STAKE);

        // Add 27 more users to reach exactly 32
        for (uint256 i = 0; i < 27; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
            dealToken(user, MIN_STAKE);
            vm.prank(user);
            staking.stake(MIN_STAKE);
        }

        // Verify we have exactly 32 stakers
        assertEq(staking.stakerCountInTree(), 32);

        // Get tier counts to verify our setup
        (uint256 old_t1, uint256 old_t2, uint256 old_t3) = staking.getTierCounts();
        assertEq(old_t1, 6, "Should have 6 users in Tier 1");
        assertEq(old_t2, 9, "Should have 9 users in Tier 2");
        assertEq(old_t3, 17, "Should have 17 users in Tier 3");

        // Verify Alice is in Tier 1 (she staked first)
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1));

        // Find a user at position 7 (first user in Tier 2)
        uint256 tier2FirstUserJoinId = staking.getCumulativeFrequency(7);
        address tier2FirstUser = staking.stakerAddress(tier2FirstUserJoinId);

        // Ensure this user is actually in Tier 2
        assertEq(uint256(staking.getCurrentTier(tier2FirstUser)), uint256(LayerEdgeStaking.Tier.Tier2));

        // Wait past the unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Now have Alice (a Tier1 user) unstake
        vm.prank(alice);
        staking.unstake(MIN_STAKE);

        // Now we have 31 users, tier counts should be:
        // 31 * 0.2 = 6.2 → 6 users in Tier1 (unchanged)
        // 31 * 0.3 = 9.3 → 9 users in Tier2 (unchanged)
        // 31 - 6 - 9 = 16 users in Tier3 (decreased by 1)

        // Verify tier counts
        (uint256 new_t1, uint256 new_t2, uint256 new_t3) = staking.getTierCounts();
        assertEq(new_t1, 6, "Should still have 6 users in Tier 1");
        assertEq(new_t2, 9, "Should still have 9 users in Tier 2");
        assertEq(new_t3, 16, "Should have 16 users in Tier 3");

        // The critical check: verify the first Tier 2 user was promoted to Tier 1
        // This is the key scenario the audit report mentioned
        assertEq(
            uint256(staking.getCurrentTier(tier2FirstUser)),
            uint256(LayerEdgeStaking.Tier.Tier1),
            "First Tier 2 user should be promoted to Tier 1"
        );

        // Also check their tier history to ensure the promotion was recorded
        LayerEdgeStaking.TierEvent[] memory userHistory = getTierHistory(tier2FirstUser);
        assertEq(userHistory.length, 3, "User should have 2 tier events");
        assertEq(uint256(userHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier3), "User should have started in Tier 3");
        assertEq(
            uint256(userHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier2), "User should have been promoted to Tier 2"
        );
        assertEq(
            uint256(userHistory[2].to), uint256(LayerEdgeStaking.Tier.Tier1), "User should have been promoted to Tier 1"
        );
    }

    function test_TierBoundary_TierCountsUnchanged_WhenUserAdded() public {
        // This test verifies that when a user is added and tier counts remain the same,
        // the appropriate tier assignments are still updated in the tier history

        // Setup 33 users to create a specific tier distribution where adding
        // a user doesn't change tier counts
        // 33 * 0.2 = 6.6 → 6 users in Tier1
        // 33 * 0.3 = 9.9 → 9 users in Tier2
        // 33 - 6 - 9 = 18 users in Tier3

        // After adding one more user (34 total):
        // 34 * 0.2 = 6.8 → 6 users in Tier1 (unchanged)
        // 34 * 0.3 = 10.2 → 10 users in Tier2 (increased by 1)
        // 34 - 6 - 10 = 18 users in Tier3 (unchanged)

        // Stake with our named users first
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(MIN_STAKE);

        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        vm.prank(dave);
        staking.stake(MIN_STAKE);

        vm.prank(eve);
        staking.stake(MIN_STAKE);

        // Add 28 more users to reach exactly 33
        for (uint256 i = 0; i < 28; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
            dealToken(user, MIN_STAKE);
            vm.prank(user);
            staking.stake(MIN_STAKE);
        }

        // Verify we have exactly 33 stakers
        assertEq(staking.stakerCountInTree(), 33);

        // Get tier counts to verify our setup
        (uint256 old_t1, uint256 old_t2, uint256 old_t3) = staking.getTierCounts();
        assertEq(old_t1, 6, "Should have 6 users in Tier 1");
        assertEq(old_t2, 9, "Should have 9 users in Tier 2");
        assertEq(old_t3, 18, "Should have 18 users in Tier 3");

        // Find a user at position 16 (boundary between Tier2 and Tier3)
        uint256 boundaryUserJoinId = staking.getCumulativeFrequency(15);
        address lastTier2User = staking.stakerAddress(boundaryUserJoinId);

        // Find the first user in Tier3
        uint256 firstTier3UserJoinId = staking.getCumulativeFrequency(16);
        address firstTier3User = staking.stakerAddress(firstTier3UserJoinId);

        // Verify these users' tiers
        assertEq(uint256(staking.getCurrentTier(lastTier2User)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(firstTier3User)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Now add one more user (frank)
        vm.prank(frank);
        staking.stake(MIN_STAKE);

        // Verify tier counts after adding the user
        (uint256 new_t1, uint256 new_t2, uint256 new_t3) = staking.getTierCounts();
        assertEq(new_t1, 6, "Should still have 6 users in Tier 1");
        assertEq(new_t2, 10, "Should now have 10 users in Tier 2");
        assertEq(new_t3, 18, "Should still have 18 users in Tier 3");

        // The critical check: verify the first user from Tier 3 was promoted to Tier 2
        assertEq(
            uint256(staking.getCurrentTier(firstTier3User)),
            uint256(LayerEdgeStaking.Tier.Tier2),
            "First Tier 3 user should be promoted to Tier 2"
        );

        // Check tier history to ensure the promotion was recorded
        LayerEdgeStaking.TierEvent[] memory userHistory = getTierHistory(firstTier3User);
        assertEq(userHistory.length, 2, "User should have 2 tier events");
        assertEq(uint256(userHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier3), "User should have started in Tier 3");
        assertEq(
            uint256(userHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier2), "User should have been promoted to Tier 2"
        );
    }

    function test_TierBoundary_Tier2UserRemoved_TierCountsUnchanged() public {
        // This test verifies that when a Tier 2 user is removed and tier counts remain the same,
        // the correct tier promotion occurs from Tier 3 to Tier 2

        // Setup 32 users exactly to create a specific tier distribution
        // This will create: 6 in Tier1, 9 in Tier2, 17 in Tier3

        // First stake with our named users
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(MIN_STAKE);

        vm.prank(charlie);
        staking.stake(MIN_STAKE);

        vm.prank(dave);
        staking.stake(MIN_STAKE);

        vm.prank(eve);
        staking.stake(MIN_STAKE);

        // Add 27 more users to reach exactly 32
        for (uint256 i = 0; i < 27; i++) {
            address user = address(uint160(uint256(keccak256(abi.encodePacked("user", i)))));
            dealToken(user, MIN_STAKE);
            vm.prank(user);
            staking.stake(MIN_STAKE);
        }

        // Verify we have exactly 32 stakers
        assertEq(staking.stakerCountInTree(), 32);

        // Find the last user in Tier 2 (at position 15)
        uint256 lastTier2UserJoinId = staking.getCumulativeFrequency(15);
        address lastTier2User = staking.stakerAddress(lastTier2UserJoinId);

        // Find the first user in Tier 3 (at position 16)
        uint256 firstTier3UserJoinId = staking.getCumulativeFrequency(16);
        address firstTier3User = staking.stakerAddress(firstTier3UserJoinId);

        // Verify these users' tiers
        assertEq(uint256(staking.getCurrentTier(lastTier2User)), uint256(LayerEdgeStaking.Tier.Tier2));
        assertEq(uint256(staking.getCurrentTier(firstTier3User)), uint256(LayerEdgeStaking.Tier.Tier3));

        // Wait past the unstaking window
        vm.warp(block.timestamp + 7 days + 1);

        // Now have the last Tier 2 user unstake
        vm.prank(lastTier2User);
        staking.unstake(MIN_STAKE);

        // Verify tier counts after removal
        (uint256 new_t1, uint256 new_t2, uint256 new_t3) = staking.getTierCounts();
        assertEq(new_t1, 6, "Should still have 6 users in Tier 1");
        assertEq(new_t2, 9, "Should still have 9 users in Tier 2");
        assertEq(new_t3, 16, "Should have 16 users in Tier 3");

        // The key check: verify the first Tier 3 user was promoted to Tier 2
        assertEq(
            uint256(staking.getCurrentTier(firstTier3User)),
            uint256(LayerEdgeStaking.Tier.Tier2),
            "First Tier 3 user should be promoted to Tier 2"
        );

        // Check tier history to ensure the promotion was recorded
        LayerEdgeStaking.TierEvent[] memory userHistory = getTierHistory(firstTier3User);
        assertEq(userHistory.length, 2, "User should have 2 tier events");
        assertEq(uint256(userHistory[0].to), uint256(LayerEdgeStaking.Tier.Tier3), "User should have started in Tier 3");
        assertEq(
            uint256(userHistory[1].to), uint256(LayerEdgeStaking.Tier.Tier2), "User should have been promoted to Tier 2"
        );
    }

    function test_AuditReport_TierBoundary_MultiplePromotions_NamedUsers() public {
        address[10] memory users = [alice, bob, charlie, dave, eve, frank, grace, heidi, ivan, judy];
        // Fund and stake for each user
        for (uint256 i = 0; i < 9; i++) {
            dealToken(users[i], MIN_STAKE);
            vm.prank(users[i]);
            staking.stake(MIN_STAKE);
        }

        dealToken(users[9], MIN_STAKE);
        vm.prank(users[9]);
        staking.stake(MIN_STAKE);

        // Assert expected tiers
        assertEq(uint256(staking.getCurrentTier(alice)), uint256(LayerEdgeStaking.Tier.Tier1), "Alice should be Tier1");
        assertEq(uint256(staking.getCurrentTier(bob)), uint256(LayerEdgeStaking.Tier.Tier1), "Bob should be Tier1");
        assertEq(
            uint256(staking.getCurrentTier(charlie)), uint256(LayerEdgeStaking.Tier.Tier2), "Charlie should be Tier2"
        );
        assertEq(uint256(staking.getCurrentTier(dave)), uint256(LayerEdgeStaking.Tier.Tier2), "Dave should be Tier2");
        assertEq(uint256(staking.getCurrentTier(eve)), uint256(LayerEdgeStaking.Tier.Tier2), "Eve should be Tier2");
        assertEq(uint256(staking.getCurrentTier(frank)), uint256(LayerEdgeStaking.Tier.Tier3), "Frank should be Tier3");

        // Assert tier history for Bob, Dave, Eve (should have promotion events if logic is correct)
        LayerEdgeStaking.TierEvent[] memory bobHistory = getTierHistory(bob);
        LayerEdgeStaking.TierEvent[] memory daveHistory = getTierHistory(dave);
        LayerEdgeStaking.TierEvent[] memory eveHistory = getTierHistory(eve);
        assertTrue(bobHistory.length >= 2, "Bob should have a promotion event");
        assertTrue(daveHistory.length >= 2, "Dave should have a promotion event");
        for (uint256 i = 0; i < daveHistory.length; i++) {
            console2.log("daveHistory[i].to", i, uint256(daveHistory[i].to));
        }
        assertTrue(eveHistory.length >= 2, "Eve should have a promotion event");
    }
}
