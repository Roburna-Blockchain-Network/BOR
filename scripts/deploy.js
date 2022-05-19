
const hre = require("hardhat");

async function main() {
  this.Iridium = await ethers.getContractFactory("Iridium")
  this.Staking = await ethers.getContractFactory("BorStaking")
  this.Bor = await ethers.getContractFactory("BattlefieldOfRenegades")
  this.BorDT = await ethers.getContractFactory("BattlefieldOfRenegadesDividendTracker")
  this.Tresuary = await ethers.getContractFactory("Tresuary")
  this.Rewardwallet = await ethers.getContractFactory("RewardWallet")

  let rba = "0xD39641D94A111b3FE7F7456a55095c16292F6dcc"
  const router = "0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3"
  const vault1 = '0x37EF590E0BDe413B6407Bc5c4e40C3706dEEBc86'
  const vault2 = '0xF75c0fb9f513CBF1e028095c42B359CAD362c016'

  this.iridium = await this.Iridium.deploy(router, vault1, vault2)
  await this.iridium.deployed()

  this.bor = await this.Bor.deploy(router, rba, vault1, vault2)
  await this.bor.deployed()

  this.staking = await this.Staking.deploy(this.bor.address, this.iridium.address)
  await this.staking.deployed()

  this.tresuary = await this.Tresuary.deploy(this.staking.address, this.bor.address, rba)
  await this.tresuary.deployed()

  this.rewardwallet = await this.Rewardwallet.deploy(this.iridium.address, this.staking.address)
  await this.tresuary.deployed()

  this.borDT = await this.BorDT.deploy( rba , this.bor.address)
  await this.borDT.deployed()

  console.log(this.iridium.address, 'irisium')
  console.log(this.bor.address, 'bor')
  console.log(this.staking.address, 'staking')
  console.log(this.tresuary.address, 'tresuary')
  console.log(this.rewardwallet.address, 'rewardwallet')
  console.log(this.borDT.address, 'borDT')


}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
