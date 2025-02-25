# Ponder Protocol

```                             
                ╭────────╮              
            ╭───────────────╮           
        ╭───────────────────────╮       
    ╭───────────────────────────────╮   
╭───────────────────────────────────────╮
    ╰───────────────────────────────╯   
        ╰───────────────────────╯       
            ╰───────────────╯           
                ╰────────╯                
```

Ponder is a decentralized exchange protocol built specifically for Bitkub Chain, featuring an innovative meme token launch platform. The protocol combines Uniswap V2's proven AMM foundation with yield farming through the KOI token and a unique fair launch mechanism.

## Core Protocol Components

### 1. Automated Market Maker (AMM)
- Constant product formula (x * y = k)
- 0.3% total trading fee split:
  - 0.25% to Liquidity Providers via k=xy formula
  - 0.05% protocol fee split between xKOI stakers (80%) and team (20%)
  - Special fee structure for launch tokens
- Time-weighted price oracle system
- Permissionless liquidity provision

### 2. xKOI Staking
- Stake KOI to receive xKOI
- 100% of protocol fees distributed via FeeDistributor contract
- Daily automatic rebasing mechanism
- Real yield from protocol revenue
- Minimum first stake requirement: 1000 KOI
- Minimum withdrawal: 0.01 KOI
- 24-hour cooldown between reward distributions

### 3. Fee Distribution System
- Dedicated FeeDistributor contract that collects, converts, and distributes fees
- All protocol fees (0.05% of trades) are:
  - Collected and aggregated by FeeDistributor
  - Converted to KOI tokens for stakers
  - Distributed to xKOI staking contract
- Holders of xKOI automatically receive their share of fees through rebasing
- Fee distribution occurs at least once per day
- Optimized batch operations for gas efficiency
- Emergency recovery functions for contract safety

## Launch Platform

The 555 Launch platform introduces a novel token launch mechanism designed to create sustainable meme token ecosystems.

### Launch Creation Process
1. Creator initiates launch with:
- Token name and symbol
- Token metadata (IPFS URI)
- Initial token supply: 555,555,555 tokens

2. Token Allocation:
- 70% (388,888,888 tokens) - Public sale contributors
- 20% (111,111,111 tokens) - Initial liquidity
- 10% (55,555,555 tokens) - Creator vesting (180 days)

### Launch Rules & Mechanics

1. Target Raise:
- Fixed at 5,555 KUB total value
- Contributions accepted in:
  - KUB (direct)
  - KOI (valued via KOI/KUB oracle)
- Maximum 20% of total value can be in KOI
- Minimum contribution: 1 KUB equivalent
- No maximum contribution per wallet

2. Time Constraints:
- Launch period: 7 days maximum
- Launches complete instantly if target is met
- All contributions refunded if target not met
- No partial fills - must reach full 5,555 KUB value

3. Pool Creation Upon Success:
- KUB contributions (example: 5,000 KUB):
  - 60% (3,000 KUB) to launch token/KUB LP
  - 20% (1,000 KUB) to KOI/KUB LP
  - 20% (1,000 KUB) allocated according to the KUB_TO_MEME_PONDER_LP constant

- KOI contributions (example: 555 KUB worth):
  - 80% to launch token/KOI LP (this is the primary source of KOI for the launch token/KOI pool)
  - 20% burned permanently

4. LP Token Distribution:
- All LP tokens locked for 180 days
- Creator receives 100% of LP tokens after lock
- No early withdrawal mechanisms
- Lock period starts from launch completion

5. Trading Begins:
- Trading enabled immediately upon pool creation
- Initial price set by pool ratios
- Special fee structure for launch tokens:
  - KUB Pairs: 0.04% protocol, 0.01% creator
  - KOI Pairs: 0.01% protocol, 0.04% creator
  - 0.25% always to LPs

### Launch Creation Rules
1. Required Parameters:
- Name and symbol cannot be empty
- Name limited to 32 characters
- Symbol limited to 8 characters
- IPFS metadata URI required
- Cannot use address(0) for any parameters

### Launch Failure Handling
1. Target not met within 7 days:
- KUB Contributions: Users must manually claim refunds using `claimRefund(launchId)`
- KOI Contributions: Users must manually claim refunds using `claimRefund(launchId)`
- Launch remains in failed state
- Creator receives nothing

2. Contract-Level Restrictions:
- Cannot start new launch if previous one exists
- Cannot contribute after deadline
- Cannot contribute if target already met
- Cannot contribute with amount that would exceed target

## Tokenomics

### KOI Token Utility
1. Launch Platform:
- Required for participating in launches
- Automatically pairs with new tokens
- Burns from launch platform activity

2. Liquidity Mining:
- Farm KOI by providing liquidity
- Boost rewards by staking KOI
- Pool-specific multipliers up to 3x

3. Protocol Fees:
- 0.05% of all trades distributed to xKOI holders
- LP rewards via 0.25% direct fee
- Launch creator incentives through fees

### Token Distribution
**Total Supply: 1,000,000,000 KOI**

- 40% (400M) - Initial Liquidity
  - KUB/KOI trading pair
  - Market depth and stability

- 40% (400M) - Community Rewards
  - Farming incentives
  - Distributed through MasterChef
  - 3.168 KOI per second emission over 4 years

- 20% (200M) - Team/Reserve (Locked)
  - 730-day (2-year) lock period via force-stake into xKOI
  - No withdrawal possible before lock period expiration
  - Automatically receives yield from protocol fees during lock

### Value Accrual Mechanisms

1. xKOI Staking:
- 100% of protocol fees (0.05% of all trades)
- Daily automatic rebasing
- Protocol-owned liquidity growth
- Minimum entry requirement of 1000 KOI for first-time stakers
- Fee distribution occurs at regular intervals via FeeDistributor

2. Launch Platform:
- KOI required for launches
- LP pair creation
- Launch token creator fees
- Automatic 20% burn of KOI contributions

3. Protocol Growth:
- Sustainable fee structure
- Deep initial liquidity
- Long-term team alignment through 2-year lock

## System Architecture

### Core Contracts

1. PonderFactory:
- Pair creation and management
- Fee collection and distribution
- Protocol configuration

2. PonderRouter:
- Trading functionality
- Liquidity management
- KKUB handling

3. FiveFiveFiveLauncher:
- Launch creation and management
- Contribution handling
- LP token generation
- Fee distribution

4. KOI Token:
- Supply management
- Team locking (730-day force-stake)
- Transfer controls
- Maximum supply cap: 1 billion KOI

5. FeeDistributor:
- Fee collection from pairs
- Pair sync and skim operations
- Batch processing for gas efficiency
- Conversion of fees to KOI
- Distribution to xKOI staking contract

6. PonderStaking:
- KOI staking for xKOI tokens
- Fee distribution via rebasing
- Team stake locking for 730 days
- Minimum entry requirement (1000 KOI)

### Integration Guide

Launch Platform Integration:
```solidity
// Create a new token launch
uint256 launchId = launcher.createLaunch(
    "Token Name",
    "SYMBOL",
    "ipfs://metadata"
);

// Contribute to launch
launcher.contribute(launchId);

// Claim vested tokens (creator)
launchToken.claimVestedTokens();

// Withdraw LP tokens (after lock period)
launcher.withdrawLP(launchId);
```

Farming Integration:
```solidity
// Stake LP tokens
masterChef.deposit(pid, amount);

// Stake KOI for boost
masterChef.boostStake(pid, amount);

// Harvest rewards
masterChef.deposit(pid, 0);

// Withdraw LP tokens
masterChef.withdraw(pid, amount);
```

Fee Distribution Integration:
```solidity
// Distribute fees from specific pairs
feeDistributor.distributePairFees([pair1, pair2, ...]);

// Convert collected fees to KOI
feeDistributor.convertFees(tokenAddress);

// Trigger fee distribution to xKOI
feeDistributor.distribute();
```

Staking Integration:
```solidity
// Stake KOI tokens for xKOI
staking.enter(amount, recipient);

// Withdraw KOI tokens (burn xKOI)
staking.leave(shareAmount);

// Claim accumulated fees without unstaking
staking.claimFees();

// Trigger reward distribution
staking.rebase();
```

## License

MIT License - see [LICENSE](LICENSE)
