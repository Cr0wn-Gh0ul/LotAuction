import {
  TransactionReceipt,
  TransactionResponse,
} from "@ethersproject/abstract-provider";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { contract, network, ethers } from "hardhat";
import { AuctionHouse } from "../typechain-types";
import { ContractTransaction } from "@ethersproject/contracts";
import type {BigNumber} from '@ethersproject/bignumber';
import { mine } from "@nomicfoundation/hardhat-network-helpers";

let signers: SignerWithAddress[];
let owner: SignerWithAddress;
let badActor: SignerWithAddress;
let auctionH: AuctionHouse;

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
    expect(auctionH.address).to.not.be.undefined;
  });
  it("should get auction", async () => {
    let tx = await auctionH.getAuction();
    expect(tx).to.not.be.undefined;
  });
  it("should bid in auction", async () => {
    let options = {
      value: ethers.utils.parseEther("0.01"),
    };
    let signerAuction = auctionH.connect(signers[0]);
    let tx = await signerAuction.addBid(options);
    await tx.wait(1);
  });
  it("should remove bid in auction", async () => {
    let signerAuction = auctionH.connect(signers[0]);
    let tx = await signerAuction.removeBid();
    await tx.wait(1);
  });
  it("should add new bid in auction", async () => {
    let options = {
      value: ethers.utils.parseEther("0.01"),
    };
    let signerAuction = auctionH.connect(signers[0]);
    let tx = await signerAuction.addBid(options);
    await tx.wait(1);
  });
  it("should increase bid in auction", async () => {
    let options = {
      value: ethers.utils.parseEther("0.005"),
    };
    let signerAuction = auctionH.connect(signers[0]);
    let tx = await signerAuction.increaseBid(options);
    await tx.wait(1);
  });
  it("should remove increased bid", async () => {
    let signerAuction = auctionH.connect(signers[0]);
    let tx = await signerAuction.removeBid();
    await tx.wait(1);
  });
  it("should bid large amount in auction", async () => {
    let options = {
      value: ethers.utils.parseEther("10"),
    };
    let signerAuction = auctionH.connect(signers[0]);
    let tx = await signerAuction.addBid(options);
    await tx.wait(1);
  });
  it("should remove bid and be refunded", async () => {
    let balance = await signers[0].getBalance()
    let signerAuction = auctionH.connect(signers[0]);
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
      let signerAuction = auctionH.connect(signers[i]);
      let tx = await signerAuction.addBid(options);
      await tx.wait(1);
    }
  });
  it("should not accept bids lower than lowest bid", async () => {
    let options = {
      value: ethers.utils.parseEther("0.019"),
    };
    let signerAuction = auctionH.connect(badActor);
    let tx = signerAuction.addBid(options);
    expect(tx).to.be.revertedWith("Bid amount is less than the lowest winning bid + minBidIncrement")
   });
   it("should not accept bids lower than lowest bid + min increment", async () => {
    let options = {
      value: ethers.utils.parseEther("0.02000000000001"),
    };
    let signerAuction = auctionH.connect(badActor);
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
    let signerAuction = auctionH.connect(badActor);
    let tx = signerAuction.addBid(options);
    await expect(tx).to.be.revertedWith("Auction has ended")
  });
  it("should not accept increased bids", async () => {
    let options = {
      value: ethers.utils.parseEther("10"),
    };
    let signerAuction = auctionH.connect(signers[0]);
    let tx = signerAuction.increaseBid(options);
    await expect(tx).to.be.revertedWith("Auction has ended")
  });
  it("should not accept removed bids", async () => {
    let signerAuction = auctionH.connect(signers[0]);
    let tx = signerAuction.removeBid();
    await expect(tx).to.be.revertedWith("Auction has ended")
  });
  it("should settle auction for reward", async () => {
    let balance = await signers[signers.length-1].getBalance()
    let signerAuction = auctionH.connect(signers[signers.length-1]);
    let tx = await signerAuction.settleAuction();
    await tx.wait(1);
    let newBalance = await signers[signers.length-1].getBalance()
    expect(newBalance).to.be.gt(balance)
  });
  it("should not collect pizes if not winner", async () => {
    let signerAuction = auctionH.connect(badActor);
      let tx = signerAuction.collectPrizes();
      await expect(tx).to.be.revertedWith("No prizes to collect")
  });
  it("should see prizes to collect", async () => {
    let signerAuction = auctionH.connect(signers[0]);
    let tx = await signerAuction.viewPrizesCount();
    expect(tx.toString()).to.be.eq("4");
  });

  it("half should collect prizes", async () => {
    for (let i = 0; i < 32; i++) {
      let signerAuction = auctionH.connect(signers[i]);
      let tx = await signerAuction.collectPrizes();
      await tx.wait(1);
    }
  });
  it("should get next auction", async () => {
    let tx = await auctionH.auctionNow()
    expect(tx.toString()).to.be.eq("2");
  });
  it("second half should collect prizes from first auction", async () => {
    for (let i = 32; i < 64; i++) {
      let signerAuction = auctionH.connect(signers[i]);
      let tx = await signerAuction.collectPrizes();
      await tx.wait(1);
    }
  });
});

/*
async function createFundedAccounts() {
  let fundingTxs: Array<Promise<ContractTransaction>> = [];
  for (let i = 0; i < 100; i++) {
    let funder = signers[(i % signers.length) - 1 + 1];
    let wallet = ethers.Wallet.createRandom();
    let signer = await ethers.getSigner(wallet.address);
    fundedAccounts.push(signer);
    fundingTxs.push(
      funder.sendTransaction({
        to: wallet.address,
        value: ethers.utils.parseEther("1.0"),
      })
    );
  }
  await Promise.allSettled(fundingTxs).then(async () => {
    for (let i = 0; i < fundingTxs.length; i++) {
      let txResponse = await fundingTxs[i];
      await txResponse.wait();
    }
  });
}
*/

async function deploy() {
  const Auction = await ethers.getContractFactory("AuctionLibrary");
  const auction = await Auction.deploy();
  await auction.deployTransaction.wait(3);
  const AuctionHouse = await ethers.getContractFactory("AuctionHouse", {
    libraries: {
      AuctionLibrary: auction.address,
    },
  });
  const auctionHouse = await AuctionHouse.deploy();
  await auctionHouse.deployTransaction.wait(3);
  auctionH = auctionHouse as AuctionHouse;
}

async function skipToAuctionEnd() {
  let latestBlock = await ethers.provider.getBlock("latest")
  let tx = await auctionH.getAuction();
  let numberOfBlocks = ((tx.endTime.toNumber() - latestBlock.number) + 1)
  await mine(numberOfBlocks)
}

