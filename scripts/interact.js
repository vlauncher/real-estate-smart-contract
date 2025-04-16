const hre = require("hardhat");

async function main() {
  const contractAddress = "0x5FbDB2315678afecb367f032d93F642f64180aa3"; // Replace with actual deployed address
  const [owner, buyer] = await hre.ethers.getSigners();

  const RealEstate = await hre.ethers.getContractFactory("RealEstate");
  const realEstate = await RealEstate.attach(contractAddress);

  // Mint a new property
  console.log("Minting a new property...");
  const mintTx = await realEstate.mint(
    owner.address,
    "123 Main St",
    1000,
    "house"
  );
  await mintTx.wait();
  console.log("Property minted with tokenId 1");

  // List property for sale
  const price = hre.ethers.parseEther("1");
  console.log("Listing property for sale...");
  const listTx = await realEstate.list(1, price);
  await listTx.wait();
  console.log("Property listed for 1 ETH");

  // Make an offer
  console.log("Making an offer...");
  const offerTx = await realEstate.connect(buyer).makeOffer(1, {
    value: hre.ethers.parseEther("1.1"),
  });
  await offerTx.wait();
  console.log("Offer made by buyer");

  // Accept offer
  console.log("Accepting offer...");
  const acceptTx = await realEstate.acceptOffer(1, buyer.address);
  await acceptTx.wait();
  console.log("Offer accepted, property transferred");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });