// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Constants.sol";
import "./RedBlackTreeLibrary.sol";

contract AuctionRuntime {
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;
    RedBlackTreeLibrary.Tree bidTree;
    
    struct AuctionData {
        uint256 maxWinningBids;
        uint256 winningBidsPlaced;
        uint256 startTime;
        uint256 endTime;
        uint256 reservePrice;
        uint256 minBidIncrement;
        uint256 totalValue;
        uint256 totalPrizes;
    }
    AuctionData public auction;
    mapping(address => uint256) addressToAmount;
    mapping(uint256 => address) amountToAddress;

    constructor(AuctionData calldata auction_) {
        auction = auction_;
    }

    function destroyAuction() private {
        selfdestruct(msg.sender);
    }


            /**
     * @dev checks if the auction is active and okay for bidding or bid removal
     * TODO: ONLY ENDED is needed
     */
    modifier isAuctionActive() {
        require(block.number <= auction_.auctionBase.endTime, "Auction has ended");
        _;
    }

    function addBid() public isAuctionActive {
        validateBid(msg.sender, msg.value);
        // if number of winning bids is equal to max number of winning bids
        if (lowestBid > 0) {
            // remove lowest winning bid from bid tree
            auction_.bidTree.remove(bidTree.first());
            // send lowest winning bid back to bidder
            _refundBid(
                auction_,
                auction_.amountToAddress[lowestBid],
                lowestBid
            );
        } else {
            // increment number of winning bids
            auction_.auctionBase.winningBidsPlaced++;
        }
        // add bid to active bid mapping
        auction_.addressToAmount[msg.sender] = msg.value;
        // for reverse tree lookup
        auction_.amountToAddress[msg.value] = msg.sender;
        // add bid to bid tree
        auction_.bidTree.insert(msg.value);
        auction_.auctionBase.totalValue += msg.value;
    }

    function removeBid(Auction storage auction_) external checkActiveAuction(auction_) {
        // get bid on this auction
        uint256 lastBid = auction_.addressToAmount[msg.sender];
        auction_.addressToAmount[msg.sender] = 0;
        // remove lowest winning bid from bid tree
        auction_.bidTree.remove(lastBid);
        // send lowest winning bid back to bidder
        // delete bid from active winningBidsPlaced
        auction_.auctionBase.winningBidsPlaced--;
        auction_.auctionBase.totalValue -= lastBid;
        _refundBid(auction_, auction_.amountToAddress[lastBid], lastBid);
    }

    function increaseBid(Auction storage auction_) external checkActiveAuction(auction_) {
        require(auction_.addressToAmount[msg.sender] > 0, "No bid exists");
        // get bid on this auction
        uint256 lastBid = auction_.addressToAmount[msg.sender];
        uint256 newBid = (lastBid + msg.value);
        // check if new bid is greater than last
        require(
            newBid > lastBid + ((lastBid * auction_.auctionBase.minBidIncrement) / 100),
            "New bid is lower than last bid plus minimum bid increment"
        );
        auction_.bidTree.remove(lastBid);
        auction_.auctionBase.totalValue += msg.value;
        auction_.addressToAmount[msg.sender] = newBid;
        // for reverse tree lookup
        auction_.amountToAddress[newBid] = msg.sender;
        // add bid to bid tree
        auction_.bidTree.insert(newBid);
    }

    function validateBid(address address_, uint256 amount_) public view returns (bool isReplacement) {
        AuctionData memory a = auction;
        precheckBid(a, address_, amount_);
        return isReplacementBid(a, amount_);
    }

    function preCheckBid(
        AuctionData memory auction_,
        uint256 amount_,
        address addr_
    ) internal view isAuctionActive 
    returns (uint256) {
        // check if bid already exists
        require(addressToAmount[addr_] == 0, "Bidder already bid");
        // chheck if bid is greater than reserve price
        require(
            amount_ >= auction_.reservePrice,
            "Bid amount is less than reserve price"
        );
        // check if bid for this amount already exists
        require(!bidTree.exists(amount_), "Bid amount already exists");
        // check if new bid is valid
        return newValidBid(auction_, amount_);
    }

    function isReplacementBid(AuctionData memory auction_, uint256 value_)
        internal
        view
        returns (uint256)
    {
        // see if we are replacing a bid
        if (auction_.winningBidsPlaced >= auction_.maxWinningBids) {
            // find lowest winning bid
            uint256 lowestBid = bidTree.first();
            // require bid is greater than lowest winning bid
            require(
                value_ >=
                    lowestBid + ((lowestBid * auction_.minBidIncrement) / 100),
                "Bid amount is less than the lowest winning bid + minBidIncrement"
            );
            // return the lowest winning bid
            return true;
        }
        // max number of winning bids not reached
        return false;
    }

    /**
     * @dev Returns the winners of an auction
     */
    function _winnersOfAuction(Auction storage auction_)
        internal
        view
        returns (address[] memory)
    {
        // create an array of addresses to store winners
        address[] memory winners = new address[](auction_.auctionBase.winningBidsPlaced);
        // get the first bid in the bid tree
        uint256 currentValue = auction_.bidTree.first();
        for (uint256 i = 0; i < auction_.auctionBase.winningBidsPlaced; i++) {
            // add the address of the bid from the bid tree to the winners array
            winners[i] = auction_.amountToAddress[currentValue];
            // get the next bid in the bid tree
            currentValue = auction_.bidTree.next(currentValue);
        }
        // return the winners array
        return winners;
    }

    /**
     * @dev Refunds a bid and removes the bid from the active bid mapping
     */
    function _refundBid(
        Auction memory auction_,
        address user_,
        uint256 amount_
    ) internal {
        // delete bid from active bid mapping
        delete auction_.amountToAddress[amount_];
        // refund bid
        (bool success, ) = user_.call{gas: 30000, value: amount_}("");
        if (!success) {
            auction_.totalValue += amount_;
        }
        auction = auction_;
        // if the user was a contract doing some weird stuff then the refund goes to auction revenue
    }
}
