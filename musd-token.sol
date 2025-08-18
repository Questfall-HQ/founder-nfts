// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract MockUSDC is ERC20, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    // EIP-3009 Transfer with Authorization typehash
    bytes32 private constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = 
        keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)");

    // Track used authorizations: authorizer => nonce => used
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    // Events
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    // mapping(address => uint256) private _balances;
    // mapping(address => mapping(address => uint256)) private _allowances;

    // uint256 private _totalSupply;
    // string public name;
    // string public symbol;
    // uint8 public decimals;
    // address public owner;

    // event Mint(address indexed to, uint256 amount);
    // event Burn(address indexed from, uint256 amount);

    // modifier onlyOwner() {
    //     require(msg.sender == owner, "Not the owner");
    //     _;
    // }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    constructor() ERC20("Mock USD Coin", "USDC") EIP712("Mock USD Coin", "2")  {
        // owner = msg.sender;
        _mint(msg.sender, 1_000_000 * 10**6); 
    }

    // function totalSupply() public view override returns (uint256) {
    //     return _totalSupply;
    // }

    // function balanceOf(address account) public view override returns (uint256) {
    //     return _balances[account];
    // }

    // function transfer(address to, uint256 amount) public override returns (bool) {
    //     address from = msg.sender;
    //     _transfer(from, to, amount);
    //     return true;
    // }

    // function allowance(address from, address spender) public view override returns (uint256) {
    //     return _allowances[from][spender];
    // }

    // function approve(address spender, uint256 amount) public override returns (bool) {
    //     address from = msg.sender;
    //     _approve(from, spender, amount);
    //     return true;
    // }

    // function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
    //     address spender = msg.sender;
    //     _spendAllowance(from, spender, amount);
    //     _transfer(from, to, amount);
    //     return true;
    // }

    // Additional functions for testnet convenience
    
    /**
     * @dev Mint tokens to any address - useful for testing
     * @param to Address to mint tokens to
     * @param amount Amount to mint (in token units, not wei)
     */
    // Testing helper functions
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function faucet() external {
        _mint(msg.sender, 10_000 * 10**6); // 10,000 USDC for testing
    }

    /**
     * EIP-3009: Transfer tokens with a signed authorization
     * This is the MAIN function for secure single-transaction payments
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp > validAfter, "Authorization not yet valid");
        require(block.timestamp < validBefore, "Authorization expired");
        require(!authorizationState[from][nonce], "Authorization already used");

        // Build the struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );
        
        // Create the hash to verify
        bytes32 hash = _hashTypedDataV4(structHash);

        // Recover the signer
        address signer = hash.recover(v, r, s);
        require(signer == from, "Invalid signature");

        // Mark authorization as used
        authorizationState[from][nonce] = true;
        //require(false, "before transfered");
        // Execute the transfer - NO ALLOWANCE INVOLVED
        // super._transfer(from, to, value);
        // SafeERC20.safeTransfer(IERC20(address(this)), to, value);
        // _transfer(from, to, value);
        // require(false, "safe transfered");

        emit AuthorizationUsed(from, nonce);
    }

   
}