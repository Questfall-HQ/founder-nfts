// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAuthERC20 is IERC20 {
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
    ) external;

    function safeTransfer(
        address to,
        uint256 value
    ) external returns (bool);

    function safeTransferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface IFounderNFT {
    function mint(address to, uint256 rarityId, uint256 amount) external;
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
    IAuthERC20 public immutable usdc;
    
    // Constructor
    constructor(address _nfts, address _usdc, address[] memory _members) Ownable(msg.sender) {
        require(_nfts != address(0) && _usdc != address(0));
        require(_members.length > 0, "No board members provided");

        nfts = IFounderNFT(_nfts);
        usdc = IAuthERC20(_usdc);
        
        // Add initial board members
        for (uint i = 0; i < _members.length; i++) {
            addBoardMember(_members[i]);
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
    // Discount System
    // ------------------------------------------------------
    
    // Ambassador codes
    struct AmbassadorCode {
        address ambassador;
        address manager;
        uint256 discount; // 0-100 (e.g., 10 = 10%)
        uint256[6] minted;
        uint256 earned;
        uint256 raised;
    }
    mapping(string => AmbassadorCode) private _amb_codes;
    
    // Create a new ambassador code
    function createAmbassadorCode(string memory code, address ambassador, address manager, uint256 discount) external onlyOwner {
        require(bytes(code).length > 0, "Empty code");
        require(ambassador != address(0), "Invalid ambassador address");
        require(discount <= 25, "Discount too high"); // Max 25% discount
        require(_amb_codes[code].ambassador == address(0), "Code already exists");
        
        _amb_codes[code] = AmbassadorCode({
            ambassador: ambassador,
            manager: manager,
            discount: discount,
            minted: [uint(0),0,0,0,0,0],
            earned: 0,
            raised: 0
        });
    }

    // Get ambassador info by the code
    function getAmbassador(string memory code) external view returns (AmbassadorCode memory) {
        require(bytes(code).length > 0, "No code provided");
        AmbassadorCode memory _code = _amb_codes[code];
        require(_code.ambassador != address(0), "Invalid code");
        return _code;
    }
    
    // -----------------------------------
    // Personal discout codes
    struct DiscounterCode {
        address discounter;
        uint256 discount; // 0-100 (e.g., 10 = 10%)
        uint256[6] minted;
    }
    mapping(string => DiscounterCode) private _dis_codes;

    // Create a new personal code
    function createDicounterCode(string memory code, address discounter, uint256 discount) external onlyOwner {
        require(bytes(code).length > 0, "Empty code");
        require(discounter != address(0), "Invalid wallet address");
        require(discount <= 30, "Discount too high"); // Max 30% discount
        require(_dis_codes[code].discounter == address(0), "Code already exists");
        
        _dis_codes[code] = DiscounterCode({
            discounter: discounter,
            discount: discount,
            minted: [uint(0),0,0,0,0,0]
        });
    }

    // Get ambassador info by the code
    function getDiscounter(string memory code) external view returns (DiscounterCode memory) {
        require(bytes(code).length > 0, "No code provided");
        DiscounterCode memory _code = _dis_codes[code];
        require(_code.discounter != address(0), "Invalid code");
        return _code;
    }
    
    // ------------------------------------------------------
    // Minting Functions
    // ------------------------------------------------------
    
    // Events
    event NFTMinted(address indexed buyer, uint256 indexed rarityId, uint256 amount, uint256 paid);
    event AmbassadorRewardPaid(address indexed ambassador, uint256 amount);

    // Get current price for a particular rarity and other payment details
    // function getPaymentDetails(uint256 rarityId, uint256 amount, string memory code) public view validRarity(rarityId) returns (uint256 payment, uint256 discount, uint256 ambassador, uint256 manager, uint256 team) {
    //     require(amount > 0, "Amount must be greater than zero");
    //     require(getAvailableNFTs(rarityId) > 0, "No NFTs left in this phase");
    //     require(getAvailableNFTs(rarityId) >= amount, "Exceeds phase remaining supply");
        
    //     payment = getPhasePrice(rarityId) * amount;
    //     discount = 0;
    //     ambassador = 0;
    //     manager = 0;
        
    //     if (bytes(refCode).length > 0) {
    //         AmbassadorCode storage code = _codes[refCode];
    //         require(code.ambassador != address(0), "Invalid code");
    //         require(code.discount <= 25 || code.ambassador == msg.sender, "This code is only for self-usage");

    //         if (code.discount < 25) {
    //             ambassador = (payment * (25 - code.discount)) / 100;
    //             if (code.manager != address(0)) {
    //                 manager = payment * 5 / 100;
    //             }
    //         }
    //         discount = (payment * code.discount) / 100;
    //     }
    //     payment -= discount;
    //     team = payment - ambassador - manager;
    // }

    struct Amounts {
        uint256 payment;
        uint256 discount;
        uint256 ambassador;
        uint256 manager;
        uint256 team;
    }

    // Mint NFTs with authorization for USDC payment
    function mint(uint256 rarityId, uint256 quantity, string memory code, uint256 validAfter, uint256 validBefore, bytes32 nonce, uint8 v, bytes32 r, bytes32 s) external {

        // Get the payment details and validate the parameters (no need for a discount value returned)
        // (uint256 payment, , uint256 ambassador, uint256 manager, uint256 team) = getPaymentDetails(rarityId, quantity, refCode);
        require(quantity > 0, "Amount must be greater than zero");
        require(getAvailableNFTs(rarityId) > 0, "No NFTs left in this phase");
        require(getAvailableNFTs(rarityId) >= quantity, "Exceeds phase remaining supply");
        
        Amounts memory amounts;
        amounts.payment = getPhasePrice(rarityId) * quantity;
        amounts.discount = 0;
        amounts.ambassador = 0;
        amounts.manager = 0;
        amounts.team = 0;
        
        AmbassadorCode storage _amb_code = _amb_codes[code];
        DiscounterCode storage _dis_code = _dis_codes[code];

        // Check for ambassador code
        if(_amb_code.ambassador != address(0)) {
            amounts.ambassador = (amounts.payment * (25 - _amb_code.discount)) / 100;
            if (_amb_code.manager != address(0)) {
                amounts.manager = amounts.payment * 5 / 100;
            }
            amounts.discount = (amounts.payment * _amb_code.discount) / 100;
        }
        // Check for discounter code
        else if(_dis_code.discounter != address(0) && _dis_code.discounter == msg.sender) {
            amounts.discount = (amounts.payment * _dis_code.discount) / 100;
        }

        amounts.payment -= amounts.discount;
        amounts.team = amounts.payment - amounts.ambassador - amounts.manager;
        
        // Payment for NFT
        usdc.transferWithAuthorization(msg.sender, address(this), amounts.payment, validAfter, validBefore, nonce, v, r, s);

        // Update ambassador
        if (_amb_code.ambassador != address(0)) {
            _amb_code.minted[rarityId] += quantity;
            _amb_code.earned += amounts.ambassador;
            _amb_code.raised += amounts.team;

            if(amounts.ambassador > 0) {
                usdc.transfer(_amb_code.ambassador, amounts.ambassador);
                emit AmbassadorRewardPaid(_amb_code.ambassador, amounts.ambassador);
            }
            
            if (amounts.manager > 0 && _amb_code.manager != address(0)) {
                usdc.transfer(_amb_code.manager, amounts.manager);
                emit AmbassadorRewardPaid(_amb_code.manager, amounts.manager);
            }
        }
        // Update discounter
        else if(_dis_code.discounter != address(0) && amounts.discount > 0) {
            _dis_code.minted[rarityId] += quantity;
        }

        // Update phase minting count
        _phases[currentPhase].minted[rarityId] += quantity;
        
        // Mint NFTs
        nfts.mint(msg.sender, rarityId, quantity);

        // Emit event
        emit NFTMinted(msg.sender, rarityId, quantity, amounts.payment);
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
        usdc.transfer(request.recipient, request.amount);
        
        emit WithdrawalExecuted(requestId, msg.sender, request.amount, request.recipient);
    }
}