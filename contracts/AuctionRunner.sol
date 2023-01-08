// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./AuctionRuntime.sol";
import "./Constants.sol";

interface IAuctionRuntime {
    struct AuctionData {
        uint256 maxWinningBids;
        uint256 winningBidsPlaced;
        uint256 endTime;
        uint256 reservePrice;
        uint256 minBidIncrement;
        uint256 totalValue;
        uint256 lotSize;
    }

    function auction() external returns (AuctionRuntime.AuctionData memory);
}

interface IAuctionOwner {
    function newPrizePool(
        uint256 idIncrement_,
        uint256 prizesPerAddress_,
        uint256 slushPrizes_,
        address slushClaimer_,
        uint256 leftToMint_
    ) external;
}

contract AuctionRunner is AccessControl {
    enum LotType {
        TYPE_1,
        TYPE_2,
        TYPE_3,
        PHASE_4
    }
    mapping(address => uint256[]) public auctionsWon;

    uint256 public blockDuration = 1800;
    uint256 public reservePrice = 0.01 ether;
    uint256 public minBidIncrement = 5;

    AuctionRuntime public currentAuction;
    uint256 public auctionCount;

    address private _auctionOwner;
    address private _owner;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");

    modifier onlyOwner() {
        require(hasRole(OWNER_ROLE, msg.sender), "Caller is not a Owner");
        _;
    }

    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a Minter");
        _;
    }

    constructor(address owner_, address minter_) {
        _auctionOwner = minter_;
        _owner = owner_;
        _setupRole(OWNER_ROLE, owner_);
        _setupRole(MINTER_ROLE, minter_);
    }

    function startAuction() public onlyOwner {
        require(
            address(currentAuction) == address(0),
            "There is already an auction running"
        );
        _createAuction();
    }

    /**
     * THOU WHO SETTLES THE AUCTION SHALL RECEIVE 10% OF THE AUCTION'S VALUE
     */
    function settleAuction() public {
        require(!currentAuction.isPaused(), "Auction is paused");
        AuctionRuntime.AuctionData memory auction_ = IAuctionRuntime(
            address(currentAuction)
        ).auction();
        require(block.number >= auction_.endTime, "Auction has not ended");
        uint256 lowestId = _tokenIdRange(
            auctionCount,
            _getAuctionLotType(auctionCount)
        );

        uint256 idIncrement_ = lowestId;
        uint256 leftToMint_ = auction_.lotSize;
        uint256 prizesPerAddress_ = auction_.lotSize /
            auction_.winningBidsPlaced;
        uint256 prizesPerAddressRemainder = auction_.lotSize %
            auction_.winningBidsPlaced;
        // first person to mint from this pool gets the remainder
        address slushClaimer_;
        uint256 slushPrizes_;
        if (prizesPerAddressRemainder > 0) {
            slushClaimer_ = msg.sender;
            slushPrizes_ = prizesPerAddressRemainder;
        } else {
            slushClaimer_ = address(0);
            slushPrizes_ = 0;
        }

        IAuctionOwner(_auctionOwner).newPrizePool(
            idIncrement_,
            prizesPerAddress_,
            slushPrizes_,
            slushClaimer_,
            leftToMint_
        );

        address[] memory winners = currentAuction.winnersOfAuction();
        for (uint256 i = 0; i < winners.length; i++) {
            auctionsWon[winners[i]].push(auctionCount);
        }
        currentAuction.destroyAuction(msg.sender);
        _createAuction();
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

    function togglePaused() external onlyOwner {
        currentAuction.togglePaused();
    }

    function withdraw() external onlyOwner {
        (bool sent, ) = _owner.call{value: address(this).balance}("");
        require(sent, "Withdraw failed");
    }

    function collectPrizes(address user_) external onlyMinter returns (uint256) {
        require(!currentAuction.isPaused(), "Auction is paused");
        require(auctionsWon[user_].length > 0, "No prizes to collect");
        uint256 lastElIdx = auctionsWon[user_].length - 1;
        uint256 auctionClaim = auctionsWon[user_][lastElIdx];
        auctionsWon[user_].pop();
        return auctionClaim;
    }

    function hasPrizes() external view returns (bool) {
        return auctionsWon[msg.sender].length > 0;
    }

    function viewWinningAuctions(uint256 idx_) external view returns (uint256) {
        return auctionsWon[msg.sender][idx_];
    }

    function _createAuction() internal {
        auctionCount++;
        LotType lotType = _getAuctionLotType(auctionCount);
        (uint256 winnersAllowed, uint256 totalTokenAmount) = _getLotInfo(
            lotType
        );

        AuctionRuntime.AuctionData memory auctionData = AuctionRuntime
            .AuctionData(
                winnersAllowed,
                0,
                block.number + blockDuration,
                reservePrice,
                minBidIncrement,
                0,
                totalTokenAmount
            );
        AuctionRuntime newAuction = new AuctionRuntime(
            auctionData,
            address(this)
        );
        currentAuction = newAuction;
    }

    function _tokenIdRange(uint256 auctionNumber_, LotType auctionLotType_)
        internal
        pure
        returns (uint256)
    {
        uint256 tokenIdLow;
        uint256 typeCount;
        if (auctionLotType_ > LotType.TYPE_1) {
            tokenIdLow += TYPE_ONE_COUNT * TYPE_ONE_TOKEN_AMOUNT;
            typeCount += TYPE_ONE_COUNT;
        } else if (auctionLotType_ == LotType.TYPE_1) {
            tokenIdLow = TYPE_ONE_TOKEN_AMOUNT * (auctionNumber_ - 1);
        }
        if (auctionLotType_ > LotType.TYPE_2) {
            tokenIdLow += TYPE_TWO_COUNT * TYPE_TWO_TOKEN_AMOUNT;
            typeCount += TYPE_TWO_COUNT;
        } else if (auctionLotType_ == LotType.TYPE_2) {
            tokenIdLow =
                tokenIdLow +
                (TYPE_TWO_TOKEN_AMOUNT * ((auctionNumber_ - 1) - typeCount));
        }
        if (auctionLotType_ > LotType.TYPE_3) {
            tokenIdLow += TYPE_THREE_COUNT * TYPE_THREE_TOKEN_AMOUNT;
            typeCount += TYPE_THREE_COUNT;
        } else if (auctionLotType_ == LotType.TYPE_3) {
            tokenIdLow =
                tokenIdLow +
                (TYPE_TWO_TOKEN_AMOUNT * ((auctionNumber_ - 1) - typeCount));
        }
        if (auctionLotType_ > LotType.PHASE_4) {
            tokenIdLow += TYPE_FOUR_COUNT * TYPE_FOUR_TOKEN_AMOUNT;
            typeCount += TYPE_FOUR_COUNT;
        } else if (auctionLotType_ == LotType.PHASE_4) {
            tokenIdLow =
                tokenIdLow +
                (TYPE_TWO_TOKEN_AMOUNT * ((auctionNumber_ - 1) - typeCount));
        }
        // return the lowest token id
        return (tokenIdLow);
    }

    /**
     * @dev returns the lot type for the current auction
     * @return lotType the lot type for the current auction
     */
    function _getAuctionLotType(uint256 currentAuction_)
        internal
        pure
        returns (LotType lotType)
    {
        if (currentAuction_ <= TYPE_ONE_COUNT) {
            return LotType.TYPE_1;
        } else if (currentAuction_ <= TYPE_ONE_COUNT + TYPE_TWO_COUNT) {
            return LotType.TYPE_2;
        } else if (
            currentAuction_ <=
            TYPE_ONE_COUNT + TYPE_TWO_COUNT + TYPE_THREE_COUNT
        ) {
            return LotType.TYPE_3;
        } else if (
            currentAuction_ <=
            TYPE_ONE_COUNT + TYPE_TWO_COUNT + TYPE_THREE_COUNT + TYPE_FOUR_COUNT
        ) {
            return LotType.PHASE_4;
        }
    }

    /**
     * @dev returns the lot info for a given lot type
     * @param lotType_ the lot type to get info for
     * @return winnersAllowed the amount of winners allowed for this lot type
     * @return totalTokenAmount the total amount of tokens per auction of this type
     */
    function _getLotInfo(LotType lotType_)
        internal
        pure
        returns (uint256 winnersAllowed, uint256 totalTokenAmount)
    {
        // get the lot info for the given lot type
        if (lotType_ == LotType.TYPE_1) {
            return (TYPE_ONE_WINNERS, TYPE_ONE_TOKEN_AMOUNT);
        } else if (lotType_ == LotType.TYPE_2) {
            return (TYPE_TWO_WINNERS, TYPE_TWO_TOKEN_AMOUNT);
        } else if (lotType_ == LotType.TYPE_3) {
            return (TYPE_THREE_WINNERS, TYPE_THREE_TOKEN_AMOUNT);
        } else if (lotType_ == LotType.PHASE_4) {
            return (TYPE_FOUR_WINNERS, TYPE_FOUR_TOKEN_AMOUNT);
        }
    }

    receive() external payable {}
}
