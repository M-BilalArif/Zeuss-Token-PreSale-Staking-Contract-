// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IERC20Burnable is IERC20 {
    function burn(uint256 amount) external;
}

contract ZeussICO is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    enum PaymentType {
        USDT, //0
        USDC, //1
        FDUSD, //2
        BUSD //3
    }

    bool public saleStatus;
    mapping(PaymentType => address) public tokenAddresses;

    // Sale variables
    uint256 usdtPrice;
    IERC20 public tokenAddress;
    IERC20Burnable BurnAddress;
    uint256 saleCounter;
    uint256 soldToken;
    address public fundsRecipentAddress =
        0xc728595c1Ae60DfA2Db7F20BBFDbEf649d7c2783;

    uint256 lastPriceUpdate;
    uint256 public constant PRICE_INCREMENT_INTERVAL = 10 days;
    uint256 public constant PRICE_INCREMENT_PERCENTAGE = 20; // 20% increment

    // Raised amounts for each token
    mapping(PaymentType => uint256) private raisedAmounts;

    struct Transaction {
        uint256 timestamp;
        uint256 amountPaid;
        uint256 tokensReceived;
        uint256 pricePerToken;
    }

    mapping(address => Transaction[]) userTransactions;

    event TokenPurchased(
        address indexed user,
        uint256 amountPaid,
        uint256 tokensReceived,
        uint256 pricePerToken
    );
    event PriceUpdated(uint256 newPrice);
    event SaleStarted();
    event SaleStopped();

    constructor(address _tokenAddress, uint256 _usdtPrice)
        Ownable(0x2cc312F73F34BcdADa7d7589CB3074c7Dc06ebE9)
    {
        tokenAddress = IERC20(_tokenAddress);
        BurnAddress = IERC20Burnable(_tokenAddress);
        usdtPrice = _usdtPrice;
        setTokenAddresses();
    }

    function setTokenAddresses() internal {
        tokenAddresses[
            PaymentType.USDT
        ] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        tokenAddresses[
            PaymentType.USDC
        ] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        tokenAddresses[
            PaymentType.FDUSD
        ] = 0xc5f0f7b66764F6ec8C8Dff7BA683102295E16409;
        tokenAddresses[
            PaymentType.BUSD
        ] = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    }

    function startSale() external onlyOwner {
        require(!saleStatus, "Sale is already started");
        saleStatus = true;
        saleCounter = 0;
        lastPriceUpdate = block.timestamp;
        emit SaleStarted();
    }

    function updateSaleStatus(bool _saleStatus) external onlyOwner {
        if (saleStatus == _saleStatus) {
            return;
        }
        saleStatus = _saleStatus;
        if (saleStatus) {
            lastPriceUpdate = block.timestamp;
        }
    }

    function updateToken(IERC20 _token) external onlyOwner {
        tokenAddress = IERC20(_token);
    }

    function updateRecipentAddress(address _fundsRecipentAddress)
        external
        onlyOwner
    {
        fundsRecipentAddress = _fundsRecipentAddress;
    }

    function buy(uint256 _amount, PaymentType _pay) external {
        require(saleStatus != false, "Sale is Closed");
        address tokenAddr = tokenAddresses[_pay];
        IERC20(tokenAddr).safeTransferFrom(
            msg.sender,
            fundsRecipentAddress,
            _amount
        );
        // TokenPrice();

        (uint256 transferAmount, uint256 burnAmount) = calculateToken(_amount);
        raisedAmounts[_pay] = raisedAmounts[_pay].add(_amount);
        uint256 tokenAmount = transferAmount.add(burnAmount);
        require(
            tokenAddress.balanceOf(address(this)) >= tokenAmount,
            "Insufficient token balance"
        );

        tokenAddress.safeTransfer(msg.sender, transferAmount);
        BurnAddress.burn(burnAmount);

        soldToken = soldToken.add(tokenAmount);
        saleCounter += 1;
        userTransactions[msg.sender].push(
            Transaction({
                timestamp: block.timestamp,
                amountPaid: _amount,
                tokensReceived: transferAmount,
                pricePerToken: usdtPrice
            })
        );
        emit TokenPurchased(msg.sender, _amount, transferAmount, usdtPrice);
    }

    function calculateToken(uint256 _amount)
        public
        view
        returns (uint256 _transferAble, uint256 _burnFee)
    {
        uint256 tokenPrice = getCurrentPrice();
        uint256 amount = (_amount * 1e18) / tokenPrice;
        uint256 burnAmount = (amount * 2) / 100;
        uint256 userAmount = amount - burnAmount;
        return (userAmount, burnAmount);
    }

    function getCurrentPrice() public view returns (uint256) {
        if (!saleStatus) {
            return usdtPrice;
        }
        uint256 currentPrice = usdtPrice;
        uint256 timePassed = block.timestamp - lastPriceUpdate;
        if (timePassed >= PRICE_INCREMENT_INTERVAL) {
            uint256 intervalsPassed = timePassed / PRICE_INCREMENT_INTERVAL;
            for (uint256 i = 0; i < intervalsPassed; i++) {
                currentPrice = currentPrice.add(
                    currentPrice.mul(PRICE_INCREMENT_PERCENTAGE).div(100)
                );
            }
        }
        return currentPrice;
    }

    // function TokenPrice() internal returns (uint256) {
    //     uint256 currentPrice = getCurrentPrice();
    //     if (currentPrice > usdtPrice) {
    //         uint256 timePassed = block.timestamp - lastPriceUpdate;
    //         uint256 intervalsPassed = timePassed / PRICE_INCREMENT_INTERVAL;
    //         usdtPrice = currentPrice;
    //         lastPriceUpdate = lastPriceUpdate.add(
    //             intervalsPassed.mul(PRICE_INCREMENT_INTERVAL)
    //         );
    //     }
    //     usdtPrice = currentPrice;
    //     return usdtPrice;
    // }

    function withdrawUnSoldTokens(address _to, uint256 _amount)
        external
        onlyOwner
    {
        require(
            _amount > 0 && tokenAddress.balanceOf(address(this)) > _amount,
            "Not enough balance"
        );
        tokenAddress.safeTransfer(_to, _amount);
    }

    function getSaleInfo()
        public
        view
        returns (
            uint256 _IcoBalance,
            uint256 _saleCounter,
            uint256 _totalRaisedUSDT,
            uint256 _totalRaisedUSDC,
            uint256 _totalRaisedFDUSD,
            uint256 _totalRaisedBUSD
        )
    {
        return (
            tokenAddress.balanceOf(address(this)),
            saleCounter,
            raisedAmounts[PaymentType.USDT],
            raisedAmounts[PaymentType.USDC],
            raisedAmounts[PaymentType.FDUSD],
            raisedAmounts[PaymentType.BUSD]
        );
    }

    function tokenSold() public view returns (uint256) {
        return soldToken;
    }

    function getUserTransactionHistory(address user)
        external
        view
        returns (Transaction[] memory)
    {
        return userTransactions[user];
    }
}
