// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IERC20Burnable is IERC20 {
    function burn(uint256 amount) external;
}

contract ZeussStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20  zeusToken;
    IERC20Burnable BurnAddress;

    uint256 public totalStaked;
    uint256 public oneYearAPY = 1000; // 1000% APY
    uint256 public sixMonthAPY = 500; // 500% APY
    uint256 public oneYearMaxAPY = 100; // Min 100% APY
    uint256 public sixMonthMaxAPY = 50; // Min 50% APY
    uint256 public constant prematureWithdrawalFee = 5; // 5% fee

    // Real-world time periods (in seconds)
    uint256 public constant stakingPeriodOneYear = 365 days;
    uint256 public constant stakingPeriodSixMonths = 182 days;
    uint256 public constant apyReductionInterval = 10 days;

    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 stakingPeriod;
        uint256 initialAPY;
        bool withdrawn;
    }

    struct StakeHistory {
        uint256 index;
        uint256 amount;
        uint256 stakingPeriod;
        bool withdrawAvailable;
        bool isWithdrawn;
        uint256 currentAPY;
        uint256 potentialReward;
    }

    mapping(address => Stake[]) public stakes;

    event Staked(address indexed user, uint256 amount, uint256 period);
    event Withdrawn(
        address indexed user,
        uint256 amount,
        uint256 reward,
        uint256 burnAmount
    );
    event EmergencyWithdrawn(
        address indexed user,
        uint256 amount,
        uint256 penalty,
        uint256 burnAmount
    );

    constructor(address _zeusToken)
        Ownable(0x2cc312F73F34BcdADa7d7589CB3074c7Dc06ebE9)
    {
        zeusToken = IERC20(_zeusToken);
        BurnAddress = IERC20Burnable(_zeusToken);
    }

    modifier onlyValidAmount(uint256 amount) {
        require(amount > 0, "Amount must be greater than 0");
        _;
    }

    modifier hasStakedTokens(address user) {
        require(stakes[user].length > 0, "No stakes found for the user");
        _;
    }

    modifier canWithdraw(uint256 stakeIndex) {
        Stake storage userStake = stakes[msg.sender][stakeIndex];
        require(!userStake.withdrawn, "Stake already withdrawn");
        require(
            block.timestamp >= userStake.startTime + userStake.stakingPeriod,
            "Staking period not over yet"
        );
        _;
    }

    modifier hasSufficientRewards(uint256 amount, uint256 period) {
        uint256 maxReward = (amount *
            ((period == stakingPeriodOneYear) ? oneYearAPY : sixMonthAPY)) /
            100;
        require(
            zeusToken.balanceOf(address(this)) >=
                totalStaked + maxReward + amount,
            "Insufficient rewards"
        );
        _;
    }

    function updateToken(IERC20 _token) external onlyOwner {
        zeusToken = IERC20(_token);
    }

    function stake(uint256 amount, uint256 period)
        external
        onlyValidAmount(amount)
        hasSufficientRewards(amount, period)
    {
        require(
            period == stakingPeriodOneYear || period == stakingPeriodSixMonths,
            "Invalid staking period"
        );

        uint256 apy = (period == stakingPeriodOneYear)
            ? oneYearAPY
            : sixMonthAPY;

        zeusToken.safeTransferFrom(msg.sender, address(this), amount);

        stakes[msg.sender].push(
            Stake({
                amount: amount,
                startTime: block.timestamp,
                stakingPeriod: period,
                initialAPY: apy,
                withdrawn: false
            })
        );

        totalStaked += amount;
        emit Staked(msg.sender, amount, period);
    }

    function withdraw(uint256 stakeIndex)
        external
        canWithdraw(stakeIndex)
        hasStakedTokens(msg.sender)
        nonReentrant
    {
        Stake storage s = stakes[msg.sender][stakeIndex];
        (uint256 reward, ) = calculateReward(stakeIndex);

        uint256 totalAmount = s.amount + reward;

        // Calculate burn fee (5% of totalAmount)
        uint256 burnAmount = (totalAmount * 5) / 100;
        uint256 userAmount = totalAmount - burnAmount;

        BurnAddress.burn(burnAmount);
        zeusToken.safeTransfer(msg.sender, userAmount);

        s.withdrawn = true;
        totalStaked -= s.amount;
        emit Withdrawn(msg.sender, userAmount, reward, burnAmount);
    }

    function prematureWithdraw(uint256 stakeIndex)
        external
        hasStakedTokens(msg.sender)
        nonReentrant
    {
        Stake storage s = stakes[msg.sender][stakeIndex];
        require(!s.withdrawn, "Already withdrawn");
        require(
            block.timestamp < s.startTime + s.stakingPeriod,
            "Use regular withdraw"
        );

        (uint256 reward, ) = calculateReward(stakeIndex);

        // Calculate penalties
        uint256 amountPenalty = (s.amount * prematureWithdrawalFee) / 100;
        uint256 rewardPenalty = (reward * prematureWithdrawalFee) / 100;

        // Calculate final amount
        uint256 totalAmount = (s.amount - amountPenalty) +
            (reward - rewardPenalty);

        // Calculate burn fee (5% of totalAmount)
        uint256 burnAmount = (totalAmount * 5) / 100;
        uint256 userAmount = totalAmount - burnAmount;

        BurnAddress.burn(burnAmount);
        zeusToken.safeTransfer(msg.sender, userAmount);
        s.withdrawn = true;
        totalStaked -= s.amount;

        emit EmergencyWithdrawn(
            msg.sender,
            userAmount,
            amountPenalty + rewardPenalty,
            burnAmount
        );
    }

    function calculateReward(uint256 stakeIndex)
        internal
        view
        returns (uint256, uint256)
    {
        Stake memory s = stakes[msg.sender][stakeIndex];
        return calculateRewardForStake(s);
    }

    function calculateRewardForStake(Stake memory s)
        internal
        view
        returns (uint256, uint256)
    {
        uint256 maxAPY = s.stakingPeriod == stakingPeriodOneYear
            ? oneYearMaxAPY
            : sixMonthMaxAPY;
        uint256 elapsed = block.timestamp - s.startTime;
        uint256 remaining = elapsed;
        uint256 currentAPY = s.initialAPY;
        uint256 totalReward = 0;

        // Calculate reward for each APY interval
        while (remaining > 0 && currentAPY > maxAPY) {
            uint256 duration = remaining > apyReductionInterval
                ? apyReductionInterval
                : remaining;

            totalReward +=
                (s.amount * currentAPY * duration) /
                (s.stakingPeriod * 100);

            remaining -= duration;
            currentAPY = (currentAPY * 90e18) / 100e18; // Reduce APY by 10%
        }

        // Add remaining time at final APY
        if (remaining > 0) {
            if (currentAPY < maxAPY) currentAPY = maxAPY;
            totalReward +=
                (s.amount * currentAPY * remaining) /
                (s.stakingPeriod * 100);
        }

        // Cap reward at maximum possible
        uint256 maxPossible = (s.amount * s.initialAPY * s.stakingPeriod) /
            (s.stakingPeriod * 100);

        if (totalReward > maxPossible) totalReward = maxPossible;

        return (totalReward, currentAPY);
    }

    function getStakingHistory(address user)
        external
        view
        returns (StakeHistory[] memory)
    {
        Stake[] memory userStakes = stakes[user];
        StakeHistory[] memory history = new StakeHistory[](userStakes.length);

        for (uint256 i = 0; i < userStakes.length; i++) {
            (uint256 reward, uint256 currentAPY) = calculateRewardForStake(
                userStakes[i]
            );

            history[i] = StakeHistory({
                index: i,
                amount: userStakes[i].amount,
                stakingPeriod: userStakes[i].stakingPeriod,
                withdrawAvailable: block.timestamp >=
                    (userStakes[i].startTime + userStakes[i].stakingPeriod),
                isWithdrawn: userStakes[i].withdrawn,
                currentAPY: currentAPY,
                potentialReward: reward
            });
        }
        return history;
    }

    // Admin functions
    function updateAPY(uint256 newOneYearAPY, uint256 newSixMonthAPY)
        external
        onlyOwner
    {
        oneYearAPY = newOneYearAPY;
        sixMonthAPY = newSixMonthAPY;
    }

    function withdrawUnsoldTokens(address to, uint256 amount)
        external
        onlyOwner
    {
        require(
            zeusToken.balanceOf(address(this)) >= totalStaked + amount,
            "Cannot withdraw staked tokens"
        );
        zeusToken.safeTransfer(to, amount);
    }

    function getTotalStakedByUser(address user)
        external
        view
        returns (uint256 totalStakedByUser)
    {
        Stake[] memory userStakes = stakes[user];
        totalStakedByUser = 0;

        for (uint256 i = 0; i < userStakes.length; i++) {
            if (!userStakes[i].withdrawn) {
                totalStakedByUser += userStakes[i].amount;
            }
        }

        return totalStakedByUser;
    }

    function getTotalRewardPool() external view returns (uint256) {
        return zeusToken.balanceOf(address(this)) - totalStaked;
    }
}
