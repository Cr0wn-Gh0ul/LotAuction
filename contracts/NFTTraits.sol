// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "./AuctionRunner.sol";

contract NFTTraits is ERC721 {
    AuctionRunner public auctionRunner;
    struct PrizePool {
        uint256 idIncrement;
        uint256 prizesPerAddress;
        uint256 slushPrizes;
        address slushClaimer;
        uint256 leftToMint;
        uint256 currentPrng;
        mapping(uint256 => uint256) idSwaps;
    }
    mapping(uint256 => PrizePool) public prizePool;

    address private _owner;

    modifier onlyAuctionRunner() {
        require(
            msg.sender == address(auctionRunner),
            "Caller is not the auction runner"
        );
        _;
    }

    constructor() ERC721("AuctionHouse", "AH") {
        _owner = msg.sender;
        auctionRunner = new AuctionRunner(msg.sender, address(this));
    }

    function mint() public {
        uint256 poolId = auctionRunner.collectPrizes(msg.sender);
        require(poolId > 0, "No prizes to collect");
        _mint(poolId, msg.sender);
    }

    function canMint() external view returns (bool) {
        return auctionRunner.hasPrizes();
    }

    function newPrizePool(
        uint256 idIncrement_,
        uint256 prizesPerAddress_,
        uint256 slushPrizes_,
        address slushClaimer_,
        uint256 leftToMint_
    ) external onlyAuctionRunner {
        uint256 poolId = auctionRunner.auctionCount();
        PrizePool storage pPool = prizePool[poolId];
            pPool.idIncrement = idIncrement_;
            pPool.prizesPerAddress = prizesPerAddress_;
            pPool.slushPrizes = slushPrizes_;
            pPool.slushClaimer = slushClaimer_;
            pPool.leftToMint = leftToMint_;        
    }

    /**
     * @dev Mints a number of tokens for a winner of an auction
     */
    function _mint(uint256 auctionId_, address to_) internal {
        PrizePool storage pPool = prizePool[auctionId_];
        uint256 idIncrementer = pPool.idIncrement;
        uint256 amount = pPool.prizesPerAddress;
        if (pPool.slushClaimer == msg.sender) {
            amount += pPool.slushPrizes;
            pPool.slushPrizes = 0;
            pPool.slushClaimer = address(0);
        }
        // get how many tokens are left to mint for this auction
        uint256 leftToMint = pPool.leftToMint;
        // get the current prng for this auction
        uint256 currentPrng = pPool.currentPrng;
        // loop through the amount of tokens to mint
        for (uint256 i = 0; i < amount; i++) {
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
            _safeMint(to_, (tokenId + idIncrementer));
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
}
