# MyToken & DynamicStake Contracts
Chainlink is a decentralized oracle network that enables smart contracts on blockchains to securely access and interact with real-world data, APIs, and external systems. Because blockchains by design can’t fetch off-chain information on their own, Chainlink “bridges” this gap by using a network of independent node operators (or “oracles”) to:

Fetch data from multiple external sources (e.g., price feeds, IoT devices, APIs)

Verify and aggregate that data off-chain

Deliver tamper-resistant inputs on-chain for consumption by smart contracts

This end-to-end decentralization prevents a single point of failure or data manipulation that centralized oracles would introduce
This repository contains two Solidity smart contracts:

1. **MyToken**: An ERC20 token with owner-controlled minting and permit functionality.
2. **DynamicStake**: A staking contract that lets users stake `MyToken`, earn dynamic rewards based on the ETH/USD price feed, and claim or unstake tokens.

---

## Table of Contents

- [Contracts](#contracts)
  - [MyToken (ERC20)](#mytoken-erc20)
  - [DynamicStake](#dynamicstake)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Deployment (Remix)](#deployment-remix)
- [Usage Examples](#usage-examples)
- [Folder Structure](#folder-structure)
- [Contributing](#contributing)
- [License](#license)

---

## Contracts

### MyToken (ERC20)

Implements a standard ERC20 token with:

- **Name**: `MyToken`
- **Symbol**: `MTK`
- **Owner-controlled minting**
- **EIP-2612 permit** (gasless approvals)

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts@5.3.0/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts@5.3.0/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts@5.3.0/access/Ownable.sol";

contract MyToken is ERC20, ERC20Permit, Ownable {
    constructor(address initialOwner)
        ERC20("MyToken", "MTK")
        ERC20Permit("MyToken")
        Ownable(initialOwner)
    {}

    /// @notice Mint new tokens to `to`. Only callable by owner.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
```

### DynamicStake

Allows users to stake `MyToken` and earn rewards dynamically based on the latest ETH/USD price from Chainlink:

- **Stake**: Users deposit `MyToken` after approving the contract.
- **Rewards**: Accrued per-minute, proportional to staked amount and ETH price.
- **Claim**: Mint reward tokens on demand.
- **Unstake**: Withdraw full stake plus accrued rewards.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts@5.2.0/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface TokenInterface {
    function allowance(address, address) external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function decimals() external view returns (uint8);
    function mint(address, uint256) external;
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}

contract DynamicStake {
    TokenInterface public myToken;
    AggregatorV3Interface public ethUsdPriceFeed;

    mapping(address => uint256) public staked;
    mapping(address => uint256) public lastClaim;

    uint256 private constant DATAFEED_DECIMALS = 8;
    uint256 private constant RATE_DIVISOR = 1e6; // adjust reward rate
    uint8 public tokenDecimals;

    event Staked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event Unstaked(address indexed user, uint256 amount);

    constructor(address tokenAddress, address priceFeedAddress) {
        myToken = TokenInterface(tokenAddress);
        ethUsdPriceFeed = AggregatorV3Interface(priceFeedAddress);
        tokenDecimals = myToken.decimals();
    }

    /// @notice Stake `amount` of MyToken (must be approved beforehand)
    function stake(uint256 amount) external {
        require(amount > 0, "Cannot stake zero");
        require(
            myToken.allowance(msg.sender, address(this)) >= amount,
            "Approve tokens first"
        );

        claimReward();
        myToken.transferFrom(msg.sender, address(this), amount);
        staked[msg.sender] += amount;
        lastClaim[msg.sender] = block.timestamp;
        emit Staked(msg.sender, amount);
    }

    /// @notice Claim accumulated rewards and reset timer
    function claimReward() public {
        uint256 reward = calculateReward(msg.sender);
        if (reward > 0) {
            myToken.mint(msg.sender, reward);
            lastClaim[msg.sender] = block.timestamp;
            emit RewardClaimed(msg.sender, reward);
        }
    }

    /// @notice Withdraw stake and pending rewards
    function unstake() external {
        require(staked[msg.sender] > 0, "No stake found");
        claimReward();

        uint256 balance = staked[msg.sender];
        staked[msg.sender] = 0;
        myToken.transfer(msg.sender, balance);
        emit Unstaked(msg.sender, balance);
    }

    /// @notice View latest ETH/USD price (8 decimals)
    function getLatestPrice() public view returns (int256) {
        (,int256 price,,,) = ethUsdPriceFeed.latestRoundData();
        return price;
    }

    /// @notice Calculate reward in tokens for `user`
    function calculateReward(address user) public view returns (uint256) {
        int256 price = getLatestPrice();
        if (price <= 0) return 0;

        uint256 minutesStaked = (block.timestamp - lastClaim[user]) / 60;
        uint256 rewardRate = uint256(price) / RATE_DIVISOR;
        uint256 adjust = 10 ** (DATAFEED_DECIMALS - uint256(tokenDecimals));

        return (staked[user] * rewardRate * minutesStaked) / adjust;
    }
}
```

---

## Prerequisites

- [Node.js](https://nodejs.org/) v12+ (optional for local testing)
- [Git](https://git-scm.com/)
- [Remix IDE](https://remix.ethereum.org)
- [MetaMask](https://metamask.io/) or another Web3 wallet
- ETH testnet funds (e.g., Goerli) for deployment

---

## Setup

1. **Clone**
   ```bash
   git clone https://github.com/<your-username>/<your-repo>.git
   cd <your-repo>
   ```

2. **Open in Remix**
   - Go to remix.ethereum.org
   - Connect your GitHub repo or manually upload `.sol` files

3. **Install OpenZeppelin & Chainlink**
   In Remix, use the **Solidity Compiler** import syntax shown above, which pulls from npm via GitHub.

---

## Deployment (Remix)

1. **Compile** each contract using Solidity `^0.8.20` (or higher).
2. **Deploy `MyToken`**:
   - Set `initialOwner` to your address.
3. **Deploy `DynamicStake`**:
   - Set `tokenAddress` to the deployed `MyToken` contract.
   - Set `priceFeedAddress` to the Chainlink ETH/USD feed on your network.
     - Example (Goerli): `0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e`
4. Confirm transactions in MetaMask.

---

## Usage Examples

```js
// After deployment, instantiate via ethers.js or web3.js:
const myToken = new ethers.Contract(
  myTokenAddress,
  MyTokenABI,
  signer
);
const stake = new ethers.Contract(
  stakeAddress,
  DynamicStakeABI,
  signer
);

// 1. Owner mints tokens:
await myToken.mint(userAddress, ethers.utils.parseUnits('1000', 18));

// 2. User approves and stakes tokens:
await myToken.connect(user).approve(stake.address, amount);
await stake.connect(user).stake(amount);

// 3. Check pending reward:
const reward = await stake.calculateReward(user.address);

// 4. Claim reward:
await stake.connect(user).claimReward();

// 5. Unstake all:
await stake.connect(user).unstake();
```

---

## Folder Structure

```
/contracts
├── MyToken.sol
└── DynamicStake.sol

README.md
```

---

## Contributing

1. Fork and clone the repo.
2. Create a feature branch: `git checkout -b feature/YourFeature`
3. Commit changes: `git commit -m "Add feature"
4. Push: `git push origin feature/YourFeature`
5. Open a Pull Request.

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

