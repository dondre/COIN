pragma solidity ^0.4.23;
import './CoinvestToken.sol';

contract TokenSwap {
    
    address oldToken;
    CoinvestToken newToken;

    /**
     * @param _oldToken Address of COIN V1.
     * @param _newToken Address of COIN V2.
    **/
    constructor(address _oldToken, address _newToken) 
      public 
    {
        oldToken = _oldToken;
        newToken = CoinvestToken(_newToken);
    }

    /**
     * @dev Only function. ERC223 transfer from old token to this contract calls this.
     * @param _from The address that has transferred this contract tokens.
     * @param _value The amount of tokens that have been transferred.
     * @param _data The extra data sent with transfer (should be nothing).
    **/
    function tokenFallback(address _from, uint _value, bytes _data) 
      external
    {
        require(msg.sender == oldToken);           // Ensure caller is old token contract.
        require(newToken.transfer(_from, _value)); // Transfer new tokens to sender.
    }
    
}
