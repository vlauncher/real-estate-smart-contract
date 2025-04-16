// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RealEstate is ERC721, Ownable {
    uint256 private nextTokenId;

    struct Property {
        string location;      // Property address or location
        uint256 area;        // Area of the property in square units
        string category;     // Category: house, apartment, land, etc.
        uint256 salePrice;   // Sale price in wei
        bool isForSale;     // True if listed for sale
        address renter;      // Current renter's address
        uint256 rentalEnd;   // Rental end timestamp
        uint256 monthlyRent; // Monthly rent in wei
    }

    mapping(uint256 => Property) public properties;
    mapping(uint256 => mapping(address => uint256)) public offers;
    mapping(uint256 => address) public managers;

    event PropertyMinted(uint256 tokenId, address owner, string location);
    event PropertyListed(uint256 tokenId, uint256 price);
    event OfferMade(uint256 tokenId, address buyer, uint256 amount);
    event OfferAccepted(uint256 tokenId, address buyer, uint256 amount);
    event OfferWithdrawn(uint256 tokenId, address buyer);
    event PropertyRented(uint256 tokenId, address renter, uint256 months, uint256 total);
    event RentalExtended(uint256 tokenId, uint256 additionalMonths, uint256 additionalRent);

    constructor() ERC721("RealEstate", "RE") Ownable(msg.sender) {
        nextTokenId = 0;
    }

    // Mint a new property (owner-only)
    function mintProperty(address to, string memory location, uint256 area, string memory category) public onlyOwner {
        nextTokenId++;
        uint256 tokenId = nextTokenId;
        _mint(to, tokenId);
        properties[tokenId] = Property(location, area, category, 0, false, address(0), 0, 0);
        emit PropertyMinted(tokenId, to, location);
    }

    // List property for sale
    function listForSale(uint256 tokenId, uint256 price) public {
        require(ownerOf(tokenId) == msg.sender || managers[tokenId] == msg.sender, "Not authorized");
        require(price > 0, "Price must be greater than 0");
        require(!isRented(tokenId), "Property is rented");
        properties[tokenId].salePrice = price;
        properties[tokenId].isForSale = true;
        emit PropertyListed(tokenId, price);
    }

    // Make an offer
    function makeOffer(uint256 tokenId) public payable {
        require(properties[tokenId].isForSale, "Not for sale");
        require(msg.value > 0, "Offer must be greater than 0");
        offers[tokenId][msg.sender] = msg.value;
        emit OfferMade(tokenId, msg.sender, msg.value);
    }

    // Accept an offer
    function acceptOffer(uint256 tokenId, address buyer) public {
        require(ownerOf(tokenId) == msg.sender || managers[tokenId] == msg.sender, "Not authorized");
        require(properties[tokenId].isForSale, "Not for sale");

        uint256 amount = offers[tokenId][buyer];
        require(amount > 0, "No offer exists");

        properties[tokenId].isForSale = false;
        properties[tokenId].salePrice = 0;
        offers[tokenId][buyer] = 0;

        address seller = ownerOf(tokenId);
        _transfer(seller, buyer, tokenId);
        payable(seller).transfer(amount);
        emit OfferAccepted(tokenId, buyer, amount);
    }

    // Withdraw an offer
    function withdrawOffer(uint256 tokenId) public {
        uint256 amount = offers[tokenId][msg.sender];
        require(amount > 0, "No offer exists");
        offers[tokenId][msg.sender] = 0;
        payable(msg.sender).transfer(amount);
        emit OfferWithdrawn(tokenId, msg.sender);
    }

    // List property for rent
    function listForRent(uint256 tokenId, uint256 monthlyRent) public {
        require(ownerOf(tokenId) == msg.sender || managers[tokenId] == msg.sender, "Not authorized");
        require(!properties[tokenId].isForSale, "Property is for sale");
        require(!isRented(tokenId), "Property is rented");
        properties[tokenId].monthlyRent = monthlyRent;
    }

    // Rent property
    function rentProperty(uint256 tokenId, uint256 months) public payable {
        require(properties[tokenId].monthlyRent > 0, "Not listed for rent");
        require(months > 0, "Invalid rental period");
        require(!isRented(tokenId), "Property is rented");

        uint256 totalRent = properties[tokenId].monthlyRent * months;
        require(msg.value >= totalRent, "Insufficient payment");
        address owner = ownerOf(tokenId);
        properties[tokenId].renter = msg.sender;
        properties[tokenId].rentalEnd = block.timestamp + (months * 30 days);
        payable(owner).transfer(totalRent);
        emit PropertyRented(tokenId, msg.sender, months, totalRent);
    }

    // Extend rental
    function extendRental(uint256 tokenId, uint256 additionalMonths) public payable {
        require(properties[tokenId].renter == msg.sender, "Not the renter");
        require(additionalMonths > 0, "Invalid additional months");
        uint256 additionalRent = properties[tokenId].monthlyRent * additionalMonths;
        require(msg.value >= additionalRent, "Insufficient payment");
        address owner = ownerOf(tokenId);
        properties[tokenId].rentalEnd += additionalMonths * 30 days;
        payable(owner).transfer(additionalRent);
        emit RentalExtended(tokenId, additionalMonths, additionalRent);
    }

    // Set property manager
    function setManager(uint256 tokenId, address manager) public {
        require(ownerOf(tokenId) == msg.sender, "Not the owner");
        managers[tokenId] = manager;
    }

    // Check if property is rented
    function isRented(uint256 tokenId) public view returns (bool) {
        return block.timestamp <= properties[tokenId].rentalEnd && properties[tokenId].renter != address(0);
    }

    // Get property details
    function getPropertyDetails(uint256 tokenId)
        public
        view
        returns (
            string memory location,
            uint256 area,
            string memory category,
            uint256 salePrice,
            bool isForSale,
            address renter,
            uint256 rentalEnd,
            uint256 monthlyRent
        )
    {
        Property memory property = properties[tokenId];
        return (
            property.location,
            property.area,
            property.category,
            property.salePrice,
            property.isForSale,
            property.renter,
            property.rentalEnd,
            property.monthlyRent
        );
    }
}