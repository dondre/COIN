pragma solidity ^0.4.20;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
**/
library SafeMathLib{
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }
  
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
**/
contract Ownable {
  address public owner;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) onlyOwner public {
    require(newOwner != address(0));
    emit OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}

/**
 * @dev Abstract contract for approveAndCall.
**/
contract ApproveAndCallFallBack {
    function receiveApproval(address from, uint256 tokens, address token, bytes data) public;
}

/**
 * @title Coinvest COIN Token
 * @dev ERC20 contract utilizing ERC865-ish structure (primarily 3esmit's iteration).
 * @dev to allow users to pay Ethereum fees in tokens.
 * @notice This is a pre-audit version!
**/
contract CoinvestToken is Ownable {
    using SafeMathLib for uint256;
    
    string public constant symbol = "COIN";
    string public constant name = "Coinvest COIN V2 Token";
    
    uint8 public constant decimals = 18;
    uint256 public _totalSupply = 107142857 * (10 ** 18);

    // Balances for each account
    mapping(address => uint256) balances;

    // Keeps track of the last nonce sent from user. Used for delegated functions.
    mapping (address => uint256) nonces;

    // Owner of account approves the transfer of an amount to another account
    mapping(address => mapping (address => uint256)) allowed;

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed from, address indexed spender, uint tokens);

    /**
     * @dev Set owner and beginning balance.
    **/
    function CoinvestToken()
      public
    {
        balances[msg.sender] = _totalSupply;
    }

/** ******************************** ERC20 ********************************* **/

    /**
     * @dev Transfers coins from one address to another.
     * @param _to The recipient of the transfer amount.
     * @param _amount The amount of tokens to transfer.
    **/
    function transfer(address _to, uint256 _amount) 
      public
    returns (bool success)
    {
        require(_transfer(msg.sender, _to, _amount));
        return true;
    }
    
    /**
     * @dev An allowed address can transfer tokens from another's address.
     * @param _from The owner of the tokens to be transferred.
     * @param _to The address to which the tokens will be transferred.
     * @param _amount The amount of tokens to be transferred.
    **/
    function transferFrom(address _from, address _to, uint _amount)
      public
    returns (bool success)
    {
        require(balances[_from] >= _amount && allowed[_from][msg.sender] >= _amount);

        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
        require(_transfer(_from, _to, _amount));
        return true;
    }
    
    /**
     * @dev Approves a wallet to transfer tokens on one's behalf.
     * @param _spender The wallet approved to spend tokens.
     * @param _amount The amount of tokens approved to spend.
    **/
    function approve(address _spender, uint256 _amount) 
      public
    returns (bool success)
    {
        require(_approve(msg.sender, _spender, _amount));
        return true;
    }
    
    /**
     * @dev Used to approve an address and call a function on it in the same transaction.
     * @dev _spender The address to be approved to spend COIN.
     * @dev _amount The amount of COIN to be approved to spend.
     * @dev _data The data to send to the called contract.
    **/
    function approveAndCall(address _spender, uint256 _amount, bytes _data) 
      public
    returns (bool success) 
    {
        require(_approve(msg.sender, _spender, _amount));
        ApproveAndCallFallBack(_spender).receiveApproval(msg.sender, _amount, address(this), _data);
        return true;
    }

/** ****************************** Internal ******************************** **/
    
    /**
     * @dev Internal transfer for all functions that transfer.
     * @param _from The address that is transferring coins.
     * @param _to The receiving address of the coins.
     * @param _amount The amount of coins being transferred.
    **/
    function _transfer(address _from, address _to, uint256 _amount)
      internal
    returns (bool success)
    {
        require(balances[_from] >= _amount);
        
        balances[_from] = balances[_from].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        
        emit Transfer(_from, _to, _amount);
        return true;
    }
    
    /**
     * @dev Internal approve for all functions that require an approve.
     * @param _owner The owner who is allowing spender to use their balance.
     * @param _spender The wallet approved to spend tokens.
     * @param _amount The amount of tokens approved to spend.
    **/
    function _approve(address _owner, address _spender, uint256 _amount) 
      internal
    returns (bool success)
    {
        require(balances[_owner] >= _amount);
        
        allowed[_owner][_spender] = _amount;
        emit Approval(_owner, _spender, _amount);
        return true;
    }
    
/** ************************ Delegated Functions *************************** **/

    /**
     * @dev Called by delegate with a signed hash of the transaction data to allow a user
     * @dev to transfer tokens without paying gas in Ether (they pay in COIN instead).
     * @param _signature Signed hash of data for this transfer.
     * @param _to The address to transfer COIN to.
     * @param _value The amount of COIN to transfer.
     * @param _gasPrice Price (IN COIN) that will be paid per unit of gas by user to "delegate".
     * @param _nonce Nonce of the user's new transaction.
    **/
    function transferPreSigned(
        bytes _signature,
        address _to, 
        uint256 _value, 
        uint256 _gasPrice, 
        uint256 _nonce) 
      public
    returns (bool) 
    {
        // Log starting gas left of transaction for later gas price calculations.
        uint256 gas = gasleft();
        
        // Recover signer address from signature; ensure address is valid.
        address from = recoverTransferPreSigned(_signature, _to, _value, _gasPrice, _nonce);
        require(from != address(0));
        
        // Require the nonce is exactly the next in line; increment nonce.
        require(_nonce == nonces[from] + 1);
        nonces[from]++;
        
        // Internal transfer.
        require(_transfer(from, _to, _value));

        // If the delegate is charging, pay them for gas in COIN.
        if (_gasPrice > 0) {
            
            // 35000 because of base fee of 21000 and ~14000 for the fee transfer.
            gas = 35000 + gas.sub(gasleft());
            require(_transfer(from, msg.sender, _gasPrice * gas));
        }
        
        return true;
    }
    
    /**
     * @dev Called by a delegate with signed hash to approve a transaction for user.
     * @dev All variables equivalent to transfer except _to:
     * @param _to The address that will be approved to transfer COIN from user's wallet.
    **/
    function approvePreSigned(
        bytes _signature,
        address _to, 
        uint256 _value, 
        uint256 _gasPrice, 
        uint256 _nonce) 
      public
    returns (bool) 
    {
        uint256 gas = gasleft();
        address from = recoverApprovePreSigned(_signature, _to, _value, _gasPrice, _nonce);
        require(from != address(0));
        require(_nonce == nonces[from] + 1);
        nonces[from]++;
        
        require(_approve(from, _to, _value));

        if (_gasPrice > 0) {
            gas = 35000 + gas.sub(gasleft());
            require(_transfer(from, msg.sender, _gasPrice * gas));
        }
        return true;
    }
    
    /**
     * @dev approveAndCallPreSigned allows a user to approve a contract and call a function on it
     * @dev in the same transaction. As with the other presigneds, a delegate calls this with signed data from user.
     * @dev This function is the big reason we're using gas price and calculating gas use.
     * @dev Using this with the investment contract can result in varying gas costs.
     * @param _extraData The data to send to the contract.
    **/
    function approveAndCallPreSigned(
        bytes _signature,
        address _to, 
        uint256 _value,
        bytes _extraData,
        uint256 _gasPrice, 
        uint256 _nonce) 
      public
    returns (bool) 
    {
        uint256 gas = gasleft();
        address from = recoverApproveAndCallPreSigned(_signature, _to, _value, _extraData, _gasPrice, _nonce);
        require(from != address(0));
        require(_nonce == nonces[from] + 1);
        nonces[from]++;
        
        require(_approve(from, _to, _value));
        ApproveAndCallFallBack(_to).receiveApproval(from, _value, address(this), _extraData);

        if (_gasPrice > 0) {
            gas = 35000 + gas.sub(gasleft());
            require(_transfer(from, msg.sender, _gasPrice * gas));
        }
        return true;
    }
    
/** ************************** PreSigned Constants ************************ **/

    /**
     * @dev Used in frontend and contract to get hashed data of a given transfer.
     * @param _to The address to transfer COIN to.
     * @param _value The amount of COIN to be transferred.
     * @param _gasPrice The agreed-upon amount of COIN to be paid per unit of gas.
     * @param _nonce The user's nonce of the new transaction.
    **/
    function getTransferHash(
        address _to, 
        uint256 _value, 
        uint256 _gasPrice,
        uint256 _nonce)
      public
      view
    returns (bytes32 txHash) {
        // 0x1296830d is the function signature of transferPreSigned (ensure delegate sends to correct function).
        return keccak256(address(this), bytes4(0x1296830d), _to, _value, _gasPrice, _nonce);
    }

    /**
     * @dev Same use and values as getTransferHash except _to:
     * @param _to The address to approve to spend COIN from the signing user.
    **/
    function getApproveHash(
        address _to, 
        uint256 _value, 
        uint256 _gasPrice,
        uint256 _nonce)
      public
      view
    returns (bytes32 txHash) {
        // 0x617b390b is the function signature of approvePreSigned.
        return keccak256(address(this), bytes4(0x617b390b), _to, _value, _gasPrice, _nonce);
    }
    
    /**
     * @dev Same as other get hashes but for approveAndCall so _extraData is added:
     * @param _extraData The data to include in the call to the _to contract (spender).
    **/
    function getApproveAndCallHash(
        address _to, 
        uint256 _value,
        bytes _extraData,
        uint256 _gasPrice,
        uint256 _nonce)
      public
      view
    returns (bytes32 txHash) {
        // 0xc8d4b389 is the function signature of approveAndCallPreSigned.
        return keccak256(address(this), bytes4(0xc8d4b389), _to, _value, _extraData, _gasPrice, _nonce);
    }
    
    /**
     * @dev Recovers are used internally to recover data from a signature or externally to check signed hash.
     * @param _sig The signed hash of the transaction.
     * @param _to The address to send coins to.
     * @param _value The amount of coins to send.
     * @param _gasPrice The agreed-upon amount to pay in COIN per unit of gas.
     * @param _nonce The nonce of this new transaction.
    **/
    function recoverTransferPreSigned(
        bytes _sig,
        address _to,
        uint256 _value,
        uint256 _gasPrice,
        uint256 _nonce) 
      public
      view
    returns (address recovered)
    {
        return ecrecoverFromSig(getSignHash(getTransferHash(_to, _value, _gasPrice, _nonce)), _sig);
    }
    
    /**
     * @dev Same as recoverTransferPreSigned except _to:
     * @param _to The address to approve to take COIN from user wallet.
    **/
    function recoverApprovePreSigned(
        bytes _sig,
        address _to,
        uint256 _value,
        uint256 _gasPrice,
        uint256 _nonce) 
      public
      view
    returns (address recovered)
    {
        return ecrecoverFromSig(getSignHash(getApproveHash(_to, _value, _gasPrice, _nonce)), _sig);
    }
    
    /**
     * @dev Same as recoverApprovePreSigned but with an added _extraData:
     * @param _extraData The data to include in the call to the contract being approved.
    **/
    function recoverApproveAndCallPreSigned(
        bytes _sig,
        address _to,
        uint256 _value,
        bytes _extraData,
        uint256 _gasPrice,
        uint256 _nonce) 
      public
      view
    returns (address recovered)
    {
        return ecrecoverFromSig(getSignHash(getApproveAndCallHash(_to, _value, _extraData, _gasPrice, _nonce)), _sig);
    }
    
    /**
     * @dev Add signature prefix to hash for recovery à la ERC191.
     * @param _hash The hashed transaction to add signature prefix to.
    **/
    function getSignHash(bytes32 _hash)
      public
      pure
    returns (bytes32 signHash)
    {
        return keccak256("\x19Ethereum Signed Message:\n32", _hash);
    }

    /**
     * @dev Helps to reduce stack depth problems for delegations.
     * @param hash The hash of signed data for the transaction.
     * @param sig Contains r, s, and v for recovery of address from the hash.
    **/
    function ecrecoverFromSig(bytes32 hash, bytes sig) 
      public 
      pure 
    returns (address recoveredAddress) 
    {
        bytes32 r;
        bytes32 s;
        uint8 v;
        if (sig.length != 65) return address(0);
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            // Here we are loading the last 32 bytes. We exploit the fact that 'mload' will pad with zeroes if we overread.
            // There is no 'mload8' to do this, but that would be nicer.
            v := byte(0, mload(add(sig, 96)))
        }
        // Albeit non-transactional signatures are not specified by the YP, one would expect it to match the YP range of [27, 28]
        // geth uses [0, 1] and some clients have followed. This might change, see https://github.com/ethereum/go-ethereum/issues/2053
        if (v < 27) {
          v += 27;
        }
        if (v != 27 && v != 28) return address(0);
        return ecrecover(hash, v, r, s);
    }

    /**
     * @dev Frontend queries to find the next nonce of the user so they can find the new nonce to send.
     * @param _owner Address that will be sending the COIN.
    **/
    function getNonce(address _owner)
      external
      view
    returns (uint256 nonce)
    {
        return nonces[_owner];
    }
    
/** ****************************** Constants ******************************* **/
    
    /**
     * @dev Return total supply of token.
    **/
    function totalSupply() 
      external
      view 
     returns (uint256)
    {
        return _totalSupply;
    }

    /**
     * @dev Return balance of a certain address.
     * @param _owner The address whose balance we want to check.
    **/
    function balanceOf(address _owner)
      external
      view 
    returns (uint256) 
    {
        return balances[_owner];
    }
    
    /**
     * @dev Allowed amount for a user to spend of another's tokens.
     * @param _owner The owner of the tokens approved to spend.
     * @param _spender The address of the user allowed to spend the tokens.
    **/
    function allowance(address _owner, address _spender) 
      external
      view 
    returns (uint256) 
    {
        return allowed[_owner][_spender];
    }
    
/** ***************************** Maintenance ****************************** **/
    
    /**
     * @dev Allow the owner to take ERC20 tokens off of this contract if they are accidentally sent.
    **/
    function token_escape(address _tokenContract)
      external
      onlyOwner
    {
        CoinvestToken lostToken = CoinvestToken(_tokenContract);
        
        uint256 stuckTokens = lostToken.balanceOf(address(this));
        lostToken.transfer(owner, stuckTokens);
    }
    
}
