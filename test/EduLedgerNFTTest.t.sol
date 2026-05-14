// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {EduLedgerNFT} from "../src/EduLedgerNFT.sol";

contract EduLedgerNFTTest is Test {
    EduLedgerNFT public nft;

    address public platformOwner = makeAddr("platformOwner");
    address public creator = makeAddr("creator");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");
    address public randomUser = makeAddr("randomUser");

    uint256 constant PRICE = 1 ether;
    string constant TOKEN_URI = "ipfs://QmHash";

    function setUp() public {
        vm.prank(platformOwner);
        nft = new EduLedgerNFT("EduLedger", "EDU");

        // Fund actors
        vm.deal(creator, 10 ether);
        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 10 ether);
        vm.deal(randomUser, 10 ether);
    }

    function _mintAndApprove() internal returns (uint256 tokenId) {
        vm.startPrank(creator);
        tokenId = nft.mintMaterial(TOKEN_URI, PRICE);
        nft.setApprovalForAll(address(nft), true);
        vm.stopPrank();
    }

    function _doPrimaryPurchase() internal returns (uint256 tokenId) {
        tokenId = _mintAndApprove();
        vm.prank(buyer1);
        nft.purchaseMaterial{value: PRICE}(tokenId);
    }

    function test_mint_tokenIdStartsAtOne() public {
        vm.prank(creator);
        uint256 id = nft.mintMaterial(TOKEN_URI, PRICE);
        assertEq(id, 1, "first token ID must be 1");
    }

    function test_mint_ownershipAssignedToMinter() public {
        vm.prank(creator);
        uint256 id = nft.mintMaterial(TOKEN_URI, PRICE);
        assertEq(nft.ownerOf(id), creator);
    }

    function test_mint_uriStoredCorrectly() public {
        vm.prank(creator);
        uint256 id = nft.mintMaterial(TOKEN_URI, PRICE);
        assertEq(nft.tokenURI(id), TOKEN_URI);
    }

    function test_mint_createsActiveListing() public {
        vm.prank(creator);
        uint256 id = nft.mintMaterial(TOKEN_URI, PRICE);

        EduLedgerNFT.Listing memory l = nft.getListing(id);
        assertTrue(l.active, "listing must be active");
        assertEq(l.price, PRICE, "listing price must match");
        assertEq(l.seller, creator, "seller must be creator");
        assertEq(l.creator, creator, "creator must be stored");
        assertTrue(l.isPrimary, "first listing must be primary");
    }

    //  Listing Updates

    /// Token owner can update listing price.
    function test_updateListing_priceChanges() public {
        vm.startPrank(creator);
        uint256 id = nft.mintMaterial(TOKEN_URI, PRICE);
        nft.updateListing(id, 2 ether);
        vm.stopPrank();

        assertEq(nft.getListing(id).price, 2 ether);
    }

    function test_updateListing_reactivatesInactiveListing() public {
        uint256 id = _doPrimaryPurchase();

        assertFalse(nft.getListing(id).active);

        vm.prank(buyer1);
        nft.updateListing(id, 2 ether);

        EduLedgerNFT.Listing memory l = nft.getListing(id);
        assertTrue(l.active);
        assertEq(l.price, 2 ether);
        assertEq(l.seller, buyer1);
    }

    // Purchase Flow

    /// Successful primary purchase transfers NFT to buyer.
    function test_purchase_nftTransfersToBuyer() public {
        uint256 id = _mintAndApprove();

        vm.prank(buyer1);
        nft.purchaseMaterial{value: PRICE}(id);

        assertEq(nft.ownerOf(id), buyer1);
    }

    /// Listing becomes inactive after purchase.
    function test_purchase_listingBecomesInactive() public {
        uint256 id = _mintAndApprove();

        vm.prank(buyer1);
        nft.purchaseMaterial{value: PRICE}(id);

        assertFalse(nft.getListing(id).active);
    }

    /// NFT cannot be purchased again until new owner relists it.
    function test_purchase_cannotBuyAgainWithoutRelist() public {
        uint256 id = _doPrimaryPurchase();

        vm.prank(buyer2);
        vm.expectRevert(EduLedgerNFT.ListingNotActive.selector);
        nft.purchaseMaterial{value: PRICE}(id);
    }

    /// New owner can relist and a second buyer can purchase.
    function test_purchase_newOwnerCanRelistAndSell() public {
        uint256 id = _doPrimaryPurchase();

        // buyer1 relists
        vm.startPrank(buyer1);
        nft.setApprovalForAll(address(nft), true);
        nft.updateListing(id, 2 ether);
        vm.stopPrank();

        // buyer2 purchases
        vm.prank(buyer2);
        nft.purchaseMaterial{value: 2 ether}(id);

        assertEq(nft.ownerOf(id), buyer2);
    }

    //  ROYALTY AND FEE DISTRIBUTION

    /// Platform owner receives exactly 10% on primary sale.
    function test_primarySale_platformReceivesTenPercent() public {
        uint256 id = _mintAndApprove();
        uint256 ownerBefore = platformOwner.balance;

        vm.prank(buyer1);
        nft.purchaseMaterial{value: PRICE}(id);

        uint256 expected = (PRICE * 10) / 100;
        assertEq(
            platformOwner.balance - ownerBefore,
            expected,
            "platform fee mismatch"
        );
    }

    /// Creator receives exactly 90% on primary sale.
    function test_primarySale_creatorReceivesNinetyPercent() public {
        uint256 id = _mintAndApprove();
        uint256 creatorBefore = creator.balance;

        vm.prank(buyer1);
        nft.purchaseMaterial{value: PRICE}(id);

        uint256 expected = (PRICE * 90) / 100;
        assertEq(
            creator.balance - creatorBefore,
            expected,
            "creator payout mismatch"
        );
    }

    //Secondary Sale

    /// Setup helper: mint → primary purchase → relist at same price.
    function _setupSecondary() internal returns (uint256 id) {
        id = _doPrimaryPurchase();

        vm.startPrank(buyer1);
        nft.setApprovalForAll(address(nft), true);
        nft.updateListing(id, PRICE);
        vm.stopPrank();
    }

    /// Platform owner receives exactly 10% on secondary sale.
    function test_secondarySale_platformReceivesTenPercent() public {
        uint256 id = _setupSecondary();
        uint256 ownerBefore = platformOwner.balance;

        vm.prank(buyer2);
        nft.purchaseMaterial{value: PRICE}(id);

        uint256 expected = (PRICE * 10) / 100;
        assertEq(platformOwner.balance - ownerBefore, expected);
    }

    /// Original creator receives exactly 5% royalty on secondary sale.
    function test_secondarySale_creatorReceivesFivePercentRoyalty() public {
        uint256 id = _setupSecondary();
        uint256 creatorBefore = creator.balance;

        vm.prank(buyer2);
        nft.purchaseMaterial{value: PRICE}(id);

        uint256 expected = (PRICE * 5) / 100;
        assertEq(creator.balance - creatorBefore, expected, "royalty mismatch");
    }

    /// Current seller (buyer1) receives exactly 85% on secondary sale.
    function test_secondarySale_sellerReceivesEightyFivePercent() public {
        uint256 id = _setupSecondary();
        uint256 sellerBefore = buyer1.balance;

        vm.prank(buyer2);
        nft.purchaseMaterial{value: PRICE}(id);

        uint256 expected = (PRICE * 85) / 100;
        assertEq(
            buyer1.balance - sellerBefore,
            expected,
            "seller payout mismatch"
        );
    }
}

// REENTRANCY ATTACKER CONTRACT
contract ReentrancyAttacker {
    EduLedgerNFT public target;

    // Token the attacker listed (receives ETH when sold → triggers receive())
    uint256 public victimToken;
    // Second token the attacker tries to drain via re-entry
    uint256 public reentrantToken;

    bool public reentryAttempted;
    bool public reentrySucceeded;

    constructor(address _target) {
        target = EduLedgerNFT(_target);
    }

    /// Step 1: attacker mints two tokens and lists both, then approves contract.
    function setupTokens(uint256 price) external {
        // Mint token A (will be bought by victim — ETH flows here → triggers attack)
        victimToken = target.mintMaterial("ipfs://victim", price);
        // Mint token B (attacker tries to buy this during re-entry using received ETH)
        reentrantToken = target.mintMaterial("ipfs://reentrant", price);

        target.setApprovalForAll(address(target), true);
    }

    receive() external payable {
        reentryAttempted = true;
        try target.purchaseMaterial{value: msg.value}(reentrantToken) {
            reentrySucceeded = true;
        } catch {
            reentrySucceeded = false;
        }
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

/// Reentrancy test contract
contract ReentrancyTest is Test {
    EduLedgerNFT public nft;
    ReentrancyAttacker public attacker;

    address public platformOwner = makeAddr("platformOwner");
    address public legitimateBuyer;

    uint256 constant PRICE = 1 ether;

    function setUp() public {
        vm.prank(platformOwner);
        nft = new EduLedgerNFT("EduLedger", "EDU");

        // Deploy attacker and fund it so it can mint
        attacker = new ReentrancyAttacker(address(nft));
        vm.deal(address(attacker), 10 ether);

        legitimateBuyer = makeAddr("legitimateBuyer");
        vm.deal(legitimateBuyer, 10 ether);
    }

    function test_reentrancy_sellerAttackIsBlocked() public {
        // Step 1: attacker sets up two listed tokens
        vm.prank(address(attacker));
        attacker.setupTokens(PRICE);

        uint256 tokenA = attacker.victimToken();

        // Step 2: legitimate buyer purchases token A
        // During this call, ETH flows to attacker.receive() which tries to re-enter
        vm.prank(legitimateBuyer);
        nft.purchaseMaterial{value: PRICE}(tokenA);

        // Step 3: verify outer purchase succeeded
        assertEq(
            nft.ownerOf(tokenA),
            legitimateBuyer,
            "buyer must own token A"
        );

        // Step 4: verify re-entry was attempted
        assertTrue(
            attacker.reentryAttempted(),
            "receive() must have been triggered"
        );

        assertFalse(
            attacker.reentrySucceeded(),
            "re-entrant call must have been blocked"
        );

        assertTrue(
            nft.getListing(attacker.reentrantToken()).active,
            "token B listing must remain active attacker failed"
        );
    }
}

// REVERT SCENARIOS
contract RevertTest is Test {
    EduLedgerNFT public nft;

    address public platformOwner = makeAddr("platformOwner");
    address public creator = makeAddr("creator");
    address public buyer = makeAddr("buyer");
    address public randomUser = makeAddr("randomUser");

    uint256 constant PRICE = 1 ether;

    function setUp() public {
        vm.prank(platformOwner);
        nft = new EduLedgerNFT("EduLedger", "EDU");

        vm.deal(creator, 10 ether);
        vm.deal(buyer, 10 ether);
        vm.deal(randomUser, 10 ether);
    }

    function _mintAndApprove() internal returns (uint256 id) {
        vm.startPrank(creator);
        id = nft.mintMaterial("ipfs://x", PRICE);
        nft.setApprovalForAll(address(nft), true);
        vm.stopPrank();
    }

    function test_revert_underpayment() public {
        uint256 id = _mintAndApprove();
        vm.prank(buyer);
        vm.expectRevert(EduLedgerNFT.InsufficientPayment.selector);
        nft.purchaseMaterial{value: PRICE - 1}(id);
    }

    function test_revert_overpayment() public {
        uint256 id = _mintAndApprove();
        vm.prank(buyer);
        vm.expectRevert(EduLedgerNFT.InsufficientPayment.selector);
        nft.purchaseMaterial{value: PRICE + 1}(id);
    }

    // Self purchase
    function test_revert_selfPurchase() public {
        uint256 id = _mintAndApprove();
        vm.prank(creator);
        vm.expectRevert(EduLedgerNFT.SelfPurchase.selector);
        nft.purchaseMaterial{value: PRICE}(id);
    }

    // Invalid / unminted token
    function test_revert_purchaseUnmintedToken() public {
        vm.prank(buyer);
        vm.expectRevert(EduLedgerNFT.TokenDoesNotExist.selector);
        nft.purchaseMaterial{value: PRICE}(999);
    }

    function test_revert_updateListingUnmintedToken() public {
        vm.prank(creator);
        vm.expectRevert(EduLedgerNFT.TokenDoesNotExist.selector);
        nft.updateListing(999, PRICE);
    }

    function test_revert_tokenIdZeroNeverMinted() public {
        vm.prank(buyer);
        vm.expectRevert(EduLedgerNFT.TokenDoesNotExist.selector);
        nft.purchaseMaterial{value: PRICE}(0);
    }

    //  Unauthorized listing updates
    function test_revert_unauthorizedUpdateListing() public {
        uint256 id = _mintAndApprove();
        vm.prank(randomUser);
        vm.expectRevert(EduLedgerNFT.NotTokenOwner.selector);
        nft.updateListing(id, 2 ether);
    }

    // Zero price
    function test_revert_mintWithZeroPrice() public {
        vm.prank(creator);
        vm.expectRevert(EduLedgerNFT.ZeroPrice.selector);
        nft.mintMaterial("ipfs://x", 0);
    }

    function test_revert_updateListingWithZeroPrice() public {
        uint256 id = _mintAndApprove();
        vm.prank(creator);
        vm.expectRevert(EduLedgerNFT.ZeroPrice.selector);
        nft.updateListing(id, 0);
    }
}

// EDGE CASES

contract EdgeCaseTest is Test {
    EduLedgerNFT public nft;

    address public platformOwner = makeAddr("platformOwner");
    address public creator = makeAddr("creator");
    address public buyer1 = makeAddr("buyer1");
    address public buyer2 = makeAddr("buyer2");

    uint256 constant PRICE = 1 ether;

    function setUp() public {
        vm.prank(platformOwner);
        nft = new EduLedgerNFT("EduLedger", "EDU");

        vm.deal(creator, 10 ether);
        vm.deal(buyer1, 10 ether);
        vm.deal(buyer2, 10 ether);
    }

    /// Token ID 0 is never assigned — first real token is always 1.
    function test_edge_tokenIdZeroIsNeverAssigned() public {
        vm.prank(creator);
        uint256 id = nft.mintMaterial("ipfs://a", PRICE);
        assertEq(id, 1, "first token must be id=1");
        assertFalse(nft.existsTokenPublic(0), "token 0 must not exist");
    }

    function test_edge_relistAfterPurchaseIsSecondary() public {
        // Mint + primary purchase
        vm.startPrank(creator);
        uint256 id = nft.mintMaterial("ipfs://b", PRICE);
        nft.setApprovalForAll(address(nft), true);
        vm.stopPrank();

        vm.prank(buyer1);
        nft.purchaseMaterial{value: PRICE}(id);

        vm.startPrank(buyer1);
        nft.setApprovalForAll(address(nft), true);
        nft.updateListing(id, PRICE);
        vm.stopPrank();

        // Verify isPrimary is false
        assertFalse(
            nft.getListing(id).isPrimary,
            "after relist must be secondary"
        );

        // Secondary purchase
        uint256 creatorBefore = creator.balance;
        vm.prank(buyer2);
        nft.purchaseMaterial{value: PRICE}(id);

        // Creator should receive 5% royalty
        uint256 royalty = (PRICE * 5) / 100;
        assertEq(
            creator.balance - creatorBefore,
            royalty,
            "secondary royalty wrong"
        );
    }
}
