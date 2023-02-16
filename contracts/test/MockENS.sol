// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockENS is ERC721 {
    constructor() ERC721("ENS Name", "ENS") {}

    mapping(uint256 => address) controller;

    function reclaim(uint256 id, address owner) external {
        controller[id] = owner;
    }

    function getController(uint256 tokenId) external view returns (address) {
        return controller[tokenId];
    }

    function nameExpires(uint256 id) external view returns (uint) {
        return block.timestamp + 365 days;
    }

    function mint(uint256 tokenId) external {
        _mint(msg.sender, tokenId);
    }
}
