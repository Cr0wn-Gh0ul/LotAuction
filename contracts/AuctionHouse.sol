// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Constants.sol";
import "./AuctionLibrary.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "hardhat/console.sol";

contract AuctionHouse is ERC721, AccessControl {
    enum LotType {
        PHASE_1,
        PHASE_2,
        PHASE_3,
        PHASE_4
    }
    struct PrizePool {
        uint256 leftToMint;
        uint256 currentPrng;
        mapping(uint256 => uint256) idSwaps;
    }
    using AuctionLibrary for AuctionLibrary.Auction;
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    uint256 public blockDuration = 1800;
    uint256 reservePrice = 0.01 ether;
    uint256 minBidIncrement = 5;
    mapping(uint256 => AuctionLibrary.Auction) private _auctions;
    // bidder address => auction numbers (auctionLive)
    mapping(address => uint256[]) public auctionsWon;
    // auction number (auctionLive) => # of tokens to be minted per address
    mapping(uint256 => uint256) public prizesPerAddress;
    // auction number (auctionLive) => prize pool
    mapping(uint256 => PrizePool) internal prizePool;
    // auction number (auctionLive) => slush fund prize amount
    mapping(uint256 => uint256) public slushPrizePool;
    // auctions with leftOver prizes
    uint256[] public auctionSlushFund;
    uint256 public auctionNow;
    bool public isPaused;
    address private _owner;

    modifier notPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Caller is not a minter");
        _;
    }

    modifier activeBidder() {
        require(
            _auctions[auctionNow].addressToAmount[msg.sender] > 0,
            "Bidder has no active bid"
        );
        _;
    }

    constructor() ERC721("AuctionHouse", "AH") {
        _setupRole(MINTER_ROLE, msg.sender);
        _owner = msg.sender;
        _createAuction();
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function addBid() external payable notPaused {
        AuctionLibrary.addBid(_auctions[auctionNow]);
    }

    function removeBid() external notPaused activeBidder {
        AuctionLibrary.removeBid(_auctions[auctionNow]);
    }

    function increaseBid() external payable notPaused activeBidder {
        AuctionLibrary.increaseBid(_auctions[auctionNow]);
    }

    function setBlockDuration(uint256 blockDuration_) external onlyOwner {
        blockDuration = blockDuration_;
    }

    function setReservePrice(uint256 _reservePrice_) external onlyOwner {
        reservePrice = _reservePrice_;
    }

    function setMinBidIncrement(uint256 minBidIncrement_) external onlyOwner {
        minBidIncrement = minBidIncrement_;
    }

    function addMinter(address minter_) external onlyOwner {
        grantRole(MINTER_ROLE, minter_);
    }

    function newOwner(address newOwner_) external onlyOwner {
        _owner = newOwner_;
    }

    function togglePaused() external onlyOwner {
        isPaused = !isPaused;
    }

    /**
     * @dev Withdraw all of the ether in this contract to the contract owner
     */
    function withdraw() external onlyOwner {
        (bool sent, ) = _owner.call{value: address(this).balance}("");
        require(sent, "Withdraw failed");
    }

    function getAuction()
        external
        view
        notPaused
        returns (AuctionLibrary.AuctionBase memory)
    {
        return _auctions[auctionNow].auctionBase;
    }

/*
TODO: Refund some % lot profit + slush fund if any, if no slush then higher %
*/
    function settleAuction() external notPaused {
        // get current auction
        AuctionLibrary.Auction storage auction = _auctions[auctionNow];
        // check if the current auction has been settled
        require(!auction.auctionBase.settled, "Auction has been settled");
        // check if the auction has ended
        require(
            block.number >= auction.auctionBase.endTime,
            "Auction has not ended"
        );
        // set auction as settled
        auction.auctionBase.settled = true;
        // get number of prizes for this auction
        (, , uint256 totalPrizes) = AuctionLibrary._getLotInfo(auction.lotType);
        // get winners of this auction
        address[] memory winners = AuctionLibrary._winnersOfAuction(auction);
        // iterate all the winners
        for (uint256 i = 0; i < winners.length; i++) {
            // add this auction to the winners address => auctions[] mapping
            auctionsWon[winners[i]].push(auctionNow);
        }

        uint256 prizesPerAddressRemainder = totalPrizes % winners.length;
        if (prizesPerAddressRemainder > 0) {
            // doesnt work, maybe just burn them all and remove slush
            //auctionsWon[msg.sender].push(auctionNow);
        }
        // map this auction => prizes per address mapping
        prizesPerAddress[auctionNow] = totalPrizes / winners.length;
        // create a new auction
        _createAuction();
        uint256 settlementReward = (auction.auctionBase.totalValue * 10) / 100;
        (bool sent, ) = msg.sender.call{value: settlementReward}("");
        require(sent, "Refund failed");
    }

    function collectPrizes() external notPaused {
        // get auctions won by this address
        //uint256[] memory auctionsWon_ = auctionsWon[msg.sender];
        // get the last auction won by this address
        
        require(auctionsWon[msg.sender].length > 0, "No prizes to collect");
        uint256 lastElIdx = auctionsWon[msg.sender].length -1;
        //uint256 targetAuction = auctionsWon[msg.sender].length - 1;
        // require this address has won at least one auction
        //require(auctionsWon_.length > 0, "No prizes to collect");
        // get the number of prizes won for this auction
        uint256 auctionClaim = auctionsWon[msg.sender][lastElIdx];
        // remove this auction from the winners address => auctions[] mapping
        auctionsWon[msg.sender].pop();
        // get the number of prizes won for this auction
        uint256 prizeAmount = prizesPerAddress[auctionClaim];
        // mint the prizes for this auction
        _mint(prizeAmount, auctionClaim, msg.sender);
    }

    function viewPrizesCount() external view returns (uint256) {
        // get auctions won by this address
        //uint256[] memory auctionsWon_ = auctionsWon[msg.sender];
        // accumulate the number of prizes won
        uint256 prizesAmount;
        for (uint256 i = 0; i < auctionsWon[msg.sender].length; i++) {
            // get auction id
            uint256 auctionClaim = auctionsWon[msg.sender][i];
            // add the number of prizes won for this auction
            prizesAmount += prizesPerAddress[auctionClaim];
        }
        // return the number of prizes won
        return prizesAmount;
    }

    /**
     * @dev Mints slush fund prizes to a specified address
     * @dev To be used for social media giveaways if any is accumulated
     * @param to_ The address to mint the tokens to
     */
    function slushMintTo(address to_) external onlyMinter {
        // auction that has slush fund
        uint256 slushAuction = auctionSlushFund[auctionSlushFund.length - 1];
        // Get the amount of tokens in the slush pool.
        uint256 slushAmount = slushPrizePool[slushAuction];
        // Remove the auction from the slush pool.
        auctionSlushFund.pop();
        // Mint the tokens to the address.
        _mint(slushAmount, slushAuction, to_);
    }

    /**
     * @dev Mints a number of tokens for a winner of an auction
     */
    function _mint(
        uint256 amount_,
        uint256 auctionId_,
        address to_
    ) internal {
        // get the prize pool by auction id
        PrizePool storage pPool = prizePool[auctionId_];
        // get the lowest token id for this auction
        (uint256 tokenIdLow, , ) = AuctionLibrary._tokenIdRange(
            auctionId_,
            _auctions[auctionId_].lotType
        );
        // get how many tokens are left to mint for this auction
        uint256 leftToMint = pPool.leftToMint;
        // get the current prng for this auction
        uint256 currentPrng = pPool.currentPrng;
        // loop through the amount of tokens to mint
        for (uint256 i = 0; i < amount_; i++) {
            /**
             * @notice Pull a random token id to be minted next
             * @dev Created by dievardump (Simon Fremaux)
             * @dev Implemented in CyberBrokersMint Contract(0xd64291d842212bcf20db9dbece7823fe103061ab) by cybourgeoisie (Ben Herdorn)
             * @dev Modifications of this function were made to optimize gas
             * @param leftToMint_ How many tokens are left to be minted
             * @param currentPrng_ The curent set prng
             **/
            currentPrng = _prng(leftToMint, currentPrng);
            uint256 index = 1 + (currentPrng % leftToMint);
            uint256 tokenId = pPool.idSwaps[index];
            if (tokenId == 0) {
                tokenId = index;
            }
            uint256 temp = pPool.idSwaps[leftToMint];
            if (temp == 0) {
                pPool.idSwaps[index] = leftToMint;
            } else {
                pPool.idSwaps[index] = temp;
                delete pPool.idSwaps[leftToMint];
            }
            leftToMint -= 1;
            _safeMint(to_, (tokenId + tokenIdLow));
        }
        pPool.leftToMint = leftToMint;
        pPool.currentPrng = currentPrng;
    }

    /**
     * @dev prng to be used by _mint
     * @param leftToMint_ number of tokens left to mint
     * @param currentPrng_ the last value returned by this function
     */
    function _prng(uint256 leftToMint_, uint256 currentPrng_)
        internal
        view
        returns (uint256)
    {
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        blockhash(block.number - 1),
                        currentPrng_,
                        leftToMint_
                    )
                )
            );
    }

    function _createAuction() internal {
        // increment auction number
        auctionNow++;
        // create new auction
        AuctionLibrary.LotType lotType = AuctionLibrary._getAuctionLotType(
            auctionNow
        );
        (uint256 winnersAllowed, , ) = AuctionLibrary._getLotInfo(lotType);
        AuctionLibrary.Auction storage auction = _auctions[auctionNow];
        auction.auctionBase.startTime = block.number;
        auction.auctionBase.endTime = block.number + blockDuration;
        auction.auctionBase.winningBidsPlaced = 0;
        auction.auctionBase.settled = false;
        auction.auctionBase.maxWinningBids = winnersAllowed;
        auction.auctionBase.reservePrice = reservePrice;
        auction.auctionBase.minBidIncrement = minBidIncrement;
        auction.lotType = lotType;

        // create a new prize pool
        PrizePool storage pPool = prizePool[auctionNow];
        // get number of tokens to be minted for this auction
        (, , uint256 tokenAmount) = AuctionLibrary._tokenIdRange(
            auctionNow,
            lotType
        );
        // set number of tokens to be minted for this auction
        pPool.leftToMint = tokenAmount;
    }
}
