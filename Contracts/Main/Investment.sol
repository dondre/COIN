pragma solidity ^0.4.20;
import './SafeMathLib.sol';
import './Privileged.sol';
import './CoinvestToken.sol';
import './Bank.sol';

/**
 * @dev This contract accepts COIN deposit with a list of every crypto in desired portfolio
 * @dev (and the % of each) stores this information, then disburses withdrawals when requested
 * @dev in COIN depending on the new price of the coins in the portfolio
**/

contract SimpleInvestment is Privileged {
    using SafeMathLib for uint256;

    Bank bank;
    CoinvestToken token;
    
    // Brokers that are allowed to buy and sell for customers. They can NOT take money,
    // but can mess around with investments so trust is necessary. Only Coinvest to start.
    mapping (address => bool) public allowedBrokers;
    
    // Address => array with index as cryptoId and value as amount held.
    mapping (address => uint256[11]) public userHoldings;

    // Info of all crpytos by unique index
    mapping (uint256 => CryptoAsset) public cryptoAssets;

    struct CryptoAsset
    {
        string name;                // Symbol of the crypto
        uint256 price;              // In USD * 10^18
        uint256 decimals;           // Number of decimal places the crypto has
    }

    event Buy(address indexed buyer, uint256[] cryptoIds, uint256[] amounts, uint256[11] indexed prices, address indexed broker);
    event Sell(address indexed seller, uint256[] cryptoIds, uint256[] amounts, uint256[11] indexed prices, address indexed broker);
    event PriceChange(uint256 indexed cryptoId, uint256 price);

/** ********************************** Defaults ************************************* **/
    
    /**
     * @dev Constructor function, construct with coinvest token.
     * @param _token The address of the Coinvest token.
    **/
    function SimpleInvestment(address _token, address _bank)
      public
    {
        token = CoinvestToken(_token);
        bank = Bank(_bank);
        initialCryptos();
    }
    
    /**
     * @dev ERC223 Compatibility for our Coinvest token.
    **/
    function tokenFallback(address, uint, bytes)
      public
      view
    {
        require(msg.sender == address(token));
    }
  
/** ********************************** External ************************************* **/
    
    /**
     * @dev Broker will call this for an investor to invest in one or multiple assets
     * @param _beneficiary The address that is being bought for
     * @param _cryptoIds The list of uint IDs for each crypto to buy
     * @param _amounts The amounts of each crypto to buy (measured in COIN wei!)
    **/
    function buy(address _beneficiary, uint256[] _cryptoIds, uint256[] _amounts)
      onlyBrokerOrSender(_beneficiary)
      external
    returns (bool success)
    {
        require(_cryptoIds.length == _amounts.length);
        
        uint256 investAmount;
        for (uint256 i = 0; i < _cryptoIds.length; i++)
        {
            uint256 cryptoId = _cryptoIds[i];
            uint256 amount = _amounts[i];
            require(cryptoAssets[cryptoId].price > 0 && amount > 0);
            
            // Add crypto amounts to user Holdings
            // SafeMath prevents (unlikely) overflow
            userHoldings[_beneficiary][cryptoId] = userHoldings[_beneficiary][cryptoId].add(amount);
            
            // Keep track of the COIN value of the investment to later accept as payment
            investAmount = investAmount.add(calculateCoinValue(cryptoId, amount));
        }
        uint256 fee = 4990000000000000000 * (10 ** 18) / cryptoAssets[0].price;
        
        assert(token.transferFrom(_beneficiary, owner, fee));
        assert(token.transferFrom(_beneficiary, bank, investAmount));
        
        emit Buy(_beneficiary, _cryptoIds, _amounts, returnPrices(), msg.sender);
        return true;
    }
    
    /**
     * @dev Broker will call this for an investor to sell one or multiple assets.
     * @dev Broker has the ability to sell whenever--trust, yes--terrible, no.
     * @dev Can fix this by having a user approve a sale, but this saves gas.
     * @param _beneficiary The address that is being sold for
     * @param _cryptoIds The list of uint IDs for each crypto
     * @param _amounts The amounts of each crypto to sell (measured in COIN wei!)
    **/
    function sell(address _beneficiary, uint256[] _cryptoIds, uint256[] _amounts)
      onlyBrokerOrSender(_beneficiary)
      external
    returns (bool success)
    {
        require(_cryptoIds.length == _amounts.length);
        
        uint256 withdrawAmount;
        for (uint256 i = 0; i < _cryptoIds.length; i++)
        {
            uint256 cryptoId = _cryptoIds[i];
            uint256 amount = _amounts[i];
            require(cryptoAssets[cryptoId].price > 0 && amount > 0);
            
            // SafeMath sub ensures underflow safety
            userHoldings[_beneficiary][cryptoId] = userHoldings[_beneficiary][cryptoId].sub(amount);
            
            // Keep track of the COIN value of the investment to later accept as payment
            withdrawAmount = withdrawAmount.add(calculateCoinValue(cryptoId, amount));
        }
        uint256 fee = 4990000000000000000 * (10 ** 18) / cryptoAssets[0].price;
        require(withdrawAmount > fee);
        
        assert(bank.transfer(owner, fee));
        assert(bank.transfer(_beneficiary, withdrawAmount - fee));
        
        emit Sell(_beneficiary, _cryptoIds, _amounts, returnPrices(), msg.sender);
        return true;
    }
    
/** **************************** Constants ********************************* **/
    
    /**
     * @dev Returns an array of crypto asset IDs that the user has holdings in
     * @param _user The user whose holdings should be checked
    **/
    function coinHoldings(address _user)
      external
      view
    returns (uint256 coinValue)
    {
        for (uint256 i = 0; i < 11; i++)
        {
            uint256 holding = userHoldings[_user][i];
            if (holding > 0) {
                uint256 cryptoValue = calculateCoinValue(i, holding);
                coinValue += cryptoValue;
            }
        }
    }
    
    /**
     * @dev Frontend queries to find the cryptos and amounts of each that the user holds.
     * @param _user The address of the user to query.
     * @return amounts An array with each crypto indexed by Id and the amount held.
    **/
    function cryptoHoldings(address _user)
      external
      view
    returns (uint256[11] amounts)
    {
        return userHoldings[_user];
    }
    
    /**
     * @dev Return prices for all cryptos for frontend.
    **/
    function returnPrices()
      public
      view
    returns (uint256[11] cryptoPrices)
    {
        for (uint256 i = 0; i < 11; i++) {
            cryptoPrices[i] = cryptoAssets[i].price;
        }
    }
    
/** ********************************** Internal ************************************** **/

    /**
     * @dev Calculates how many COIN wei an amount of a crypto asset is worth.
     * @param _cryptoId The symbol of the cryptonized asset.
     * @param _amount The amount of the cryptonized asset desired.
     * @return coinAmount The value in COIN of this crypto position.
    **/
    function calculateCoinValue(uint256 _cryptoId, uint256 _amount)
      public 
      view
    returns (uint256 coinAmount)
    {
        CryptoAsset memory crypto = cryptoAssets[_cryptoId];
        uint256 currentCoinValue = cryptoAssets[0].price;
        uint256 tokenValue = crypto.price;
        
        // We must get the coinAmount in COIN "wei" so coin is made 18 decimals longer
        // eachTokenValue finds the amount of COINs 1 token is worth
        uint256 eachTokenValue = tokenValue * (10 ** 18) / currentCoinValue;
        
        // We must now find the COIN value of the desired amount of the token
        // _amount will be given in native token "wei" so we must make sure we account for that
        coinAmount = eachTokenValue * _amount / (10 ** crypto.decimals); 
        return coinAmount;
    }
    
    /**
     * @dev Run on construction so I don't need to add all these by hand.
    **/
    function initialCryptos() 
      internal 
    {
        addCrypto(0, "COIN", 10 ** 18, 18);
        addCrypto(1, "BTC", 10 ** 18, 8);
        addCrypto(2, "ETH", 10 ** 18, 18);
        addCrypto(3, "XRP", 10 ** 18, 6);
        addCrypto(4, "LTC", 10 ** 18, 8);
        addCrypto(5, "DASH", 10 ** 18, 8);
        addCrypto(6, "BCH", 10 ** 18, 8);
        addCrypto(7, "XMR", 10 ** 18, 12);
        addCrypto(8, "XEM", 10 ** 18, 6);
        addCrypto(9, "EOS", 10 ** 18, 18);
        addCrypto(10, "IBTC", 10 ** 18, 8);
    }
    
/** ********************************* Only Oracle *********************************** **/

    /**
     * @dev Oracle sets the current market price for all used cryptos.
     * @param _prices Array of the new prices for each crypto.
    **/
    function setPrices(uint256[9] _prices)
      external
      onlyPrivileged
    returns (bool success)
    {
        for (uint256 i = 0; i < 9; i++) {
            require(cryptoAssets[i + 1].price > 0);
    
            cryptoAssets[i + 1].price = _prices[i];
            emit PriceChange(i + 1, _prices[i]);
        }
        uint256 inverseBTC = (10 ** 36) / _prices[0];
        emit PriceChange(10, inverseBTC);

        return true;
    }
    
/** ********************************* Only Owner ************************************* **/
    
    /**
     * @dev Adds a new crypto for investing
     * @param _symbol Market symbol of the new crypto
     * @param _decimals How many decimal places the crypto has
     * @param _price Current market price to begin the crypto selling at
    **/
    function addCrypto(uint256 _cryptoId, string _symbol, uint256 _price, uint256 _decimals)
      onlyOwner
      public
    returns (bool success)
    {
        require(_decimals > 0 && _price > 0);
        
        CryptoAsset memory crypto = CryptoAsset(_symbol, _price, _decimals);
        cryptoAssets[_cryptoId] = crypto;
        return true;
    }
    
    /**
     * @dev Owner can either add or remove a broker from allowedBrokers.
     * @dev At the beginning this will only be the Coinvest frontend.
     * @param _broker The address of the broker whose status will be modified
     * @param _add True if the broker is being added, False if the broker is being deleted
    **/
    function modifyBroker(address _broker, bool _add)
      onlyOwner
      external
    returns (bool success)
    {
        require(_broker != 0);
        
        allowedBrokers[_broker] = _add;
        return true;
    }
    
/** ********************************* Modifiers ************************************* **/
    
    /**
     * @dev For buys and sells we only want an approved broker or the buyer/seller
     * @dev themselves to mess with the buyer/seller's portfolio
     * @param beneficiary The buyer or seller whose portfolio is being modified
    **/
    modifier onlyBrokerOrSender(address beneficiary)
    {
        require(allowedBrokers[msg.sender] || msg.sender == beneficiary);
        _;
    }
}
