// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract FounderNFT is ERC1155, Ownable {

    // ------------------------------------------------------
    // Constructor
    // ------------------------------------------------------
    constructor(address initialOwner, string memory image) ERC1155(image) Ownable(initialOwner) {
        _initRarityTiers(); // Initialize rarity tiers
    }    

    // ------------------------------------------------------
    // Contract metadata for marketplaces
    // ------------------------------------------------------
        
    string public name = "Questfall Founder NFT";
    string public symbol = "QFNFT";
    
    // ------------------------------------------------------
    // Contract settings change
    // ------------------------------------------------------
    
    // Change the uri of the NFT
    function setUri(string memory image) external onlyOwner {
        _setURI(image);
    }

    // ------------------------------------------------------
    // External minting contracts
    // ------------------------------------------------------
    
    // Minter role for external minting contract
    mapping(address => bool) public authorizedMinters;
    
    // Authorize/deauthorize minter contracts
    function setAuthorizedMinter(address minter, bool authorized) external onlyOwner {
        authorizedMinters[minter] = authorized;
    }

    // Protector for minting functions
    modifier onlyMinter() {
        require(authorizedMinters[msg.sender], "Not authorized minter");
        _;
    }

    // ------------------------------------------------------
    // Rarity tiers
    // ------------------------------------------------------

    // Rarity tiers
    enum Rarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, MYTHICAL }
    
    struct RarityTier {
        string name;           // the name of this rarity tier (common, rare...)
        string code;           // another way of representation of the rarity tier (F,E,D,C,B,A)
        uint256 maxSupply;     // total supply hard cap for this rarity tier
        uint256 currentSupply; // the current supply of this rarity tier
        uint256 pointsNFT;     // the amount of founder points per NFT of this rarity
    }
    
    // Rarity ID corresponds to rarity tier data (0=COMMON, 1=UNCOMMON, etc.)
    mapping(Rarity => RarityTier) public rarityTiers;

    // Generate rarity tiers parameters
    function _initRarityTiers() internal {
        rarityTiers[Rarity.COMMON]    = RarityTier({name: "Common",    code: "F", maxSupply: 3200, currentSupply: 0, pointsNFT:  100});
        rarityTiers[Rarity.UNCOMMON]  = RarityTier({name: "Uncommon",  code: "E", maxSupply: 1600, currentSupply: 0, pointsNFT:  224});
        rarityTiers[Rarity.RARE]      = RarityTier({name: "Rare",      code: "D", maxSupply:  800, currentSupply: 0, pointsNFT:  502});
        rarityTiers[Rarity.EPIC]      = RarityTier({name: "Epic",      code: "C", maxSupply:  400, currentSupply: 0, pointsNFT: 1126});
        rarityTiers[Rarity.LEGENDARY] = RarityTier({name: "Legendary", code: "B", maxSupply:  200, currentSupply: 0, pointsNFT: 2526});
        rarityTiers[Rarity.MYTHICAL]  = RarityTier({name: "Mythical",  code: "A", maxSupply:  100, currentSupply: 0, pointsNFT: 5666});
    }

    // Get the rarity tier info for a given rarity (storage)
    function _Tier(uint256 rarityId) view internal returns (RarityTier storage) {
        require(rarityId >= uint256(Rarity.COMMON) && rarityId <= uint256(Rarity.MYTHICAL), "Invalid rarity ID");
        return rarityTiers[Rarity(rarityId)];
    }

    // Get the rarity tier info for a given rarity (memory)
    function __Tier(uint256 rarityId) view internal returns (RarityTier memory) {
        require(rarityId >= uint256(Rarity.COMMON) && rarityId <= uint256(Rarity.MYTHICAL), "Invalid rarity ID");
        return rarityTiers[Rarity(rarityId)];
    }

    // ------------------------------------------------------
    // Minting NFTs
    // ------------------------------------------------------
    bool mintingAcitve = true;

    // Protector for minting
    modifier activeMinting() {
        require(mintingAcitve, "Minting disabled");
        _;
    }

    // Protector for trading when minting is active
    modifier allowTransfer(address to) {
        require(!mintingAcitve || to.code.length == 0, "Trading closed while minting");
        _;
    }

    // Turn the minting off
    function disableMinting() external onlyOwner activeMinting {
        for (uint i = uint(Rarity.COMMON); i <= uint(Rarity.MYTHICAL); i++) {
            RarityTier memory tier = __Tier(i);
            require(tier.currentSupply == tier.maxSupply, "There are unminted NFTs");
        }
        mintingAcitve = false;
    }

    // Public mint function - available only for authorized minters
    function mint(address to, uint256 rarityId, uint256 amount) external onlyMinter activeMinting {
        require(amount > 0, "Amount must be greater than zero");
        RarityTier storage tier = _Tier(rarityId);
        require(tier.currentSupply + amount <= tier.maxSupply, "Exceeds max supply");
        
        tier.currentSupply += amount;
        _mint(to, rarityId, amount, "");
    }
    
    // Batch mint multiple rarities
    function mintBatch(address to, uint256[] memory rarityIds, uint256[] memory amounts) external onlyMinter activeMinting {
        require(rarityIds.length == amounts.length, "Arrays length mismatch");
        require(rarityIds.length > 0, "Empty arrays");
        
        for (uint i = 0; i < rarityIds.length; i++) {
            RarityTier storage tier = _Tier(rarityIds[i]);
            require(tier.currentSupply + amounts[i] <= tier.maxSupply, "Exceeds max supply");
            tier.currentSupply += amounts[i];
        }
        
        _mintBatch(to, rarityIds, amounts, "");
    }
    
    // Mint function for the team
    function ownerMint(address to, uint256 rarityId, uint256 amount) external onlyOwner activeMinting {
        require(amount > 0, "Amount must be greater than zero");
        RarityTier storage tier = _Tier(rarityId);
        require(tier.currentSupply + amount <= tier.maxSupply, "Exceeds max supply");
        
        tier.currentSupply += amount;
        _mint(to, rarityId, amount, "");
    }

    // Secure safeTransferFrom while minting is active
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) public override allowTransfer(to) {
        super.safeTransferFrom(from, to, id, value, data);
    }

    // Secure safeBatchTransferFrom while minting is active
    function safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory values, bytes memory data) public override allowTransfer(to) {
        super.safeBatchTransferFrom(from, to, ids, values, data);
    }

    // ------------------------------------------------------
    // Burning NFTs
    // ------------------------------------------------------
    
    // Burn single NFT type
    function burn(uint256 rarityId, uint256 amount) external {
        require(!mintingAcitve, "Minting is still active");
        require(amount > 0, "Amount must be greater than zero");
        require(balanceOf(msg.sender, rarityId) >= amount, "Insufficient balance");
        RarityTier storage tier = _Tier(rarityId);
        require(tier.currentSupply >= amount, "Insufficient supply");

        tier.currentSupply -= amount;
        _burn(msg.sender, rarityId, amount);
    }

    // ------------------------------------------------------
    // Founder points
    // ------------------------------------------------------

    // Get the total amount of founder points for a given rarity
    function getPointsTotal(uint256 rarityId) public view returns (uint256) {
        RarityTier memory tier = __Tier(rarityId);
        uint points = tier.pointsNFT;
        uint count = tier.currentSupply;
        return count * points;
    }

    // Get the total amount of founder points for all rarities
    function getPointsTotal() public view returns (uint256) {
        uint sum = 0;
        for (uint i = uint(Rarity.COMMON); i <= uint(Rarity.MYTHICAL); i++) {
            sum += getPointsTotal(i);
        }
        return sum;
    }

    // Get the founder points for a given wallet address and given rarity
    function getPointsWallet(address account, uint256 rarityId) public view returns (uint256) {
        RarityTier memory tier = __Tier(rarityId);
        uint count = balanceOf(account, rarityId);
        uint points = tier.pointsNFT;
        return count * points;
    }

    // Get the founder points for a given wallet address
    function getPointsWallet(address account) public view returns (uint256) {
        uint sum = 0;
        for (uint i = uint(Rarity.COMMON); i <= uint(Rarity.MYTHICAL); i++) {
            sum += getPointsWallet(account, i);
        }
        return sum;
    }    
}