# LayerEdge - Staking contest details

- Join [Sherlock Discord](https://discord.gg/MABEWyASkp)
- Submit findings using the **Issues** page in your private contest repo (label issues as **Medium** or **High**)
- [Read for more details](https://docs.sherlock.xyz/audits/watsons)

# Q&A

### Q: On what chains are the smart contracts going to be deployed?
Ethereum and LayerEdge L1, An EVM-enabled cosmos chain.
___

### Q: If you are integrating tokens, are you allowing only whitelisted tokens to work with the codebase or any complying with the standard? Are they assumed to have certain properties, e.g. be non-reentrant? Are there any types of [weird tokens](https://github.com/d-xo/weird-erc20) you want to integrate?
On Ethereum, we use EDGEN, an OpenZeppelin implementation of the ERC20Permit token. 
On LayerEdge, we use the WETH9 contract, a Fork of the WETH token on Ethereum.
___

### Q: Are there any limitations on values set by admins (or other roles) in the codebase, including restrictions on array lengths?
The owner of the protocol can change the following data:
1. APY Rates:
No upper limits on tier1APY, tier2APY, tier3APY
Historical APY values are stored in unbounded arrays (tierAPYHistory)
2. minStakeAmount:
No upper limit (could potentially be set so high that new staking becomes impossible)
3. MAX_USERS Constraint:
Fenwick tree size fixed at 100,000,000 (MAX_USERS constant)
Cannot be adjusted by admin
4. Reward Reserve:
Admin can withdraw any amount from rewardsReserve

___

### Q: Are there any limitations on values set by admins (or other roles) in protocols you integrate with, including restrictions on array lengths?
No third-party protocol integration!
___

### Q: Is the codebase expected to comply with any specific EIPs?
1. EIP-1822/EIP-1967: Universal Upgradeable Proxy Standard (UUPS) and Standard Proxy Storage Slots, as implemented through OpenZeppelin's UUPSUpgradeable pattern
2. ERC-20: For the staking token interactions (stakingToken) and reward distributions
3. WETH9 specification: While not a formal EIP, the contract interacts with WETH9 through the IWETH interface for native token handling.
___

### Q: Are there any off-chain mechanisms involved in the protocol (e.g., keeper bots, arbitrage bots, etc.)? We assume these mechanisms will not misbehave, delay, or go offline unless otherwise specified.
No off-chain mechanisms.
___

### Q: What properties/invariants do you want to hold even if breaking them has a low/unknown impact?
1. Tier distribution correctness: Exactly 20% in Tier 1, 30% in Tier 2, and 50% in Tier 3 (with minimum guarantees of at least 1 user per tier when applicable)
2. First-come-first-serve (FCFS) ordering: Earlier stakers should always have priority for higher tiers
3. Interest calculation accuracy: User rewards must be calculated correctly based on their tier history, time staked, and APY rates
4. Tier history integrity: A user's tier history must accurately reflect all tier changes with correct timestamps
5. Permanent tier demotion: Users who unstake below minStakeAmount should permanently remain in Tier 3(Out of tree/system)
6. Reentrance protection: All state-changing operations must be safe from reentrancy attacks
7. APY history preservation: Historical APY rates must be preserved for accurate interest calculations across rate changes.
___

### Q: Please discuss any design choices you made.
Tier System & User Ranking
1. Fenwick Tree for Efficient Ranking:
We chose a Fenwick Tree (Binary Indexed Tree) data structure for tracking user ranks with O(log n) operations
This enables efficient tier boundary management without requiring expensive array reordering operations
2. Fixed Tier Percentages:
Hardcoded tier percentages (20%, 30%, 50%) provide predictability rather than allowing admin-adjustable percentages
F3. First-Come-First-Served (FCFS):
A clear fairness mechanism where early adopters get priority for higher tiers
Incentivizes long-term staking commitment

Native Token Support
Dual Token Functionality:
Supports both ERC20 (on Ethereum) and wrapped native token (on LayerEdge L1)
Simplifies multi-chain deployment with minimum code changes.


___

### Q: Please list any relevant protocol resources.
Docs can be found here in the repo: ./docs/LayerEdgeStaking.md
___

### Q: Additional audit information.
1. Tier Boundary Adjustments:
- Verify all tier updates occur correctly when boundaries shift, especially in the rare cases where multiple users change tiers simultaneously
- The fix adds loops that handle multi-user updates - check for any edge cases
2. Interest Calculation Across Tier Changes:
- The calculateUnclaimedInterest() function handles complex tier transition cases
- Verify interest calculation correctness when users move between tiers or when APY rates change
- Look for precision loss or rounding errors in interest calculations
3. Native Token Handling:
- The contract supports both ERC20 and wrapped native token (WETH) mechanisms
- Examine unwrapping and transferring of ETH operations in unstakeNative() and claimInterestNative()
- Verify ETH transfer security and error handling
4. Fenwick Tree Implementation:
- The ranking system relies on a Fenwick Tree library for efficient operations
- Check index calculation and boundary conditions in tree operations
- Confirm tree state remains consistent through stake/unstake sequences.


# Audit scope

[edgen-staking @ 94286c4972d5f89bc05b372bee5fad4e067ace1a](https://github.com/Layer-Edge/edgen-staking/tree/94286c4972d5f89bc05b372bee5fad4e067ace1a)
- [edgen-staking/src/WETH9.sol](edgen-staking/src/WETH9.sol)
- [edgen-staking/src/library/FenwickTree.sol](edgen-staking/src/library/FenwickTree.sol)
- [edgen-staking/src/stake/LayerEdgeStaking.sol](edgen-staking/src/stake/LayerEdgeStaking.sol)


