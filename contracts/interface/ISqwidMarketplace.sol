// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../../@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../../@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../@openzeppelin/contracts/utils/Counters.sol";
import "../../@openzeppelin/contracts/access/Ownable.sol";
import "./IRoyaltyInfo.sol";

interface ISqwidMarketplace {
    enum TypeItem {
        Regular,
        Auction,
        Raffle
    }

    struct MarketItem {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address payable seller;
        address payable owner;
        address creator;
        uint256 price;
        uint256 marketFee;
        bool onSale;
        TypeItem typeItem;
        MarketItemSale[] sales;
    }

    struct MarketItemSale {
        address seller;
        address buyer;
        uint256 price;
        TypeItem typeItem;
    }

    struct AuctionData {
        uint256 deadline;
        uint256 minBid;
        address highestBidder;
        uint256 highestBid;
    }

    struct RaffleData {
        uint256 deadline;
        uint256 totalValue;
        mapping(address => uint256) addressToAmount;
        mapping(uint256 => address) indexToAddress;
        uint256 totalAddresses;
    }

    event MarketItemUpdate(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address creator,
        uint256 price,
        uint256 marketFee,
        TypeItem typeItem
    );

    event MarketItemSold(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price,
        TypeItem typeItem
    );

    event MarketFeeChanged(uint256 prevValue, uint256 newValue);

    event RoyaltiesPaid(uint256 indexed tokenId, uint256 value);

    function getMarketFee() external view returns (uint256);

    function setMarketFee(uint256 newMarketFee) external;

    function setLoanAddress(address loanAddress) external;

    function createMarketItem(address nftContract, uint256 tokenId)
        external
        returns (uint256);

    function fetchItem(uint256 itemId)
        external
        view
        returns (MarketItem memory);

    function updateMarketItemOwner(uint256 itemId, address newItemOwner)
        external;

    function fetchMyItemsCreated() external view returns (MarketItem[] memory);

    function fetchAddressItemsCreated(address targetAddress)
        external
        view
        returns (MarketItem[] memory);

    function fetchMyItemsOnSale() external view returns (MarketItem[] memory);

    function fetchAddressItemsOnSale(address targetAddress)
        external
        view
        returns (MarketItem[] memory);

    function fetchMyItemsOwned() external view returns (MarketItem[] memory);

    function fetchAddressItemsOwned(address targetAddress)
        external
        view
        returns (MarketItem[] memory);

    function putNewNftOnSale(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external;

    function putMarketItemOnSale(uint256 itemId, uint256 price) external;

    function createMarketSale(uint256 itemId) external payable;

    function unlistMarketItem(uint256 itemId) external;

    function fetchItemsOnSale() external view returns (MarketItem[] memory);

    function createNewNftAuction(
        address nftContract,
        uint256 tokenId,
        uint256 numMinutes,
        uint256 minBid
    ) external;

    function createMarketItemAuction(
        uint256 itemId,
        uint256 numMinutes,
        uint256 minBid
    ) external;

    function createBid(uint256 itemId) external payable;

    function endAuction(uint256 itemId) external;

    function fetchAuctionData(uint256 itemId)
        external
        view
        returns (AuctionData memory auctionData);

    function fetchAuctions() external view returns (MarketItem[] memory);

    function createNewNftRaffle(
        address nftContract,
        uint256 tokenId,
        uint256 numMinutes
    ) external;

    function createMarketItemRaffle(uint256 itemId, uint256 numMinutes)
        external;

    function enterRaffle(uint256 itemId) external payable;

    function endRaffle(uint256 itemId) external;

    function fetchRaffleData(uint256 itemId)
        external
        view
        returns (uint256 deadline, uint256 contribution);

    function fetchRaffles() external view returns (MarketItem[] memory);
}
