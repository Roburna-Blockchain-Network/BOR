const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Iridium", function () {
  before(async function () {
    this.Token = await ethers.getContractFactory("Iridium")
    this.signers = await ethers.getSigners()
    this.owner = this.signers[0]
    this.vault1 = this.signers[1]
    this.vault2 = this.signers[4]
    this.alice = this.signers[2]
    this.bob = this.signers[3]
    this.provider = await ethers.provider
    this.router = await new ethers.Contract('0x10ED43C718714eb63d5aA57B78B54704E256024E', ['function addLiquidityETH(address token, uint amountTokenDesired, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity)', 'function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable returns (uint[] memory amounts)', 'function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external returns (uint[] memory amounts)', 'function swapExactTokensForETHSupportingFeeOnTransferTokens( uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline) external'], this.provider)    
    const RouterWSigner = await this.router.connect(this.owner)
    let rba = "0x72A80De6cB2C99d39139eF789c1f5E78a70345aB"
    
   
    this.token = await this.Token.deploy(this.router.address, this.vault1.address, this.vault2.address)
    await this.token.deployed()
    
    
    await this.token.approve('0x10ED43C718714eb63d5aA57B78B54704E256024E', ethers.utils.parseEther("90000"));
    await RouterWSigner.addLiquidityETH(
      this.token.address,
      ethers.utils.parseEther("90000"),
      ethers.utils.parseEther("90000"),
      ethers.utils.parseEther("200"),
      this.owner.address ,
      Math.floor(Date.now() / 1000) + 60 * 10,
      {value : ethers.utils.parseEther("200")}
    );

    await this.token.transfer(this.alice.address, ethers.utils.parseEther("90000"))
  })
  
  it("total supply = 10000000", async function () {
       
    expect(await this.token.totalSupply()).to.equal(ethers.utils.parseEther("10000000"))

  })

  it("doesn’t takes fee when transfer between wallets", async function(){
    await this.token.connect(this.alice).transfer(this.bob.address, ethers.utils.parseEther("10000"))
    expect(await this.token.balanceOf(this.alice.address)).to.equal(ethers.utils.parseEther("80000"))
    expect(await this.token.balanceOf(this.bob.address)).to.equal(ethers.utils.parseEther("10000"))
  })

  it("Make sure it updates buy/sell fees ", async function(){
    await this.token.updateBuyFees(500, 500, 500)
    await this.token.updateSellFees(500, 500, 500)

    let buyFees = await this.token.buyTotalFees()
    let sellFees = await this.token.sellTotalFees()

    console.log(buyFees)
    console.log(sellFees)
    expect(buyFees).to.equal(1500)
    expect(sellFees).to.equal(1500)
  })

  it("Check set/get functions ", async function(){


  })

  it("takes fee when buying", async function(){
     const RouterWSigner = await this.router.connect(this.owner)
     const WETH ="0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c"
     const path2 = [WETH, this.token.address]
     
     
     await this.token.approve('0x10ED43C718714eb63d5aA57B78B54704E256024E', ethers.utils.parseEther("1000000"))
     await RouterWSigner.swapExactETHForTokens(
       ethers.utils.parseEther("10"),
       path2,
       this.owner.address,
       Math.floor(Date.now() / 1000) + 60 * 10,
       {value : ethers.utils.parseEther("10")}
     )
  
     await RouterWSigner.swapExactETHForTokens(
      ethers.utils.parseEther("10"),
      path2,
      this.owner.address,
      Math.floor(Date.now() / 1000) + 60 * 10,
      {value : ethers.utils.parseEther("10")}
     )
  
  
    
     const cb = await this.token.balanceOf(this.token.address)
     const contractBal = await ethers.utils.formatEther(cb)
     await console.log(contractBal, "contract balance")

     
     
    
  })
 
  it("takes fee when selling", async function(){
    await this.token.connect(this.alice).approve('0x10ED43C718714eb63d5aA57B78B54704E256024E', ethers.utils.parseEther("10000000"));
    const RouterWSigner = await this.router.connect(this.owner)
    const WETH ="0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c"
    const path = [this.token.address,  WETH]
    await RouterWSigner.connect(this.alice).swapExactTokensForETHSupportingFeeOnTransferTokens(
      ethers.utils.parseEther("20000"),
      1,
      path,
      this.alice.address,
      Math.floor(Date.now() / 1000) + 60 * 10
    )

    await RouterWSigner.connect(this.alice).swapExactTokensForETHSupportingFeeOnTransferTokens(
      ethers.utils.parseEther("10000"),
      1,
      path,
      this.alice.address,
      Math.floor(Date.now() / 1000) + 60 * 10
    )

    

    const cb = await this.token.balanceOf(this.token.address)
    const contractBal = await ethers.utils.formatEther(cb)
    await console.log(contractBal, "contract balance")

  })

  it("Check that the fees are sent to appropriate wallets correctly", async function(){
    const RouterWSigner = await this.router.connect(this.owner)
    const WETH ="0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c"
    const path = [this.token.address,  WETH]
    
    await RouterWSigner.connect(this.alice).swapExactTokensForETHSupportingFeeOnTransferTokens(
        ethers.utils.parseEther("10000"),
        1,
        path,
        this.alice.address,
        Math.floor(Date.now() / 1000) + 60 * 10
    )
    let vault1balance = await this.vault1.getBalance()
    let vault2balance = await this.vault2.getBalance()
    console.log(vault1balance)
    console.log(vault2balance)

  })


  
  
  it("Swap from wallets that are excluded and not excluded from fee", async function(){
    const RouterWSigner = await this.router.connect(this.owner)
    const WETH ="0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c"
    const path = [this.token.address,  WETH]
    const path2 = [WETH, this.token.address]

    await RouterWSigner.swapExactTokensForETHSupportingFeeOnTransferTokens(
        ethers.utils.parseEther("10000"),
        1,
        path,
        this.owner.address,
        Math.floor(Date.now() / 1000) + 60 * 10
    )

    await RouterWSigner.connect(this.alice).swapExactETHForTokens(
        ethers.utils.parseEther("10"),
        path2,
        this.owner.address,
        Math.floor(Date.now() / 1000) + 60 * 10,
        {value : ethers.utils.parseEther("10")}
      )
  })
 
  
  it("Make sure swap and liquify works", async function(){
    const RouterWSigner = await this.router.connect(this.owner)
    const WETH ="0xbb4cdb9cbd36b01bd1cbaebf2de08d9173bc095c"
    const path = [this.token.address,  WETH]
    const path2 = [WETH, this.token.address]

    await RouterWSigner.swapExactTokensForETHSupportingFeeOnTransferTokens(
        ethers.utils.parseEther("10000"),
        1,
        path,
        this.owner.address,
        Math.floor(Date.now() / 1000) + 60 * 10
    )

    expect(await RouterWSigner.connect(this.alice).swapExactTokensForETHSupportingFeeOnTransferTokens(
        ethers.utils.parseEther("10000"),
        1,
        path,
        this.alice.address,
        Math.floor(Date.now() / 1000) + 60 * 10
    )).to.emit(this.token, "SwapAndLiquify")
    
    const cb = await this.token.balanceOf(this.token.address)
     const contractBal = await ethers.utils.formatEther(cb)
     await console.log(contractBal, "contract balance")
    
  })

});