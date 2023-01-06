import {
  TransactionReceipt,
  TransactionResponse,
} from "@ethersproject/abstract-provider";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { contract, ethers } from "hardhat";
import { AuctionHouse } from "../typechain-types";
import { ContractTransaction } from "@ethersproject/contracts";

let signers: SignerWithAddress[];
let owner: SignerWithAddress;
let auctionH: AuctionHouse;

describe("Auction", () => {
  before(async () => {
    signers = await ethers.getSigners();
    owner = signers[0];
    signers.shift();
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
  ///
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
  it("should add 64 bids in auction", async () => {
    let bidValue = ethers.utils.parseEther("0.01")
    for (let i = 0; i < 64; i++) {
      bidValue = bidValue.add(bidValue.mul(5).div(100))
      console.log(bidValue.toString())
      let options = {
        value: bidValue,
      };
      let signerAuction = auctionH.connect(signers[i]);
      let tx = await signerAuction.addBid(options);
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
