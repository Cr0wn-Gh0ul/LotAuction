// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./RedBlackTreeLibrary.sol";

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

    // current auction number
    uint256 public auctionLive;
    // minimum bid
    uint256 public reservePrice;
    // minimum bid increment percentage
    uint256 public minBidIncrementPercentage;

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
        (uint256 winnersAllowed,) = getLotInfo(
            auction.lotType
        );
        if (auction.winningBidsPlaced >= winnersAllowed) {
            uint256 lowestBid = bidTrees[auctionLive].first();
            require(
                amount > lowestBid,
                "Bid amount is less than the lowest winning bid"
            );
            bidTrees[auctionLive].remove(lowestBid);
        }
        bidTrees[auctionLive].insert(amount);
        bids[auctionLive][amount] = msg.sender;
        auction.winningBidsPlaced++;
    }

    function getBids()
        internal
        returns (uint256[] memory bids, address[] memory bidders)
    {
        // ...
    }

/*
    TODO: 
*/
    function settleAuction() external {

    }

    function winnersOfAuction(uint256 auctionId)
        external
        view
        returns (address[] memory)
    {
        bidTrees[auctionId].first();
        for (uint256 > i = 0; i < winnersAllowed; i++) {
            winners[i] = bids[auctionId][bidTrees[auctionId].first()];
            bidTrees[auctionId].remove(bidTrees[auctionId].first());
        }
    }

    function getLotInfo(LotType lotType_)
        internal
        pure
        returns (uint256 winnersAllowed, uint256 amountOfType)
    {
        if (lotType_ == LotType.PHASE_1) {
            return (64, 20);
        } else if (lotType_ == LotType.PHASE_2) {
            return (32, 15);
        } else if (lotType_ == LotType.PHASE_3) {
            return (8, 10);
        } else if (lotType_ == LotType.PHASE_4) {
            return (4, 5);
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
