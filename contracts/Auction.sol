// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./RedBlackTreeLibrary.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract AttributeAuction {
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

    // auction number (auctionLive) => auction info
    mapping(uint256 => Auction) public auctions;
    // auction number (auctionLive) => (bid amount => bidder address)
    mapping(uint256 => mapping(uint256 => address)) public bids;
    // auction number (auctionLive) => bid tree
    mapping(uint256 => RedBlackTreeLibrary.Tree) public bidTrees;
    
    mapping(address => uint256[]) public auctionsWon;
    mapping(uint256 => uint256) public prizes;

    mapping(uint256 => uint256) internal _idSwaps;

    // current auction number
    uint256 public auctionLive;
    // minimum bid
    uint256 public reservePrice;
    // minimum bid increment percentage
    uint256 public minBidIncrementPercentage;

        uint256 internal _leftToMint;
        uint256 internal _currentPrng;

/*
    TODO: swap out timestamp for block number
*/
    function _createAuction() internal {
        auctionLive++;
        auctions[auctionLive] = Auction({
            startTime: block.timestamp,
            endTime: block.timestamp + 6 hours,
            winningBidsPlaced: 0,
            settled: false,
            lotType: getAuctionLotType()
        });
    }

    function getAuction(uint256 auctionId)
        external
        view
        returns (Auction memory)
    {
        // ...
    }

/*
only accepts bids greater than the reserve price
only accepts bids greater than the lowest winning bid if the auction is full
does not accept bids if the auction is full and the bid is less than the lowest winning bid
does not accept bids if the auction is full and the bid is equal to the lowest winning bid
does not accept bids that are equal to a bid that has already been placed
accepts any bid if auction is not full
allows for multiple bids by the same address 
TODO: right & left shift to lessing percision to avoid 1 wei incremental bids - but maybe not needed.
*/
    function addBid() external payable {
        uint256 amount = msg.value;
        Auction memory auction = auctions[auctionLive];
        require(!auction.settled, "Auction has been settled");
        require(
            auction.startTime >= block.timestamp,
            "Auction has not started"
        );
        require(auction.endTime <= block.timestamp, "Auction has ended");
        require(
            amount > reservePrice,
            "Bid amount is less than reserve price"
        );
        require(!bidTrees[auctionLive].exists(amount), "Bid already exists");
        (uint256 winnersAllowed,,) = getLotInfo(
            auction.lotType
        );
        if (auction.winningBidsPlaced >= winnersAllowed) {
            uint256 lowestBid = bidTrees[auctionLive].first();
            require(
                amount > lowestBid,
                "Bid amount is less than the lowest winning bid"
            );
            bidTrees[auctionLive].remove(lowestBid);
            auction.winningBidsPlaced--;
        }
        bidTrees[auctionLive].insert(amount);
        bids[auctionLive][amount] = msg.sender;
        auction.winningBidsPlaced++;
        auctions[auctionLive] = auction;
    }

    function collectPrizes() external {
        uint256[] memory auctionsWon_ = auctionsWon[msg.sender];
        require(auctionsWon_.length > 0, "No prizes to collect");
        uint256 auctionClaim = auctionsWon_[auctionsWon_.length - 1];
        auctionsWon[msg.sender].pop();
        uint256 prizeAmount = prizes[auctionClaim];
        for (uint256 i = 0; i < prizeAmount; i++) {
            //mint()
        }

    }

    function settleAuction() external {
        Auction memory auction = auctions[auctionLive];
        require(!auction.settled, "Auction has been settled");
        require(auction.endTime <= block.timestamp, "Auction has not ended");
        auction.settled = true;
        (,,uint256 totalPrizes) = getLotInfo(
            auction.lotType
        );
        address[] memory winners = winnersOfAuction(auctionLive);
        for (uint256 i = 0; i < winners.length; i++) {
            // TODO: Does not work if totalPrizes is not divisible by winners.length
            auctionsWon[winners[i]].push(auctionLive);
            prizes[auctionLive] += totalPrizes / winners.length;
        }
        _createAuction();
    }

/*
    function _mint(uint256 amount_) internal {
        uint256 leftToMint = _leftToMint;
        require(
            (_totalMinted(leftToMint) + amount_) <= MAX_SUPPLY,
            "Mint would exceed total supply"
        );
        uint256 currentPrng = _currentPrng;
        uint256 tokenId;
        for (uint256 i = 0; i < amount_; i++) {
            (tokenId, leftToMint, currentPrng) = _pullRandomTokenId(leftToMint, currentPrng);
            _safeMint(msg.sender, tokenId);
        }
        _leftToMint = leftToMint;
        _currentPrng = currentPrng;
    }


    function _pullRandomTokenId(uint256 leftToMint_, uint256 currentPrng_)
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 newPrng = _prng(leftToMint_, currentPrng_);
        uint256 index = 1 + (newPrng % leftToMint_);
        uint256 tokenId = _idSwaps[index];
        if (tokenId == 0) {
            tokenId = index;
        }
        uint256 temp = _idSwaps[leftToMint_];
        if (temp == 0) {
            _idSwaps[index] = leftToMint_;
        } else {
            _idSwaps[index] = temp;
            delete _idSwaps[leftToMint_];
        }
        return (tokenId, leftToMint_ - 1, newPrng);
    }


    function _prng(uint256 leftToMint_, uint256 currentPrng_) internal view returns (uint256) {
        return
            uint256(
                keccak256(abi.encodePacked(blockhash(block.number - 1), currentPrng_, leftToMint_))
            );
    }
*/

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

    function getLotInfo(LotType lotType_)
        internal
        pure
        returns (uint256 winnersAllowed, uint256 amountOfType, uint256 totalAmount)
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
