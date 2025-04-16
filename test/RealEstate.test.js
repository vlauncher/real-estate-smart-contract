const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("RealEstate Contract", function () {
  let RealEstate, realEstate, propertyOwner, buyer, manager;
  const PROPERTY_LOCATION = "123 Main St";
  const PROPERTY_AREA = 1000;
  const PROPERTY_CATEGORY = "house";
  const SALE_PRICE = ethers.parseEther("1");
  const MONTHLY_RENT = ethers.parseEther("0.1");
  const OFFER_AMOUNT = ethers.parseEther("1.1");

  beforeEach(async function () {
    [propertyOwner, buyer, manager] = await ethers.getSigners();
    RealEstate = await ethers.getContractFactory("RealEstate");
    realEstate = await RealEstate.deploy();
    await realEstate.waitForDeployment();

    // Mint a property
    await realEstate.mintProperty(propertyOwner.address, PROPERTY_LOCATION, PROPERTY_AREA, PROPERTY_CATEGORY);
  });

  it("Should mint a new property", async function () {
    const [location, area, category] = await realEstate.getPropertyDetails(1);
    expect(location).to.equal(PROPERTY_LOCATION);
    expect(area).to.equal(PROPERTY_AREA);
    expect(category).to.equal(PROPERTY_CATEGORY);
    expect(await realEstate.ownerOf(1)).to.equal(propertyOwner.address);
  });

  it("Should list a property for sale", async function () {
    await realEstate.listForSale(1, SALE_PRICE);
    const [, , , salePrice, isForSale] = await realEstate.getPropertyDetails(1);
    expect(salePrice).to.equal(SALE_PRICE);
    expect(isForSale).to.be.true;
  });

  it("Should allow making and accepting an offer", async function () {
    await realEstate.listForSale(1, SALE_PRICE);
    await realEstate.connect(buyer).makeOffer(1, { value: OFFER_AMOUNT });
    const initialBalance = await ethers.provider.getBalance(propertyOwner.address);
    await realEstate.acceptOffer(1, buyer.address);
    expect(await realEstate.ownerOf(1)).to.equal(buyer.address);
    const finalBalance = await ethers.provider.getBalance(propertyOwner.address);
    expect(finalBalance).to.be.gt(initialBalance);
  });

  it("Should allow withdrawing an offer", async function () {
    await realEstate.listForSale(1, SALE_PRICE);
    await realEstate.connect(buyer).makeOffer(1, { value: OFFER_AMOUNT });
    const initialBalance = await ethers.provider.getBalance(buyer.address);
    await realEstate.connect(buyer).withdrawOffer(1);
    const finalBalance = await ethers.provider.getBalance(buyer.address);
    expect(finalBalance).to.be.gt(initialBalance);
  });

  it("Should list and rent a property", async function () {
    await realEstate.listForRent(1, MONTHLY_RENT);
    const months = 2;
    const totalRent = MONTHLY_RENT * BigInt(months);
    await realEstate.connect(buyer).rentProperty(1, months, { value: totalRent });
    const [, , , , , renter, rentalEnd] = await realEstate.getPropertyDetails(1);
    expect(renter).to.equal(buyer.address);
    expect(rentalEnd).to.be.gt(0);
  });

  it("Should extend a rental", async function () {
    await realEstate.listForRent(1, MONTHLY_RENT);
    await realEstate.connect(buyer).rentProperty(1, 1, { value: MONTHLY_RENT });
    const [, , , , , , initialRentalEnd] = await realEstate.getPropertyDetails(1);
    await realEstate.connect(buyer).extendRental(1, 1, { value: MONTHLY_RENT });
    const [, , , , , , finalRentalEnd] = await realEstate.getPropertyDetails(1);
    expect(finalRentalEnd).to.be.gt(initialRentalEnd);
  });

  it("Should set and use a property manager", async function () {
    await realEstate.setManager(1, manager.address);
    await realEstate.connect(manager).listForSale(1, SALE_PRICE);
    const [, , , salePrice, isForSale] = await realEstate.getPropertyDetails(1);
    expect(salePrice).to.equal(SALE_PRICE);
    expect(isForSale).to.be.true;
  });

  it("Should revert if unauthorized user tries to list property", async function () {
    await expect(realEstate.connect(buyer).listForSale(1, SALE_PRICE)).to.be.revertedWith("Not authorized");
  });

  it("Should correctly report if property is rented", async function () {
    await realEstate.listForRent(1, MONTHLY_RENT);
    await realEstate.connect(buyer).rentProperty(1, 1, { value: MONTHLY_RENT });
    expect(await realEstate.isRented(1)).to.be.true;
    await ethers.provider.send("evm_increaseTime", [31 * 24 * 60 * 60]); // 31 days
    await ethers.provider.send("evm_mine"); // Mine a new block to apply time increase
    expect(await realEstate.isRented(1)).to.be.false;
  });
});