// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Constants.sol";
import "./RedBlackTreeLibrary.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * TODO:
 * - rename variables (pre _, post _, descriptive names)
 * - restructure to proper order
 * - add comments
 */
contract AttributeAuction is ERC721, Ownable {
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;
    enum LotType {
        PHASE_1,
        PHASE_2,
        PHASE_3,
        PHASE_4
    }
    struct Auction {
        uint256 startTime;
        uint256 endTime;
        uint256 winningBidsPlaced;
        bool settled;
        LotType lotType;
    }
    struct PrizePool {
        uint256 leftToMint;
        uint256 currentPrng;
        mapping(uint256 => uint256) idSwaps;
    }
    // auction number (auctionLive) => auction info
    mapping(uint256 => Auction) public auctions;
    // auction number (auctionLive) => (bid amount => bidder address)
    mapping(uint256 => mapping(uint256 => address)) public bids;
    // auction number (auctionLive) => (bidder address => bidAmount)
    mapping(uint256 => mapping(address => uint256)) public activeBid;
    // auction number (auctionLive) => bid tree
    mapping(uint256 => RedBlackTreeLibrary.Tree) public bidTrees;
    // bidder address => auction numbers (auctionLive)
    mapping(address => uint256[]) public auctionsWon;
    // auction number (auctionLive) => # of tokens to be minted per address
    mapping(uint256 => uint256) public prizes;
    // auction number (auctionLive) => prize pool
    mapping(uint256 => PrizePool) internal prizePool;
    // auction number (auctionLive) => slush fund prize amount
    mapping(uint256 => uint256) public slushPrizePool;
    // auctions with leftOver prizes
    uint256[] public auctionSlushFund;
    // current auction number
    uint256 public auctionLive;
    // minimum bid
    uint256 public reservePrice;
    // minimum bid increment percentage
    uint256 public minBidIncrementPercentage;
    // auction duration
    uint256 public blockDuration;
    // contract paused
    bool isPaused;

    modifier notPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    modifier activeBidder() {
        require(
            activeBid[auctionLive][msg.sender] > 0,
            "Bidder has no active bid"
        );
        _;
    }

    constructor() ERC721("AttributeAuction", "ATTR") {
        reservePrice = 0.01 ether; // 0.01 ETH
        minBidIncrementPercentage = 5; // 5%
        blockDuration = 1800; // about 6 hours
        _createAuction(); // start the first auction
    }

    /**
     * @dev Adds a bid to the auction
     * @dev Only accepts bids greater than the reserve price
     * @dev Only accepts bids greater than the lowest winning bid if the auction is full
     * @dev Does not accept bids if the auction is full and the bid is less than or equal to the lowest winning bid
     * @dev Does not accept bids that are equal to a bid that has already been placed
     * @dev Accepts any bid over reserve price if auction is not full
     * @dev Does not accept bids from an address more than once
     */
    function addBid() public payable notPaused {
        // get current auction
        Auction memory auction = auctions[auctionLive];
        // check if this is a valid bid
        uint256 lowestBid = validateBid(auction, msg.value, msg.sender);
        // if number of winning bids is equal to max number of winning bids
        if (lowestBid > 0) {
            // remove lowest winning bid from bid tree
            bidTrees[auctionLive].remove(lowestBid);
            // send lowest winning bid back to bidder
            refundBid(bids[auctionLive][lowestBid], lowestBid);
        } else {
            // increment number of winning bids
            auction.winningBidsPlaced++;
        }
        // add bid to active bid mapping
        activeBid[auctionLive][msg.sender] = msg.value;
        // add bid to bid tree
        bidTrees[auctionLive].insert(msg.value);
        // for reverse tree lookup
        bids[auctionLive][msg.value] = msg.sender;
        // update auction info
        auctions[auctionLive] = auction;
    }

    /**
     * @dev increases bid in the auction
     * @dev Only accepts bids that have already been placed
     */
    function increaseBid() external payable notPaused activeBidder {
        // get bid on this auction
        uint256 lastBid = activeBid[auctionLive][msg.sender];
        // check if bid is greater than last bid + reserve price
        require(
            msg.value > lastBid + ((lastBid * minBidIncrementPercentage) / 100),
            "New bid is too low"
        );
        // remove last bid from this auction
        activeBid[auctionLive][msg.sender] = 0;
        // add the new bid
        addBid();
    }

    /**
     * @dev Removes a bid from the auction
     * @dev Only accepts bids that have already been placed
     */
    function removeBid() external payable notPaused activeBidder {
        Auction memory auction = auctions[auctionLive];
        // check if auction is active
        checkActiveAuction(auction);
        // get bid on this auction
        uint256 lastBid = activeBid[auctionLive][msg.sender];
        // remove lowest winning bid from bid tree
        bidTrees[auctionLive].remove(lastBid);
        // send lowest winning bid back to bidder
        refundBid(bids[auctionLive][lastBid], lastBid);
        // delete bid from active winningBidsPlaced
        auction.winningBidsPlaced--;
        // update auction
        auctions[auctionLive] = auction;
    }

    /**
     * @dev checks if the auction is active and okay for bidding or bid removal
     */
    function checkActiveAuction(Auction memory auction) public view {
        // check if the current auction has been settled
        require(!auction.settled, "Auction has been settled");
        // check if the auction has started
        require(auction.startTime >= block.number, "Auction has not started");
        // check if the auction has ended
        require(auction.endTime <= block.number, "Auction has ended");
    }

    function validateBid(
        Auction memory auction,
        uint256 amount_,
        address addr_
    ) public view returns (uint256) {
        // check the active auction
        checkActiveAuction(auction);
        // check if bid already exists
        require(activeBid[auctionLive][addr_] == 0, "Bid already exists");
        // chheck if bid is greater than reserve price
        require(
            amount_ > reservePrice,
            "Bid amount is less than reserve price"
        );
        // check if bid for this amount already exists
        require(!bidTrees[auctionLive].exists(amount_), "Bid already exists");
        // check if new bid is valid
        return newValidBid(auction, amount_);
    }

    function newValidBid(Auction memory auction_, uint256 value_)
        public
        view
        returns (uint256)
    {
        // get lot info
        (uint256 winnersAllowed, , ) = getLotInfo(auction_.lotType);
        // see if we are replacing a bid
        if (auction_.winningBidsPlaced >= winnersAllowed) {
            // find lowest winning bid
            uint256 lowestBid = bidTrees[auctionLive].first();
            // require bid is greater than lowest winning bid
            require(
                value_ >
                    lowestBid + ((lowestBid * minBidIncrementPercentage) / 100),
                "Bid amount is less than the lowest winning bid + minBidIncrementPercentage"
            );
            // return the lowest winning bid
            return lowestBid;
        }
        // max number of winning bids not reached
        return 0;
    }

    /**
     * @dev Settles a auction that has completed
     * @dev Adds winners of the auction to the winners mapping
     */
    function settleAuction() external notPaused {
        // get current auction
        Auction memory auction = auctions[auctionLive];
        // check if the current auction has been settled
        require(!auction.settled, "Auction has been settled");
        // check if the auction has ended
        require(auction.endTime <= block.timestamp, "Auction has not ended");
        // set auction as settled
        auction.settled = true;
        // get number of prizes for this auction
        (, , uint256 totalPrizes) = getLotInfo(auction.lotType);
        // get winners of this auction
        address[] memory winners = winnersOfAuction(auctionLive);
        // iterate all the winners
        for (uint256 i = 0; i < winners.length; i++) {
            // add this auction to the winners address => auctions[] mapping
            auctionsWon[winners[i]].push(auctionLive);
        }
        uint256 prizesPerAddressRemainder = totalPrizes % winners.length;
        if (prizesPerAddressRemainder > 0) {
            // add this auction to the slush fund
            auctionSlushFund.push(auctionLive);
            // add remainder amount of tokens to slush fund
            slushPrizePool[auctionLive] = prizesPerAddressRemainder;
        }
        // map this auction => prizes per address mapping
        prizes[auctionLive] = totalPrizes / winners.length;
        // update auction info
        auctions[auctionLive] = auction;
        // create a new auction
        _createAuction();
    }

    /**
     * @dev Collects prizes for a winner for one auction they have won
     * @dev It must be called once per auction won
     */
    function collectPrizes() external notPaused {
        // get auctions won by this address
        uint256[] memory auctionsWon_ = auctionsWon[msg.sender];
        // get the last auction won by this address
        uint256 targetAuction = auctionsWon_.length - 1;
        // require this address has won at least one auction
        require(auctionsWon_.length > 0, "No prizes to collect");
        // get the number of prizes won for this auction
        uint256 auctionClaim = auctionsWon_[targetAuction];
        // remove this auction from the winners address => auctions[] mapping
        auctionsWon[msg.sender].pop();
        // get the number of prizes won for this auction
        uint256 prizeAmount = prizes[auctionClaim];
        // mint the prizes for this auction
        _mint(prizeAmount, targetAuction, msg.sender);
    }

    /**
     * @dev Returns the number of prizes a winner has won
     */
    function viewPrizesCount() external view returns (uint256) {
        // get auctions won by this address
        uint256[] memory auctionsWon_ = auctionsWon[msg.sender];
        // accumulate the number of prizes won
        uint256 prizesAmount;
        for (uint256 i = 0; i < auctionsWon_.length; i++) {
            // get auction id
            uint256 auctionClaim = auctionsWon_[i];
            // add the number of prizes won for this auction
            prizesAmount += prizes[auctionClaim];
        }
        // return the number of prizes won
        return prizesAmount;
    }

    /**
     * @dev Mints slush fund prizes to a specified address
     * @dev To be used for social media giveaways if any is accumulated
     */
    function slushMintTo(address to_) external onlyOwner {
        // auction that has slush fund
        uint256 slushAuction = auctionSlushFund[auctionSlushFund.length - 1];
        // Get the amount of tokens in the slush pool.
        uint256 slushAmount = slushPrizePool[slushAuction];
        // Remove the auction from the slush pool.
        auctionSlushFund.pop();
        // Mint the tokens to the address.
        _mint(slushAmount, slushAuction, to_);
    }

    function setReservePrice(uint256 _reservePrice) external onlyOwner {
        reservePrice = _reservePrice;
    }

    function setMinBidIncrementPercentage(uint256 _minBidIncrementPercentage)
        external
        onlyOwner
    {
        minBidIncrementPercentage = _minBidIncrementPercentage;
    }

    function setBlockDuration(uint256 _blockDuration) external onlyOwner {
        blockDuration = _blockDuration;
    }

    function togglePaused() external onlyOwner {
        isPaused = !isPaused;
    }

    /**
     * @dev Withdraw all of the ether in this contract to the contract owner
     */
    function withdraw() external onlyOwner {
        (bool sent, ) = owner().call{value: address(this).balance}("");
        require(sent, "Withdraw failed");
    }

    /**
     * @dev Refunds a bid and removes the bid from the active bid mapping
     */
    function refundBid(address user_, uint256 amount_) internal {
        // delete bid from active bid mapping
        delete bids[auctionLive][amount_];
        // refund bid
        (bool sent, ) = user_.call{value: amount_}("");
        require(sent, "Refund failed");
    }

    /**
     * @dev Creates a new auction
     */
    function _createAuction() internal notPaused {
        // increment auction number
        auctionLive++;
        // create new auction
        auctions[auctionLive] = Auction({
            startTime: block.number,
            endTime: block.number + blockDuration,
            winningBidsPlaced: 0,
            settled: false,
            lotType: getAuctionLotType()
        });
        // create a new prize pool
        PrizePool storage pPool = prizePool[auctionLive];
        // get number of tokens to be minted for this auction
        (, , uint256 tokenAmount) = tokenIdRange(auctionLive);
        // set number of tokens to be minted for this auction
        pPool.leftToMint = tokenAmount;
    }

    /**
     * @dev Mints a number of tokens for a winner of an auction
     */
    function _mint(
        uint256 amount_,
        uint256 auctionId,
        address to
    ) internal {
        // get the prize pool by auction id
        PrizePool storage pPool = prizePool[auctionId];
        // get the lowest token id for this auction
        (uint256 tokenIdLow, , ) = tokenIdRange(auctionId);
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
            _safeMint(to, (tokenId + tokenIdLow));
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

    /**
     * @dev Returns the winners of an auction
     * @param auctionId The id of the auction to get winners for
     */
    function winnersOfAuction(uint256 auctionId)
        internal
        view
        returns (address[] memory)
    {
        // get auction by id
        Auction memory auction = auctions[auctionId];
        // create an array of addresses to store winners
        address[] memory winners = new address[](auction.winningBidsPlaced);
        // get the first bid in the bid tree
        uint256 currentValue = bidTrees[auctionId].first();
        for (uint256 i = 0; i < (auction.winningBidsPlaced - 1); i++) {
            // add the address of the bid from the bid tree to the winners array
            winners[i] = bids[auctionId][currentValue];
            // get the next bid in the bid tree
            currentValue = bidTrees[auctionId].next(currentValue);
        }
        // return the winners array
        return winners;
    }

    /**
     * @dev Returns the token id range for an auction
     * @param auctionId The id of the auction to get the token id range for
     * @return tokenIdLow The lowest token id for this auction
     * @return tokenIdHigh The highest token id for this auction
     * @return tokenAmount The amount of tokens in this auction
     */
    function tokenIdRange(uint256 auctionId)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        // get auction by id
        Auction memory auction = auctions[auctionId];
        // get the token id range for the auction
        uint256 tokenAmount;
        // get the highest token id for this auction
        uint256 tokenIdHigh;
        // get the lowest token id for this auction
        uint256 tokenIdLow;
        // get the token id range for the auction based on the auction phase
        if (auction.lotType > LotType.PHASE_1) {
            tokenIdHigh += PHASE_ONE_COUNT * PHASE_ONE_TOKEN_AMOUNT;
        } else if (auction.lotType == LotType.PHASE_1) {
            tokenIdHigh += auctionId * PHASE_ONE_TOKEN_AMOUNT;
            tokenIdLow = tokenIdHigh - PHASE_ONE_TOKEN_AMOUNT;
            tokenAmount = PHASE_ONE_TOKEN_AMOUNT;
        }
        if (auction.lotType > LotType.PHASE_2) {
            tokenIdHigh += PHASE_TWO_COUNT * PHASE_TWO_TOKEN_AMOUNT;
        } else if (auction.lotType == LotType.PHASE_2) {
            tokenIdHigh += auctionId * PHASE_TWO_TOKEN_AMOUNT;
            tokenIdLow = tokenIdHigh - PHASE_TWO_TOKEN_AMOUNT;
            tokenAmount = PHASE_TWO_TOKEN_AMOUNT;
        }
        if (auction.lotType > LotType.PHASE_3) {
            tokenIdHigh += PHASE_THREE_COUNT * PHASE_THREE_TOKEN_AMOUNT;
        } else if (auction.lotType == LotType.PHASE_3) {
            tokenIdHigh += auctionId * PHASE_THREE_TOKEN_AMOUNT;
            tokenIdLow = tokenIdHigh - PHASE_THREE_TOKEN_AMOUNT;
            tokenAmount = PHASE_THREE_TOKEN_AMOUNT;
        }
        if (auction.lotType > LotType.PHASE_4) {
            tokenIdHigh += PHASE_FOUR_COUNT * PHASE_FOUR_TOKEN_AMOUNT;
        } else if (auction.lotType == LotType.PHASE_4) {
            tokenIdHigh += auctionId * PHASE_FOUR_TOKEN_AMOUNT;
            tokenIdLow = tokenIdHigh - PHASE_FOUR_TOKEN_AMOUNT;
            tokenAmount = PHASE_FOUR_TOKEN_AMOUNT;
        }
        // return the lowest token id, the highest token id, and the amount of tokens in the auction
        return (tokenIdLow, tokenIdHigh, tokenAmount);
    }

    /**
     * @dev returns the lot info for a given lot type
     * @param lotType_ the lot type to get info for
     * @return winnersAllowed the amount of winners allowed for this lot type
     * @return amountOfType the amount of auctions of this type
     * @return totalAmount the total amount of tokens per auction of this type
     */
    function getLotInfo(LotType lotType_)
        internal
        pure
        returns (
            uint256 winnersAllowed,
            uint256 amountOfType,
            uint256 totalAmount
        )
    {
        // get the lot info for the given lot type
        if (lotType_ == LotType.PHASE_1) {
            return (PHASE_ONE_WINNERS, PHASE_ONE_COUNT, PHASE_ONE_TOKEN_AMOUNT);
        } else if (lotType_ == LotType.PHASE_2) {
            return (PHASE_TWO_WINNERS, PHASE_TWO_COUNT, PHASE_TWO_TOKEN_AMOUNT);
        } else if (lotType_ == LotType.PHASE_3) {
            return (
                PHASE_THREE_WINNERS,
                PHASE_THREE_COUNT,
                PHASE_THREE_TOKEN_AMOUNT
            );
        } else if (lotType_ == LotType.PHASE_4) {
            return (
                PHASE_FOUR_WINNERS,
                PHASE_FOUR_COUNT,
                PHASE_FOUR_TOKEN_AMOUNT
            );
        }
    }

    /**
     * @dev returns the lot type for the current auction
     * @return lotType the lot type for the current auction
     */
    function getAuctionLotType() internal view returns (LotType lotType) {
        uint256 currentAuction = auctionLive;
        if (currentAuction <= PHASE_ONE_COUNT) {
            return LotType.PHASE_1;
        } else if (currentAuction <= PHASE_ONE_COUNT + PHASE_TWO_COUNT) {
            return LotType.PHASE_2;
        } else if (
            currentAuction <=
            PHASE_ONE_COUNT + PHASE_TWO_COUNT + PHASE_THREE_COUNT
        ) {
            return LotType.PHASE_3;
        } else if (
            currentAuction <=
            PHASE_ONE_COUNT +
                PHASE_TWO_COUNT +
                PHASE_THREE_COUNT +
                PHASE_FOUR_COUNT
        ) {
            return LotType.PHASE_4;
        }
    }
}
