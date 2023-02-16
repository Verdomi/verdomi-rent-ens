// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

error RentENS__EthTransferFailed();
error RentENS__MustBeEnsOwner();
error RentENS__RentalPeriodLongerThanRegistration();
error RentENS__NotEnoughEtherSent();
error RentENS__ListingIsNotActive();
error RentENS__MustBeEnsRenter();
error RentENS__RentalPeriodNotOver();
error RentENS__FeeTooHigh();
error RentENS__EnsIsNotRented();

pragma solidity ^0.8.17;

interface ENS {
    function reclaim(uint256 id, address owner) external;

    function transferFrom(address from, address to, uint256 tokenId) external;

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function nameExpires(uint256 id) external view returns (uint);

    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

contract RentENS is ERC721, ERC2981, ERC721Holder, Ownable {
    event ListingCreated(
        address indexed ensOwner,
        uint256 indexed tokenId,
        uint128 price,
        uint64 duration
    );

    event ListingCanceled(
        address indexed ensOwner,
        uint256 indexed tokenId,
        uint128 price,
        uint64 duration
    );

    event ListingBought(
        address indexed ensOwner,
        address indexed renter,
        uint256 indexed tokenId,
        uint128 price,
        uint64 duration
    );

    event ExtensionCreated(
        address indexed ensOwner,
        address indexed renter,
        uint256 indexed tokenId,
        uint128 price,
        uint64 duration
    );

    event ExtensionCanceled(
        address indexed ensOwner,
        address indexed renter,
        uint256 indexed tokenId,
        uint128 price,
        uint64 duration
    );

    event ExtensionBought(
        address indexed ensOwner,
        address indexed renter,
        uint256 indexed tokenId,
        uint128 price,
        uint64 duration
    );

    event NameRegained(address indexed ensOwner, uint256 indexed tokenId);

    constructor(address ensAddress) ERC721("RentENS", "RENS") {
        _setDefaultRoyalty(msg.sender, 500);
        ens = ENS(ensAddress);
    }

    ENS internal immutable ens;
    string private s_baseUri = "";

    mapping(uint256 => tokenInfo) s_tokens;
    mapping(uint256 => listingInfo) s_listings;
    mapping(uint256 => listingInfo) s_extensions;

    struct tokenInfo {
        address owner;
        address renter;
        uint256 expirationTime;
    }

    struct listingInfo {
        uint64 duration;
        uint128 price;
        bool active;
    }

    function createListing(uint256 tokenId, listingInfo calldata listing) external {
        if (ens.ownerOf(tokenId) != msg.sender) {
            revert RentENS__MustBeEnsOwner();
        }
        if (block.timestamp + listing.duration > ens.nameExpires(tokenId)) {
            revert RentENS__RentalPeriodLongerThanRegistration();
        }

        s_tokens[tokenId].owner = msg.sender;

        s_listings[tokenId] = listing;

        emit ListingCreated(msg.sender, tokenId, listing.price, listing.duration);

        if (s_extensions[tokenId].active) {
            s_extensions[tokenId].active = false;
            emit ExtensionCanceled(
                msg.sender,
                address(0),
                tokenId,
                listing.price,
                listing.duration
            );
        }
    }

    function cancelListing(uint256 tokenId) external {
        if (ens.ownerOf(tokenId) != msg.sender) {
            revert RentENS__MustBeEnsOwner();
        }
        s_listings[tokenId].active = false;
        emit ListingCanceled(
            msg.sender,
            tokenId,
            getListingPrice(tokenId),
            getListingDuration(tokenId)
        );
    }

    function rent(uint256 tokenId) external payable {
        listingInfo memory listing = s_listings[tokenId];
        if (msg.value != listing.price) {
            revert RentENS__NotEnoughEtherSent();
        }
        // Update information
        // Update expiration time first, then check if listing is active since the expiration time affects it
        s_tokens[tokenId].expirationTime = listing.duration + block.timestamp;
        // This will revert the transaction if the listing is not active or if the final renting duration is longer than the time the ENS is registered for
        if (!isListingActive(tokenId)) {
            revert RentENS__ListingIsNotActive();
        }
        s_listings[tokenId].active = false;
        s_tokens[tokenId].renter = msg.sender;

        address ensOwner = getEnsOwner(tokenId);
        ens.transferFrom(ensOwner, address(this), tokenId);

        // Transfer fee to fee receiver and payment to ENS owner
        _sendEth(ensOwner);

        // Mint Rent ENS Token to renter
        _mint(msg.sender, tokenId);

        // Emit event
        emit ListingBought(ensOwner, msg.sender, tokenId, listing.price, listing.duration);
    }

    function createExtensionOffer(uint256 tokenId, listingInfo calldata extension) external {
        tokenInfo memory token = s_tokens[tokenId];
        if (msg.sender != token.owner) {
            revert RentENS__MustBeEnsOwner();
        }
        if (token.renter == address(0)) {
            revert RentENS__EnsIsNotRented();
        }
        if (getExpirationTime(tokenId) + extension.duration > ens.nameExpires(tokenId)) {
            revert RentENS__RentalPeriodLongerThanRegistration();
        }

        s_extensions[tokenId] = extension;

        emit ExtensionCreated(
            msg.sender,
            token.renter,
            tokenId,
            extension.price,
            extension.duration
        );
    }

    function cancelExtensionOffer(uint256 tokenId) external {
        if (msg.sender != getEnsOwner(tokenId)) {
            revert RentENS__MustBeEnsOwner();
        }
        s_extensions[tokenId].active = false;

        emit ExtensionCanceled(
            getEnsOwner(tokenId),
            getRenter(tokenId),
            tokenId,
            getExtensionPrice(tokenId),
            getExtensionDuration(tokenId)
        );
    }

    function acceptExtensionOffer(uint256 tokenId) external payable {
        listingInfo memory extension = s_extensions[tokenId];
        tokenInfo memory token = s_tokens[tokenId];
        if (msg.value != extension.price) {
            revert RentENS__NotEnoughEtherSent();
        }
        if (msg.sender != token.renter) {
            revert RentENS__MustBeEnsRenter();
        }

        // Update information
        // Update expiration time first, then check if extension is active since the expiration time affects it
        s_tokens[tokenId].expirationTime += extension.duration;
        // This will revert the transaction if the offer is not active or if the final renting duration is longer than the time the ENS is registered for
        if (!isExtensionOfferActive(tokenId)) {
            revert RentENS__ListingIsNotActive();
        }
        s_extensions[tokenId].active = false;

        // Transfer fee to fee receiver and payment to ENS owner
        _sendEth(getEnsOwner(tokenId));

        emit ExtensionBought(
            getEnsOwner(tokenId),
            msg.sender,
            tokenId,
            extension.price,
            extension.duration
        );
    }

    function regainENS(uint256 tokenId) external {
        tokenInfo memory token = s_tokens[tokenId];
        if (msg.sender != token.owner) {
            revert RentENS__MustBeEnsOwner();
        }
        if (token.renter != token.owner || token.expirationTime > block.timestamp) {
            revert RentENS__RentalPeriodNotOver();
        }

        s_tokens[tokenId].renter = address(0);
        s_extensions[tokenId].active = false;

        _burn(tokenId);
        ens.reclaim(tokenId, msg.sender);
        ens.transferFrom(address(this), msg.sender, tokenId);

        emit NameRegained(msg.sender, tokenId);
    }

    function regainControlAsRenter(uint256 tokenId) external {
        if (msg.sender != getRenter(tokenId)) {
            revert RentENS__MustBeEnsRenter();
        }
        ens.reclaim(tokenId, msg.sender);
    }

    function setFee(address receiver, uint96 feeNumerator) external onlyOwner {
        if (feeNumerator > 500) {
            revert RentENS__FeeTooHigh();
        }
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function _sendEth(address to) internal {
        // Retrieve fee information
        (address feeReceiver, uint256 fee) = royaltyInfo(0, msg.value);

        // Transfer fee to fee receiver
        (bool feeSuccess, ) = payable(feeReceiver).call{value: fee}("");
        if (!feeSuccess) {
            revert RentENS__EthTransferFailed();
        }

        // Transfer the rest of sent ether to the given address
        (bool ownerSuccess, ) = payable(to).call{value: msg.value - fee}("");
        if (!ownerSuccess) {
            revert RentENS__EthTransferFailed();
        }
    }

    function isListingActive(uint256 tokenId) public view returns (bool) {
        listingInfo memory listing = s_listings[tokenId];
        tokenInfo memory token = s_tokens[tokenId];
        address ensOwner = ens.ownerOf(tokenId);
        if (
            !listing.active ||
            ensOwner != token.owner ||
            token.expirationTime >= ens.nameExpires(tokenId) ||
            token.expirationTime <= block.timestamp ||
            ens.isApprovedForAll(ensOwner, address(this))
        ) {
            return false;
        } else {
            return true;
        }
    }

    function isExtensionOfferActive(uint256 tokenId) public view returns (bool) {
        listingInfo memory extension = s_extensions[tokenId];
        tokenInfo memory token = s_tokens[tokenId];
        if (
            !extension.active ||
            token.expirationTime >= ens.nameExpires(tokenId) ||
            token.expirationTime <= block.timestamp
        ) {
            return false;
        } else {
            return true;
        }
    }

    function getEnsOwner(uint256 tokenId) public view returns (address) {
        return s_tokens[tokenId].owner;
    }

    function getRenter(uint256 tokenId) public view returns (address) {
        return s_tokens[tokenId].renter;
    }

    function getExpirationTime(uint256 tokenId) public view returns (uint256) {
        return s_tokens[tokenId].expirationTime;
    }

    function getListingDuration(uint256 tokenId) public view returns (uint64) {
        return s_listings[tokenId].duration;
    }

    function getListingPrice(uint256 tokenId) public view returns (uint128) {
        return s_listings[tokenId].price;
    }

    function getExtensionDuration(uint256 tokenId) public view returns (uint64) {
        return s_extensions[tokenId].duration;
    }

    function getExtensionPrice(uint256 tokenId) public view returns (uint128) {
        return s_extensions[tokenId].price;
    }

    /**
     * @dev Necessary override function
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Internal function to update tokenInfo and set the new token owner as controller after every token transfer
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 firstTokenId,
        uint256 batchSize
    ) internal override {
        s_tokens[firstTokenId].renter = to;
        ens.reclaim(firstTokenId, to);
    }

    /**
     * @dev Necessary override function to correctly display tokenURI
     */
    function _baseURI() internal view override returns (string memory) {
        return s_baseUri;
    }
}
