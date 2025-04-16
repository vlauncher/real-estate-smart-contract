// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RealEstate is ERC721, Ownable {
    uint256 private tokenCounter;

    struct Prop {
        string addr;      // Property address or location
        uint256 size;     // Area of the property
        string cat;       // Category: house, apt, land, etc.
        uint256 price;    // Sale price in wei
        bool forSale;     // True if for sale
        address renter;   // Current renter
        uint256 rentalEnd;// Rental end timestamp
        uint256 rentMonth;// Monthly rent in wei
    }

    struct Auction {
        uint256 startPrice;  // Starting bid
        uint256 highBid;     // Highest bid so far
        address highBidder;  // Address of highest bidder
        uint256 endTime;     // Auction end time
        bool ended;          // True if auction ended
    }

    mapping(uint256 => Prop) public props;
    mapping(uint256 => mapping(address => uint256)) public offers;
    mapping(uint256 => address) public managers;
    mapping(uint256 => Auction) public auctions;

    event Minted(uint256 tokenId, address owner, string addr);
    event Listed(uint256 tokenId, uint256 price);
    event Offer(uint256 tokenId, address buyer, uint256 amount);
    event OfferAccepted(uint256 tokenId, address buyer, uint256 amount);
    event OfferWithdrawn(uint256 tokenId, address buyer);
    event Rented(uint256 tokenId, address renter, uint256 months, uint256 total);
    event Extend(uint256 tokenId, uint256 addMonths, uint256 addRent);
    event AuctionStarted(uint256 tokenId, uint256 startPrice, uint256 endTime);
    event Bid(uint256 tokenId, address bidder, uint256 amount);
    event AuctionEnded(uint256 tokenId, address winner, uint256 amount);

    constructor() ERC721("RealEstate", "RE") Ownable(msg.sender) {
        tokenCounter = 0;
    }

    // Mint a new property (owner-only)
    function mint(address to, string memory _addr, uint256 _size, string memory _cat) public onlyOwner {
        tokenCounter++;
        uint256 tokenId = tokenCounter;
        _mint(to, tokenId);
        props[tokenId] = Prop(_addr, _size, _cat, 0, false, address(0), 0, 0);
        emit Minted(tokenId, to, _addr);
    }

    // List property for sale
    function list(uint256 tokenId, uint256 _price) public {
        require(ownerOf(tokenId) == msg.sender || managers[tokenId] == msg.sender, "Not auth");
        require(_price > 0, "Price > 0");
        require(!isRented(tokenId), "Rented");
        props[tokenId].price = _price;
        props[tokenId].forSale = true;
        emit Listed(tokenId, _price);
    }

    // Make an offer
    function makeOffer(uint256 tokenId) public payable {
        require(props[tokenId].forSale, "Not for sale");
        require(msg.value > 0, "Value > 0");
        offers[tokenId][msg.sender] = msg.value;
        emit Offer(tokenId, msg.sender, msg.value);
    }

    // Accept an offer
    function acceptOffer(uint256 tokenId, address buyer) public {
        require(ownerOf(tokenId) == msg.sender || managers[tokenId] == msg.sender, "Not auth");
        require(props[tokenId].forSale, "Not for sale");

        uint256 amt = offers[tokenId][buyer];
        require(amt > 0, "No offer");

        props[tokenId].forSale = false;
        props[tokenId].price = 0;
        offers[tokenId][buyer] = 0;

        address seller = ownerOf(tokenId);
        _transfer(seller, buyer, tokenId);
        payable(seller).transfer(amt);
        emit OfferAccepted(tokenId, buyer, amt);
    }

    // Withdraw an offer
    function withdrawOffer(uint256 tokenId) public {
        uint256 amt = offers[tokenId][msg.sender];
        require(amt > 0, "No offer");
        offers[tokenId][msg.sender] = 0;
        payable(msg.sender).transfer(amt);
        emit OfferWithdrawn(tokenId, msg.sender);
    }

    // List property for rent
    function listRent(uint256 tokenId, uint256 _rentMonth) public {
        require(ownerOf(tokenId) == msg.sender || managers[tokenId] == msg.sender, "Not auth");
        require(!props[tokenId].forSale, "For sale");
        require(!isRented(tokenId), "Rented");
        props[tokenId].rentMonth = _rentMonth;
    }

    // Rent property
    function rent(uint256 tokenId, uint256 months) public payable {
        require(props[tokenId].rentMonth > 0, "Not for rent");
        require(months > 0, "Invalid");
        require(!isRented(tokenId), "Rented");

        uint256 total = props[tokenId].rentMonth * months;
        require(msg.value >= total, "Insufficient");
        address ownr = ownerOf(tokenId);
        props[tokenId].renter = msg.sender;
        props[tokenId].rentalEnd = block.timestamp + (months * 30 days);
        payable(ownr).transfer(total);
        emit Rented(tokenId, msg.sender, months, total);
    }

    // Extend rental
    function extend(uint256 tokenId, uint256 addMonths) public payable {
        require(props[tokenId].renter == msg.sender, "Not renter");
        require(addMonths > 0, "Invalid");
        uint256 addRent = props[tokenId].rentMonth * addMonths;
        require(msg.value >= addRent, "Insufficient");
        address ownr = ownerOf(tokenId);
        props[tokenId].rentalEnd += addMonths * 30 days;
        payable(ownr).transfer(addRent);
        emit Extend(tokenId, addMonths, addRent);
    }

    // Start auction
    function startAuction(uint256 tokenId, uint256 _startPrice, uint256 duration) public {
        require(ownerOf(tokenId) == msg.sender || managers[tokenId] == msg.sender, "Not auth");
        require(!props[tokenId].forSale, "For sale");
        require(!isRented(tokenId), "Rented");
        auctions[tokenId] = Auction(_startPrice, 0, address(0), block.timestamp + duration, false);
        emit AuctionStarted(tokenId, _startPrice, block.timestamp + duration);
    }

    // Place bid
    function bid(uint256 tokenId) public payable {
        Auction storage auc = auctions[tokenId];
        require(block.timestamp < auc.endTime, "Ended");
        require(msg.value > auc.highBid && msg.value >= auc.startPrice, "Low bid");
        if (auc.highBidder != address(0))
            payable(auc.highBidder).transfer(auc.highBid);
        auc.highBid = msg.value;
        auc.highBidder = msg.sender;
        emit Bid(tokenId, msg.sender, msg.value);
    }

    // End auction
    function endAuction(uint256 tokenId) public {
        Auction storage auc = auctions[tokenId];
        require(block.timestamp >= auc.endTime, "Not ended");
        require(!auc.ended, "Already ended");
        auc.ended = true;
        if (auc.highBidder != address(0)) {
            address seller = ownerOf(tokenId);
            _transfer(seller, auc.highBidder, tokenId);
            payable(seller).transfer(auc.highBid);
            emit AuctionEnded(tokenId, auc.highBidder, auc.highBid);
        } else {
            emit AuctionEnded(tokenId, address(0), 0);
        }
    }

    // Set property manager
    function setMgr(uint256 tokenId, address mgr) public {
        require(ownerOf(tokenId) == msg.sender, "Not owner");
        managers[tokenId] = mgr;
    }

    // Check if rented
    function isRented(uint256 tokenId) public view returns (bool) {
        return block.timestamp <= props[tokenId].rentalEnd && props[tokenId].renter != address(0);
    }

    // Get property details
    function getProp(uint256 tokenId)
        public
        view
        returns (
            string memory,
            uint256,
            string memory,
            uint256,
            bool,
            address,
            uint256,
            uint256
        )
    {
        Prop memory p = props[tokenId];
        return (p.addr, p.size, p.cat, p.price, p.forSale, p.renter, p.rentalEnd, p.rentMonth);
    }
}
