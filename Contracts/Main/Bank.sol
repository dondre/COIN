pragma solidity ^0.4.18;
import './Privileged.sol';
import './CoinvestToken.sol';

/**
 * @title Bank
 * @dev Bank holds all user funds so Investment contract can easily be replaced.
**/

contract Bank is Privileged {
    CoinvestToken coinvestToken; // Coinvest token that this fund will hold.

/** ********************************* Default *********************************** **/
    
    /**
     * @param _coinvestToken address of the Coinvest token.
    **/
    function Bank(address _coinvestToken)
      public
    {
        coinvestToken = CoinvestToken(_coinvestToken);
    }
    
    /**
     * @dev ERC223 Compatibility for our Coinvest token.
    **/
    function tokenFallback(address, uint, bytes)
      public
      view
    {
        require(msg.sender == address(coinvestToken));
    }

/** ****************************** Only Investment ****************************** **/
    
    /**
     * @dev Investment contract needs to be able to disburse funds to users.
     * @param _to Address to send funds to.
     * @param _value Amount of funds to send to _to.
    **/
    function transfer(address _to, uint256 _value)
      external
      onlyPrivileged
    returns (bool success)
    {
       assert(coinvestToken.transfer(_to, _value));
       return true;
    }
    
}
