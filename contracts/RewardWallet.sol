// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract RewardWallet is Ownable {
   
   uint256 public totalDeposited; 
   address public deployer;
   IERC20 public iridium;

   event Deposit(address user, uint256 amount);
   event Withdrawal(address user, uint256 amount);
   
   constructor(IERC20 _iridium, address _stakingContract){
      deployer = _msgSender();
      iridium = _iridium;
      //transferOwnership
      transferOwnership(_stakingContract);
   }

   function deposit(uint256 amount) external{
      require(iridium.allowance(msg.sender, address(this)) >= amount, "Insufficient allowance.");
      totalDeposited += amount;
      iridium.transferFrom(msg.sender, address(this), amount);

      emit Deposit(msg.sender, amount);
   }

   function transfer(address account, uint256 amount) external onlyOwner{
      require(amount <= totalDeposited, "Insufficient funds");
      totalDeposited -= amount;
      iridium.transfer(account, amount);

      emit Withdrawal(account, amount);
   }

   function getTotalDeposited() external view returns(uint256){
      return totalDeposited;
   }
}