// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "../@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../@openzeppelin/contracts/utils/Counters.sol";
import "../@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IRoyaltyInfo.sol";

contract SqwidMarketplace is ERC1155Holder, Ownable, ReentrancyGuard {
    enum TypeItem {
        Regular,
        Auction,
        Raffle
    }

    // A market item can represent just one token or a batch of tokens
    struct MarketItem {
        uint256 itemId; // Incremental ID in the market contract
        address nftContract;
        uint256 tokenId; // Incremental ID in the NFT contract
        uint256 amount; // Number of tokens in the batch
        address payable seller;
        address payable owner;
        address creator;
        uint256 price;
        uint256 marketFee; // Market fee at the moment of creating the item
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

    // bytes4(keccak256("royaltyInfo(uint256,uint256)")) == 0x2a55205a
    bytes4 private constant INTERFACE_ID_ERC2981 = 0x2a55205a;

    address private _loanAddress;
    uint256 private _marketFee;
    using Counters for Counters.Counter;
    Counters.Counter private _itemIds;
    Counters.Counter private _onRegularSale;
    Counters.Counter private _onAuction;
    Counters.Counter private _onRaffle;

    mapping(uint256 => MarketItem) private _idToMarketItem;

    mapping(uint256 => AuctionData) private _idToAuctionData;

    mapping(uint256 => RaffleData) private _idToRaffleData;

    event MarketItemUpdate(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 amount,
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

    constructor(uint256 marketFee) {
        _marketFee = marketFee;
    }

    /**
     * Returns current market fee percentage with two decimal points.
     * E.g. 250 --> 2.5%
     */
    function getMarketFee() public view returns (uint256) {
        return _marketFee;
    }

    /**
     * Sets market fee percentage with two decimal points.
     * E.g. 250 --> 2.5%
     */
    function setMarketFee(uint256 marketFee) public virtual onlyOwner {
        require(
            marketFee <= 5000,
            "SqwidMarketplace: Market fee value cannot be higher than 5000."
        );
        uint256 prevMarketFee = _marketFee;
        _marketFee = marketFee;
        emit MarketFeeChanged(prevMarketFee, marketFee);
    }

    /**
     * Sets loan contract address.
     */
    function setLoanAddress(address loanAddress) public virtual onlyOwner {
        _loanAddress = loanAddress;
    }

    /**
     * Creates new market item.
     */
    function createMarketItem(
        address nftContract,
        uint256 tokenId,
        uint256 amount
    ) public returns (uint256) {
        require(
            IERC1155(nftContract).balanceOf(msg.sender, tokenId) >= amount,
            "SqwidMarketplace: This address does not own enough tokens."
        );

        // Map new MarketItem
        _itemIds.increment();
        uint256 itemId = _itemIds.current();
        _idToMarketItem[itemId].itemId = itemId;
        _idToMarketItem[itemId].nftContract = nftContract;
        _idToMarketItem[itemId].tokenId = tokenId;
        _idToMarketItem[itemId].amount = amount;
        _idToMarketItem[itemId].creator = msg.sender;
        _idToMarketItem[itemId].owner = payable(msg.sender);

        emit MarketItemUpdate(
            itemId,
            nftContract,
            tokenId,
            amount,
            msg.sender,
            msg.sender,
            0,
            0,
            TypeItem.Regular
        );

        return itemId;
    }

    /**
     * Updates a market item owner from SqwidLoan contract.
     */
    function updateMarketItemOwner(uint256 itemId, address newItemOwner)
        public
        virtual
    {
        require(
            msg.sender == _loanAddress,
            "SqwidMarketplace: Only loan contract can change item owner."
        );

        _idToMarketItem[itemId].owner = payable(newItemOwner);
    }

    /**
     * Returns detail of a market item.
     */
    function fetchItem(uint256 itemId) public view returns (MarketItem memory) {
        return _idToMarketItem[itemId];
    }

    /**
     * Returns items created by caller.
     */
    function fetchMyItemsCreated() public view returns (MarketItem[] memory) {
        return fetchAddressItemsCreated(msg.sender);
    }

    /**
     * Returns items created by an address.
     */
    function fetchAddressItemsCreated(address targetAddress)
        public
        view
        returns (MarketItem[] memory)
    {
        // Get total number of items created by target address
        uint256 totalItemCount = _itemIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_idToMarketItem[i + 1].creator == targetAddress) {
                itemCount += 1;
            }
        }

        // Initialize array
        MarketItem[] memory items = new MarketItem[](itemCount);

        // Fill array
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_idToMarketItem[i + 1].creator == targetAddress) {
                uint256 currentId = _idToMarketItem[i + 1].itemId;
                MarketItem storage currentItem = _idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }

    /**
     * Returns items currently on sale (regular, auction or raffle) by caller.
     */
    function fetchMyItemsOnSale() public view returns (MarketItem[] memory) {
        return fetchAddressItemsOnSale(msg.sender);
    }

    /**
     * Returns items currently on sale (regular, auction or raffle) by an address.
     */
    function fetchAddressItemsOnSale(address targetAddress)
        public
        view
        returns (MarketItem[] memory)
    {
        // Get total number of items on sale by target address
        uint256 totalItemCount = _itemIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (
                _idToMarketItem[i + 1].seller == targetAddress &&
                _idToMarketItem[i + 1].onSale &&
                (_idToMarketItem[i + 1].typeItem == TypeItem.Regular ||
                    _idToMarketItem[i + 1].typeItem == TypeItem.Auction)
            ) {
                itemCount += 1;
            }
        }

        // Initialize array
        MarketItem[] memory items = new MarketItem[](itemCount);

        // Fill array
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (
                _idToMarketItem[i + 1].seller == targetAddress &&
                _idToMarketItem[i + 1].onSale &&
                (_idToMarketItem[i + 1].typeItem == TypeItem.Regular ||
                    _idToMarketItem[i + 1].typeItem == TypeItem.Auction)
            ) {
                uint256 currentId = _idToMarketItem[i + 1].itemId;
                MarketItem storage currentItem = _idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }

    /**
     * Returns items owned by caller.
     */
    function fetchMyItemsOwned() public view returns (MarketItem[] memory) {
        return fetchAddressItemsOwned(msg.sender);
    }

    /**
     * Returns items owned by an address.
     */
    function fetchAddressItemsOwned(address targetAddress)
        public
        view
        returns (MarketItem[] memory)
    {
        // Get total number of items owned by target address
        uint256 totalItemCount = _itemIds.current();
        uint256 itemCount = 0;
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_idToMarketItem[i + 1].owner == targetAddress) {
                itemCount += 1;
            }
        }

        // Initialize array
        MarketItem[] memory items = new MarketItem[](itemCount);

        // Fill array
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_idToMarketItem[i + 1].owner == targetAddress) {
                uint256 currentId = _idToMarketItem[i + 1].itemId;
                MarketItem storage currentItem = _idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }

    /////////////////////////// REGULAR SALE ////////////////////////////////////

    /**
     * Puts on sale a new NFT.
     */
    function putNewNftOnSale(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) public {
        require(price > 0, "SqwidMarketplace: Price must be greater than 0.");

        // Create market item
        uint256 itemId = createMarketItem(nftContract, tokenId, amount);

        // Put on sale
        putMarketItemOnSale(itemId, price);
    }

    /**
     * Puts on sale existing market item.
     * TODO receive amount
     */
    function putMarketItemOnSale(uint256 itemId, uint256 price) public {
        require(
            _idToMarketItem[itemId].itemId > 0,
            "SqwidMarketplace: itemId does not exist."
        );
        require(
            !_idToMarketItem[itemId].onSale,
            "SqwidMarketplace: This item is already on sale."
        );
        require(price > 0, "SqwidMarketplace: Price must be greater than 0.");

        // Transfer ownership of the token to this contract
        IERC1155(_idToMarketItem[itemId].nftContract).safeTransferFrom(
            msg.sender,
            address(this),
            _idToMarketItem[itemId].tokenId,
            1,
            ""
        );

        // Update MarketItem
        _idToMarketItem[itemId].seller = payable(msg.sender);
        _idToMarketItem[itemId].owner = payable(address(0));
        _idToMarketItem[itemId].price = price;
        _idToMarketItem[itemId].marketFee = _marketFee;
        _idToMarketItem[itemId].onSale = true;
        _idToMarketItem[itemId].typeItem = TypeItem.Regular;

        _onRegularSale.increment();

        emit MarketItemUpdate(
            itemId,
            _idToMarketItem[itemId].nftContract,
            _idToMarketItem[itemId].tokenId,
            msg.sender,
            _idToMarketItem[itemId].creator,
            price,
            _marketFee,
            TypeItem.Regular
        );
    }

    /**
     * Creates a new sale for a existing market item.
     */
    function createMarketSale(uint256 itemId) public payable nonReentrant {
        require(
            _idToMarketItem[itemId].onSale &&
                _idToMarketItem[itemId].typeItem == TypeItem.Regular,
            "SqwidMarketplace: This item is not currently on sale."
        );
        uint256 price = _idToMarketItem[itemId].price;
        require(
            msg.value == price,
            "SqwidMarketplace: Value of transaction must be equal to sale price."
        );

        // Process transaction
        _createItemTransaction(itemId, msg.sender, msg.value);

        // Update item in the mapping
        address payable seller = _idToMarketItem[itemId].seller;
        _idToMarketItem[itemId].owner = payable(msg.sender);
        _idToMarketItem[itemId].onSale = false;
        _idToMarketItem[itemId].seller = payable(address(0));
        _idToMarketItem[itemId].price = 0;
        _idToMarketItem[itemId].sales.push(
            MarketItemSale(seller, msg.sender, price, TypeItem.Regular)
        );

        _onRegularSale.decrement();

        emit MarketItemSold(
            itemId,
            _idToMarketItem[itemId].nftContract,
            _idToMarketItem[itemId].tokenId,
            seller,
            msg.sender,
            price,
            TypeItem.Regular
        );
    }

    /**
     * Unlist item from regular sale.
     */
    function unlistMarketItem(uint256 itemId) public {
        require(
            _idToMarketItem[itemId].onSale &&
                _idToMarketItem[itemId].typeItem == TypeItem.Regular,
            "SqwidMarketplace: This item is not currently on sale."
        );
        require(
            msg.sender == _idToMarketItem[itemId].seller,
            "SqwidMarketplace: Only seller can unlist item."
        );

        // Transfer ownership back to seller
        IERC1155(_idToMarketItem[itemId].nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            _idToMarketItem[itemId].tokenId,
            1,
            ""
        );

        // Update MarketItem
        _idToMarketItem[itemId].owner = payable(msg.sender);
        _idToMarketItem[itemId].onSale = false;
        _idToMarketItem[itemId].seller = payable(address(0));
        _idToMarketItem[itemId].price = 0;

        _onRegularSale.decrement();
    }

    /**
     * Returns market items on regular sale.
     */
    function fetchItemsOnSale() public view returns (MarketItem[] memory) {
        uint256 currentIndex = 0;

        // Initialize array
        MarketItem[] memory items = new MarketItem[](_onRegularSale.current());

        // Fill array
        for (uint256 i = 0; i < _itemIds.current(); i++) {
            if (
                _idToMarketItem[i + 1].onSale &&
                (_idToMarketItem[i + 1].typeItem == TypeItem.Regular)
            ) {
                uint256 currentId = _idToMarketItem[i + 1].itemId;
                MarketItem storage currentItem = _idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }

    /////////////////////////// AUCTION ////////////////////////////////////

    /**
     * Creates an auction for a new item.
     */
    function createNewNftAuction(
        address nftContract,
        uint256 tokenId,
        uint256 numMinutes,
        uint256 minBid
    ) public {
        require(
            numMinutes <= 44640,
            "SqwidMarketplace: Number of minutes cannot be greater than 44,640."
        ); // 44,640 min = 1 month

        // Create market item
        uint256 itemId = createMarketItem(nftContract, tokenId);

        // Create auction
        createMarketItemAuction(itemId, numMinutes, minBid);
    }

    /**
     * Creates an auction from an existing market item.
     */
    function createMarketItemAuction(
        uint256 itemId,
        uint256 numMinutes,
        uint256 minBid
    ) public {
        require(
            _idToMarketItem[itemId].itemId > 0,
            "SqwidMarketplace: itemId does not exist."
        );
        require(
            !_idToMarketItem[itemId].onSale,
            "SqwidMarketplace: This item is already on sale."
        );
        require(
            numMinutes <= 44640,
            "SqwidMarketplace: Number of minutes cannot be greater than 44,640."
        ); // 44,640 min = 1 month

        // Transfer ownership of the token to this contract
        IERC1155(_idToMarketItem[itemId].nftContract).safeTransferFrom(
            msg.sender,
            address(this),
            _idToMarketItem[itemId].tokenId,
            1,
            ""
        );

        // Update MarketItem
        _idToMarketItem[itemId].seller = payable(msg.sender);
        _idToMarketItem[itemId].owner = payable(address(0));
        _idToMarketItem[itemId].price = 0;
        _idToMarketItem[itemId].marketFee = _marketFee;
        _idToMarketItem[itemId].onSale = true;
        _idToMarketItem[itemId].typeItem = TypeItem.Auction;

        // Create AuctionData
        uint256 deadline = (block.timestamp + numMinutes * 1 minutes);
        _idToAuctionData[itemId].deadline = deadline;
        _idToAuctionData[itemId].minBid = minBid;
        _idToAuctionData[itemId].highestBidder = address(0);
        _idToAuctionData[itemId].highestBid = 0;

        _onAuction.increment();

        emit MarketItemUpdate(
            itemId,
            _idToMarketItem[itemId].nftContract,
            _idToMarketItem[itemId].tokenId,
            msg.sender,
            msg.sender,
            0,
            _marketFee,
            TypeItem.Auction
        );
    }

    /**
     * Adds bid to an active auction.
     */
    function createBid(uint256 itemId) public payable {
        require(
            _idToMarketItem[itemId].onSale &&
                _idToMarketItem[itemId].typeItem == TypeItem.Auction &&
                _idToAuctionData[itemId].deadline >= block.timestamp,
            "SqwidMarketplace: There is no active auction for this item."
        );
        require(
            msg.value >= _idToAuctionData[itemId].minBid ||
                msg.sender == _idToAuctionData[itemId].highestBidder,
            "SqwidMarketplace: Bid value cannot be lower than minimum bid."
        );
        require(
            msg.value > _idToAuctionData[itemId].highestBid ||
                msg.sender == _idToAuctionData[itemId].highestBidder,
            "SqwidMarketplace: Bid value cannot be lower than highest bid."
        );

        // Update AuctionData
        if (msg.sender == _idToAuctionData[itemId].highestBidder) {
            // Highest bidder increases bid value
            _idToAuctionData[itemId].highestBid += msg.value;
        } else {
            if (_idToAuctionData[itemId].highestBidder != address(0)) {
                // Return bid amount to previous highest bidder, if exists
                payable(_idToAuctionData[itemId].highestBidder).transfer(
                    _idToAuctionData[itemId].highestBid
                );
            }
            _idToAuctionData[itemId].highestBid = msg.value;
            _idToAuctionData[itemId].highestBidder = msg.sender;
        }

        // Extend deadline if we are on last 10 minutes
        uint256 secsToDeadline = _idToAuctionData[itemId].deadline -
            block.timestamp;
        if (secsToDeadline < 600) {
            _idToAuctionData[itemId].deadline += (600 - secsToDeadline);
        }
    }

    /**
     * Distributes NFT and bidded amount after auction deadline is reached.
     */
    function endAuction(uint256 itemId) public nonReentrant {
        require(
            _idToMarketItem[itemId].onSale &&
                _idToMarketItem[itemId].typeItem == TypeItem.Auction,
            "SqwidMarketplace: There is no auction for this item."
        );
        require(
            _idToAuctionData[itemId].deadline < block.timestamp,
            "SqwidMarketplace: Auction deadline has not been reached yet."
        );

        // Update MarketItem
        _idToMarketItem[itemId].onSale = false;
        _onAuction.decrement();

        if (_idToAuctionData[itemId].highestBid > 0) {
            // Create transaction
            _createItemTransaction(
                itemId,
                _idToAuctionData[itemId].highestBidder,
                _idToAuctionData[itemId].highestBid
            );

            // Update item in the mapping
            _idToMarketItem[itemId].owner = payable(
                _idToAuctionData[itemId].highestBidder
            );
            _idToMarketItem[itemId].sales.push(
                MarketItemSale(
                    _idToMarketItem[itemId].seller,
                    _idToAuctionData[itemId].highestBidder,
                    _idToAuctionData[itemId].highestBid,
                    TypeItem.Auction
                )
            );

            emit MarketItemSold(
                itemId,
                _idToMarketItem[itemId].nftContract,
                _idToMarketItem[itemId].tokenId,
                _idToMarketItem[itemId].seller,
                _idToAuctionData[itemId].highestBidder,
                _idToAuctionData[itemId].highestBid,
                TypeItem.Auction
            );
        } else {
            // Transfer ownership of the token back to seller
            IERC1155(_idToMarketItem[itemId].nftContract).safeTransferFrom(
                address(this),
                _idToMarketItem[itemId].seller,
                _idToMarketItem[itemId].tokenId,
                1,
                ""
            );
            // Update item in the mapping
            _idToMarketItem[itemId].owner = payable(
                _idToMarketItem[itemId].seller
            );
        }

        delete _idToAuctionData[itemId];
    }

    /**
     * Returns auction data.
     */
    function fetchAuctionData(uint256 itemId)
        public
        view
        returns (AuctionData memory auctionData)
    {
        require(
            _idToMarketItem[itemId].onSale &&
                _idToMarketItem[itemId].typeItem == TypeItem.Auction,
            "SqwidMarketplace: There is no auction open for this item."
        );
        return _idToAuctionData[itemId];
    }

    /**
     * Returns active auctions.
     */
    function fetchAuctions() public view returns (MarketItem[] memory) {
        uint256 currentIndex = 0;

        // Initialize array
        MarketItem[] memory items = new MarketItem[](_onAuction.current());

        // Fill array
        for (uint256 i = 0; i < _itemIds.current(); i++) {
            if (
                _idToMarketItem[i + 1].onSale &&
                _idToMarketItem[i + 1].typeItem == TypeItem.Auction
            ) {
                uint256 currentId = _idToMarketItem[i + 1].itemId;
                MarketItem storage currentItem = _idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }

    /////////////////////////// RAFFLE ////////////////////////////////////

    /**
     * Creates a raffle for a new item.
     */
    function createNewNftRaffle(
        address nftContract,
        uint256 tokenId,
        uint256 numMinutes
    ) public {
        require(
            numMinutes <= 525600,
            "SqwidMarketplace: Number of minutes cannot be greater than 525,600."
        ); // 525,600 min = 1 year

        // Create market item
        uint256 itemId = createMarketItem(nftContract, tokenId);

        // Create raffle
        createMarketItemRaffle(itemId, numMinutes);
    }

    /**
     * Creates a raffle from an existing market item.
     */
    function createMarketItemRaffle(uint256 itemId, uint256 numMinutes) public {
        require(
            _idToMarketItem[itemId].itemId > 0,
            "SqwidMarketplace: itemId does not exist."
        );
        require(
            !_idToMarketItem[itemId].onSale,
            "SqwidMarketplace: This item is already on sale."
        );
        require(
            numMinutes <= 525600,
            "SqwidMarketplace: Number of minutes cannot be greater than 525,600."
        ); // 525,600 min = 1 year

        // Transfer ownership of the token to this contract
        IERC1155(_idToMarketItem[itemId].nftContract).safeTransferFrom(
            msg.sender,
            address(this),
            _idToMarketItem[itemId].tokenId,
            1,
            ""
        );

        // Update MarketItem
        _idToMarketItem[itemId].seller = payable(msg.sender);
        _idToMarketItem[itemId].owner = payable(address(0));
        _idToMarketItem[itemId].price = 0;
        _idToMarketItem[itemId].marketFee = _marketFee;
        _idToMarketItem[itemId].onSale = true;
        _idToMarketItem[itemId].typeItem = TypeItem.Raffle;

        // Create RaffleData
        uint256 deadline = (block.timestamp + numMinutes * 1 minutes);
        _idToRaffleData[itemId].deadline = deadline;

        _onRaffle.increment();

        emit MarketItemUpdate(
            itemId,
            _idToMarketItem[itemId].nftContract,
            _idToMarketItem[itemId].tokenId,
            msg.sender,
            msg.sender,
            0,
            _marketFee,
            TypeItem.Raffle
        );
    }

    /**
     * Adds entry to an active raffle.
     */
    function enterRaffle(uint256 itemId) public payable {
        require(
            _idToMarketItem[itemId].onSale &&
                _idToMarketItem[itemId].typeItem == TypeItem.Raffle,
            "SqwidMarketplace: There is no raffle active for this item."
        );
        require(
            msg.value >= 1 * (10**18),
            "SqwidMarketplace: Value of transaction must be at least 1 REEF."
        );

        uint256 value = msg.value / (10**18);

        // Update RaffleData
        if (!(_idToRaffleData[itemId].addressToAmount[msg.sender] > 0)) {
            _idToRaffleData[itemId].indexToAddress[
                _idToRaffleData[itemId].totalAddresses
            ] = payable(msg.sender);
            _idToRaffleData[itemId].totalAddresses += 1;
        }
        _idToRaffleData[itemId].addressToAmount[msg.sender] += value;
        _idToRaffleData[itemId].totalValue += value;
    }

    /**
     * Ends open raffle.
     */
    function endRaffle(uint256 itemId) public nonReentrant {
        require(
            _idToMarketItem[itemId].onSale &&
                _idToMarketItem[itemId].typeItem == TypeItem.Raffle,
            "SqwidMarketplace: There is no raffle open for this item."
        );
        require(
            _idToRaffleData[itemId].deadline < block.timestamp,
            "SqwidMarketplace: Raffle deadline has not been reached yet."
        );

        // Update MarketItem
        _idToMarketItem[itemId].onSale = false;
        _onRaffle.decrement();

        // Check if there are participants in the raffle
        if (_idToRaffleData[itemId].totalAddresses == 0) {
            address payable seller = _idToMarketItem[itemId].seller;
            // Transfer ownership back to seller
            IERC1155(_idToMarketItem[itemId].nftContract).safeTransferFrom(
                address(this),
                seller,
                _idToMarketItem[itemId].tokenId,
                1,
                ""
            );

            // Update item in the mapping
            _idToMarketItem[itemId].owner = seller;

            delete _idToRaffleData[itemId];
        } else {
            // Choose winner for the raffle
            uint256 totalValue = _idToRaffleData[itemId].totalValue;
            uint256 indexWinner = _pseudoRand() % totalValue;
            uint256 lastIndex = 0;
            for (
                uint256 i = 0;
                i < _idToRaffleData[itemId].totalAddresses;
                i++
            ) {
                address currAddress = _idToRaffleData[itemId].indexToAddress[i];
                lastIndex += _idToRaffleData[itemId].addressToAmount[
                    currAddress
                ];
                if (indexWinner < lastIndex) {
                    address payable seller = _idToMarketItem[itemId].seller;
                    _createItemTransaction(
                        itemId,
                        currAddress,
                        totalValue * (10**18)
                    );

                    // Update item in the mapping
                    _idToMarketItem[itemId].owner = payable(currAddress);
                    _idToMarketItem[itemId].sales.push(
                        MarketItemSale(
                            seller,
                            currAddress,
                            totalValue * (10**18),
                            TypeItem.Raffle
                        )
                    );

                    delete _idToRaffleData[itemId];

                    break;
                }
            }

            emit MarketItemSold(
                itemId,
                _idToMarketItem[itemId].nftContract,
                _idToMarketItem[itemId].tokenId,
                _idToMarketItem[itemId].seller,
                msg.sender,
                totalValue,
                TypeItem.Raffle
            );
        }
    }

    /**
     * Returns deadline of raffle and amount contributed by caller.
     */
    function fetchRaffleData(uint256 itemId)
        public
        view
        returns (uint256 deadline, uint256 contribution)
    {
        require(
            _idToMarketItem[itemId].onSale &&
                _idToMarketItem[itemId].typeItem == TypeItem.Raffle,
            "SqwidMarketplace: There is no raffle open for this item."
        );
        return (
            _idToRaffleData[itemId].deadline,
            _idToRaffleData[itemId].addressToAmount[msg.sender] * (10**18)
        );
    }

    /**
     * Returns active raffles.
     */
    function fetchRaffles() public view returns (MarketItem[] memory) {
        uint256 currentIndex = 0;

        // Initialize array
        MarketItem[] memory items = new MarketItem[](_onRaffle.current());

        // Fill array
        for (uint256 i = 0; i < _itemIds.current(); i++) {
            if (
                _idToMarketItem[i + 1].onSale &&
                _idToMarketItem[i + 1].typeItem == TypeItem.Raffle
            ) {
                uint256 currentId = _idToMarketItem[i + 1].itemId;
                MarketItem storage currentItem = _idToMarketItem[currentId];
                items[currentIndex] = currentItem;
                currentIndex += 1;
            }
        }

        return items;
    }

    /////////////////////////// UTILS ////////////////////////////////////

    /**
     * Pays royalties to the address designated by the NFT contract and returns the sale place
     * minus the royalties payed.
     */
    function _deduceRoyalties(
        address _nftContract,
        uint256 _tokenId,
        uint256 _grossSaleValue,
        address payable _seller
    ) internal returns (uint256 netSaleAmount) {
        // Get amount of royalties to pay and recipient
        (address royaltiesReceiver, uint256 royaltiesAmount) = IERC2981(
            _nftContract
        ).royaltyInfo(_tokenId, _grossSaleValue);

        // If seller and royalties receiver are the same, royalties will not be deduced
        if (_seller == royaltiesReceiver) {
            return _grossSaleValue;
        }

        // Deduce royalties from sale value
        uint256 netSaleValue = _grossSaleValue - royaltiesAmount;

        // Transfer royalties to rightholder if amount is not 0
        if (royaltiesAmount > 0) {
            (bool success, ) = royaltiesReceiver.call{value: royaltiesAmount}(
                ""
            );
            if (!success) {
                // TODO make amount claimable
            }
        }

        // Broadcast royalties payment
        emit RoyaltiesPaid(_tokenId, royaltiesAmount);

        return netSaleValue;
    }

    /**
     * Gets a pseudo-random number
     */
    function _pseudoRand() internal view returns (uint256) {
        uint256 seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp +
                        block.difficulty +
                        ((
                            uint256(keccak256(abi.encodePacked(block.coinbase)))
                        ) / (block.timestamp)) +
                        block.gaslimit +
                        ((uint256(keccak256(abi.encodePacked(msg.sender)))) /
                            (block.timestamp)) +
                        block.number
                )
            )
        );

        return seed;
    }

    /**
     * Creates transaction of token and selling amount
     */
    function _createItemTransaction(
        uint256 itemId,
        address tokenRecipient,
        uint256 saleValue
    ) internal {
        // Pay royalties
        address nftContract = _idToMarketItem[itemId].nftContract;
        uint256 tokenId = _idToMarketItem[itemId].tokenId;
        address payable seller = _idToMarketItem[itemId].seller;
        if (_checkRoyalties(nftContract)) {
            saleValue = _deduceRoyalties(
                nftContract,
                tokenId,
                saleValue,
                seller
            );
        }

        // Pay market fee
        uint256 marketFeeAmount = (saleValue *
            _idToMarketItem[itemId].marketFee) / 10000;
        (bool successFee, ) = owner().call{value: marketFeeAmount}("");
        require(successFee, "SqwidMarketplace: Market fee transfer failed.");
        uint256 netSaleValue = saleValue - marketFeeAmount;

        // Transfer value of the transaction to the seller
        (bool successTx, ) = seller.call{value: netSaleValue}("");
        require(successTx, "SqwidMarketplace: Seller payment transfer failed.");

        // Transfer ownership of the token to buyer
        IERC1155(nftContract).safeTransferFrom(
            address(this),
            tokenRecipient,
            tokenId,
            1,
            ""
        );
    }

    /**
     * Checks if a contract supports EIP-2981 for royalties.
     * View EIP-165 (https://eips.ethereum.org/EIPS/eip-165).
     */
    function _checkRoyalties(address contractAddress)
        internal
        view
        returns (bool)
    {
        bool success = IERC165(contractAddress).supportsInterface(
            INTERFACE_ID_ERC2981
        );
        return success;
    }
}
