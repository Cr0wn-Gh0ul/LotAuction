// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Constants.sol";
import "./RedBlackTreeLibrary.sol";

library AuctionLibrary {
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;
    enum LotType {
        PHASE_1,
        PHASE_2,
        PHASE_3,
        PHASE_4
    }
    struct Auction {
        AuctionBase auctionBase;
        LotType lotType;
        mapping(address => uint256) addressToAmount;
        mapping(uint256 => address) amountToAddress;
        RedBlackTreeLibrary.Tree bidTree;
    }

    struct AuctionBase {
        uint256 maxWinningBids;
        uint256 winningBidsPlaced;
        uint256 startTime;
        uint256 endTime;
        uint256 reservePrice;
        uint256 minBidIncrement;
        uint256 totalValue;
        bool settled;
    }

        /**
     * @dev checks if the auction is active and okay for bidding or bid removal
     * TODO: ONLY ENDED is needed
     */
    modifier checkActiveAuction(Auction storage auction_) {
        // check if the current auction has been settled
        require(!auction_.auctionBase.settled, "Auction has been settled");
        // check if the auction has started
        require(block.number >= auction_.auctionBase.startTime, "Auction has not started");
        // check if the auction has ended
        require(block.number <= auction_.auctionBase.endTime, "Auction has ended");
        _;
    }


    function addBid(Auction storage auction_) public {
        // check if this is a valid bid
        uint256 lowestBid = validateBid(auction_, msg.value, msg.sender);
        // if number of winning bids is equal to max number of winning bids
        if (lowestBid > 0) {
            // remove lowest winning bid from bid tree
            auction_.bidTree.remove(lowestBid);
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

    function validateBid(
        Auction storage auction_,
        uint256 amount_,
        address addr_
    ) public view checkActiveAuction(auction_) 
    returns (uint256) {
        // check if bid already exists
        require(auction_.addressToAmount[addr_] == 0, "Bid already exists");
        // chheck if bid is greater than reserve price
        require(
            amount_ >= auction_.auctionBase.reservePrice,
            "Bid amount is less than reserve price"
        );
        // check if bid for this amount already exists
        require(!auction_.bidTree.exists(amount_), "Bid already exists");
        // check if new bid is valid
        return newValidBid(auction_, amount_);
    }

    function newValidBid(Auction storage auction_, uint256 value_)
        public
        view
        returns (uint256)
    {
        // see if we are replacing a bid
        if (auction_.auctionBase.winningBidsPlaced >= auction_.auctionBase.maxWinningBids) {
            // find lowest winning bid
            uint256 lowestBid = auction_.bidTree.first();
            // require bid is greater than lowest winning bid
            require(
                value_ >=
                    lowestBid + ((lowestBid * auction_.auctionBase.minBidIncrement) / 100),
                "Bid amount is less than the lowest winning bid + minBidIncrement"
            );
            // return the lowest winning bid
            return lowestBid;
        }
        // max number of winning bids not reached
        return 0;
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
        Auction storage auction_,
        address user_,
        uint256 amount_
    ) internal {
        // delete bid from active bid mapping
        delete auction_.amountToAddress[amount_];
        // refund bid
        (bool sent, ) = user_.call{value: amount_}("");
        require(sent, "Refund failed");
    }


    function _tokenIdRange(uint256 auctionId_, LotType auctionLotType)
        internal
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {

        // get the token id range for the auction
        uint256 tokenAmount;
        // get the highest token id for this auction
        uint256 tokenIdHigh;
        // get the lowest token id for this auction
        uint256 tokenIdLow;
        // get the token id range for the auction based on the auction phase
        if (auctionLotType > LotType.PHASE_1) {
            tokenIdHigh += PHASE_ONE_COUNT * PHASE_ONE_TOKEN_AMOUNT;
        } else if (auctionLotType == LotType.PHASE_1) {
            tokenIdHigh += auctionId_ * PHASE_ONE_TOKEN_AMOUNT;
            tokenIdLow = tokenIdHigh - PHASE_ONE_TOKEN_AMOUNT;
            tokenAmount = PHASE_ONE_TOKEN_AMOUNT;
        }
        if (auctionLotType > LotType.PHASE_2) {
            tokenIdHigh += PHASE_TWO_COUNT * PHASE_TWO_TOKEN_AMOUNT;
        } else if (auctionLotType == LotType.PHASE_2) {
            tokenIdHigh += auctionId_ * PHASE_TWO_TOKEN_AMOUNT;
            tokenIdLow = tokenIdHigh - PHASE_TWO_TOKEN_AMOUNT;
            tokenAmount = PHASE_TWO_TOKEN_AMOUNT;
        }
        if (auctionLotType > LotType.PHASE_3) {
            tokenIdHigh += PHASE_THREE_COUNT * PHASE_THREE_TOKEN_AMOUNT;
        } else if (auctionLotType == LotType.PHASE_3) {
            tokenIdHigh += auctionId_ * PHASE_THREE_TOKEN_AMOUNT;
            tokenIdLow = tokenIdHigh - PHASE_THREE_TOKEN_AMOUNT;
            tokenAmount = PHASE_THREE_TOKEN_AMOUNT;
        }
        if (auctionLotType > LotType.PHASE_4) {
            tokenIdHigh += PHASE_FOUR_COUNT * PHASE_FOUR_TOKEN_AMOUNT;
        } else if (auctionLotType == LotType.PHASE_4) {
            tokenIdHigh += auctionId_ * PHASE_FOUR_TOKEN_AMOUNT;
            tokenIdLow = tokenIdHigh - PHASE_FOUR_TOKEN_AMOUNT;
            tokenAmount = PHASE_FOUR_TOKEN_AMOUNT;
        }
        // return the lowest token id, the highest token id, and the amount of tokens in the auction
        return (tokenIdLow, tokenIdHigh, tokenAmount);
    }

    /**
     * @dev returns the lot type for the current auction
     * @return lotType the lot type for the current auction
     */
    function _getAuctionLotType(uint256 currentAuction) internal pure returns (LotType lotType) {
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

    /**
     * @dev returns the lot info for a given lot type
     * @param lotType_ the lot type to get info for
     * @return winnersAllowed the amount of winners allowed for this lot type
     * @return amountOfType the amount of auctions of this type
     * @return totalAmount the total amount of tokens per auction of this type
     */
    function _getLotInfo(LotType lotType_)
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
}
