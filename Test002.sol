// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract Test002 is Ownable, ERC20 {
    
    string private constant _name = "Test002";
    string private constant _symbol = "TESTV2";
    uint8 private constant _decimals = 18;

    bool public limited;
    uint256 public maxHoldingAmount;
    uint256 public minHoldingAmount;
    address public uniswapV2Pair;
    address public teamWallet;
    uint256 public taxPercentage = 20;
    uint256 public feePercentage = 10;
    uint256 public _totalSupply = 10000000 * 10**18;

    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapPair;

    mapping(address => bool) public blacklists;

    constructor() ERC20("Test002", "TESTV2") {
        _mint(msg.sender, _totalSupply);

       IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);//
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
    }

    function blacklist(address _address, bool _isBlacklisting) external onlyOwner {
        blacklists[_address] = _isBlacklisting;
    }

    function setRule(bool _limited, address _uniswapV2Pair, uint256 _maxHoldingAmount, uint256 _minHoldingAmount) external onlyOwner {
        limited = _limited;
        uniswapV2Pair = _uniswapV2Pair;
        maxHoldingAmount = _maxHoldingAmount;
        minHoldingAmount = _minHoldingAmount;
    }

    function setTaxAndFee(uint256 _taxPercentage, uint256 _feePercentage) external onlyOwner {
        require(_taxPercentage + _feePercentage <= 10, "Total tax and fee cannot exceed 10%");
        taxPercentage = _taxPercentage;
        feePercentage = _feePercentage;
    }

    function setTeamWallet(address _wallet) external onlyOwner {
        require(_wallet != address(0), "Invalid team wallet address");
        teamWallet = _wallet;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(!blacklists[to] && !blacklists[from], "Blacklisted");

        if (uniswapV2Pair == address(0)) {
            require(from == owner() || to == owner(), "Trading is not started");
            return;
        }

        if (limited && from == uniswapV2Pair) {
            require(super.balanceOf(to) + amount <= maxHoldingAmount && super.balanceOf(to) + amount >= minHoldingAmount, "Forbid");
        }
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        if (taxPercentage > 0 || feePercentage > 0) {
            uint256 taxAmount = amount * taxPercentage / 100;
            uint256 feeAmount = amount * feePercentage / 100;
            uint256 transferAmount = amount - taxAmount - feeAmount;

            super._transfer(sender, address(this), taxAmount);
            super._transfer(sender, teamWallet, feeAmount);
            super._transfer(sender, address(this), transferAmount);

            // Swap tokens to ETH
            _swapTokensForEth(address(this).balance);

            // Transfer ETH to team wallet
            uint256 ethBalance = address(this).balance;
            if (ethBalance > 0) {
                payable(teamWallet).transfer(ethBalance);
            }
        } else {
            super._transfer(sender, recipient, amount);
        }
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        approve(address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }

    function updateTaxAndFee(uint256 _taxPercentage, uint256 _feePercentage) external onlyOwner {
        require(_taxPercentage + _feePercentage <= 30, "Total tax and fee cannot exceed 30%");
        taxPercentage = _taxPercentage;
        feePercentage = _feePercentage;
    }

    function withdrawETH(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient contract balance");
        payable(teamWallet).transfer(amount);
    }
}
