const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RealEstate Contract", function () {
  let RealEstate, realEstate, owner, addr1, addr2;
  const PROPERTY_ADDRESS = "123 Main St";
  const PROPERTY_SIZE = 1000;
  const PROPERTY_CATEGORY = "house";
  const SALE_PRICE = ethers.parseEther("1");
  const RENT_MONTH = ethers.parseEther("0.1");
  const OFFER_AMOUNT = ethers.parseEther("1.1");
  const AUCTION_START_PRICE = ethers.parseEther("0.5");
  const AUCTION_DURATION = 86400; // 1 day in seconds

  beforeEach(async function () {
    [owner, addr1, addr2] = await ethers.getSigners();
    RealEstate = await ethers.getContractFactory("RealEstate");
    realEstate = await RealEstate.deploy();
    await realEstate.waitForDeployment();

    // Mint a property
    await realEstate.mint(owner.address, PROPERTY_ADDRESS, PROPERTY_SIZE, PROPERTY_CATEGORY);
  });

  it("Should mint a new property", async function () {
    const [addr, size, cat] = await realEstate.getProp(1);
    expect(addr).to.equal(PROPERTY_ADDRESS);
    expect(size).to.equal(PROPERTY_SIZE);
    expect(cat).to.equal(PROPERTY_CATEGORY);
    expect(await realEstate.ownerOf(1)).to.equal(owner.address);
  });

  it("Should list a property for sale", async function () {
    await realEstate.list(1, SALE_PRICE);
    const [, , , price, forSale] = await realEstate.getProp(1);
    expect(price).to.equal(SALE_PRICE);
    expect(forSale).to.be.true;
  });

  it("Should allow making and accepting an offer", async function () {
    await realEstate.list(1, SALE_PRICE);
    await realEstate.connect(addr1).makeOffer(1, { value: OFFER_AMOUNT });
    const initialBalance = await ethers.provider.getBalance(owner.address);
    await realEstate.acceptOffer(1, addr1.address);
    expect(await realEstate.ownerOf(1)).to.equal(addr1.address);
    const finalBalance = await ethers.provider.getBalance(owner.address);
    expect(finalBalance).to.be.gt(initialBalance);
  });

  it("Should allow withdrawing an offer", async function () {
    await realEstate.list(1, SALE_PRICE);
    await realEstate.connect(addr1).makeOffer(1, { value: OFFER_AMOUNT });
    const initialBalance = await ethers.provider.getBalance(addr1.address);
    await realEstate.connect(addr1).withdrawOffer(1);
    const finalBalance = await ethers.provider.getBalance(addr1.address);
    expect(finalBalance).to.be.gt(initialBalance);
  });

  it("Should list and rent a property", async function () {
    await realEstate.listRent(1, RENT_MONTH);
    const months = 2;
    const totalRent = RENT_MONTH * BigInt(months);
    await realEstate.connect(addr1).rent(1, months, { value: totalRent });
    const [, , , , , renter, rentalEnd] = await realEstate.getProp(1);
    expect(renter).to.equal(addr1.address);
    expect(rentalEnd).to.be.gt(0);
  });

  it("Should extend a rental", async function () {
    await realEstate.listRent(1, RENT_MONTH);
    await realEstate.connect(addr1).rent(1, 1, { value: RENT_MONTH });
    const [, , , , , , initialRentalEnd] = await realEstate.getProp(1);
    await realEstate.connect(addr1).extend(1, 1, { value: RENT_MONTH });
    const [, , , , , , finalRentalEnd] = await realEstate.getProp(1);
    expect(finalRentalEnd).to.be.gt(initialRentalEnd);
  });

  it("Should start and end an auction with a winning bid", async function () {
    await realEstate.startAuction(1, AUCTION_START_PRICE, AUCTION_DURATION);
    await realEstate.connect(addr1).bid(1, { value: AUCTION_START_PRICE + BigInt(1) });
    await ethers.provider.send("evm_increaseTime", [AUCTION_DURATION + 1]);
    await realEstate.endAuction(1);
    expect(await realEstate.ownerOf(1)).to.equal(addr1.address);
  });

  it("Should set and use a property manager", async function () {
    await realEstate.setMgr(1, addr2.address);
    await realEstate.connect(addr2).list(1, SALE_PRICE);
    const [, , , price, forSale] = await realEstate.getProp(1);
    expect(price).to.equal(SALE_PRICE);
    expect(forSale).to.be.true;
  });

  it("Should revert if unauthorized user tries to list property", async function () {
    await expect(realEstate.connect(addr1).list(1, SALE_PRICE)).to.be.revertedWith("Not auth");
  });

  it("Should correctly report if property is rented", async function () {
    await realEstate.listRent(1, RENT_MONTH);
    await realEstate.connect(addr1).rent(1, 1, { value: RENT_MONTH });
    expect(await realEstate.isRented(1)).to.be.true;
    await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]); // 31 days
    await ethers.provider.send("evm_mine"); // Mine a new block to apply time increase
    expect(await realEstate.isRented(1)).to.be.false;
  });
});