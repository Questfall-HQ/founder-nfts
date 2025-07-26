// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IFounderNFT {
    function mint(address to, uint256 rarityId, uint256 amount) external;
    function mintBatch(address to, uint256[] memory rarityIds, uint256[] memory amounts) external;
    function tiers(uint256 rarityId) external view returns (
        string memory name,
        string memory code,
        uint256 maxSupply,
        uint256 currentSupply,
        uint256 pointsNFT
    );
}

contract FounderNFTMinter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------
    // System
    // ------------------------------------------------------
    
    // Constants and State Variables
    IFounderNFT public immutable nfts;
    IERC20 public immutable usdc;
    
    // Constructor
    constructor(address initialOwner, address _nftContract, address _usdc, address[] memory _initialBoardMembers) Ownable(initialOwner) {
        require(_nftContract != address(0) && _usdc != address(0));

        nfts = IFounderNFT(_nftContract);
        usdc = IERC20(_usdc);
        
        // Add initial board members
        for (uint i = 0; i < _initialBoardMembers.length; i++) {
            boardMembers[_initialBoardMembers[i]] = true;
            boardMemberCount++;
            emit BoardMemberAdded(_initialBoardMembers[i]);
        }
    }

    // View balance
    function getContractBalance() external view returns (uint256) {
        return usdc.balanceOf(address(this));
    }

    // Rarity checker
    modifier validRarity(uint256 rarityId) {
        require(rarityId <= 5, "Invalid rarity ID");
        _;
    }
    
    // ------------------------------------------------------
    // Phase Management
    // ------------------------------------------------------
    
    // Phase events
    event PhaseStarted(uint256 indexed phaseId);
    event PhaseSupplyUpdated(uint256 indexed phaseId, uint256 indexed rarityId, uint256 newSupply);
    
    // Phase settings
    uint256 public currentPhase = 0;

    struct PhaseConfig {
        uint256[6] prices; // Prices for each rarity tier (COMMON to MYTHICAL)
        uint256[6] supply; // Max supply for each tier in this phase
        uint256[6] minted; // Current minted in this phase
    }
    mapping(uint256 => PhaseConfig) private _phases;

    // Get phase price for a given rarity
    function getPhasePrice(uint256 rarityId) public view validRarity(rarityId) returns (uint256) {
        PhaseConfig memory phase = _phases[currentPhase];
        return phase.prices[rarityId];
    }

    // Get the number of nfts already minted during the phase
    function getPhaseMinted(uint256 rarityId) public view validRarity(rarityId) returns (uint256) {
        PhaseConfig memory phase = _phases[currentPhase];
        return phase.minted[rarityId];
    }

    // Get phase supply for a given rarity
    function getPhaseSupply(uint256 rarityId) public view validRarity(rarityId) returns (uint256) {
        PhaseConfig memory phase = _phases[currentPhase];
        return phase.supply[rarityId];
    }

    // Get the amount of NFTs left for minting during current phase
    function getAvailableNFTs(uint256 rarityId) public view validRarity(rarityId) returns (uint256) {
        PhaseConfig memory phase = _phases[currentPhase];
        return phase.supply[rarityId] - phase.minted[rarityId];
    }

    // Get remaining supply from the core NFT contract
    function getRemainingSupply(uint256 rarityId) public view validRarity(rarityId) returns (uint256) {
        (, , uint256 maxSupply, uint256 currentSupply, ) = nfts.tiers(rarityId);
        return maxSupply - currentSupply;
    }

    // Start a new phase
    function startPhase(uint256[6] memory prices, uint256[6] memory supply) external onlyOwner {

        for (uint i = 0; i < 6; i++) {
            require(supply[i] <= getRemainingSupply(i), "Phase supply exceeds remaining NFT supply");
        }
        
        if (currentPhase > 0) {
            for (uint i = 0; i < 6; i++) {
                require(getAvailableNFTs(i) == 0, "Previous phase not fully minted");
                require (prices[i] > getPhasePrice(i), "New price must be higher");
            }
        }

        currentPhase++;
        _phases[currentPhase] = PhaseConfig({
            prices: prices,
            supply: supply,
            minted: [uint(0), 0, 0, 0, 0, 0]
        });
        
        emit PhaseStarted(currentPhase);
    }

    // Emergency function to update phase supply if needed (with validation)
    function updatePhaseSupply(uint256 rarityId, uint256 newSupply) external onlyOwner validRarity(rarityId) {
        require(currentPhase > 0, "No active phase");
        
        PhaseConfig storage phase = _phases[currentPhase];
        require(newSupply >= phase.minted[rarityId], "New supply less than already minted");
        require(newSupply - phase.minted[rarityId] <= getRemainingSupply(rarityId), "New supply exceeds remaining NFT supply");
        
        phase.supply[rarityId] = newSupply;
        
        emit PhaseSupplyUpdated(currentPhase, rarityId, newSupply);
    }

    // ------------------------------------------------------
    // Ambassador System
    // ------------------------------------------------------
    
    // Ambassador settings
    struct AmbassadorCode {
        address ambassador;
        uint256 discount; // 0-100 (e.g., 10 = 10%)
        uint256[6] minted;
        uint256 earned;
        uint256 raised;
    }
    mapping(string => AmbassadorCode) private _codes;
    
    // Create a new ambassador code
    function createAmbassadorCode(string memory code, address ambassador, uint256 discount) external onlyOwner {
        require(bytes(code).length > 0, "Empty code");
        require(ambassador != address(0), "Invalid ambassador address");
        require(discount <= 30, "Discount too high"); // Max 30% discount
        require(_codes[code].ambassador == address(0), "Code already exists");
        
        _codes[code] = AmbassadorCode({
            ambassador: ambassador,
            discount: discount,
            minted: [uint(0),0,0,0,0,0],
            earned: 0,
            raised: 0
        });
    }

    // Get ambassador info by the code
    function getAmbassador(string memory refCode) external view returns (AmbassadorCode memory) {
        require(bytes(refCode).length > 0, "No code provided");
        AmbassadorCode memory code = _codes[refCode];
        require(code.ambassador != address(0), "Invalid code");
        return code;
    }
    
    // ------------------------------------------------------
    // Minting Functions
    // ------------------------------------------------------
    
    // Events
    event NFTMinted(address indexed buyer, uint256 indexed rarityId, uint256 amount, uint256 paid);
    event AmbassadorRewardPaid(address indexed ambassador, uint256 amount);

    // Get current price for a particular rarity and other payment details
    function getPaymentDetails(uint256 rarityId, uint256 amount, string memory refCode) public view validRarity(rarityId) returns (uint256 payment, uint256 discount, uint256 ambassador, uint256 team) {
        require(amount > 0, "Amount must be greater than zero");
        require(getAvailableNFTs(rarityId) > 0, "No NFTs left in this phase");
        require(getAvailableNFTs(rarityId) >= amount, "Exceeds phase remaining supply");
        
        payment = getPhasePrice(rarityId) * amount;
        team = payment;
        discount = 0;
        ambassador = 0;
        
        if (bytes(refCode).length > 0) {
            AmbassadorCode storage code = _codes[refCode];
            require(code.ambassador != address(0), "Invalid code");
            require(code.discount <= 25 || code.ambassador == msg.sender, "This code is only for self-usage");

            if (code.discount < 25) {
                ambassador = (payment * (25 - code.discount)) / 100;
            }
            discount = (payment * code.discount) / 100;
        }
        payment -= discount;
        team -= ambassador;
    }

    // Particular rarity minting
    function mint(uint256 rarityId, uint256 amount, string memory refCode) external validRarity(rarityId) nonReentrant {
        
        // Get the payment details and validate the pararameters (no need for a discount value returned)
        (uint256 payment, , uint256 ambassador, uint256 team) = getPaymentDetails(rarityId, amount, refCode);
        
        // Update phase minting count
        _phases[currentPhase].minted[rarityId] += amount;
        
        // Mint NFT
        nfts.mint(msg.sender, rarityId, amount);

        // Ambassador update stats
        if (bytes(refCode).length > 0) {
            AmbassadorCode storage code = _codes[refCode];
            // Update ambassador stats 
            code.minted[rarityId] += amount;
            code.earned += ambassador;
            code.raised += team;
        }

        // Transfer USDC from user (only the final discounted price)
        usdc.safeTransferFrom(msg.sender, address(this), payment);
        // Transfer USDC to the Ambassador
        if (bytes(refCode).length > 0 && ambassador > 0) {
            AmbassadorCode storage code = _codes[refCode];
            usdc.safeTransfer(code.ambassador, ambassador);
            emit AmbassadorRewardPaid(code.ambassador, ambassador);
        }
        emit NFTMinted(msg.sender, rarityId, amount, payment);
    }
    
    // Batch minting
    function mintBatch(uint256[] memory rarityIds, uint256[] memory amounts, string memory refCode) external nonReentrant {
        require(rarityIds.length == amounts.length, "Arrays length mismatch");
        require(rarityIds.length > 0, "Empty arrays");
        
        uint256 paymentTotal = 0;
        uint256 discountTotal = 0;
        uint256 ambassadorTotal = 0;
        uint256 teamTotal = 0;
        uint256[6] memory payments = [uint(0),0,0,0,0,0];

        // Gather payment details and validate parameters
        for (uint i = 0; i < rarityIds.length; i++) {
            // Get the payment details and validate the pararameters
            (uint256 payment, uint256 discount, uint256 ambassador, uint256 team) = getPaymentDetails(rarityIds[i], amounts[i], refCode);
            paymentTotal += payment;
            discountTotal += discount;
            ambassadorTotal += ambassador;
            teamTotal += team;
            payments[rarityIds[i]] += payment;
        }
        
        // Ambassador update stats
        if (bytes(refCode).length > 0) {
            AmbassadorCode storage code = _codes[refCode];
            // Update ambassador stats 
            for (uint i = 0; i < rarityIds.length; i++) {
                code.minted[rarityIds[i]] += amounts[i];
            }
            code.earned += ambassadorTotal;
            code.raised += teamTotal;
        }
        
        // Update phase minting count
        for (uint i = 0; i < rarityIds.length; i++) {
            _phases[currentPhase].minted[rarityIds[i]] += amounts[i];
        }
        
        // Mint NFTs
        nfts.mintBatch(msg.sender, rarityIds, amounts);
        
        // Transfer USDC from user (only the final discounted price)
        usdc.safeTransferFrom(msg.sender, address(this), paymentTotal);
        
        // Transfer USDC to Ambassador
        if (bytes(refCode).length > 0 && ambassadorTotal > 0) {
            AmbassadorCode memory code = _codes[refCode];
            usdc.safeTransfer(code.ambassador, ambassadorTotal);
            emit AmbassadorRewardPaid(code.ambassador, ambassadorTotal);
        }

        // Emit events for each rarity
        for (uint i = 0; i < rarityIds.length; i++) {
            emit NFTMinted(msg.sender, rarityIds[i], amounts[i], payments[i]);
        }
    }

    // ------------------------------------------------------
    // Withdrawal System
    // ------------------------------------------------------
    
    // Events
    event WithdrawalRequested(uint256 indexed requestId, address indexed boardMember, uint256 amount, address recipient);
    event WithdrawalApproved(uint256 indexed requestId, address indexed boardMember);
    event WithdrawalBlocked(uint256 indexed requestId, address indexed boardMember);
    event WithdrawalExecuted(uint256 indexed requestId, address indexed boardMember, uint256 amount, address recipient);
    event BoardMemberAdded(address indexed member);

    // Board members for withdrawal approval
    mapping(address => bool) public boardMembers;
    uint256 public boardMemberCount = 0;
    
    // Withdrawal management
    uint256 public constant WITHDRAWAL_TIMEOUT = 7 days;
    
    struct WithdrawalRequest {
        uint256 amount;
        address recipient;
        uint256 requestTime;
        uint256 approvals;
        mapping(address => bool) hasApproved;
        bool executed;
        bool blocked;
    }
    
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    uint256 public withdrawalRequestCounter = 0;

    // Protector for only board memeber only
    modifier onlyBoardMember() {
        require(boardMembers[msg.sender], "Not a board member");
        _;
    }

    // Add a board memeber (called from constructor)
    function addBoardMember(address member) internal {
        require(!boardMembers[member], "Already a board member");
        boardMembers[member] = true;
        boardMemberCount++;
        emit BoardMemberAdded(member);
    }
    
    // Request a new withdrowal
    function requestWithdrawal(uint256 amount, address recipient) external onlyBoardMember {
        require(amount > 0, "Amount must be greater than zero");
        require(recipient != address(0), "Invalid recipient");
        require(usdc.balanceOf(address(this)) >= amount, "Insufficient balance");
        
        uint256 requestId = withdrawalRequestCounter++;
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        
        request.amount = amount;
        request.recipient = recipient;
        request.requestTime = block.timestamp;
        request.approvals = 0;
        request.executed = false;
        request.blocked = false;
        
        emit WithdrawalRequested(requestId, msg.sender, amount, recipient);
    }
    
    // Approve a withdrawal request
    function approveWithdrawal(uint256 requestId) external onlyBoardMember {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        require(!request.executed, "Already executed");
        require(!request.blocked, "Request blocked");
        require(!request.hasApproved[msg.sender], "Already approved");
        
        request.hasApproved[msg.sender] = true;
        request.approvals++;
        
        emit WithdrawalApproved(requestId, msg.sender);
        
        // If all board members approved, execute immediately
        if (request.approvals == boardMemberCount) {
            _executeWithdrawal(requestId);
        }
    }
    
    // Block a withdrawal request
    function blockWithdrawal(uint256 requestId) external onlyBoardMember {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        require(!request.executed, "Already executed");
        require(!request.blocked, "Already blocked");
        
        request.blocked = true;
        
        emit WithdrawalBlocked(requestId, msg.sender);
    }
    
    // Execute withdrawal request after timeout
    function executeWithdrawal(uint256 requestId) external {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        require(!request.executed, "Already executed");
        require(!request.blocked, "Request blocked");
        require(block.timestamp >= request.requestTime + WITHDRAWAL_TIMEOUT, "Timeout not reached");
        
        _executeWithdrawal(requestId);
    }
    
    // Actual withdrawal
    function _executeWithdrawal(uint256 requestId) internal {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        
        request.executed = true;
        usdc.safeTransfer(request.recipient, request.amount);
        
        emit WithdrawalExecuted(requestId, msg.sender, request.amount, request.recipient);
    }
}