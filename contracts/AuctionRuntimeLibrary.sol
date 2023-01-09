// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "./Constants.sol";
import "./RedBlackTreeLibrary.sol";

library AuctionRuntimeLibrary {
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;
    struct AuctionData {
        uint256 maxWinningBids;
        uint256 winningBidsPlaced;
        uint256 endTime;
        uint256 reservePrice;
        uint256 minBidIncrement;
        uint256 totalValue;
        uint256 lotSize;
        bool isPaused;
        mapping(address => uint256) addressToAmount;
        mapping(uint256 => address) amountToAddress;
        RedBlackTreeLibrary.Tree bidTree;
    }

    modifier isAuctionActive(AuctionData storage auction_) {
        require(block.number <= auction_.endTime, "Auction has ended");
        _;
    }

    modifier hasActiveBid(AuctionData storage auction_) {
        require(auction_.addressToAmount[msg.sender] > 0, "No bid exists");
        _;
    }

    modifier notPaused(AuctionData storage auction_) {
        require(!auction_.isPaused, "Contract is paused");
        _;
    }

/*
    constructor(AuctionData memory auction_, address auctionOwner_) {
        auction = auction_;
        _auctionOwner = auctionOwner_;
    }
*/
/*
    function togglePaused(AuctionData storage auction_) external onlyAuctionOwner(auction_) {
        auction_.isPaused = !auction_.isPaused;
    }
*/
    function addBid(AuctionData storage auction_) public isAuctionActive(auction_) {
        bool isReplacement = _validateBid(auction_, msg.sender, msg.value);
        // if number of winning bids is equal to max number of winning bids
        if (isReplacement) {
            uint256 lowestBid = auction_.bidTree.first();
            _removeBid(auction_, auction_.amountToAddress[lowestBid], lowestBid);
        } else {
            // increment number of winning bids
            auction_.winningBidsPlaced++;
        }
        // add bid to active bid mapping
        auction_.addressToAmount[msg.sender] = msg.value;
        // for reverse tree lookup
        auction_.amountToAddress[msg.value] = msg.sender;
        // add bid to bid tree
        auction_.bidTree.insert(msg.value);
        auction_.totalValue += msg.value;
    }

    function removeBid(AuctionData storage auction_) external isAuctionActive(auction_) hasActiveBid(auction_) {
        auction_.winningBidsPlaced--;
        _removeBid(auction_, msg.sender, auction_.addressToAmount[msg.sender]);
    }

    function emergencyRelease(AuctionData storage auction_) external hasActiveBid(auction_) {
        require(auction_.isPaused, "Contract is not paused");
        auction_.winningBidsPlaced--;
        _removeBid(auction_, msg.sender, auction_.addressToAmount[msg.sender]);
    }

    function _removeBid(AuctionData storage auction_, address user_, uint256 amount_) internal {
        delete auction_.addressToAmount[user_];
        delete auction_.amountToAddress[amount_];
        auction_.bidTree.remove(amount_);
        bool success = _refundBid(user_, amount_);
        if (success) {
            auction_.totalValue -= amount_;
        }
    }

    function increaseBid(AuctionData storage auction_) external isAuctionActive(auction_) hasActiveBid(auction_) {
        uint256 lastBid = auction_.addressToAmount[msg.sender];
        uint256 newBid = (lastBid + msg.value);
        require(
            newBid > lastBid + ((lastBid * auction_.minBidIncrement) / 100),
            "New bid is lower than last bid plus minimum bid increment"
        );
        auction_.bidTree.remove(lastBid);
        auction_.totalValue += msg.value;
        auction_.addressToAmount[msg.sender] = newBid;
        auction_.amountToAddress[newBid] = msg.sender;
        auction_.bidTree.insert(newBid);
    }

    function validateBid(AuctionData storage auction_, address address_, uint256 amount_)
        public
        view
        returns (bool isReplacement)
    {
        return _validateBid(auction_, address_, amount_);
    }

    function _validateBid(
        AuctionData storage auction_,
        address address_,
        uint256 amount_
    ) internal view returns (bool isReplacement) {
        preCheckBid(auction_, address_, amount_);
        return isReplacementBid(auction_, amount_);
    }

    function preCheckBid(
        AuctionData storage auction_,
        address addr_,
        uint256 amount_
    ) internal view isAuctionActive(auction_) {
        // check if bid already exists
        require(auction_.addressToAmount[addr_] == 0, "Bidder already bid");
        // chheck if bid is greater than reserve price
        require(
            amount_ >= auction_.reservePrice,
            "Bid amount is less than reserve price"
        );
        // check if bid for this amount already exists
        require(!auction_.bidTree.exists(amount_), "Bid amount already exists");
    }

    function isReplacementBid(AuctionData storage auction_, uint256 value_)
        internal
        view
        returns (bool)
    {
        // see if we are replacing a bid
        if (auction_.winningBidsPlaced >= auction_.maxWinningBids) {
            // find lowest winning bid
            uint256 lowestBid = auction_.bidTree.first();
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
    function winnersOfAuction(AuctionData storage auction_) external view returns (address[] memory) {
        // create an array of addresses to store winners
        address[] memory winners = new address[](auction_.winningBidsPlaced);
        // get the first bid in the bid tree
        uint256 currentValue = auction_.bidTree.first();
        for (uint256 i = 0; i < auction_.winningBidsPlaced; i++) {
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
    function _refundBid(address to_, uint256 amount_) internal returns (bool) {
        // refund bid
        (bool success, ) = to_.call{gas: 30000, value: amount_}("");
        return success;
    }
}
