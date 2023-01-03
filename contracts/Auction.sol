// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./RedBlackTreeLibrary.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract AttributeAuction is ERC721Enumerable {
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
    // auction number (auctionLive) => bid tree
    mapping(uint256 => RedBlackTreeLibrary.Tree) public bidTrees;

    mapping(address => uint256[]) public auctionsWon;
    mapping(uint256 => uint256) public prizes;

    mapping(uint256 => PrizePool) internal prizePool;

    // current auction number
    uint256 public auctionLive;
    // minimum bid
    uint256 public reservePrice;
    // minimum bid increment percentage
    uint256 public minBidIncrementPercentage;

    constructor() ERC721("AttributeAuction", "ATTR") {
        reservePrice = 0.01 ether;
        minBidIncrementPercentage = 5;
        _createAuction();
    }

    /**
     * @dev Creates a new auction
     * TODO: swap out timestamp for block number
     */
    function _createAuction() internal {
        // increment auction number
        auctionLive++;
        // create new auction
        auctions[auctionLive] = Auction({
            startTime: block.timestamp,
            endTime: block.timestamp + 6 hours,
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
     * @dev Adds a bid to the auction
     * @dev Only accepts bids greater than the reserve price
     * @dev Only accepts bids greater than the lowest winning bid if the auction is full
     * @dev Does not accept bids if the auction is full and the bid is less than or equal to the lowest winning bid
     * @dev Does not accept bids that are equal to a bid that has already been placed
     * @dev Accepts any bid over reserve price if auction is not full
     * TODO: disallow for multiple bids by the same address
     */
    function addBid() external payable {
        // get current auction
        Auction memory auction = auctions[auctionLive];
        // get bid amount
        uint256 amount = msg.value;

        // check if the current auction has been settled
        // TODO: May be unnecessary
        require(!auction.settled, "Auction has been settled");
        // check if the auction has started
        // TODO: May not be needed, but may be good for UI
        require(
            auction.startTime >= block.timestamp,
            "Auction has not started"
        );
        // check if the auction has ended
        require(auction.endTime <= block.timestamp, "Auction has ended");
        // check if bid is greater than reserve price
        require(amount > reservePrice, "Bid amount is less than reserve price");
        // check if bid for this amount already exists
        // TODO: Maybe Helper function for frontend
        require(!bidTrees[auctionLive].exists(amount), "Bid already exists");
        // get max number of winning bids allowed for this auction
        (uint256 winnersAllowed, , ) = getLotInfo(auction.lotType);
        // if number of winning bids is equal to max number of winning bids
        if (auction.winningBidsPlaced >= winnersAllowed) {
            // find lowest winning bid
            uint256 lowestBid = bidTrees[auctionLive].first();
            // require bid is greater than lowest winning bid
            // TODO: require it is minBidIncrementPercentage greater than lowest winning bid
            require(
                amount > lowestBid,
                "Bid amount is less than the lowest winning bid"
            );
            // remove lowest winning bid from bid tree
            bidTrees[auctionLive].remove(lowestBid);
            // decrement number of winning bids
            // TODO: this is a little ugly, maybe make a helper function
            auction.winningBidsPlaced--;
        }
        // add bid to bid tree
        bidTrees[auctionLive].insert(amount);
        // add bid to address mapping for this auction
        // for reverse tree lookup
        bids[auctionLive][amount] = msg.sender;
        // increment number of winning bids
        auction.winningBidsPlaced++;
        // update auction info
        auctions[auctionLive] = auction;
    }

    /**
     * @dev Settles a auction that has completed
     * @dev Adds winners of the auction to the winners mapping
     */
    function settleAuction() external {
        // get current auction
        Auction memory auction = auctions[auctionLive];
        // check if the current auction has been settled
        // TODO: May be unnecessary
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
            // map this auction => prizes per address mapping
            // TODO: Does not work if totalPrizes is not divisible by winners.length
            prizes[auctionLive] += totalPrizes / winners.length;
        }
        // update auction info
        auctions[auctionLive] = auction;
        // create a new auction
        _createAuction();
    }

    /**
     * @dev Collects prizes for a winner for one auction they have won
     * @dev It must be called once per auction won
     * TODO: Create a view function that returns the number of prizes a winner has
     */
    function collectPrizes() external {
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
        _mint(prizeAmount, targetAuction);
    }

    /**
     * @dev Mints a number of tokens for a winner of an auction
     */
    function _mint(uint256 amount_, uint256 auctionId) internal {
        PrizePool storage pPool = prizePool[auctionId];
        (uint256 tokenIdLow, , ) = tokenIdRange(auctionId);
        uint256 leftToMint = pPool.leftToMint;
        uint256 currentPrng = pPool.currentPrng;
        uint256 tokenId;
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
            tokenId = pPool.idSwaps[index];
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
            _safeMint(msg.sender, (tokenId + tokenIdLow));
        }
        pPool.leftToMint = leftToMint;
        pPool.currentPrng = currentPrng;
    }

    /**
     * @dev prng to be used by _pullRandomTokenId
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

    function winnersOfAuction(uint256 auctionId)
        internal
        view
        returns (address[] memory)
    {
        Auction memory auction = auctions[auctionId];
        address[] memory winners = new address[](auction.winningBidsPlaced);
        uint256 currentValue = bidTrees[auctionId].first();
        for (uint256 i = 0; i < (auction.winningBidsPlaced - 1); i++) {
            winners[i] = bids[auctionId][currentValue];
            currentValue = bidTrees[auctionId].next(currentValue);
        }
        return winners;
    }

    function tokenIdRange(uint256 auctionId)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        Auction memory auction = auctions[auctionId];
        uint256 tokenAmount;
        uint256 tokenIdHigh;
        uint256 tokenIdLow;
        if (auction.lotType > LotType.PHASE_1) {
            tokenIdHigh += 20 * 256;
        } else if (auction.lotType == LotType.PHASE_1) {
            tokenIdHigh += auctionId * 256;
            tokenIdLow = tokenIdHigh - 256;
            tokenAmount = 256;
        }
        if (auction.lotType > LotType.PHASE_2) {
            tokenIdHigh += 15 * 128;
        } else if (auction.lotType == LotType.PHASE_2) {
            tokenIdHigh += auctionId * 128;
            tokenIdLow = tokenIdHigh - 128;
            tokenAmount = 128;
        }
        if (auction.lotType > LotType.PHASE_3) {
            tokenIdHigh += 10 * 64;
        } else if (auction.lotType == LotType.PHASE_3) {
            tokenIdHigh += auctionId * 64;
            tokenIdLow = tokenIdHigh - 64;
            tokenAmount = 64;
        }
        if (auction.lotType > LotType.PHASE_4) {
            tokenIdHigh += 5 * 32;
        } else if (auction.lotType == LotType.PHASE_4) {
            tokenIdHigh += auctionId * 32;
            tokenIdLow = tokenIdHigh - 32;
            tokenAmount = 32;
        }
        return (tokenIdLow, tokenIdHigh, tokenAmount);
    }

    function getLotInfo(LotType lotType_)
        internal
        pure
        returns (
            uint256 winnersAllowed,
            uint256 amountOfType,
            uint256 totalAmount
        )
    {
        if (lotType_ == LotType.PHASE_1) {
            return (64, 20, 256);
        } else if (lotType_ == LotType.PHASE_2) {
            return (32, 15, 128);
        } else if (lotType_ == LotType.PHASE_3) {
            return (8, 10, 64);
        } else if (lotType_ == LotType.PHASE_4) {
            return (4, 5, 32);
        }
    }

    function getAuctionLotType() internal view returns (LotType) {
        uint256 currentAuction = auctionLive;
        if (currentAuction <= 20) {
            return LotType.PHASE_1;
        } else if (currentAuction <= 35) {
            return LotType.PHASE_2;
        } else if (currentAuction <= 45) {
            return LotType.PHASE_3;
        } else if (currentAuction <= 50) {
            return LotType.PHASE_4;
        }
    }
}
