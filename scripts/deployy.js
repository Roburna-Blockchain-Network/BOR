const hre = require("hardhat");

async function main() {
  
  this.Farm = await ethers.getContractFactory("BorFarm")
  this.Tresuary = await ethers.getContractFactory("FarmTresuary")
  this.Rewardwallet = await ethers.getContractFactory("RewardWallet")

  let iridium = "0xeDa2628c9c94BF16af7DC7CD1058d140ceEb9d25"
  const router = "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"
  const pair = '0xca747D0B0dead46101CeAcE376D9B29e2816E576'
  const farm = '0x5106856af775B808e8443841ac58BE410C71ce35'

  

  

 

  this.rewardwallet = await this.Rewardwallet.deploy(iridium, farm)
  await this.rewardwallet.deployed()

  
  
  
  console.log(this.rewardwallet.address, 'rewardwallet')
  


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});