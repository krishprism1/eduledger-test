// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {
    ERC721URIStorage
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title EduLedgerNFT
 * @notice ERC721 marketplace for academic materials
 */
contract EduLedgerNFT is ERC721URIStorage {
    // Errors
    error NotOwner();
    error ZeroAddress();
    error ZeroPrice();
    error TokenDoesNotExist();
    error NotTokenOwner();
    error MarketplaceNotApproved();
    error ListingNotActive();
    error InsufficientPayment();
    error SelfPurchase();
    error TransferFailed();
    error Reentrant();

    // Events
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /// @notice Emitted when new academic material NFT is minted and auto-listed.
    event MaterialMinted(
        uint256 indexed tokenId,
        address indexed creator,
        string tokenURI,
        uint256 price
    );

    /// @notice Emitted whenever a listing price is set or updated.
    event ListingUpdated(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price,
        bool active
    );

    /// @notice Emitted after a successful purchase.
    event MaterialPurchased(
        uint256 indexed tokenId,
        address indexed buyer,
        address indexed seller,
        uint256 price,
        bool wasPrimary
    );

    // Types
    struct Listing {
        uint256 price; // current listing price in wei
        bool active; // whether the token is currently for sale
        address seller; // who is selling (may differ from original creator on resale)
        address creator; // permanently stored original creator
        bool isPrimary; // true until first successful purchase
    }

    // State

    // Manual ownership
    address private _owner;

    // Manual reentrancy lock
    bool private _locked;

    // Token ID counter — starts at 1 per requirement
    uint256 private _nextTokenId;

    // tokenId → Listing
    mapping(uint256 => Listing) private _listings;

    // Modifiers
    modifier onlyOwner() {
        if (msg.sender != _owner) revert NotOwner();
        _;
    }

    modifier nonReentrant() {
        if (_locked) revert Reentrant();
        _locked = true;
        _;
        _locked = false;
    }

    modifier tokenExists(uint256 tokenId) {
        if (!_existsToken(tokenId)) revert TokenDoesNotExist();
        _;
    }

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC721(name_, symbol_) {
        _owner = msg.sender;
        _nextTokenId = 1;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function owner() external view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address old = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(old, newOwner);
    }

    // Minting
    function mintMaterial(
        string calldata tokenURI_,
        uint256 price
    ) external returns (uint256 tokenId) {
        if (price == 0) revert ZeroPrice();

        tokenId = _nextTokenId++;
        _safeMint(msg.sender, tokenId);
        _setTokenURI(tokenId, tokenURI_);

        _listings[tokenId] = Listing({
            price: price,
            active: true,
            seller: msg.sender,
            creator: msg.sender,
            isPrimary: true
        });

        emit MaterialMinted(tokenId, msg.sender, tokenURI_, price);
        emit ListingUpdated(tokenId, msg.sender, price, true);
    }

    // Listing Management
    function updateListing(
        uint256 tokenId,
        uint256 newPrice
    ) external tokenExists(tokenId) {
        if (newPrice == 0) revert ZeroPrice();

        if (ownerOf(tokenId) != msg.sender) revert NotTokenOwner();

        Listing storage listing = _listings[tokenId];

        listing.price = newPrice;
        listing.active = true;
        listing.seller = msg.sender;

        emit ListingUpdated(tokenId, msg.sender, newPrice, true);
    }

    // Purchasing
    function purchaseMaterial(
        uint256 tokenId
    ) external payable nonReentrant tokenExists(tokenId) {
        Listing memory listing = _listings[tokenId];

        if (!listing.active) revert ListingNotActive();
        if (listing.seller == msg.sender) revert SelfPurchase();
        if (msg.value != listing.price) revert InsufficientPayment();
        if (
            !isApprovedForAll(listing.seller, address(this)) &&
            getApproved(tokenId) != address(this)
        ) {
            revert MarketplaceNotApproved();
        }

        uint256 salePrice = listing.price;
        bool wasPrimary = listing.isPrimary;

        _listings[tokenId].active = false;
        _listings[tokenId].isPrimary = false;

        // Fee calculation
        // Primary:   platformFee = 10%,  creatorPayout = 90%
        // Secondary: platformFee = 10%,  royalty = 5%,  sellerPayout = 85%
        uint256 platformFee = (salePrice * 10) / 100;

        if (wasPrimary) {
            uint256 creatorPayout = salePrice - platformFee;

            // Transfer platform fee to owner
            (bool ok1, ) = _owner.call{value: platformFee}("");
            if (!ok1) revert TransferFailed();

            // Transfer remainder to creator / seller
            (bool ok2, ) = listing.seller.call{value: creatorPayout}("");
            if (!ok2) revert TransferFailed();
        } else {
            // Secondary sale
            uint256 royalty = (salePrice * 5) / 100; // 5%
            uint256 sellerPayout = salePrice - platformFee - royalty; // 85%

            // Platform fee → owner
            (bool ok1, ) = _owner.call{value: platformFee}("");
            if (!ok1) revert TransferFailed();

            // Royalty → original creator
            (bool ok2, ) = listing.creator.call{value: royalty}("");
            if (!ok2) revert TransferFailed();

            // Remainder → current seller
            (bool ok3, ) = listing.seller.call{value: sellerPayout}("");
            if (!ok3) revert TransferFailed();
        }

        IERC721(address(this)).transferFrom(
            listing.seller,
            msg.sender,
            tokenId
        );

        _listings[tokenId].seller = msg.sender;

        emit MaterialPurchased(
            tokenId,
            msg.sender,
            listing.seller,
            salePrice,
            wasPrimary
        );
    }

    function getListing(
        uint256 tokenId
    ) external view returns (Listing memory) {
        return _listings[tokenId];
    }

    function getCreator(uint256 tokenId) external view returns (address) {
        return _listings[tokenId].creator;
    }

    function totalMinted() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    function _existsToken(uint256 tokenId) internal view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }

    function existsTokenPublic(uint256 tokenId) external view returns (bool) {
        return _existsToken(tokenId);
    }
}
