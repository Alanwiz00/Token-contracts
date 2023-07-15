// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract Newerc1 is Ownable, ERC20 {
    using SafeMath for uint256;

    uint256 firstBlock;

    mapping(address => bool) public blacklists;
    mapping(address => uint256) private _balances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => mapping (address => uint256)) private _allowances;

    bool public inSwap = false;
    bool public tradingOpen = false;
    bool public swapEnabled = false;

    uint256 private constant _totalSupply = 10000000 * 10 ** 18;
    uint256 private _maxTxAmount = 50000 * 10 ** 18;
    uint256 private _maxWalletSize = 250000 *10 ** 18;
    uint256 private _swapTokenAT = 5000 * 10 ** 18;
    uint256 private _maxTaxSwap= 10000 * 10** 18;

    uint256 private _tFee;
    uint256 private _bTax=15;
    uint256 private _sTax=20;
    uint256 private _fBTax=2;
    uint256 private _fSTax=3;
    uint256 private _bBurn = 2;
    uint256 private _sBurn = 5;
    uint256 private _tBurn = 10;
    uint256 private _rBTaxAt=20;
    uint256 private _rSTaxAt=20;
    uint256 private _buyCount=0;
    
    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    address payable private _teamWallet;
    address payable private _marketingWallet;

    event MaxTxAmountUpdated(uint _maxTxAmount);
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() ERC20("Newerc1", "NT1") {
        _mint(msg.sender, _totalSupply);

        _teamWallet = payable(_msgSender());
        _marketingWallet = payable(0x000);
        _balances[_msgSender()] = _totalSupply;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_teamWallet] = true;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    //PRIVATE FUNCTIONS
    /**
    //THE FOLLOWING ARE PRIVATE FUNCTIONS
    // WHICH GOVERNS HOW THE ERC20 CONTRACT BEHAVES
    **/

    function approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "Transfer to zero address");
        require(amount <= _balances[msg.sender], "Insufficient balance");
        require(amount > 0, "Transfer amount must be greater than zero");

        uint256 taxAmount=0;
        if (from != owner() && to != owner()) {
            taxAmount = amount.mul((_buyCount>_rBTaxAt)?_fBTax.add(_bBurn):_bTax.add(_bBurn)).div(100);

            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _isExcludedFromFee[to] ) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");

                if (firstBlock + 3  > block.number) {
                    require(!isContract(to));
                }
                _buyCount++;
            }

            if (to != uniswapV2Pair && ! _isExcludedFromFee[to]) {
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
            }

            if(to == uniswapV2Pair && from!= address(this) ){
                taxAmount = amount.mul((_buyCount>_rSTaxAt)?_fSTax.add(_bBurn):_sTax.add(_bBurn)).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to == uniswapV2Pair && swapEnabled && contractTokenBalance>_swapTokenAT) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    takeTax(address(this).balance);
                }
            }
        }

        uint256 tBurn = taxAmount.mul(_tBurn).div(100);
        if(taxAmount>0){
            _balances[address(this)]=_balances[address(this)].add(taxAmount);
            emit Transfer(from, address(this),taxAmount.sub(tBurn));
        }
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
        ) override internal virtual {
        require(!blacklists[to] && !blacklists[from], "Blacklisted");
        
        // Check allowance
        require(amount <= super.allowance(from, address(this)), "Not enough allowance");

        if (uniswapV2Pair == address(0)) {
            require(from == owner() || to == owner(), "trading is not started");
            return;
        }
    }

    // Swap Tokens on Uniswap
    function swapTokensForEth(uint256 tokenAmount) private  {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function sendETHToFee(uint256 amount) private {
        _teamWallet.transfer(amount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    // Take Tax to Taxation Wallet
    function takeTax(uint256 amount) private {
        _teamWallet.transfer(amount);
    }
    
    //EXTERNAL FUNTIONS
    /**
    /THE FOLLOWING EXTERNAL FUNCTIONS CAN ONLY
    /BE CALLED BY THE OWNER OR AUTHORIZED ADDRESS
    **/
    // Remove limits and allow maxWalletSize == totalSupply
    function removeLimits() external onlyOwner{
        _maxTxAmount = _totalSupply;
        _maxWalletSize = _totalSupply;
        emit MaxTxAmountUpdated(_maxTxAmount);
    }
    
    // Set Final Tax Fee
    function setFee() external onlyOwner {
        _bTax = _fBTax;
        _sTax = _fSTax;
        _bBurn = _bBurn;
        _sBurn = _sBurn;
        _tBurn = _tBurn;
    }

    // Bots control
    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    // @Dev opens trading by initializing the uniswapo router
    function openTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        // Set UniswapV2 Router Configuration
        uniswapV2Router = IUniswapV2Router02(0xC532a74256D3Db42D0Bf7a0400fEFDbad7694008);
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        swapEnabled = true;
        tradingOpen = true;
        firstBlock = block.number;
    }    

    // Manually Swap Contract Fee Balance to ETH
    function manualswap() external {
        require(_msgSender() == _marketingWallet || _msgSender() == _teamWallet);
        uint256 contractBalance = balanceOf(address(this));
        swapTokensForEth(contractBalance);
    }

    // Manually Send Contract Balance to Tax Wallet
    function manualsend() external {
        require(_msgSender() == _marketingWallet || _msgSender() == _teamWallet);
        uint256 contractETHBalance = address(this).balance;
        takeTax(contractETHBalance);
    }

    // @Dev allows you to burn your tokens if you are tired of holding
    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}
