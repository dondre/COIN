pragma solidity ^0.4.15;
import './Ownable.sol';
import './CoinvestToken.sol'; 

contract ICO is Ownable {
    CoinvestToken token;
    
    uint256 public max_contribution = 50 ether; // Whale protection: 50 ETH max deposit
    uint256 public min_contribution = 1 ether / 1000; // Minnow protection: 0.001 ETH min deposit
    
    uint256 public start_block; // Starting block of the crowdsale, accepts funds ON this block
    uint256 public end_block; // Ending block of the crowdsale, no funds accepted on or after this block.
    uint256 public price; // Amount of tokens to be sent per each WEI(ETH) contributed.

    mapping (address => uint256) public buyers; // Keeps track of contributions from each address.
    /**
     * @notice The `price` should be calculated as follows:
     * Targeted parameters 1100 COIN for $700 USD
     * 
     * Assume ETH price = $1310 USD
     * 1310 / 700 * 1100 = 2058 
    **/
    
    /**
     * @dev Emitted when a user purchases COIN.
     * @param _owner The user who has purchase and now owns the COIN.
     * @param _amount The amount of COIN the _owner has purchased.
    **/
    event Buy(address indexed _owner, uint256 indexed _amount);

    /**
     * @dev Initialize contract.
     * @param _tokenAddress The address of the COIN token.
     * @param _start_block The block that we want the ICO to start (inclusive).
     * @param _end_block The block that we want the ICO to end (exclusive).
    **/
    function ICO(address _tokenAddress, uint256 _start_block, uint256 _end_block, uint256 _price)
      public
    {
        token = CoinvestToken(_tokenAddress);
        start_block = _start_block;
        end_block = _end_block;
        price = _price;
    }

    /**
     * @dev ERC223 compatibility.
    **/
    function tokenFallback(address, uint, bytes)
      external
      view
    {
        assert(msg.sender == address(token));
    }

    /**
     * @dev Fallback used for most purchases.
    **/
    function()
      external
      payable
    {
        purchase(msg.sender);
    }

      /**
     * @dev Main purchase function. Split from fallback to allow purchasing to another wallet.
     * @param _beneficiary The address that will receive COIN tokens.
    */
    function purchase(address _beneficiary)
      public
      payable
    {
        require(token.balanceOf(address(this)) > 0);
        require(msg.value >= min_contribution);
        require(buyers[msg.sender] < max_contribution);
        require((block.number < end_block) && (block.number >= start_block));
        require(tx.gasprice <= 50 * (10 ** 9));

        uint256 refundAmount = 0;
        uint256 etherAmount = msg.value;
        // If buyer is trying to buy more than their limit...
        if (buyers[msg.sender] + etherAmount > max_contribution) {
            refundAmount = (buyers[msg.sender] + etherAmount) - max_contribution;
            etherAmount = msg.value - refundAmount;
        }

        uint256 tokens_bought = etherAmount * price;
        // If the buyer is trying to buy more tokens than are available...
        if(token.balanceOf(address(this)) < tokens_bought)
        {
            refundAmount += etherAmount - (token.balanceOf(address(this)) / price);
            etherAmount = etherAmount - refundAmount;
            
            msg.sender.transfer(refundAmount);
            tokens_bought = token.balanceOf(address(this));
        // If buyer has paid too much but did not buy the rest of the tokens...
        } else if (refundAmount > 0) {
            msg.sender.transfer(refundAmount);
        }
        
        buyers[msg.sender] += etherAmount;
        token.transfer(_beneficiary, tokens_bought);
        Buy(_beneficiary, tokens_bought);
    }

    /**
     * @dev Set the timeframes of the crowdsale.
     * @param _start_block The block on which the crowdsale will start (inclusive).
     * @param _end_block The block at which the crowdsale will end (exclusive).
    **/
    function set_timeframes(uint256 _start_block, uint256 _end_block) 
      external
      onlyOwner
    {
        // Timeframes may only be changed before the crowdsale begins.
        require(block.number < start_block);
        
        start_block = _start_block;
        end_block = _end_block;
    }
    
    /**
     * @dev Owner may withdraw the Ether that has been used to purchase COIN.
    **/
    function withdraw_ether() 
      external
      onlyOwner
    {
        owner.transfer(this.balance);
    }
    
    /**
     * @dev Owner may withdraw any remaining tokens from the crowdsale.
    **/
    function withdraw_token() 
      external
      onlyOwner
    {
        // Tokens may only be withdrawn after crowdsale ends.
        require(block.number >= end_block);
        
        token.transfer(msg.sender, token.balanceOf(this));
    }

    /**
     * @dev Allow the owner to take ERC20 tokens off of this contract if they are accidentally sent.
    **/
    function token_escape(address _tokenContract)
      external
      onlyOwner
    {
        require(_tokenContract != address(token));
        
        CoinvestToken lostToken = CoinvestToken(_tokenContract);
        
        uint256 stuckTokens = lostToken.balanceOf(address(this));
        lostToken.transfer(owner, stuckTokens);
    }
    
    /**
     * @dev Used externally to check the address of the Coinvest token.
     * @return Address of the Coinvest token. 
    **/
    function tokenAddress() 
      external 
      view
    returns (address)
    {
        return address(token);
    }

}
