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

let auctionAmount = 5;
let auctionArray = new Array(auctionAmount);

describe("Auction Advanced", async () => {
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
  auctionArray.forEach(function (item, index) {
    it(index + " should add 64 bids in auction", async () => {
      let bidValue = ethers.utils.parseEther("0.02");
      for (let i = 0; i < 64; i++) {
        bidValue = bidValue.add(bidValue.mul(5).div(100));
        let options = {
          value: bidValue,
        };
        let signerAuction = currentAuction.connect(signers[i]);
        let tx = await signerAuction.addBid(options);
        await tx.wait(1);
      }
    });
    it("should mine to after auction ends", async () => {
      await skipToAuctionEnd();
    });
    it("should settle auction for reward", async () => {
      let balance = await signers[signers.length - 1].getBalance();
      let signerAuction = currentAuction.connect(signers[signers.length - 1]);
      let tx = await signerAuction.settleAuction();
      await tx.wait(1);
      let newBalance = await signers[signers.length - 1].getBalance();
      expect(newBalance).to.be.gt(balance);
    });
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
