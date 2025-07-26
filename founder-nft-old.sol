// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// ---------------------------------------------------------
// IERC20
// ---------------------------------------------------------
interface IERC20 {
    function transfer(address,uint256) external returns (bool);
    function transferFrom(address,address,uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

// ---------------------------------------------------------
// IERC721Receiver
// ---------------------------------------------------------
interface IERC721Receiver {
    function onERC721Received(address op, address from, uint256 id, bytes calldata data) external returns (bytes4);
}

// ---------------------------------------------------------
//
// Main smart-contract
//
// ---------------------------------------------------------
contract FounderNFT {
    
    // ---------------------------------------------------
    // ERC-721 core
    // ---------------------------------------------------
    string public name = "Questfall Founder NFT";
    string public symbol = "QFNFT";
    uint16 public hardcap = 6300;

    // ---------------------------------------------------
    // Events
    // ---------------------------------------------------
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // ---------------------------------------------------
    // Errors
    // ---------------------------------------------------
    error NotFound();
    error NotAllowed();
    error BadReceiver();
    error NoAvailableNFT();
    error ZeroAddress();

    // ---------------------------------------------------
    // Owner
    // ---------------------------------------------------
    event OwnershipTransferred(address previousOwner, address newOwner);
    address public owner;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotAllowed();
        _;
    }
    
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address prevOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(prevOwner, newOwner);
    }

    // ---------------------------------------------------
    // USDC
    // ---------------------------------------------------
    address public immutable USDC;

    // ---------------------------------------------------
    // Custom reentrancy guard
    // ---------------------------------------------------
    bool private _isEntered = false;

    modifier nonReentrant() {
        if (_isEntered) revert NotAllowed();
        _isEntered = true;
        _;
        _isEntered = false;
    }

    // ---------------------------------------------------
    // Constructor
    // ---------------------------------------------------
    constructor(address _usdc, address[3] memory _investors) {
        // set USDC contract address
        USDC = _usdc;

        // set the owner
        owner = msg.sender;

        // add investor addresses
        _genesisAddInvestors(_investors);

        // create rarity tiers
        _genesisCreateTiers();

        // mint team nfts
        _genesisMintTeam();
    }

    // ---------------------------------------------------
    //
    // MARKETPLACE-BLOCK SWITCH
    //
    // ---------------------------------------------------
    error TradingBlocked();

    bool public tradingActive = false;
    event tradingActivity(bool status);

    function setTradingActive(bool on) external onlyOwner {
        tradingActive = on;
        emit tradingActivity(on);
    }

    modifier onlyAllowedRecipient(address to) {
        if (!tradingActive && to.code.length != 0) revert TradingBlocked();
        _;
    }


    // ---------------------------------------------------
    // ERC-721 basic
    // ---------------------------------------------------
    mapping(uint16 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    function _id(uint256 id) private view returns (uint16) {
        if (id > hardcap || id == 0) revert NotFound();
        return uint16(id);
    }

    function totalSupply() external view returns (uint256) {
        return
            tiers[Rarity.COMMON].minted +
            tiers[Rarity.UNCOMMON].minted +
            tiers[Rarity.RARE].minted +
            tiers[Rarity.EPIC].minted +
            tiers[Rarity.LEGENDARY].minted +
            tiers[Rarity.MYTHICAL].minted;
    }
    function balanceOf(address a) public view returns (uint256) { 
        return _balances[a]; 
    }
    function ownerOf(uint256 id) public view returns (address) {
        address o = _owners[_id(id)];
        if (o == address(0)) revert NotFound();
        return o;
    }
    function approve(address to, uint16 id) external {
        address o = ownerOf(id);
        if (msg.sender != o && !_operatorApprovals[o][msg.sender]) revert NotAllowed();
        _tokenApprovals[id] = to;
        emit Approval(o, to, id);
    }
    function getApproved(uint256 id) external view returns (address) { 
        address a = _tokenApprovals[_id(id)];
        if (a == address(0)) revert NotFound();
        return a; 
    }
    function setApprovalForAll(address op, bool ok) external {
        if (op == msg.sender) revert NotAllowed();
        _operatorApprovals[msg.sender][op] = ok;
        emit ApprovalForAll(msg.sender, op, ok);
    }
    function isApprovedForAll(address o, address op) external view returns (bool) {
        return _operatorApprovals[o][op];
    }
    function transferFrom(address from, address to, uint256 id) public onlyAllowedRecipient(to) {
        if (!_isApprovedOrOwner(msg.sender, id)) revert NotAllowed();
        _transfer(from, to, _id(id));
    }
    function safeTransferFrom(address from, address to, uint256 id) public onlyAllowedRecipient(to) {
        safeTransferFrom(from, to, id, "");
    }
    function safeTransferFrom(address from, address to, uint256 id, bytes memory data) public {
        transferFrom(from, to, id);
        _checkOnERC721Received(from, to, id, data);
    }
    function _isApprovedOrOwner(address spender, uint256 id) internal view returns (bool) {
        address o = ownerOf(id);
        return spender == o || _tokenApprovals[_id(id)] == spender || _operatorApprovals[o][spender];
    }
    function _checkOnERC721Received(address from, address to, uint256 id, bytes memory data) internal {
        if (to.code.length == 0) return;
        bytes4 ret = IERC721Receiver(to).onERC721Received(msg.sender, from, id, data);
        if (ret != IERC721Receiver.onERC721Received.selector) revert BadReceiver();
    }
    function tokenURI(uint256 id) external view returns (string memory) {
        if (_owners[_id(id)] == address(0)) revert NotFound();
        return tiers[_rarities[_id(id)]].url;
    }
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x80ac58cd || // ERC-721
            interfaceId == 0x5b5e139f || // ERC-721 Metadata
            interfaceId == 0x01ffc9a7;   // ERC-165
    }
    
    // ---------------------------------------------------
    //
    // NFT BASE
    //
    // ---------------------------------------------------
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Mint(address indexed to, uint256 indexed tokenId, Rarity rarity, uint256 price);
    event Burn(address indexed from, uint256 indexed tokenId);

    enum Rarity {
        COMMON, UNCOMMON, RARE, EPIC, LEGENDARY, MYTHICAL
    }
    struct TierData {
        uint128 price;   
        uint16  points;  // the maximum amount of point per nft is 5666
        uint16  hardcap; // the maximum of all tiers is 3200 nfts
        uint16  minted;  // the amount of minted nfts can't exceed the hardcap
        string  url;
    }
    mapping(Rarity => TierData) public tiers;      // 6 rarity tiers  
    mapping(uint16 => Rarity)  private _rarities;  // rarity by nft id
    mapping(uint16 => address) private _owners;    // current owner of nft by its id
    mapping(address => uint16) private _balances;  // number of nfts by the owner (required by ERC-721 standart)
    mapping(address => uint16) private _points;    // the balance of founder points by the address
    uint16 private _nextTokenId = 1;               // counter for minting
    uint32 public totalFounderPoints = 0;          // total founder points supply

    uint128 private constant COMMON_PRICE     = 70   * 10**6;   // 70 USDC (6 decimals)
    uint128 private constant UNCOMMON_PRICE   = 140  * 10**6;
    uint128 private constant RARE_PRICE       = 280  * 10**6;
    uint128 private constant EPIC_PRICE       = 560  * 10**6;
    uint128 private constant LEGENDARY_PRICE  = 1120 * 10**6;
    uint128 private constant MYTHICAL_PRICE   = 2240 * 10**6;

    uint16 private constant COMMON_MAX     = 3200;
    uint16 private constant UNCOMMON_MAX   = 1600;
    uint16 private constant RARE_MAX       = 800;
    uint16 private constant EPIC_MAX       = 400;
    uint16 private constant LEGENDARY_MAX  = 200;
    uint16 private constant MYTHICAL_MAX   = 100;

    uint16 private constant COMMON_POINTS     = 100;
    uint16 private constant UNCOMMON_POINTS   = 224;
    uint16 private constant RARE_POINTS       = 502;
    uint16 private constant EPIC_POINTS       = 1126;
    uint16 private constant LEGENDARY_POINTS  = 2526;
    uint16 private constant MYTHICAL_POINTS   = 5666;

    // ---------------------------------------------------
    // Create tiers (called from constructor)
    // ---------------------------------------------------
    function _genesisCreateTiers() private {
        tiers[Rarity.COMMON]    = TierData(COMMON_PRICE,    COMMON_POINTS,    COMMON_MAX,    0, "");
        tiers[Rarity.UNCOMMON]  = TierData(UNCOMMON_PRICE,  UNCOMMON_POINTS,  UNCOMMON_MAX,  0, "");
        tiers[Rarity.RARE]      = TierData(RARE_PRICE,      RARE_POINTS,      RARE_MAX,      0, "");
        tiers[Rarity.EPIC]      = TierData(EPIC_PRICE,      EPIC_POINTS,      EPIC_MAX,      0, "");
        tiers[Rarity.LEGENDARY] = TierData(LEGENDARY_PRICE, LEGENDARY_POINTS, LEGENDARY_MAX, 0, "");
        tiers[Rarity.MYTHICAL]  = TierData(MYTHICAL_PRICE,  MYTHICAL_POINTS,  MYTHICAL_MAX,  0, "");
    }

    // ---------------------------------------------------
    // Mint team NFTs to the owner wallet (called from constructor)
    // ---------------------------------------------------
    function _genesisMintTeam() private {
        _genesisMintTeamRarity(Rarity.COMMON,    800);
        _genesisMintTeamRarity(Rarity.UNCOMMON,  400);
        _genesisMintTeamRarity(Rarity.RARE,      200);
        _genesisMintTeamRarity(Rarity.EPIC,      100);
        _genesisMintTeamRarity(Rarity.LEGENDARY,  50);
        _genesisMintTeamRarity(Rarity.MYTHICAL,   25);
    }

    function _genesisMintTeamRarity(Rarity rarity, uint16 amount) private {
        for (uint16 i; i < amount; ++i) { _mint(owner, rarity, 0); }
    }

    // ---------------------------------------------------
    // MAIN MINTING FUNCTION
    // ---------------------------------------------------
    function _mint(address to, Rarity rarity, uint256 paid) private {
        if (to == address(0)) revert ZeroAddress();
        if (_owners[_nextTokenId] != address(0)) revert NotFound();
        if (rarity < Rarity.COMMON || rarity > Rarity.MYTHICAL) revert NotAllowed();
        
        TierData storage data = tiers[rarity];
        if (data.minted >= data.hardcap) revert NoAvailableNFT();
        if (_nextTokenId > hardcap) revert NoAvailableNFT();
        
        _balances[to]++;
        _points[to] += data.points;
        _owners[_nextTokenId] = to;
        _rarities[_nextTokenId] = rarity;
        
        data.minted++;
        totalFounderPoints += data.points;

        emit Mint(to, _nextTokenId, rarity, paid);
        _nextTokenId++;
    }

    // ---------------------------------------------------
    // MAIN TRANSFER FUNCTION
    // ---------------------------------------------------
    function _transfer(address from, address to, uint16 id) private {
        if (_owners[id] != from) revert NotAllowed();
        if (to == address(0)) revert ZeroAddress();

        uint16 pts = tiers[_rarities[id]].points;
        _tokenApprovals[id] = address(0);
        _balances[from]--;
        _balances[to]++;
        _points[from] -= pts;
        _points[to] += pts;
        _owners[id] = to;
        emit Transfer(from, to, id);
    }

    // ---------------------------------------------------
    // MAIN BURN FUNCTION
    // ---------------------------------------------------
    function _burn(uint16 id) private {
        if (msg.sender != _owners[id]) revert NotAllowed();

        Rarity rarity = _rarities[id];
        uint16 pts = tiers[rarity].points;

        _tokenApprovals[id] = address(0);
        _balances[msg.sender] -= 1;
        _points[msg.sender]   -= pts;
        _owners[id] = address(0);

        totalFounderPoints -= pts;

        emit Burn(msg.sender, id);
    }

    // ---------------------------------------------------
    // Change the url of the nft image
    // ---------------------------------------------------
    function setTokenURI(Rarity rarity, string calldata uri) external onlyOwner {
        tiers[rarity].url = uri;
    }
    
    // ---------------------------------------------------
    // Get the token rarity
    // ---------------------------------------------------
    function tokenRarity(uint16 id) external view returns (Rarity) {
        if (_owners[id] == address(0)) revert NotFound();
        return _rarities[id];
    }

    // ---------------------------------------------------
    // Get the total amount of Founder Points by the wallet
    // ---------------------------------------------------
    function addressFounderPoints(address a) external view returns (uint256 total) {
        return _points[a];
    }

    // ---------------------------------------------------
    //
    // REFERRAL PROGRAM
    //
    // ---------------------------------------------------
    struct Code {
        uint16 discountBps;   // 100 = 1 %, can be > 2_500
        address ambassador;
    }
    mapping(bytes32 => Code) public codes;

    // ---------------------------------------------------
    // Add new code
    // ---------------------------------------------------
    function addCode(string calldata codeStr, uint16 discountBps, address ambassador) external onlyOwner {
        if (ambassador == address(0)) revert ZeroAddress();
        if (discountBps > 3000) revert NotAllowed();

        bytes32 codeHash = keccak256(bytes(codeStr));
        codes[codeHash] = Code(discountBps, ambassador);
    }

    // ---------------------------------------------------
    // Remove existing code
    // ---------------------------------------------------
    function removeCode(string calldata codeStr) external onlyOwner {
        delete codes[keccak256(bytes(codeStr))];
    }

    // ---------------------------------------------------
    //
    // PHASES
    //
    // ---------------------------------------------------
    
    struct Phase {
        uint32  startDay;           // 0-based day (block.timestamp / 1 days)
        uint32  durationDays;       // length (days)
        uint16  startBps;           // 10000 = 100 %
        uint16  endBps;             // 10000 = 100 %
    }
    Phase public phase;             // 0 values mean “no phase”
    bool public allowPhases = true; // whether phases can be created

    event MintingStarted(uint32 startDay, uint32 durationDays, uint16 startBps, uint16 endBps);
    event MintingStopped();
    
    error MintingClosed();
    error MintingActive();
    error MintingFinalized();
    error BadDuration();
    error BadMultipliers();
    error BadReferral();
    error PaymentFail();
    
    // Returns the current day (0-based)
    function _today() private view returns (uint32) {
        return uint32(block.timestamp / 1 days);
    }

    // Returns true if a phase is currently running
    function mintingActive() public view returns (bool) {
        if (phase.durationDays == 0) return false; // not started yet
        uint32 today = _today();
        return today < phase.startDay + phase.durationDays;
    }

    // ---------------------------------------------------
    // Start a new phase.
    // @param durationDays length of the phase in days
    // @param startPct     price multiplier at day 0 in %  (150 = 150 %)
    // @param endPct       price multiplier at last day in % (200 = 200 %)
    // ---------------------------------------------------
    function startPhase(uint32 durationDays, uint16 startPct, uint16 endPct) external onlyOwner {
        if (!allowPhases) revert MintingFinalized();
        if (mintingActive()) revert MintingActive();
        if (durationDays == 0) revert BadDuration();
        if (startPct == 0 || endPct == 0 || endPct < startPct) revert BadMultipliers();

        uint32 today = _today();
        phase = Phase({
            startDay:     today,
            durationDays: durationDays,
            startBps:     startPct * 100,   // convert % → bps
            endBps:       endPct   * 100
        });

        emit MintingStarted(today, durationDays, startPct, endPct);
    }

    // ---------------------------------------------------
    /// Emergency stop of the currently active phase.
    /// Only callable by the owner while a phase is running.
    // ---------------------------------------------------
    function stopPhase() external onlyOwner {
        if (!mintingActive()) revert MintingClosed();
        delete phase;                // resets all fields to 0
        emit MintingStopped();
    }

    // ---------------------------------------------------------
    // Get the price for a given rarity.
    // If minting has never started → base price.
    // If a phase is active → interpolated price.
    // If a phase existed but has ended → final price of that phase.
    // ---------------------------------------------------------
    function activePrice(Rarity rarity) public view returns (uint256) {
        if (!mintingActive()) return 0;

        uint32 elapsed = _today() - phase.startDay;
        uint256 delta = uint256(phase.endBps) - uint256(phase.startBps);
        uint256 mult  = uint256(phase.startBps) + delta * elapsed / phase.durationDays;
        uint256 base = uint256(tiers[rarity].price);
        return base * mult / 10_000;
    }

    // ---------------------------------------------------------
    // Paid minting
    // Only callable when there is an active phase.
    // No discount if no code provided
    // ---------------------------------------------------------
    function mint(Rarity rarity, string calldata referral) external nonReentrant {
        uint256 fullPrice = activePrice(rarity); // if minting is not active will return 0, otherwise will return the actual price
        if (fullPrice == 0) revert MintingClosed();
        
        uint256 userPrice = fullPrice;
        uint256 userDiscount = 0;

        if (bytes(referral).length != 0) {
            bytes32 codeHash = keccak256(bytes(referral));
            Code memory code = codes[codeHash];
            if (code.ambassador == address(0)) revert BadReferral();
            uint256 discount = uint256(code.discountBps) * fullPrice / 10_000;
            if (discount > fullPrice * 30 / 100 || discount == 0) revert BadReferral(); // while referral program gets 25% there are 30% special discounts for some users
            userDiscount = discount;
            userPrice = fullPrice - userDiscount;
        }

        // transfer from minter
        if (!IERC20(USDC).transferFrom(msg.sender, address(this), userPrice)) revert PaymentFail();

        // transfer ambassador reward, if any
        if (userDiscount > 0 && userDiscount < fullPrice * 25 / 100) {
            uint256 ambReward = fullPrice * 25 / 100 - userDiscount;
            if (!IERC20(USDC).transfer(codes[keccak256(bytes(referral))].ambassador, ambReward)) revert PaymentFail();
        }

        _mint(msg.sender, rarity, userPrice);
    }

    // ---------------------------------------------------------
    // Burn NFT
    // ---------------------------------------------------------
    function burn(uint16 tokenId) external {
        _burn(tokenId);
    }

    // ---------------------------------------------------------
    /// Finalizes the minting forever
    /// - Requires no active phase.
    /// - Permanently locks the contract so no further phases can ever be created.
    // ---------------------------------------------------------
    function finalize() external onlyOwner {
        if (mintingActive()) revert MintingActive();

        // Prevent any new phases
        allowPhases = false;
    }

    // ---------------------------------------------------------
    /// Mint left NFTs after finalization
    /// - Requires no active phase.
    /// - Mints a part of remaining NFTs for a given tier) to the owner.
    // ---------------------------------------------------------
    function finalizeRarity(Rarity rarity, uint16 count) external onlyOwner {
        if (allowPhases) revert NotAllowed();
        
        TierData storage data = tiers[rarity];
        uint16 left = data.hardcap - data.minted;
        if (left > count && count > 0) left = count;

        for (uint16 j = 0; j < left; j++) {
            _mint(owner, rarity, 0);
        }
    }

    // ---------------------------------------------------
    //
    // WITHDRAWAL
    //
    // ---------------------------------------------------
    error BadAmount();
    error Executed();
    error Blocked();
    error Approved();
    error Waiting();
    error NotInvestor();

    event WithdrawalRequested(uint256 indexed id, address indexed requester, uint256 amount);
    event WithdrawalApproved(uint256 indexed id, address indexed approver);
    event WithdrawalBlocked(uint256 indexed id, address indexed blocker);
    event WithdrawalExecuted(uint256 indexed id, address indexed executor, uint256 amount, address reciever);
    
    mapping(address => bool) public isInvestor;
    uint256 public constant WITHDRAWAL_DELAY = 7 days;
    uint256 public withdrawalRequestCounter;

    struct WithdrawalRequest {
        address receiver;
        uint256 amount;
        uint256 initiated;
        bool executed;
        bool blocked;
        mapping(address => bool) approvals;
        uint8 approvalCount;
    }
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;

    modifier onlyInvestor() {
        if (!isInvestor[msg.sender]) revert NotInvestor();
        _;
    }

    // ---------------------------------------------------
    // Add investors
    // called once from a contract constructor
    // ---------------------------------------------------
    function _genesisAddInvestors(address[3] memory _investors) private {
        for (uint256 i; i < 3; ++i) { 
            if (_investors[i] == address(0)) revert ZeroAddress();
            isInvestor[_investors[i]] = true; 
        }
    }

    // ---------------------------------------------------
    // Request a withdrawal 
    // including auto approval from a requester
    // which can be only an investor (1 of 3)
    // ---------------------------------------------------
    function requestWithdrawal(uint256 amount) external onlyInvestor {

        // perform checks on the parameters
        if (amount <= 0 || amount > IERC20(USDC).balanceOf(address(this))) revert BadAmount();
        
        // create a new withdrawal request
        uint256 id = ++withdrawalRequestCounter;
        WithdrawalRequest storage request = withdrawalRequests[id];
        request.receiver    = msg.sender;
        request.amount      = amount;
        request.initiated   = block.timestamp;

        // automatically approve by requester
        request.approvals[msg.sender] = true;
        request.approvalCount = 1;

        // emit blockchain events on a request
        emit WithdrawalRequested(id, msg.sender, amount);
        emit WithdrawalApproved(id, msg.sender);
    }

    // ---------------------------------------------------
    // Approve the existing withdrawal request
    // can be performed only with investor wallets
    // ---------------------------------------------------
    function approveWithdrawal(uint256 id) external onlyInvestor {
        
        // get the withdrawal request by its id
        WithdrawalRequest storage request = withdrawalRequests[id];

        // perform the checks that the appoval makes sense
        if (request.executed) revert Executed();
        if (request.blocked) revert Blocked();
        if (request.approvals[msg.sender]) revert Approved();
        
        // approve the withdrawal request
        request.approvals[msg.sender] = true;
        request.approvalCount++;

        // emit blockchain events on approval
        emit WithdrawalApproved(id, msg.sender);
    }

    // ---------------------------------------------------
    // Block the withdrawal
    // can be perfomed only with investors wallets
    // ---------------------------------------------------
    function blockWithdrawal(uint256 id) external onlyInvestor {
        
        // get the withdrawal request by its id
        WithdrawalRequest storage request = withdrawalRequests[id];

        // perform the checks that the appoval makes sense
        if (request.executed) revert Executed();
        if (request.blocked) revert Blocked();

        // block the withdrawal request
        request.blocked = true;

        // emit blockchain events on approval
        emit WithdrawalBlocked(id, msg.sender);
    }

    // ---------------------------------------------------
    // Withdrawal execution
    // Will proceed if request was not blocked 
    // while the time has passed or three approvals were gathered
    // ---------------------------------------------------
    function executeWithdrawal(uint256 id) external nonReentrant onlyInvestor {
        
        // get the withdrawal request by its idue
        WithdrawalRequest storage request = withdrawalRequests[id];
        
        // perform the checks for the withdrawal
        if (request.executed) revert Executed();
        if (request.blocked) revert Blocked();
        if (block.timestamp < request.initiated + WITHDRAWAL_DELAY && request.approvalCount < 3) revert Waiting();
        if (!isInvestor[request.receiver]) revert NotAllowed();

        // proceed the USDC transaction
        if (!IERC20(USDC).transfer(request.receiver, request.amount)) revert PaymentFail();

        // mark a withdrawal as completed
        request.executed = true;

        // emit blockchain events on withdrawal
        emit WithdrawalExecuted(id, msg.sender, request.amount, request.receiver);
    }
    
}