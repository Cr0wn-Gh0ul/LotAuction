import {
  TransactionReceipt,
  TransactionResponse,
} from "@ethersproject/abstract-provider";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { contract, network, ethers } from "hardhat";
import { AuctionRunner } from "../typechain-types";
import { ContractTransaction } from "@ethersproject/contracts";
import type {BigNumber} from '@ethersproject/bignumber';
import { mine } from "@nomicfoundation/hardhat-network-helpers";
import { AuctionRuntime, NFTTraits } from "../typechain-types/contracts";

let signers: SignerWithAddress[];
let owner: SignerWithAddress;
let badActor: SignerWithAddress;

let nftContract: NFTTraits
let auctionHouse: AuctionRunner;
let currentAuction: AuctionRuntime;

describe("Auction", () => {
  before(async () => {
    signers = await ethers.getSigners();
    signers.forEach(signer => {
      let orig = signer.sendTransaction;
      signer.sendTransaction = function(transaction) {
        transaction.gasLimit = ethers.BigNumber.from("15000000".toString());
        return orig.apply(signer, [transaction]);
      }
    });
    owner = signers[0];
    signers.shift();
    badActor = signers[signers.length - 1]
    signers.pop();
  });
  it("should deploy", async () => {
    await deploy();
    expect(currentAuction.address).to.not.be.undefined;
  });
  it("should get auction", async () => {
    let tx = await currentAuction.auction();
    expect(tx).to.not.be.undefined;
  });
  it("should bid in auction", async () => {
    let options = {
      value: ethers.utils.parseEther("0.01"),
    };
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = await signerAuction.addBid(options);
    await tx.wait(1);
  });
  it("should remove bid in auction", async () => {
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = await signerAuction.removeBid();
    await tx.wait(1);
  });
  it("should add new bid in auction", async () => {
    let options = {
      value: ethers.utils.parseEther("0.01"),
    };
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = await signerAuction.addBid(options);
    await tx.wait(1);
  });
  it("should increase bid in auction", async () => {
    let options = {
      value: ethers.utils.parseEther("0.005"),
    };
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = await signerAuction.increaseBid(options);
    await tx.wait(1);
  });
  it("should remove increased bid", async () => {
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = await signerAuction.removeBid();
    await tx.wait(1);
  });
  it("should bid large amount in auction", async () => {
    let options = {
      value: ethers.utils.parseEther("10"),
    };
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = await signerAuction.addBid(options);
    await tx.wait(1);
  });
  it("should remove bid and be refunded", async () => {
    let balance = await signers[0].getBalance()
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = await signerAuction.removeBid();
    let receipt = await tx.wait(1);
    let gas = ethers.BigNumber.from(receipt.cumulativeGasUsed).mul(receipt.effectiveGasPrice);
    let newBalance = await signers[0].getBalance()
    expect(newBalance).to.be.eq(balance.add(ethers.utils.parseEther("10")).sub(gas))
  });
  it("should add 64 bids in auction", async () => {
    let bidValue = ethers.utils.parseEther("0.02")
    for (let i = 0; i < 64; i++) {
      bidValue = bidValue.add(bidValue.mul(5).div(100))
      let options = {
        value: bidValue,
      };
      let signerAuction = currentAuction.connect(signers[i]);
      let tx = await signerAuction.addBid(options);
      await tx.wait(1);
    }
  });
  it("should not accept bids lower than lowest bid", async () => {
    let options = {
      value: ethers.utils.parseEther("0.019"),
    };
    let signerAuction = currentAuction.connect(badActor);
    let tx = signerAuction.addBid(options);
    expect(tx).to.be.revertedWith("Bid amount is less than the lowest winning bid + minBidIncrement")
   });
   it("should not accept bids lower than lowest bid + min increment", async () => {
    let options = {
      value: ethers.utils.parseEther("0.02000000000001"),
    };
    let signerAuction = currentAuction.connect(badActor);
    let tx = signerAuction.addBid(options);
    expect(tx).to.be.revertedWith("Bid amount is less than the lowest winning bid + minBidIncrement")
   });
   
  it("should mine to after auction ends", async () => {
    await skipToAuctionEnd()
  });
  it("should not accept new bids", async () => {
    let options = {
      value: ethers.utils.parseEther("10"),
    };
    let signerAuction = currentAuction.connect(badActor);
    let tx = signerAuction.addBid(options);
    await expect(tx).to.be.revertedWith("Auction has ended")
  });
  it("should not accept increased bids", async () => {
    let options = {
      value: ethers.utils.parseEther("10"),
    };
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = signerAuction.increaseBid(options);
    await expect(tx).to.be.revertedWith("Auction has ended")
  });
  it("should not accept removed bids", async () => {
    let signerAuction = currentAuction.connect(signers[0]);
    let tx = signerAuction.removeBid();
    await expect(tx).to.be.revertedWith("Auction has ended")
  });
  
  it("should settle auction for reward", async () => {
    let balance = await signers[signers.length-1].getBalance()
    let signerAuction = auctionHouse.connect(signers[signers.length-1]);
    let tx = await signerAuction.settleAuction();
    await tx.wait(1);
    let newBalance = await signers[signers.length-1].getBalance()
    expect(newBalance).to.be.gt(balance)
  });
  it("should not collect pizes if not from nft contract", async () => {
    let signerAuction = auctionHouse.connect(badActor);
      let tx = signerAuction.collectPrizes(badActor.address);
      await expect(tx).to.be.revertedWith("Caller is not a Minter")
  });
  /*
  it("should see prizes to collect", async () => {
    let signerAuction = auctionHouse.connect(signers[0]);
    let tx = await signerAuction.viewPrizesCount();
    expect(tx.toString()).to.be.eq("4");
  });
*/
  it("half should collect prizes", async () => {
    for (let i = 0; i < 32; i++) {
      let signerAuction = nftContract.connect(signers[i]);
      let tx = await signerAuction.mint();
      await tx.wait(1);
    }
  });
  it("should get next auction", async () => {
    let tx = await auctionHouse.auctionCount()
    expect(tx.toString()).to.be.eq("2");
  });
  it("second half should collect prizes from first auction", async () => {
    for (let i = 32; i < 64; i++) {
      let signerAuction = nftContract.connect(signers[i]);
      let tx = await signerAuction.mint();
      await tx.wait(1);
    }
  });
  
});

async function deploy() {
  const NFTTraits = await ethers.getContractFactory("NFTTraits");
  const nft = await NFTTraits.deploy();
  await nft.deployTransaction.wait(2);
  nftContract = nft as NFTTraits;
  let auctionRunnerAddress = await nftContract.auctionRunner();
  auctionHouse = await ethers.getContractAt("AuctionRunner", auctionRunnerAddress);
  await startAuction();
  await setCurrentAuction()
}

async function startAuction() {
  let tx = await auctionHouse.startAuction();
  await tx.wait(2);
}

async function setCurrentAuction() {
  let currentAuctionAddress = await auctionHouse.currentAuction();
  let auction = await ethers.getContractAt("AuctionRuntime", currentAuctionAddress);
  currentAuction = auction as AuctionRuntime;
}

async function skipToAuctionEnd() {
  let latestBlock = await ethers.provider.getBlock("latest")
  let tx = await currentAuction.auction();
  let numberOfBlocks = ((tx.endTime.toNumber() - latestBlock.number) + 1)
  await mine(numberOfBlocks)
}


