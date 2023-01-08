// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./RedBlackTreeLibrary.sol";

contract Auction {
    using RedBlackTreeLibrary for RedBlackTreeLibrary.Tree;
    RedBlackTreeLibrary.Tree bidTree;

    uint256 constant reservePrice = 0.01 ether; // 0.01 ETH
    uint256 constant minBidIncrementPercentage = 5; // 5%
    uint256 constant blockDuration = 1800; // about 6 hours

    mapping(address => uint256) public addressToAmount;
    mapping(uint256 => address) public amountToAddress;

    uint256 public maxWinningBids;
    uint256 public winningBidsPlaced;
    uint256 public totalPrizes;
    uint256 public prizesPerAddress;
    uint256 public startTime;
    uint256 public endTime;
    bool public settled;

    constructor(uint256 maxWinningBids_) {
        maxWinningBids = maxWinningBids_;
        startTime = block.number;
        endTime = block.number + blockDuration;

    }

    function addBid() public payable {
        // check if this is a valid bid
        uint256 lowestBid = validateBid(msg.value, msg.sender);
        // if number of winning bids is equal to max number of winning bids
        if (lowestBid > 0) {
            // remove lowest winning bid from bid tree
            bidTree.remove(lowestBid);
            // send lowest winning bid back to bidder
            _refundBid(amountToAddress[lowestBid], lowestBid);
        } else {
            // increment number of winning bids
            winningBidsPlaced++;
        }
        // add bid to active bid mapping
        addressToAmount[msg.sender] = msg.value;
        // for reverse tree lookup
        amountToAddress[msg.value] = msg.sender;
        // add bid to bid tree
        bidTree.insert(msg.value);

    }

    function removeBid() external {
        // check if auction is active
        checkActiveAuction();
        // get bid on this auction
        uint256 lastBid = addressToAmount[msg.sender];
        // remove lowest winning bid from bid tree
        bidTree.remove(lastBid);
        // send lowest winning bid back to bidder
        _refundBid(amountToAddress[lastBid], lastBid);
        // delete bid from active winningBidsPlaced
        winningBidsPlaced--;
    }

    function increaseBid() external payable {
        // get bid on this auction
        uint256 lastBid = addressToAmount[msg.sender];
        // check if bid is greater than last bid + reserve price
        require(
            msg.value > lastBid + ((lastBid * minBidIncrementPercentage) / 100),
            "New bid is too low"
        );
        // remove last bid from this auction
        addressToAmount[msg.sender] = 0;
        // add the new bid
        addBid();
    }

    function settleAuction() external {
        // check if the current auction has been settled
        require(!settled, "Auction has been settled");
        // check if the auction has ended
        require(endTime <= block.timestamp, "Auction has not ended");
        // set auction as settled
        settled = true;
        uint256 prizesPerAddressRemainder = totalPrizes % winningBidsPlaced;

        // map this auction => prizes per address mapping
        prizesPerAddress = totalPrizes / winningBidsPlaced;

        // TODO: CreateNextAuction + send all winners addresses to main contract + send all eth to main contract + prizesPerAddressRemainder to main contract
    }

    function collectPrizes() external {
        require(addressToAmount[msg.sender] > 0, "No prizes to collect");
        // remove this auction from the winners address => auctions[] mapping
        addressToAmount[msg.sender] = 0;
        //TODO:  mint the prizes for this auction
        //_mint(prizeAmount, msg.sender);
    }


    function validateBid(
        uint256 amount_,
        address addr_
    ) public view returns (uint256) {
        // check the active auction
        checkActiveAuction();
        // check if bid already exists
        require(addressToAmount[addr_] == 0, "Bid already exists");
        // chheck if bid is greater than reserve price
        require(
            amount_ > reservePrice,
            "Bid amount is less than reserve price"
        );
        // check if bid for this amount already exists
        require(!bidTree.exists(amount_), "Bid already exists");
        // check if new bid is valid
        return newValidBid(amount_);
    }

        /**
     * @dev checks if the auction is active and okay for bidding or bid removal
     * TODO: MAKE THIS A MODIFIER
     */
    function checkActiveAuction() public view {
        // check if the current auction has been settled
        require(settled, "Auction has been settled");
        // check if the auction has started
        require(startTime >= block.number, "Auction has not started");
        // check if the auction has ended
        require(endTime <= block.number, "Auction has ended");
    }

        function newValidBid(uint256 value_)
        public
        view
        returns (uint256)
    {
        // see if we are replacing a bid
        if (winningBidsPlaced >= maxWinningBids) {
            // find lowest winning bid
            uint256 lowestBid = bidTree.first();
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
     * @dev Returns the winners of an auction
     */
    function _winnersOfAuction()
        internal
        view
        returns (address[] memory)
    {
        // create an array of addresses to store winners
        address[] memory winners = new address[](winningBidsPlaced);
        // get the first bid in the bid tree
        uint256 currentValue = bidTree.first();
        for (uint256 i = 0; i < winningBidsPlaced; i++) {
            // add the address of the bid from the bid tree to the winners array
            winners[i] = amountToAddress[currentValue];
            // get the next bid in the bid tree
            currentValue = bidTree.next(currentValue);
        }
        // return the winners array
        return winners;
    }


        /**
     * @dev Refunds a bid and removes the bid from the active bid mapping
     */
    function _refundBid(address user_, uint256 amount_) internal {
        // delete bid from active bid mapping
        delete amountToAddress[amount_];
        // refund bid
        (bool sent, ) = user_.call{value: amount_}("");
        require(sent, "Refund failed");
    }
}
