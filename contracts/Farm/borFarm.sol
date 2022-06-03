// SPDX-License-Identifier: MIT
pragma solidity ^0.8.11;

import "./IFarmTresuary.sol";
import "../Stake/IRewardWallet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract BorFarm is Ownable {

    mapping(address => uint256) public stakingBalance;
    mapping(address => bool) public isStaking;
    mapping(address => uint256) public startTime;
    mapping(address => uint256) public userRewards;
    

    uint256 rewardRate = 86400;
    uint256 oldRewardRate;
    uint256 rewardRateUpdatedTime;

    IFarmTresuary public tresuary;
    IRewardWallet public rewardWallet;
       

    IERC20 public lpToken;
    IERC20 public rewardsToken;
    

    event Stake(address indexed from, uint256 amount);
    event Unstake(address indexed from, uint256 amount);
    event RewardsWithdrawal(address indexed to, uint256 amount);
    event RewardRateUpdated(uint256 oldRate, uint256 newRate);
    event TresuaryUpdated(IFarmTresuary oldTresuary, IFarmTresuary newTresuary);
    event RewardWalletUpdated(IRewardWallet oldRewardWallet, IRewardWallet newRewardWallet);
    event LogWithdrawalBNB(address account, uint256 amount);
    event LogWithdrawToken(address token, address account, uint256 amount);


    constructor(IERC20 _lpToken, IERC20 _rewardsToken) {
        lpToken = _lpToken;
        rewardsToken = _rewardsToken;
    }

    
    function stake(uint256 amount) public {
        require(amount > 0 && lpToken.balanceOf(msg.sender) >= amount, "Incufficient LP balance");

        if(isStaking[msg.sender] == true){
            uint256 toTransfer = getTotalRewards(msg.sender);
            userRewards[msg.sender] += toTransfer;
        }

        tresuary.deposit(msg.sender, amount);
        stakingBalance[msg.sender] += amount;
        startTime[msg.sender] = block.timestamp;
        isStaking[msg.sender] = true;
        emit Stake(msg.sender, amount);
    }


    function unstake(uint256 amount) public {
        require(isStaking[msg.sender] = true && stakingBalance[msg.sender] >= amount, "Nothing to unstake");
        uint256 rewards = getTotalRewards(msg.sender);
        startTime[msg.sender] = block.timestamp;
        stakingBalance[msg.sender] -= amount;
        tresuary.withdraw(msg.sender, amount);
        userRewards[msg.sender] += rewards;
        if(stakingBalance[msg.sender] == 0){
            isStaking[msg.sender] = false;
        }
        emit Unstake(msg.sender, amount);
    }


    function getTotalTime(address user) public view returns(uint256){
        uint256 finish = block.timestamp;
        uint256 totalTime = finish - startTime[user];
        return totalTime;
    }


    function getTotalRewards(address user) public view returns(uint256) {
        uint256 newRewards = 0;
        if (stakingBalance[user] > 0) {
            if (
                block.timestamp > rewardRateUpdatedTime &&
                startTime[user] < rewardRateUpdatedTime
            ) {
                uint256 time1 = rewardRateUpdatedTime -
                    startTime[user];
                uint256 timeRate1 = (time1 * 10**18) / oldRewardRate;

                uint256 time2 = block.timestamp - rewardRateUpdatedTime;
                uint256 timeRate2 = (time2 * 10**18) /
                    rewardRate;

                newRewards =
                    (stakingBalance[user] * (timeRate1 + timeRate2)) /
                    10**18;
            } else {
                uint256 time = block.timestamp - startTime[user];
                uint256 timeRate = (time * 10**18) /
                    rewardRate;
                newRewards = (stakingBalance[user] * timeRate) / 10**18;
            }
        }
        return newRewards + userRewards[user];
        
    } 

    function setRewardRate(uint256 _rewardRate) external onlyOwner {
        emit RewardRateUpdated(rewardRate, _rewardRate);
        rewardRateUpdatedTime = block.timestamp;
        oldRewardRate = rewardRate;
        rewardRate = _rewardRate;      
    }


    function setTresuary(IFarmTresuary _tresuary) external onlyOwner {
        emit TresuaryUpdated(tresuary, _tresuary);
        tresuary = _tresuary;
    }

    function setRewardWallet(IRewardWallet _rewardWallet) external onlyOwner {
        emit RewardWalletUpdated(rewardWallet, _rewardWallet);
        rewardWallet = _rewardWallet;
    }

    function withdrawBNB(address payable account, uint256 amount) external onlyOwner {
      require(amount <= (address(this)).balance, "Incufficient funds");
      account.transfer(amount);
      emit LogWithdrawalBNB(account, amount);
    }

    /**
     * @notice Should not be withdrawn scam token.
     */
    function withdrawToken(IERC20 token, address account, uint256 amount) external onlyOwner {
      require(amount <= token.balanceOf(account), "Incufficient funds");
      require(token.transfer(account, amount), "Transfer Fail");
      emit LogWithdrawToken(address(token), account, amount);
    }

   
    function withdrawRewards() external {
        uint256 toWithdraw = getTotalRewards(msg.sender);

        require(toWithdraw > 0 || userRewards[msg.sender] > 0, "Incufficient rewards balance");
            
        uint256 oldBalance = userRewards[msg.sender];
        userRewards[msg.sender] = 0;
        toWithdraw += oldBalance;
        
        startTime[msg.sender] = block.timestamp;
        rewardWallet.transfer(msg.sender, toWithdraw);
        emit RewardsWithdrawal(msg.sender, toWithdraw);
    } 

}