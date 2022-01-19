// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../@openzeppelin/contracts/access/Ownable.sol";
import "../@openzeppelin/contracts/utils/Counters.sol";
import "./NftRoyalties.sol";

contract CoralNFT is ERC1155, NftRoyalties, Ownable {
    // bytes4(keccak256("hasMutableURI(uint256))")) == 0xc962d178
    bytes4 private constant INTERFACE_ID_MUTABLE_URI = 0xc962d178;

    using Counters for Counters.Counter;
    Counters.Counter private tokenIds;
    address private marketplaceAddress;
    address private loanAddress;

    mapping(bytes4 => bool) private supportedInterfaces;

    mapping(uint256 => bool) private mutableMetadataMapping;

    // mapping(uint256 => address[]) private owners;

    constructor(address _marketplaceAddress, address _loanAddress) ERC1155("") {
        marketplaceAddress = _marketplaceAddress;
        loanAddress = _loanAddress;
    }

    /**
     * Creates a new token
     */
    function createToken(
        string memory _tokenURI,
        uint256 _amount,
        address _royaltyRecipient,
        uint256 _royaltyValue,
        bool _mutableMetada
    ) public returns (uint256) {
        tokenIds.increment();
        uint256 tokenId = tokenIds.current();

        _mint(msg.sender, tokenId, _amount, "");
        // setTokenUri(tokenId, _tokenURI);
        setApprovalForAll(marketplaceAddress, true);
        setApprovalForAll(loanAddress, true);

        if (_royaltyValue > 0) {
            _setTokenRoyalty(tokenId, _royaltyRecipient, _royaltyValue);
        }

        mutableMetadataMapping[tokenId] = _mutableMetada;

        return tokenId;
    }

    /**
     * Returns whether or not a token has mutable URI.
     */
    function hasMutableURI(uint256 _tokenId)
        external
        view
        returns (bool mutableMetadata)
    {
        return mutableMetadataMapping[_tokenId];
    }

    /**
     * Overrides supportsInterface method to include support for EIP-2981 and mutable URI interfaces.
     */
    function supportsInterface(bytes4 _interfaceId)
        public
        view
        virtual
        override
        returns (bool)
    {
        return
            super.supportsInterface(_interfaceId) ||
            _interfaceId == INTERFACE_ID_ERC2981 ||
            _interfaceId == INTERFACE_ID_MUTABLE_URI;
    }
}
