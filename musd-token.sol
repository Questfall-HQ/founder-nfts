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
        keccak256(
            "TransferWithAuthorization("
                "address from,"
                "address to,"
                "uint256 value,"
                "uint256 validAfter,"
                "uint256 validBefore,"
                "bytes32 nonce"
            ")"
        );

    // Track used authorizations: authorizer => nonce => used
    mapping(address => mapping(bytes32 => bool)) public authorizationState;

    // Events
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    constructor() ERC20("Mock USD Coin", "USDC") EIP712("Mock USD Coin", "2")  {
        _mint(msg.sender, 1_000_000 * 10**6); 
    }

    // Testing helper functions
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function faucet() external {
        _mint(msg.sender, 1_000_000 * 10**6); // 1,000,000 USDC for testing
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

        // Execute the transfer - NO ALLOWANCE INVOLVED
        super._transfer(from, to, value);

        emit AuthorizationUsed(from, nonce);
    }

   
}