// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts@5.2.0/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface TokenInterface {
    function allowance(address owner, address spender) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
    function mint(address account, uint256 amount) external;
    function transfer(address to, uint256 value) external returns (bool);    
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract DynamicStake {
    TokenInterface public myToken;
    AggregatorV3Interface public ethUsdPriceFeed;

    mapping(address => uint256) public staked;
    mapping(address => uint256) public lastClaim;

    uint256 constant DATAFEED_PRICE_DECIMALS = 8;
    uint256 constant RATE_DIVISOR = 1000000; // rewardRate 0.01% ETH price per minute, with 8 decimals 
    uint8 public tokenDecimals;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);

    constructor(address _token) {
        myToken = TokenInterface(_token);
        tokenDecimals = myToken.decimals();
        /**
        * Network: Ronin Saigon
        * Aggregator: ETH/USD
        * Other Data Feeds: https://docs.chain.link/data-feeds/price-feeds/addresses
        */
        address _priceFeedAddress = 0x798c8F5FF3dBa2B8CD95814936e1725c539d5C98;
        ethUsdPriceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    //Before stake, go to the token and Approve the amount to this contract transfer from you account
    function stake(uint256 _amount) external {
        require(_amount > 0, "Nothing to stake");
        require(myToken.allowance(msg.sender, address(this)) >= _amount, "Approve the token amount before stake");
        require(myToken.balanceOf(msg.sender) >= _amount, "Amount > token balance");

        myToken.transferFrom(msg.sender, address(this), _amount);
        claimReward();
        staked[msg.sender] += _amount;
        lastClaim[msg.sender] = block.timestamp;
        emit Staked (msg.sender, _amount);
    }

    function claimReward() public {
        uint256 reward = calculateReward(msg.sender);
        if (reward > 0) {
            myToken.mint(msg.sender, reward);
            lastClaim[msg.sender] = block.timestamp;
            emit RewardClaimed(msg.sender, reward);
        }
    }

    function getCLDataFeedLatest() public view returns (int) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = ethUsdPriceFeed.latestRoundData();
        return price;
    }

    function calculateMinutesStaked(address user) public view returns (uint256) {
        if (lastClaim[user] > 0) {
            return (block.timestamp - lastClaim[user]) / 60;
        } else {
            return 0;
        }
    }    

    function calculateReward(address user) public view returns (uint256) {
        int price = getCLDataFeedLatest();
        if (price <= 0) return 0;

        // Dynamic rate based on ETH/USD price, per minute
        uint256 rewardRate = uint256(price) / RATE_DIVISOR;
        uint256 minutesStaked = calculateMinutesStaked(user); // reward per minute
        uint256 decimalsAdjustment = 10 ** (DATAFEED_PRICE_DECIMALS - uint256(tokenDecimals));
        uint256 rewardAmount = (staked[user] * rewardRate * minutesStaked) / decimalsAdjustment;
        return rewardAmount;
    }

    function unStake() external {
        require(staked[msg.sender] > 0, "not staked");
        claimReward();
        uint256 amount = staked[msg.sender];
        staked[msg.sender] = 0;
        myToken.transfer(msg.sender, amount);
        emit Unstaked (msg.sender, amount);
    }    
}
}
