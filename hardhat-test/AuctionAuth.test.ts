import {
  TransactionReceipt,
  TransactionResponse,
} from "@ethersproject/abstract-provider";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { contract, network, ethers } from "hardhat";
import { AuctionRunner, NFTTraits } from "../typechain-types";
import { ContractTransaction } from "@ethersproject/contracts";
import type { BigNumber } from "@ethersproject/bignumber";
import { mine } from "@nomicfoundation/hardhat-network-helpers";

let signers: SignerWithAddress[];
let owner: SignerWithAddress;
let badActor: SignerWithAddress;

let nftContract: NFTTraits;
let currentAuction: AuctionRunner;

describe("Auction Auth", () => {
  before(async () => {
    signers = await ethers.getSigners();
    signers.forEach((signer) => {
      let orig = signer.sendTransaction;
      signer.sendTransaction = function (transaction) {
        transaction.gasLimit = ethers.BigNumber.from("15000000".toString());
        return orig.apply(signer, [transaction]);
      };
    });
    owner = signers[0];
    signers.shift();
    badActor = signers[signers.length - 1];
    signers.pop();
  });
  it("should deploy", async () => {
    await deploy();
    expect(currentAuction.address).to.not.be.undefined;
  });
  it("should fail newPrizePool()", async () => {
    let signerAuction = nftContract.connect(owner);
    let tx = signerAuction.newPrizePool(1,2,3,owner.address,5);
    expect(tx).to.be.revertedWith("Caller is not the auction runner")
  });
  it("should fail updateAuctionRunner()", async () => {
    let signerAuction = nftContract.connect(badActor);
    let tx = signerAuction.updateAuctionRunner(badActor.address);
    expect(tx).to.be.revertedWith("Ownable: caller is not the owner")
  });
  it("should success updateAuctionRunner()", async () => {
    let signerAuction = nftContract.connect(owner);
    let tx = await signerAuction.updateAuctionRunner(owner.address);
  });
  it("should fail setBlockDuration()", async () => {
    let signerAuction = currentAuction.connect(badActor);
    let tx = signerAuction.setBlockDuration(1234);
    expect(tx).to.be.revertedWith("Caller is not a Owner")
  });
  it("should success setBlockDuration()", async () => {
    let signerAuction = currentAuction.connect(owner);
    await signerAuction.setBlockDuration(1234);
  });
  it("should fail setReservePrice()", async () => {
    let signerAuction = currentAuction.connect(badActor);
    let tx = signerAuction.setReservePrice(1234);
    expect(tx).to.be.revertedWith("Caller is not a Owner")
  });
  it("should success setReservePrice()", async () => {
    let signerAuction = currentAuction.connect(owner);
    await signerAuction.setReservePrice(1234);
  });
  it("should fail setMinBidIncrement()", async () => {
    let signerAuction = currentAuction.connect(badActor);
    let tx = signerAuction.setMinBidIncrement(1234);
    expect(tx).to.be.revertedWith("Caller is not a Owner")
  });
  it("should success setMinBidIncrement()", async () => {
    let signerAuction = currentAuction.connect(owner);
    await signerAuction.setMinBidIncrement(1234);
  });
  it("should fail togglePaused()", async () => {
    let signerAuction = currentAuction.connect(badActor);
    let tx = signerAuction.togglePaused();
    expect(tx).to.be.revertedWith("Caller is not a Owner")
  });
  it("should success togglePaused()", async () => {
    let signerAuction = currentAuction.connect(owner);
    await signerAuction.togglePaused();
  });
  it("should fail withdraw()", async () => {
    let signerAuction = currentAuction.connect(badActor);
    let tx = signerAuction.withdraw();
    expect(tx).to.be.revertedWith("Caller is not a Owner")
  });
  it("should success togglePaused()", async () => {
    let signerAuction = currentAuction.connect(owner);
    await signerAuction.withdraw();
  });
  it("should not collect pizes if not from nft contract", async () => {
    let signerAuction = currentAuction.connect(badActor);
      let tx = signerAuction.collectPrizes(badActor.address);
      await expect(tx).to.be.revertedWith("Caller is not a Minter")
  });
});

async function deploy() {
  const Auction = await ethers.getContractFactory("AuctionRuntimeLibrary");
  const auction = await Auction.deploy();
  await auction.deployTransaction.wait(2);
  const NFTTraits = await ethers.getContractFactory("NFTTraits", {
    libraries: {
      AuctionRuntimeLibrary: auction.address,
    },
  });
  const nft = await NFTTraits.deploy();
  await nft.deployTransaction.wait(2);
  nftContract = nft as NFTTraits;
  let auctionRunnerAddress = await nftContract.auctionRunner();
  currentAuction = await ethers.getContractAt(
    "AuctionRunner",
    auctionRunnerAddress
  );
  let tx = await currentAuction.startAuction();
  await tx.wait(2);
}

async function skipToAuctionEnd() {
  let latestBlock = await ethers.provider.getBlock("latest");
  let tx = await currentAuction.getAuctionEndTime();
  let numberOfBlocks = tx.toNumber() - latestBlock.number + 1;
  await mine(numberOfBlocks);
}
