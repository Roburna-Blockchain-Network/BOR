// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./token/ERC20.sol";
import "./token/ERC1363/ERC1363.sol";
import "./token/ERC2612/ERC2612.sol";
import "./token/extensions/ERC20Burnable.sol";
import "./token/extensions/ERC20TokenRecover.sol";
import "./interfaces/IDEXRouter.sol";
import "./interfaces/IDEXFactory.sol";
import "./interfaces/IDEXPair.sol";
import "./IBattlefieldOfRenegades.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IBattlefieldOfRenegadesDividendTracker.sol";


contract BattlefieldOfRenegades is ERC20, ERC1363, ERC2612, ERC20Burnable, ERC20TokenRecover, IBattlefieldOfRenegades {
    
    mapping(address => bool) public override dexRouters;
    // store addresses that are automatic market maker (dex) pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping(address => bool) public override automatedMarketMakerPairs;

    IDEXRouter public override defaultDexRouter;
    address public override defaultPair;
    

    address public immutable override RBA; 
    address public override vault1; 
    address public override vault2;
    address public override liquidityWallet;
    IBattlefieldOfRenegadesDividendTracker public override dividendTracker;

    bool public override transfersEnabled = false;
    bool private isSwappingFees;

    // Supply and amounts
    // 100 millions (this will also be the total supply as there is not public mint function)
    uint256 private _startSupply = 100000000 * (10**18);
    uint256 public override swapTokensAtAmount = 2400 * (10**18);
    uint256 public override maxWalletToken =  500000 * (10**18); // 0,5% of total supply

    // fees (from a total of 10000)
    uint256 public override buyFeesCollected = 0;
    uint256 public override buyDividendFee = 400;
    uint256 public override buyLiquidityFee = 100;
    uint256 public override buyGameVaultFee = 500;
    uint256 public override buySafetyVaultFee = 200;
    uint256 public override buyTotalFees = buyDividendFee + buyLiquidityFee + buyGameVaultFee + buySafetyVaultFee;

    uint256 public override sellFeesCollected = 0;
    uint256 public override sellDividendFee = 400;
    uint256 public override sellLiquidityFee = 100;
    uint256 public override sellGameVaultFee = 500;
    uint256 public override sellSafetyVaultFee = 200;
    uint256 public override sellTotalFees = sellDividendFee + sellLiquidityFee + sellGameVaultFee + sellSafetyVaultFee;

    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public override gasForProcessing = 300000;

    // white listed adresses (excluded from fees and dividends)
    // these addresses can also make transfers before presale is over
    mapping(address => bool) public override whitelistedAddresses;

    // exlcude from fees and max transaction amount
    mapping(address => bool) private _isExcludedFromFees;

    bool private nameChanged = false;

    constructor(
        address _routerAddress,
        address _rba,
        address _vault1,
        address _vault2
    ) ERC2612("BattlefieldOfRenegades", "BOR") {
        IDEXRouter _dexRouter = IDEXRouter(_routerAddress);
        RBA = _rba;
        vault1 = _vault1;
        liquidityWallet = owner();
        vault2 = _vault2;

        defaultDexRouter = _dexRouter;
        dexRouters[_routerAddress] = true;
        defaultPair = IDEXFactory(_dexRouter.factory()).createPair(address(this), _dexRouter.WETH());
        
        _setAutomatedMarketMakerPair(defaultPair, true);
        //_mint is an internal function in ERC20.sol that is only called here, and CANNOT be called ever again
        _mint(owner(), _startSupply);
    }

    function initializeDividendTracker(IBattlefieldOfRenegadesDividendTracker _dividendTracker) external override onlyOwner {
        require(address(dividendTracker) == address(0), "BattlefieldOfRenegades: Dividend tracker already initialized");
        dividendTracker = _dividendTracker;

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(defaultPair));
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(defaultDexRouter));

        // whitlist wallets f.e. owner wallet to send tokens before presales are over
        setWhitelistAddress(address(this), true);
        setWhitelistAddress(owner(), true);
        setWhitelistAddress(vault1, true);
    }

    receive() external payable {}

    //== BEP20 owner function ==
    function getOwner() public view override returns (address) {
        return owner();
    }

    function updateNameAndSymbol(string memory name_, string memory symbol_) external onlyOwner {
        require(!nameChanged, "BattlefieldOfRenegades: Name already changed");
        _name = name_;
        _symbol = symbol_;
        nameChanged = true;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1363, ERC2612) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function recoverERC20(address tokenAddress, uint256 tokenAmount)
        public
        override(ERC20TokenRecover, IERC20TokenRecover)
        onlyOwner
    {
        require(tokenAddress != address(this), "Cannot retrieve BattlefieldOfRenegadess");
        super.recoverERC20(tokenAddress, tokenAmount);
    }

    function setWhitelistAddress(address _whitelistAddress, bool whitelisted) public override onlyOwner {
        whitelistedAddresses[_whitelistAddress] = whitelisted;
        excludeFromFees(_whitelistAddress, whitelisted);
        if (whitelisted) {
            dividendTracker.excludeFromDividends(_whitelistAddress);
        } else {
            dividendTracker.includeInDividends(_whitelistAddress);
        }
    }

    function updateDividendTracker(address newAddress) external override onlyOwner {
        require(newAddress != address(0), "BattlefieldOfRenegades: Dividend tracker not yet initialized");
        require(newAddress != address(dividendTracker), "BattlefieldOfRenegades: The dividend tracker already has that address");

        IBattlefieldOfRenegadesDividendTracker newDividendTracker = IBattlefieldOfRenegadesDividendTracker(payable(newAddress));
        require(
            newDividendTracker.getOwner() == address(this),
            "BattlefieldOfRenegades: The new dividend tracker must be owned by the BattlefieldOfRenegades token contract"
        );

        setWhitelistAddress(address(newDividendTracker), true);
        dividendTracker = newDividendTracker;
        emit UpdateDividendTracker(newAddress, address(dividendTracker));
    }

    function addNewRouter(address _router, bool makeDefault) external override onlyOwner {
        dexRouters[_router] = true;
        dividendTracker.excludeFromDividends(_router);

        if (makeDefault) {
            emit UpdateDefaultDexRouter(_router, address(defaultDexRouter));
            defaultDexRouter = IDEXRouter(_router);
            defaultPair = IDEXFactory(defaultDexRouter.factory()).createPair(address(this), defaultDexRouter.WETH());
            _setAutomatedMarketMakerPair(defaultPair, true);
        }
    }

    function excludeFromFees(address account, bool excluded) public override onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "BattlefieldOfRenegades: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;
        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) external override onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            excludeFromFees(accounts[i], excluded);
        }
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external override onlyOwner {
        require(
            value || pair != defaultPair,
            "BattlefieldOfRenegades: The default pair cannot be removed from automatedMarketMakerPairs"
        );
        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(
            automatedMarketMakerPairs[pair] != value,
            "BattlefieldOfRenegades: Automated market maker pair is already set to that value"
        );

        automatedMarketMakerPairs[pair] = value;
        if (value && address(dividendTracker) != address(0)) dividendTracker.excludeFromDividends(pair);
        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function updateMinTokenBalance(uint256 minTokens) external override onlyOwner {
        dividendTracker.updateMinTokenBalance(minTokens);
    }

    function updateVault1(address newVault1) external override onlyOwner {
        require(newVault1 != vault1, "BattlefieldOfRenegades: The gameVault wallet is already this address");
        setWhitelistAddress(newVault1, true);
        emit vault1Updated(newVault1, vault1);
        vault1 = newVault1;
    }

    function updateVault2(address newVault2) external override onlyOwner {
        require(newVault2 != vault2, "BattlefieldOfRenegades: The safetyVault wallet is already this address");
        setWhitelistAddress(newVault2, true);
        emit vault2Updated(newVault2, vault2);
        vault2 = newVault2;
    }

    function updateLiquidityWallet(address newLiquidityWallet) external override onlyOwner {
        require(newLiquidityWallet != liquidityWallet, "BattlefieldOfRenegades: The liquidity wallet is already this address");
        setWhitelistAddress(newLiquidityWallet, true);
        emit LiquidityWalletUpdated(newLiquidityWallet, liquidityWallet);
        liquidityWallet = newLiquidityWallet;
    }

    function updateGasForProcessing(uint256 newValue) external override onlyOwner {
        require(
            newValue >= 200000 && newValue <= 500000,
            "BattlefieldOfRenegades: gasForProcessing must be between 200,000 and 500,000"
        );
        require(newValue != gasForProcessing, "BattlefieldOfRenegades: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external override onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view override returns (uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view override returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) external view override returns (bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) external view override returns (uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account) external view override returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    function getAccountDividendsInfo(address account)
        external
        view
        override
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external
        view
        override
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external override {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external override {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view override returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view override returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    /**
     * Enable or disable transfers, used before presale and on critical problems in or with the token contract
     */
    function setTransfersEnabled(bool enabled) external override onlyOwner {
        transfersEnabled = enabled;
    }

    function updateBuyFees(
        uint256 _dividendFee,
        uint256 _liquidityFee,
        uint256 _gameVaultFee,
        uint256 _safetyVaultFee
    ) external override onlyOwner {
        buyDividendFee = _dividendFee;
        buyLiquidityFee = _liquidityFee;
        buyGameVaultFee = _gameVaultFee;
        buySafetyVaultFee = _safetyVaultFee;
        buyTotalFees = buyDividendFee + buyLiquidityFee + buyGameVaultFee + buySafetyVaultFee;
        require(buyTotalFees <= 5000, "Max fee  is 50%");
    }

    function updateSellFees(
        uint256 _dividendFee,
        uint256 _liquidityFee,
        uint256 _gameVaultFee,
        uint256 _safetyVaultFee
    ) external override onlyOwner {
        sellDividendFee = _dividendFee;
        sellLiquidityFee = _liquidityFee;
        sellGameVaultFee = _gameVaultFee;
        sellSafetyVaultFee = _safetyVaultFee;
        sellTotalFees = sellDividendFee + sellLiquidityFee + sellGameVaultFee + sellSafetyVaultFee;
        require(sellTotalFees <= 5000, "Max fee is 50%");
    }

    function updateSwapTokensAtAmount(uint256 _swapTokensAtAmount) external override onlyOwner {
        require(_swapTokensAtAmount > 0, "BattlefieldOfRenegades: Amount should be higher then 0");
        require(_swapTokensAtAmount <= 10 * (10**6) * (10**18), "BattlefieldOfRenegades: Max should be at 10%");
        swapTokensAtAmount = _swapTokensAtAmount;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        // when NOT from or to owner, to safetyVault address or to dex pair
        // check if target wallet exeeds the maxWalletPAirs
        if (
            from != owner() &&
            to != owner() &&
            to != address(0) &&
            to != 0x000000000000000000000000000000000000dEaD &&
            !automatedMarketMakerPairs[to]
        ) {
            uint256 contractBalanceRecepient = balanceOf(to);
            require(
                contractBalanceRecepient + amount <= maxWalletToken,
                "BattlefieldOfRenegades: Exceeds maximum wallet token amount."
            );
        }

        // only whitelisted addresses can make transfers when transfers are disabled
        if (!transfersEnabled) {
            require(whitelistedAddresses[from], "BattlefieldOfRenegades: Transfering is disabled");
        }

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 senderBalance = balanceOf(from);
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");

        // take fee
        amount = collectFees(from, to, amount);

        if (address(dividendTracker) != address(0)) {
            try dividendTracker.setBalance(payable(from), balanceOf(from) - amount) {} catch {}
            try dividendTracker.setBalance(payable(to), balanceOf(to) + amount) {} catch {}
        }

        // swap fees before transfer has happened and after dividend balances are done
        swapFeesIfAmountIsReached(from, to);

        super._transfer(from, to, amount);

        if (address(dividendTracker) != address(0) && !isSwappingFees) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
            } catch {}
        }
    }

    function collectFees(
        address from,
        address to,
        uint256 amount
    ) private returns (uint256) {
        if (!isSwappingFees && !_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            uint256 fees;
            if (automatedMarketMakerPairs[from]) {
                fees = (amount * buyTotalFees) / 10000;
                buyFeesCollected += fees;
            } else if (automatedMarketMakerPairs[to]) {
                fees = (amount * sellTotalFees) / 10000;
                sellFeesCollected += fees;
            }

            amount = amount - fees;
            super._transfer(from, address(this), fees);
        }
        return amount;
    }

    function swapFeesIfAmountIsReached(address from, address to) private {
        uint256 contractTokenBalance = balanceOf(address(this));
        
        if (
            contractTokenBalance >= swapTokensAtAmount &&
            !isSwappingFees &&
            !automatedMarketMakerPairs[from] && // do not swap fees on buys
            from != liquidityWallet &&
            to != liquidityWallet
        ) {
            isSwappingFees = true;

            buyFeesCollected = (contractTokenBalance / (buyFeesCollected + sellFeesCollected)) * buyFeesCollected;
            sellFeesCollected = contractTokenBalance - buyFeesCollected;

            uint256 gameVaultTokens = (buyFeesCollected * buyGameVaultFee) / buyTotalFees;
            gameVaultTokens += (sellFeesCollected * sellGameVaultFee) / sellTotalFees;
            if (gameVaultTokens > 0) swapAndSendToFeeGameVault(gameVaultTokens);

            uint256 safetyVaultTokens = (buyFeesCollected * buySafetyVaultFee) / buyTotalFees;
            safetyVaultTokens += (sellFeesCollected * sellSafetyVaultFee) / sellTotalFees;
            if (safetyVaultTokens > 0) swapAndSendToFeeSafetyVault(safetyVaultTokens);


            uint256 swapTokens = (buyFeesCollected * buyLiquidityFee) / buyTotalFees;
            swapTokens = (sellFeesCollected * sellLiquidityFee) / sellTotalFees;
            if (swapTokens > 0) swapAndLiquify(swapTokens);

            uint256 sellTokens = balanceOf(address(this));
            if (sellTokens > 0) swapAndSendDividends(sellTokens);

            buyFeesCollected = 0;
            sellFeesCollected = 0;

            isSwappingFees = false;
        }
    }

    function swapAndSendToFeeGameVault(uint256 tokens) private {
        uint256 initialBNBBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBNBBalance = address(this).balance - initialBNBBalance;
        payable(vault1).transfer(newBNBBalance);
    }

    function swapAndSendToFeeSafetyVault(uint256 tokens) private {
        uint256 initialBNBBalance = address(this).balance;
        swapTokensForEth(tokens);
        uint256 newBNBBalance = address(this).balance - initialBNBBalance;
        payable(vault2).transfer(newBNBBalance);
    }

    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens / 2;
        uint256 otherHalf = tokens - half;

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance - initialBalance;

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = defaultDexRouter.WETH();

        _approve(address(this), address(defaultDexRouter), tokenAmount);

        // make the swap
        defaultDexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(defaultDexRouter), tokenAmount);

        // add the liquidity
        defaultDexRouter.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
    }

    function swapAndSendDividends(uint256 tokens) private {
        swapTokensForRBA(tokens, address(this));
        uint256 dividends = IERC20(RBA).balanceOf(address(this));
        bool success = IERC20(RBA).transfer(address(dividendTracker), dividends);

        if (success) {
            dividendTracker.distributeDividends(dividends);
            emit SendDividends(tokens, dividends);
        }
    }

    function swapTokensForRBA(uint256 tokenAmount, address recipient) private {
        // generate the uniswap pair path of weth -> RBA
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = defaultDexRouter.WETH();
        path[2] = RBA;

        _approve(address(this), address(defaultDexRouter), tokenAmount);

        // make the swap
        defaultDexRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of RBA
            path,
            recipient,
            block.timestamp
        );
    }
}