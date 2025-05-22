// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {FenwickTree} from "@src/library/FenwickTree.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IWETH} from "@interfaces/IWETH.sol";

/**
 * @title LayerEdgeStaking
 * @notice Tiered staking contract with different APY rates based on staking position
 * @dev Implements a first-come-first-serve tiered system with different rewards
 */
contract LayerEdgeStaking is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using FenwickTree for FenwickTree.Tree;

    // Tier enum
    enum Tier {
        None,
        Tier1,
        Tier2,
        Tier3
    }

    // Constants
    uint256 public constant SECONDS_IN_YEAR = 365 days;
    uint256 public constant PRECISION = 1e18;
    uint256 public constant UNSTAKE_WINDOW = 7 days;
    uint256 public constant MAX_USERS = 100_000_000;

    // Tier percentages
    uint256 public constant TIER1_PERCENTAGE = 20; // First 20% of stakers
    uint256 public constant TIER2_PERCENTAGE = 30; // Next 30% of stakers

    // APY rates for tiers (can be changed by admin)
    uint256 public tier1APY;
    uint256 public tier2APY;
    uint256 public tier3APY;

    // ERC20 token being staked
    IERC20 public stakingToken;

    // Events
    event Staked(address indexed user, uint256 amount, Tier tier);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event TierChanged(address indexed user, Tier to);
    event APYUpdated(Tier indexed tier, uint256 rate, uint256 timestamp);
    event RewardsDeposited(address indexed sender, uint256 amount);
    event UnstakedQueued(address indexed user, uint256 index, uint256 amount);

    // User information
    struct UserInfo {
        uint256 balance; // Current staked balance
        uint256 lastClaimTime; // Last time user claimed or updated interest
        uint256 interestEarned; // Unclaimed interest earned
        uint256 totalClaimed; // Total interest claimed
        uint256 joinId; // Position in the stakers array (for tier calculation)
        uint256 lastTimeTierChanged;
        bool outOfTree; // Whether user is out of the tree
        bool isActive; // Whether user has any active stake
        bool isFirstDepositMoreThanMinStake; // Whether user's first deposit was more than min stake
    }

    // APY Period information with separate start times for each tier
    struct APYPeriod {
        uint256 rate; // APY rate for this period
        uint256 startTime; // When this APY period started
    }
    // Tier history for each user

    struct TierEvent {
        Tier from;
        Tier to;
        uint256 timestamp;
    }

    // Add a struct for unstake requests
    struct UnstakeRequest {
        uint256 amount;
        uint256 timestamp;
        bool completed;
    }

    // Storage
    mapping(Tier => APYPeriod[]) public tierAPYHistory; // tier => APY periods
    mapping(address => UserInfo) public users;
    mapping(uint256 => address) public stakerAddress;
    mapping(address => TierEvent[]) public stakerTierHistory;
    mapping(address => UnstakeRequest[]) public unstakeRequests;
    uint256 public stakerCountInTree;
    uint256 public stakerCountOutOfTree;
    uint256 public totalStaked;
    uint256 public rewardsReserve; // Tracking rewards available in the contract
    uint256 public nextJoinId;
    uint256 public minStakeAmount;
    bool public compoundingEnabled;
    FenwickTree.Tree private stakerTree;

    modifier whenCompoundingEnabled() {
        require(compoundingEnabled, "Compounding is disabled");
        _;
    }

    //constructor
    constructor() {
        _disableInitializers();
    }

    receive() external payable {
        require(msg.sender == address(stakingToken), "Only staking token can send ETH");
    }

    fallback() external payable {
        revert("Fallback not allowed");
    }

    // Initializer
    function initialize(address _stakingToken, address _admin) public initializer {
        require(_stakingToken != address(0), "Invalid token address");
        stakingToken = IERC20(_stakingToken);
        __Ownable_init(_admin);
        __Pausable_init();
        __ReentrancyGuard_init();

        // Set initial APY rates
        tier1APY = 50 * PRECISION; // 50%
        tier2APY = 35 * PRECISION; // 35%
        tier3APY = 20 * PRECISION; // 20%

        //Initialize tree
        stakerTree.size = MAX_USERS;
        nextJoinId = 1;
        minStakeAmount = 3000 * 1e18;

        // Initialize APY history for each tier
        uint256 currentTime = block.timestamp;
        tierAPYHistory[Tier.Tier1].push(APYPeriod({rate: tier1APY, startTime: currentTime}));
        tierAPYHistory[Tier.Tier2].push(APYPeriod({rate: tier2APY, startTime: currentTime}));
        tierAPYHistory[Tier.Tier3].push(APYPeriod({rate: tier3APY, startTime: currentTime}));
    }

    /*//////////////////////////////////////////////////////////////
                         CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stake tokens
     * @param amount Amount to stake
     */
    function stake(uint256 amount) external nonReentrant whenNotPaused {
        _stake(amount, msg.sender, false);
    }

    /**
     * @notice Stake native tokens. Internally converts to a wrapped token
     */
    function stakeNative() external payable nonReentrant whenNotPaused {
        _stake(msg.value, msg.sender, true);
    }

    /**
     * @notice Unstake tokens
     * @param amount Amount to unstake
     */
    function unstake(uint256 amount) external nonReentrant whenNotPaused {
        _unstake(amount, msg.sender);
    }

    /**
     * @notice Complete a specific unstake request
     * @param index Index of the unstake request to complete
     */
    function completeUnstake(uint256 index) external nonReentrant whenNotPaused {
        _completeUnstake(msg.sender, index, false);
    }

    /**
     * @notice Complete a specific unstake request with native token
     * @param index Index of the unstake request to complete
     */
    function completeUnstakeNative(uint256 index) external nonReentrant whenNotPaused {
        _completeUnstake(msg.sender, index, true);
    }

    /**
     * @notice Claim accrued interest
     */
    function claimInterest() external nonReentrant whenNotPaused {
        _claimInterest(msg.sender, false);
    }

    /**
     * @notice Claim accrued interest for native tokens
     */
    function claimInterestNative() external nonReentrant whenNotPaused {
        _claimInterest(msg.sender, true);
    }

    /**
     * @notice Compound interest by adding it to staked balance
     */
    function compoundInterest() external whenCompoundingEnabled nonReentrant whenNotPaused {
        _updateInterest(msg.sender);

        UserInfo storage user = users[msg.sender];
        uint256 claimable = user.interestEarned;

        require(claimable > 0, "Nothing to compound");

        // Check if we have enough rewards in the contract
        require(rewardsReserve >= claimable, "Insufficient rewards in contract");

        // Update rewards reserve
        rewardsReserve -= claimable;

        // Add earned interest to staked balance
        user.balance += claimable;
        totalStaked += claimable;

        // Reset interest tracking
        user.lastClaimTime = block.timestamp;
        user.interestEarned = 0;
        user.totalClaimed += claimable;

        // Determine user's tier for event (might have changed due to increased balance)
        Tier tier = getCurrentTier(msg.sender);

        emit RewardClaimed(msg.sender, claimable);
        emit Staked(msg.sender, claimable, tier);
    }

    /**
     * @notice Update APY rate for a specific tier
     * @param tier The tier to update (1, 2, or 3)
     * @param rate The new APY rate (e.g., 50 * PRECISION for 50%)
     */
    function updateTierAPY(Tier tier, uint256 rate) external onlyOwner {
        require(tier >= Tier.Tier1 && tier <= Tier.Tier3, "Invalid tier");

        // Update the current rate for the tier
        if (tier == Tier.Tier1) {
            tier1APY = rate;
        } else if (tier == Tier.Tier2) {
            tier2APY = rate;
        } else {
            tier3APY = rate;
        }

        // Add to history for this specific tier
        tierAPYHistory[tier].push(APYPeriod({rate: rate, startTime: block.timestamp}));

        emit APYUpdated(tier, rate, block.timestamp);
    }

    /**
     * @notice Update all tier APY rates at once
     * @param _tier1APY APY for tier 1
     * @param _tier2APY APY for tier 2
     * @param _tier3APY APY for tier 3
     */
    function updateAllAPYs(uint256 _tier1APY, uint256 _tier2APY, uint256 _tier3APY) external onlyOwner {
        // Update all rates
        tier1APY = _tier1APY;
        tier2APY = _tier2APY;
        tier3APY = _tier3APY;

        uint256 currentTime = block.timestamp;

        // Add to history for each tier
        tierAPYHistory[Tier.Tier1].push(APYPeriod({rate: _tier1APY, startTime: currentTime}));
        tierAPYHistory[Tier.Tier2].push(APYPeriod({rate: _tier2APY, startTime: currentTime}));
        tierAPYHistory[Tier.Tier3].push(APYPeriod({rate: _tier3APY, startTime: currentTime}));

        emit APYUpdated(Tier.Tier1, _tier1APY, currentTime);
        emit APYUpdated(Tier.Tier2, _tier2APY, currentTime);
        emit APYUpdated(Tier.Tier3, _tier3APY, currentTime);
    }

    /**
     * @notice Deposit tokens to be used as rewards
     * @param amount Amount to deposit
     */
    function depositRewards(uint256 amount) external whenNotPaused nonReentrant {
        require(amount > 0, "Cannot deposit zero amount");

        // Update rewards reserve
        rewardsReserve += amount;

        // Transfer tokens from sender to contract
        require(stakingToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");

        emit RewardsDeposited(msg.sender, amount);
    }

    /**
     * @notice Emergency withdraw rewards in case of shutdown (only admin)
     * @param amount Amount to withdraw
     */
    function withdrawRewards(uint256 amount) external onlyOwner {
        require(amount > 0, "Cannot withdraw zero amount");
        require(amount <= rewardsReserve, "Insufficient rewards");

        rewardsReserve -= amount;

        // Transfer tokens to admin
        require(stakingToken.transfer(owner(), amount), "Token transfer failed");
    }

    /// @notice - Only owner can pause the contract ops
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice - Only owner can unpause the contract ops
    function unPause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Set the minimum stake amount
     * @param amount The new minimum stake amount
     */
    function setMinStakeAmount(uint256 amount) external onlyOwner {
        minStakeAmount = amount;
    }

    /**
     * @notice Set the compounding status
     * @param status The new compounding status
     */
    function setCompoundingStatus(bool status) external onlyOwner {
        compoundingEnabled = status;
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the user's current tier
     * @param userAddr User address
     * @return The user's tier (1, 2, or 3)
     */
    function getCurrentTier(address userAddr) public view returns (Tier) {
        UserInfo memory user = users[userAddr];

        // If user has unstaked, permanently tier 3
        if (user.outOfTree) {
            return Tier.Tier3;
        }

        // If not active or below minimum stake, tier 3
        if (!user.isActive || (!user.isFirstDepositMoreThanMinStake && user.balance < minStakeAmount)) {
            return Tier.Tier3;
        }

        // Get user's rank from the tree
        uint256 rank = stakerTree.query(user.joinId);

        // Compute tier based on rank
        return _computeTierByRank(rank, stakerCountInTree);
    }

    /**
     * @notice Get the APY rate for a user
     * @param userAddr User address
     * @return APY rate for the user
     */
    function getUserAPY(address userAddr) public view returns (uint256) {
        Tier tier = getCurrentTier(userAddr);

        if (tier == Tier.Tier1) {
            return tier1APY;
        } else if (tier == Tier.Tier2) {
            return tier2APY;
        } else {
            return tier3APY;
        }
    }

    /**
     * @notice Calculate unclaimed interest for a user
     * @param userAddr User address
     * @return totalInterest Total unclaimed interest
     */
    function calculateUnclaimedInterest(address userAddr) public view returns (uint256 totalInterest) {
        UserInfo memory user = users[userAddr];

        // Return stored interest if no balance
        if (user.balance == 0) return user.interestEarned;

        // Start with stored interest
        totalInterest = user.interestEarned;

        // Get the user's tier history
        TierEvent[] storage userTierHistory = stakerTierHistory[userAddr];

        if (userTierHistory.length == 0) return totalInterest;

        uint256 fromTime = user.lastClaimTime;
        uint256 toTime = block.timestamp;

        // Find the tier the user was in at fromTime
        Tier currentTier = Tier.Tier3; // Default tier if no history
        uint256 relevantStartIndex = 0;

        // Find the most recent tier event before fromTime
        for (uint256 i = 0; i < userTierHistory.length; i++) {
            if (userTierHistory[i].timestamp <= fromTime) {
                currentTier = userTierHistory[i].to;
                relevantStartIndex = i;
            } else {
                break;
            }
        }

        // Process tier periods starting from the relevant tier
        uint256 periodStart = fromTime;
        uint256 periodEnd;

        // First handle the tier the user was in at fromTime
        if (
            relevantStartIndex + 1 < userTierHistory.length
                && userTierHistory[relevantStartIndex + 1].timestamp < toTime
        ) {
            periodEnd = userTierHistory[relevantStartIndex + 1].timestamp;
        } else {
            periodEnd = toTime;
        }

        // Calculate interest for this initial period
        if (periodEnd > periodStart) {
            uint256 apy = getTierAPYForPeriod(currentTier, periodStart, periodEnd);
            uint256 periodInterest =
                ((user.balance * apy * (periodEnd - periodStart)) / (SECONDS_IN_YEAR * PRECISION)) / 100;
            totalInterest += periodInterest;
        }

        // Then process any subsequent tier changes within our calculation window
        for (uint256 i = relevantStartIndex + 1; i < userTierHistory.length; i++) {
            if (userTierHistory[i].timestamp >= toTime) break;

            periodStart = userTierHistory[i].timestamp;
            periodEnd = (i == userTierHistory.length - 1) ? toTime : userTierHistory[i + 1].timestamp;
            if (periodEnd > toTime) periodEnd = toTime;

            if (periodEnd <= periodStart) continue;

            Tier periodTier = userTierHistory[i].to;
            uint256 apy = getTierAPYForPeriod(periodTier, periodStart, periodEnd);

            uint256 periodInterest =
                ((user.balance * apy * (periodEnd - periodStart)) / (SECONDS_IN_YEAR * PRECISION)) / 100;
            totalInterest += periodInterest;
        }
        return totalInterest;
    }

    /**
     * @notice Get tier counts
     * @return tier1Count Number of tier 1 stakers
     * @return tier2Count Number of tier 2 stakers
     * @return tier3Count Number of tier 3 stakers
     */
    function getTierCounts() public view returns (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count) {
        return getTierCountForStakerCount(stakerCountInTree);
    }

    function getTierCountForStakerCount(uint256 stakerCount)
        public
        pure
        returns (uint256 tier1Count, uint256 tier2Count, uint256 tier3Count)
    {
        // Calculate tier 1 count (20% of active stakers)
        tier1Count = (stakerCount * TIER1_PERCENTAGE) / 100;

        // Ensure at least 1 staker in tier 1 if there are any active stakers
        if (tier1Count == 0 && stakerCount > 0) {
            tier1Count = 1;
        }

        // Calculate remaining stakers after tier 1
        uint256 remainingAfterTier1 = stakerCount > tier1Count ? stakerCount - tier1Count : 0;

        // Calculate tier 2 count (30% of total active stakers, but don't exceed remaining)
        uint256 calculatedTier2Count = (stakerCount * TIER2_PERCENTAGE) / 100;

        if (calculatedTier2Count == 0 && remainingAfterTier1 > 0) {
            tier2Count = 1;
        } else {
            tier2Count = calculatedTier2Count > remainingAfterTier1 ? remainingAfterTier1 : calculatedTier2Count;
        }

        // Tier 3 is everyone else
        tier3Count = stakerCount > (tier1Count + tier2Count) ? stakerCount - tier1Count - tier2Count : 0;

        return (tier1Count, tier2Count, tier3Count);
    }

    /**
     * @notice Get user staking information
     * @param userAddr User address
     * @return balance Current staked balance
     * @return tier Current tier
     * @return apy Current APY rate
     * @return pendingRewards Unclaimed rewards
     */
    function getUserInfo(address userAddr)
        external
        view
        returns (uint256 balance, Tier tier, uint256 apy, uint256 pendingRewards)
    {
        UserInfo memory user = users[userAddr];

        return (user.balance, getCurrentTier(userAddr), getUserAPY(userAddr), calculateUnclaimedInterest(userAddr));
    }

    /**
     * @notice Get the APY rate for a specific tier during a time period
     * @param tier The tier to get the APY for
     * @param startTime Start time of the period
     * @param endTime End time of the period
     * @return Weighted average APY rate for the tier during this period
     */
    function getTierAPYForPeriod(Tier tier, uint256 startTime, uint256 endTime) public view returns (uint256) {
        require(startTime < endTime, "Invalid time period");
        require(tier >= Tier.Tier1 && tier <= Tier.Tier3, "Invalid tier");

        // Get APY history for this tier
        APYPeriod[] storage apyPeriods = tierAPYHistory[tier];

        // If no history, return current rate
        if (apyPeriods.length == 0) {
            if (tier == Tier.Tier1) return tier1APY;
            else if (tier == Tier.Tier2) return tier2APY;
            else return tier3APY;
        }

        // Handle case when startTime is before first recorded APY
        if (startTime < apyPeriods[0].startTime) {
            startTime = apyPeriods[0].startTime;
            if (startTime >= endTime) return apyPeriods[0].rate;
        }

        // Find all applicable APY periods
        uint256 totalDuration = 0;
        uint256 weightedSum = 0;

        for (uint256 i = 0; i < apyPeriods.length; i++) {
            // Get current period
            APYPeriod memory period = apyPeriods[i];

            // Skip periods completely before our period of interest
            if (i < apyPeriods.length - 1 && apyPeriods[i + 1].startTime <= startTime) continue;

            // Period start is max of period.startTime and our startTime
            uint256 periodStart = (period.startTime > startTime) ? period.startTime : startTime;

            // Period end is min of next period start and our endTime
            uint256 periodEnd;
            if (i < apyPeriods.length - 1) {
                periodEnd = (apyPeriods[i + 1].startTime < endTime) ? apyPeriods[i + 1].startTime : endTime;
            } else {
                periodEnd = endTime;
            }

            // Skip if period has no duration
            if (periodEnd <= periodStart) continue;

            // Calculate duration of this sub-period
            uint256 duration = periodEnd - periodStart;
            totalDuration += duration;

            // Add weighted contribution to sum
            weightedSum += period.rate * duration;

            // If we've reached the end of our period, we're done
            if (periodEnd >= endTime) break;
        }

        // Return weighted average (or 0 if no duration)
        if (totalDuration == 0) return 0;
        return weightedSum / totalDuration;
    }

    /**
     * @notice Get the length of the tier history for a user
     * @param user The address of the user
     * @return The length of the tier history
     */
    function stakerTierHistoryLength(address user) external view returns (uint256) {
        return stakerTierHistory[user].length;
    }

    /**
     * @notice Get the length of the tier APY history for a tier
     * @param tier The tier to get the length of the APY history for
     * @return The length of the APY history
     */
    function getTierAPYHistoryLength(Tier tier) external view returns (uint256) {
        return tierAPYHistory[tier].length;
    }

    /**
     * @notice Get the total stakers count
     * @return The total stakers count
     */
    function getTotalStakersCount() external view returns (uint256) {
        return stakerCountInTree + stakerCountOutOfTree;
    }

    function getCumulativeFrequency(uint256 rank) external view returns (uint256) {
        return stakerTree.findByCumulativeFrequency(rank);
    }

    /*//////////////////////////////////////////////////////////////
                        UI DATA PROVIDERS
    //////////////////////////////////////////////////////////////*/
    function getAllInfoOfUser(address userAddr)
        external
        view
        returns (UserInfo memory user, Tier tier, uint256 apy, uint256 pendingRewards, TierEvent[] memory tierHistory)
    {
        user = users[userAddr];
        tier = getCurrentTier(userAddr);
        apy = getUserAPY(userAddr);
        pendingRewards = calculateUnclaimedInterest(userAddr);
        tierHistory = stakerTierHistory[userAddr];
    }

    function getAllStakingInfo()
        external
        view
        returns (
            uint256 _totalStaked,
            uint256 _stakerCountInTree,
            uint256 _stakerCountOutOfTree,
            uint256 _rewardsReserve,
            uint256 _minStakeAmount,
            uint256 _tier1Count,
            uint256 _tier2Count,
            uint256 _tier3Count
        )
    {
        (_tier1Count, _tier2Count, _tier3Count) = getTierCountForStakerCount(stakerCountInTree);

        return (
            totalStaked,
            stakerCountInTree,
            stakerCountOutOfTree,
            rewardsReserve,
            minStakeAmount,
            _tier1Count,
            _tier2Count,
            _tier3Count
        );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _stake(uint256 amount, address userAddr, bool isNative) internal {
        require(amount > 0, "Cannot stake zero amount");

        UserInfo storage user = users[userAddr];

        // Update interest before changing balance
        _updateInterest(userAddr);

        // Transfer tokens from user to contract
        if (!isNative) {
            require(stakingToken.transferFrom(userAddr, address(this), amount), "Token transfer failed");
        } else {
            IWETH(address(stakingToken)).deposit{value: amount}();
        }

        Tier tier = Tier.Tier3;

        //Staking for first time and amount is less than minStakeAmount, user will be in tier 3 permanently and out of the tree
        if (!user.isActive && amount < minStakeAmount) {
            stakerCountOutOfTree++;
            user.isActive = true;
            user.outOfTree = true;
            _recordTierChange(userAddr, tier);
        }

        // If first time staking, register staker position whose stake is more than minStakeAmount
        if (!user.isActive && amount >= minStakeAmount) {
            user.joinId = nextJoinId++;
            stakerTree.update(user.joinId, 1);
            stakerAddress[user.joinId] = userAddr;
            user.isActive = true;
            stakerCountInTree++;

            uint256 rank = stakerTree.query(user.joinId);
            tier = _computeTierByRank(rank, stakerCountInTree);
            user.isFirstDepositMoreThanMinStake = true;

            _recordTierChange(userAddr, tier);
            _checkBoundariesAndRecord(false);
        }

        // Update user balances
        user.balance += amount;
        user.lastClaimTime = block.timestamp;

        // Update total staked
        totalStaked += amount;

        emit Staked(userAddr, amount, tier);
    }

    function _unstake(uint256 amount, address userAddr) internal {
        UserInfo storage user = users[userAddr];

        // require(user.isActive, "No active stake");
        require(user.balance >= amount, "Insufficient balance");
        // Update interest before changing balance
        _updateInterest(userAddr);

        // Update user balances
        user.balance -= amount;
        user.lastClaimTime = block.timestamp;

        // Update total staked
        totalStaked -= amount;

        if (!user.outOfTree && user.balance < minStakeAmount) {
            // execute this before removing from tree, this will make sure to calculate interest
            //for amount left after unstake
            _recordTierChange(userAddr, Tier.Tier3);
            stakerTree.update(user.joinId, -1);
            stakerCountInTree--;
            user.outOfTree = true;
            stakerCountOutOfTree++;
            _checkBoundariesAndRecord(true);
        }

        // Add unstake request instead of immediate transfer
        unstakeRequests[userAddr].push(UnstakeRequest({amount: amount, timestamp: block.timestamp, completed: false}));

        emit UnstakedQueued(userAddr, unstakeRequests[userAddr].length - 1, amount);
    }

    function _completeUnstake(address userAddr, uint256 index, bool isNative) internal {
        UnstakeRequest[] storage requests = unstakeRequests[userAddr];
        require(index < requests.length, "Invalid unstake request index");

        UnstakeRequest storage request = requests[index];
        require(!request.completed, "Unstake request already completed");
        require(block.timestamp >= request.timestamp + UNSTAKE_WINDOW, "Unstaking window not reached");

        request.completed = true;

        // Transfer tokens back to user
        if (!isNative) {
            require(stakingToken.transfer(userAddr, request.amount), "Token transfer failed");
        } else {
            IWETH(address(stakingToken)).withdraw(request.amount);
            (bool success,) = payable(userAddr).call{value: request.amount}("");
            require(success, "Unstake native transfer failed");
        }

        emit Unstaked(userAddr, request.amount);
    }

    function _claimInterest(address userAddr, bool isNative) internal {
        _updateInterest(userAddr);

        UserInfo storage user = users[userAddr];
        uint256 claimable = user.interestEarned;

        require(claimable > 0, "Nothing to claim");

        // Check if we have enough rewards in the contract
        require(rewardsReserve >= claimable, "Insufficient rewards in contract");

        user.lastClaimTime = block.timestamp;
        user.interestEarned = 0;
        user.totalClaimed += claimable;

        // Update rewards reserve
        rewardsReserve -= claimable;

        // Transfer tokens to user
        if (!isNative) {
            require(stakingToken.transfer(userAddr, claimable), "Token transfer failed");
        } else {
            IWETH(address(stakingToken)).withdraw(claimable);
            (bool success,) = payable(userAddr).call{value: claimable}("");
            require(success, "Claim interest native transfer failed");
        }

        emit RewardClaimed(userAddr, claimable);
    }

    /**
     * @notice Update user's interest
     * @param userAddr User address
     */
    function _updateInterest(address userAddr) internal {
        users[userAddr].interestEarned = calculateUnclaimedInterest(userAddr);
    }

    function _recordTierChange(address user, Tier newTier) internal {
        // Get current tier
        Tier old = Tier.Tier3;

        if (stakerTierHistory[user].length > 0) {
            old = stakerTierHistory[user][stakerTierHistory[user].length - 1].to;
        }

        // If this is the same tier as before, no change to record
        if (
            stakerTierHistory[user].length > 0
                && stakerTierHistory[user][stakerTierHistory[user].length - 1].to == newTier
        ) return;

        uint256 currentTime = block.timestamp;

        //push event - ensure neither from nor to is Tier.None
        stakerTierHistory[user].push(TierEvent({from: old, to: newTier, timestamp: currentTime}));

        users[user].lastTimeTierChanged = currentTime;

        emit TierChanged(user, newTier);
    }

    function _checkBoundariesAndRecord(bool isRemoval) internal {
        // recompute thresholds
        uint256 n = stakerCountInTree;
        uint256 oldN = isRemoval ? n + 1 : n - 1;

        // old and new thresholds
        (uint256 old_t1, uint256 old_t2,) = getTierCountForStakerCount(oldN);
        (uint256 new_t1, uint256 new_t2,) = getTierCountForStakerCount(n);

        // Tier 1 boundary handling
        if (new_t1 != 0) {
            if (new_t1 != old_t1) {
                // Need to update all users between the old and new boundaries
                if (new_t1 > old_t1) {
                    // Promotion case: update all users from old_t1+1 to new_t1
                    for (uint256 rank = old_t1 + 1; rank <= new_t1; rank++) {
                        _findAndRecordTierChange(rank, n);
                    }
                } else {
                    // Demotion case: update all users from new_t1+1 to old_t1
                    for (uint256 rank = new_t1 + 1; rank <= old_t1; rank++) {
                        _findAndRecordTierChange(rank, n);
                    }
                }
            }
            // Handle case where Tier 1 count stays the same
            else if (isRemoval && new_t1 > 0) {
                _findAndRecordTierChange(new_t1, n);
            } else if (!isRemoval) {
                _findAndRecordTierChange(old_t1, n);
            }
        }

        // Tier 2 boundary handling
        if (new_t1 + new_t2 > 0) {
            if (new_t2 != old_t2) {
                // Need to update all users between the old and new tier 2 boundaries
                uint256 old_boundary = old_t1 + old_t2;
                uint256 new_boundary = new_t1 + new_t2;

                if (new_boundary > old_boundary) {
                    // Promotion case: update all users from old_boundary+1 to new_boundary
                    for (uint256 rank = old_boundary + 1; rank <= new_boundary; rank++) {
                        _findAndRecordTierChange(rank, n);
                    }
                } else {
                    // Demotion case: update all users from new_boundary+1 to old_boundary
                    for (uint256 rank = new_boundary + 1; rank <= old_boundary; rank++) {
                        _findAndRecordTierChange(rank, n);
                    }
                }
            }
            // Handle case where Tier 2 count stays the same
            else if (isRemoval) {
                _findAndRecordTierChange(new_t1 + new_t2, n);
            } else if (!isRemoval) {
                _findAndRecordTierChange(old_t1 + old_t2, n);
            }
        }
    }

    /**
     * @notice Find the user at a given rank and record the tier change
     * @param rank The rank of the user
     * @param _stakerCountInTree The total number of stakers
     */
    function _findAndRecordTierChange(uint256 rank, uint256 _stakerCountInTree) internal {
        uint256 joinIdCross = stakerTree.findByCumulativeFrequency(rank);
        address userCross = stakerAddress[joinIdCross];
        uint256 _rank = stakerTree.query(joinIdCross);
        Tier toTier = _computeTierByRank(_rank, _stakerCountInTree);
        _recordTierChange(userCross, toTier);
    }

    /**
     * @notice Compute the tier for a user based on their rank and total stakers
     * @param rank The rank of the user
     * @param totalStakers The total number of stakers
     * @return The tier of the user
     */
    function _computeTierByRank(uint256 rank, uint256 totalStakers) internal pure returns (Tier) {
        if (rank == 0 || rank > totalStakers) return Tier.Tier3;
        (uint256 tier1Count, uint256 tier2Count,) = getTierCountForStakerCount(totalStakers);
        if (rank <= tier1Count) return Tier.Tier1;
        else if (rank <= tier1Count + tier2Count) return Tier.Tier2;
        return Tier.Tier3;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
