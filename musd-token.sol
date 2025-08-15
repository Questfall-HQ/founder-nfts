// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address approver, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed approver, address indexed spender, uint256 value);
}

contract MockUSDC is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals;
    address public owner;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor() {
        name = "Mock USD Coin";
        symbol = "MUSDC";
        decimals = 6; // USDC uses 6 decimals
        owner = msg.sender;
        
        // Mint initial supply to deployer (1 million MUSDC)
        uint256 initialSupply = 1000000 * 10**decimals;
        _totalSupply = initialSupply;
        _balances[msg.sender] = initialSupply;
        emit Transfer(address(0), msg.sender, initialSupply);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        address from = msg.sender;
        _transfer(from, to, amount);
        return true;
    }

    function allowance(address from, address spender) public view override returns (uint256) {
        return _allowances[from][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        address from = msg.sender;
        _approve(from, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    // Additional functions for testnet convenience
    
    /**
     * @dev Mint tokens to any address - useful for testing
     * @param to Address to mint tokens to
     * @param amount Amount to mint (in token units, not wei)
     */
    function mint(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "Mint to zero address");
        
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
        emit Mint(to, amount);
    }

    /**
     * @dev Public faucet function - anyone can mint up to 10,000 MUSDC per call
     */
    function faucet() public {
        uint256 faucetAmount = 10000 * 10**decimals; // 10,000 MUSDC
        
        _totalSupply += faucetAmount;
        _balances[msg.sender] += faucetAmount;
        emit Transfer(address(0), msg.sender, faucetAmount);
        emit Mint(msg.sender, faucetAmount);
    }

    /**
     * @dev Burn tokens from caller's balance
     * @param amount Amount to burn
     */
    function burn(uint256 amount) public {
        address account = msg.sender;
        require(_balances[account] >= amount, "Burn amount exceeds balance");

        _balances[account] -= amount;
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
        emit Burn(account, amount);
    }

    /**
     * @dev Transfer ownership to a new address
     * @param newOwner New owner address
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is zero address");
        owner = newOwner;
    }

    // Internal functions
    
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "Transfer amount exceeds balance");
        
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function _approve(address approver, address spender, uint256 amount) internal {
        require(approver != address(0), "Approve from zero address");
        require(spender != address(0), "Approve to zero address");

        _allowances[approver][spender] = amount;
        emit Approval(approver, spender, amount);
    }

    function _spendAllowance(address approver, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(approver, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "Insufficient allowance");
            unchecked {
                _approve(approver, spender, currentAllowance - amount);
            }
        }
    }
}