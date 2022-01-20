// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "../@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../@openzeppelin/contracts/utils/Counters.sol";
import "../@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IRoyaltyInfo.sol";

contract SqwidMarketplace is ERC1155Holder, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    enum PositionState {
        Available,
        RegularSale,
        Auction,
        Raffle,
        Loan
    }

    /**
     * Represents a specific token in the marketplace.
     */
    struct Item {
        uint256 itemId; // Incremental ID in the market contract
        address nftContract;
        uint256 tokenId; // Incremental ID in the NFT contract
        address creator;
        uint256 positionCount;
        ItemSale[] sales;
    }

    /**
     * Represents the position of a certain amount of tokens for an owner.
     * E.g.:
     *      - Alice has 10 XYZ tokens in auction
     *      - Alice has 2 XYZ tokens for sale for 5 Reef
     *      - Alice has 1 ABC token in a raffle
     *      - Bob has 10 XYZ tokens in sale for 5 Reef
     */
    struct Position {
        uint256 positionId;
        uint256 itemId;
        address payable owner;
        uint256 amount;
        uint256 price;
        uint256 marketFee; // Market fee at the moment of creating the item
        PositionState state;
    }

    struct ItemSale {
        address seller;
        address buyer;
        uint256 price;
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

    struct ItemReturn {
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        address creator;
        ItemSale[] sales;
        Position[] positions;
    }

    struct PositionReturn {
        uint256 positionId;
        Item item;
        address payable owner;
        uint256 amount;
        uint256 price;
        uint256 marketFee;
        PositionState state;
        AuctionData auctionData;
        RaffleDataReturn raffleData;
    }

    struct RaffleDataReturn {
        uint256 deadline;
        uint256 totalValue;
        uint256 totalAddresses;
    }

    // bytes4(keccak256("royaltyInfo(uint256,uint256)")) == 0x2a55205a
    bytes4 private constant INTERFACE_ID_ERC2981 = 0x2a55205a;

    address private _loanAddress;
    uint256 private _marketFee;
    Counters.Counter private _itemIds;
    Counters.Counter private _positionIds;
    Counters.Counter private _onRegularSale;
    Counters.Counter private _onAuction;
    Counters.Counter private _onRaffle;

    mapping(uint256 => Item) private _idToItem;

    mapping(uint256 => Position) private _idToPosition;

    mapping(uint256 => AuctionData) private _idToAuctionData;

    mapping(uint256 => RaffleData) private _idToRaffleData;

    event ItemCreated(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address creator
    );

    event PositionUpdate(
        uint256 indexed positionId,
        uint256 indexed itemId,
        address indexed owner,
        uint256 amount,
        uint256 price,
        uint256 marketFee,
        PositionState state
    );

    event PositionDelete(uint256 indexed positionId);

    event MarketItemSold(
        uint256 indexed itemId,
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price
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
    function createItem(address nftContract, uint256 tokenId)
        public
        returns (uint256)
    {
        require(
            IERC1155(nftContract).balanceOf(msg.sender, tokenId) > 0,
            "SqwidMarketplace: This address does not own enough tokens."
        );

        // Check if item already exists
        uint256 totalItemCount = _itemIds.current();
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (
                _idToItem[i + 1].nftContract == nftContract &&
                _idToItem[i + 1].tokenId == tokenId
            ) {
                revert("SqwidMarketplace: Item already exists.");
            }
        }

        // Map new Item
        _itemIds.increment();
        uint256 itemId = _itemIds.current();
        _idToItem[itemId].itemId = itemId;
        _idToItem[itemId].nftContract = nftContract;
        _idToItem[itemId].tokenId = tokenId;
        _idToItem[itemId].creator = msg.sender;
        _idToItem[itemId].positionCount = 0;

        emit ItemCreated(itemId, nftContract, tokenId, msg.sender);

        return itemId;
    }

    /**
     * Updates a item position from SqwidLoan contract.
     * TODO
     */
    // function updatePosition(
    //     uint256 positionId,
    //     address newItemOwner,
    //     bool isOnLoan
    // ) public virtual {
    //     require(
    //         msg.sender == _loanAddress,
    //         "SqwidMarketplace: Only loan contract can change item position owner."
    //     );

    //     _idToPosition[positionId].owner = payable(newItemOwner);
    //     _idToPosition[positionId].state = isOnLoan
    //         ? PositionState.Loan
    //         : PositionState.Available;

    //     emit PositionUpdate(
    //         positionId,
    //         _idToPosition[positionId].itemId,
    //         newItemOwner,
    //         _idToPosition[positionId].amount,
    //         _idToPosition[positionId].price,
    //         _idToPosition[positionId].marketFee,
    //         _idToPosition[positionId].state
    //     );
    // }

    /**
     * Returns item and all its item positions.
     */
    function fetchItem(uint256 itemId) public view returns (ItemReturn memory) {
        require(
            _idToItem[itemId].itemId > 0,
            "SqwidMarketplace: itemId does not exist."
        );

        return
            ItemReturn(
                itemId,
                _idToItem[itemId].nftContract,
                _idToItem[itemId].tokenId,
                _idToItem[itemId].creator,
                _idToItem[itemId].sales,
                _fetchPositionsByItemId(itemId)
            );
    }

    /**
     * Returns items created by caller.
     */
    function fetchMyItemsCreated() public view returns (ItemReturn[] memory) {
        return fetchAddressItemsCreated(msg.sender);
    }

    /**
     * Returns items created by an address.
     */
    function fetchAddressItemsCreated(address targetAddress)
        public
        view
        returns (ItemReturn[] memory)
    {
        // Get total number of items created by target address
        uint256 totalItemCount = _itemIds.current();
        uint256 itemCount = 0;
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_idToItem[i + 1].creator == targetAddress) {
                itemCount += 1;
            }
        }

        // Initialize array
        ItemReturn[] memory items = new ItemReturn[](itemCount);

        // Fill array
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < totalItemCount; i++) {
            if (_idToItem[i + 1].creator == targetAddress) {
                items[currentIndex] = fetchItem(i + 1);
                currentIndex += 1;
            }
        }

        return items;
    }

    // /**
    //  * Returns items currently on sale (regular, auction or raffle) by caller.
    //  */
    // function fetchMyItemsOnSale() public view returns (Item[] memory) {
    //     return fetchAddressItemsOnSale(msg.sender);
    // }

    // /**
    //  * Returns items currently on sale (regular, auction or raffle) by an address.
    //  */
    // function fetchAddressItemsOnSale(address targetAddress)
    //     public
    //     view
    //     returns (MarketItem[] memory)
    // {
    //     // Get total number of items on sale by target address
    //     uint256 totalItemCount = _itemIds.current();
    //     uint256 itemCount = 0;
    //     uint256 currentIndex = 0;
    //     for (uint256 i = 0; i < totalItemCount; i++) {
    //         if (
    //             _idToItem[i + 1].seller == targetAddress &&
    //             _idToItem[i + 1].onSale &&
    //             (_idToItem[i + 1].typeItem == TypeItem.Regular ||
    //                 _idToItem[i + 1].typeItem == TypeItem.Auction)
    //         ) {
    //             itemCount += 1;
    //         }
    //     }

    //     // Initialize array
    //     MarketItem[] memory items = new MarketItem[](itemCount);

    //     // Fill array
    //     for (uint256 i = 0; i < totalItemCount; i++) {
    //         if (
    //             _idToItem[i + 1].seller == targetAddress &&
    //             _idToItem[i + 1].onSale &&
    //             (_idToItem[i + 1].typeItem == TypeItem.Regular ||
    //                 _idToItem[i + 1].typeItem == TypeItem.Auction)
    //         ) {
    //             uint256 currentId = _idToItem[i + 1].itemId;
    //             MarketItem storage currentItem = _idToItem[currentId];
    //             items[currentIndex] = currentItem;
    //             currentIndex += 1;
    //         }
    //     }

    //     return items;
    // }

    /**
     * Returns items owned by caller.
     */
    // function fetchMyItemsOwned() public view returns () {
    //     return fetchAddressItemsOwned(msg.sender);
    // }

    // /**
    //  * Returns items owned by an address.
    //  */
    // function fetchAddressItemsOwned(address targetAddress)
    //     public
    //     view
    //     returns (MarketItem[] memory)
    // {
    //     // Get total number of items owned by target address
    //     uint256 totalItemCount = _itemIds.current();
    //     uint256 itemCount = 0;
    //     uint256 currentIndex = 0;
    //     for (uint256 i = 0; i < totalItemCount; i++) {
    //         if (_idToItem[i + 1].owner == targetAddress) {
    //             itemCount += 1;
    //         }
    //     }

    //     // Initialize array
    //     MarketItem[] memory items = new MarketItem[](itemCount);

    //     // Fill array
    //     for (uint256 i = 0; i < totalItemCount; i++) {
    //         if (_idToItem[i + 1].owner == targetAddress) {
    //             uint256 currentId = _idToItem[i + 1].itemId;
    //             MarketItem storage currentItem = _idToItem[currentId];
    //             items[currentIndex] = currentItem;
    //             currentIndex += 1;
    //         }
    //     }

    //     return items;
    // }

    /**
     * Returns item position.
     */
    function fetchPosition(uint256 positionId)
        public
        view
        returns (PositionReturn memory)
    {
        require(
            _idToPosition[positionId].positionId > 0,
            "SqwidMarketplace: positionId does not exist."
        );

        AuctionData memory auctionData;
        RaffleDataReturn memory raffleData;
        if (_idToPosition[positionId].state == PositionState.Auction) {
            auctionData = _idToAuctionData[positionId];
        } else if (_idToPosition[positionId].state == PositionState.Raffle) {
            raffleData.deadline = _idToRaffleData[positionId].deadline;
            raffleData.totalValue = _idToRaffleData[positionId].totalValue;
            raffleData.totalAddresses = _idToRaffleData[positionId]
                .totalAddresses;
        }

        return
            PositionReturn(
                positionId,
                _idToItem[_idToPosition[positionId].itemId],
                _idToPosition[positionId].owner,
                _idToPosition[positionId].amount,
                _idToPosition[positionId].price,
                _idToPosition[positionId].marketFee,
                _idToPosition[positionId].state,
                auctionData,
                raffleData
            );
    }

    /////////////////////////// REGULAR SALE ////////////////////////////////////

    /**
     * Puts on sale a new NFT.
     */
    function putNewItemOnSale(
        address nftContract,
        uint256 tokenId,
        uint256 amount,
        uint256 price
    ) public {
        require(price > 0, "SqwidMarketplace: Price must be greater than 0.");
        require(amount > 0, "SqwidMarketplace: Amount must be greater than 0.");

        // Create market item
        uint256 itemId = createItem(nftContract, tokenId);

        // Put on sale
        putItemOnSale(itemId, amount, price);
    }

    /**
     * Puts on sale existing market item.
     */
    function putItemOnSale(
        uint256 itemId,
        uint256 amount,
        uint256 price
    ) public {
        require(
            _idToItem[itemId].itemId > 0,
            "SqwidMarketplace: itemId does not exist."
        );
        require(price > 0, "SqwidMarketplace: Price must be greater than 0.");

        require(
            _getOwnerUnavailableAmount(itemId, msg.sender) + amount <=
                IERC1155(_idToItem[itemId].nftContract).balanceOf(
                    msg.sender,
                    _idToItem[itemId].tokenId
                ),
            "SqwidMarketplace: Available NFT balance is not enough."
        );

        // Transfer ownership of the token to this contract
        IERC1155(_idToItem[itemId].nftContract).safeTransferFrom(
            msg.sender,
            address(this),
            _idToItem[itemId].tokenId,
            amount,
            ""
        );

        // Map new Position
        _positionIds.increment();
        uint256 positionId = _positionIds.current();
        _idToPosition[positionId] = Position(
            positionId,
            itemId,
            payable(msg.sender),
            amount,
            price,
            _marketFee,
            PositionState.RegularSale
        );

        _idToItem[itemId].positionCount++;

        _onRegularSale.increment();

        emit PositionUpdate(
            positionId,
            itemId,
            msg.sender,
            amount,
            price,
            _marketFee,
            PositionState.RegularSale
        );
    }

    /**
     * Creates a new sale for a existing market item.
     */
    function createSale(uint256 positionId, uint256 amount)
        public
        payable
        nonReentrant
    {
        require(
            _idToPosition[positionId].state == PositionState.RegularSale,
            "SqwidMarketplace: This item is not currently on sale."
        );
        require(
            _idToPosition[positionId].amount >= amount,
            "SqwidMarketplace: The amount sent is greater than the amount available."
        );
        uint256 price = _idToPosition[positionId].price;
        require(
            msg.value == (price * amount),
            "SqwidMarketplace: Value of transaction must be equal to sale price * amount."
        );

        uint256 itemId = _idToPosition[positionId].itemId;
        address seller = _idToPosition[positionId].owner;

        // Process transaction
        _createItemTransaction(positionId, msg.sender, msg.value, amount);

        // Update item and item position
        _idToItem[itemId].sales.push(ItemSale(seller, msg.sender, msg.value));
        if (amount == _idToPosition[positionId].amount) {
            delete _idToPosition[positionId];
            emit PositionDelete(positionId);
            _idToItem[itemId].positionCount--;
        } else {
            _idToPosition[positionId].amount -= amount;
        }

        // Create new position or update exising one for the buyer
        uint256 buyerPositionId;
        Position memory buyerPosition = _fetchAvalailablePosition(
            itemId,
            msg.sender
        );
        if (buyerPosition.itemId != 0) {
            buyerPositionId = buyerPosition.itemId;
            _idToPosition[buyerPositionId].amount += amount;
        } else {
            _positionIds.increment();
            buyerPositionId = _positionIds.current();
            _idToPosition[buyerPositionId] = Position(
                buyerPositionId,
                itemId,
                payable(msg.sender),
                amount,
                0,
                0,
                PositionState.Available
            );
            _idToItem[itemId].positionCount++;
        }

        emit PositionUpdate(
            buyerPositionId,
            _idToPosition[buyerPositionId].itemId,
            _idToPosition[buyerPositionId].owner,
            _idToPosition[buyerPositionId].amount,
            _idToPosition[buyerPositionId].price,
            _idToPosition[buyerPositionId].marketFee,
            _idToPosition[buyerPositionId].state
        );

        _onRegularSale.decrement();

        emit MarketItemSold(
            itemId,
            _idToItem[itemId].nftContract,
            _idToItem[itemId].tokenId,
            seller,
            msg.sender,
            msg.value
        );
    }

    /**
     * Unlist item from regular sale.
     */
    function unlistPositionOnSale(uint256 positionId) public {
        require(
            _idToPosition[positionId].state == PositionState.RegularSale,
            "SqwidMarketplace: This item is not currently on sale."
        );
        require(
            msg.sender == _idToPosition[positionId].owner,
            "SqwidMarketplace: Only seller can unlist item."
        );

        uint256 itemId = _idToPosition[positionId].itemId;
        uint256 amount = _idToPosition[positionId].amount;

        // Transfer ownership back to seller
        IERC1155(_idToItem[itemId].nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            _idToItem[itemId].tokenId,
            amount,
            ""
        );

        // Delete item position
        delete _idToPosition[positionId];
        emit PositionDelete(positionId);

        // Create new position or update exising one for seller
        uint256 sellerPositionId;
        Position memory sellerPosition = _fetchAvalailablePosition(
            itemId,
            msg.sender
        );
        if (sellerPosition.itemId != 0) {
            sellerPositionId = sellerPosition.itemId;
            _idToPosition[sellerPositionId].amount += amount;
            _idToItem[itemId].positionCount--;
        } else {
            _positionIds.increment();
            sellerPositionId = _positionIds.current();
            _idToPosition[sellerPositionId] = Position(
                sellerPositionId,
                itemId,
                payable(msg.sender),
                amount,
                0,
                0,
                PositionState.Available
            );
        }

        _onRegularSale.decrement();
    }

    /**
     * Returns market item positions on regular sale.
     */
    function fetchPositionsOnSale()
        public
        view
        returns (PositionReturn[] memory)
    {
        uint256 currentIndex = 0;

        // Initialize array
        PositionReturn[] memory items = new PositionReturn[](
            _onRegularSale.current()
        );

        // Fill array
        for (uint256 i = 0; i < _itemIds.current(); i++) {
            if (_idToPosition[i + 1].state == PositionState.RegularSale) {
                items[currentIndex] = fetchPosition(i + 1);
                currentIndex += 1;
            }
        }

        return items;
    }

    /////////////////////////// AUCTION ////////////////////////////////////

    /**
     * Creates an auction for a new item.
     */
    // function createNewNftAuction(
    //     address nftContract,
    //     uint256 tokenId,
    //     uint256 numMinutes,
    //     uint256 minBid
    // ) public {
    //     require(
    //         numMinutes <= 44640,
    //         "SqwidMarketplace: Number of minutes cannot be greater than 44,640."
    //     ); // 44,640 min = 1 month

    //     // Create market item
    //     uint256 itemId = createMarketItem(nftContract, tokenId);

    //     // Create auction
    //     createMarketItemAuction(itemId, numMinutes, minBid);
    // }

    /**
     * Creates an auction from an existing market item.
     */
    // function createMarketItemAuction(
    //     uint256 itemId,
    //     uint256 numMinutes,
    //     uint256 minBid
    // ) public {
    //     require(
    //         _idToItem[itemId].itemId > 0,
    //         "SqwidMarketplace: itemId does not exist."
    //     );
    //     require(
    //         !_idToItem[itemId].onSale,
    //         "SqwidMarketplace: This item is already on sale."
    //     );
    //     require(
    //         numMinutes <= 44640,
    //         "SqwidMarketplace: Number of minutes cannot be greater than 44,640."
    //     ); // 44,640 min = 1 month

    //     // Transfer ownership of the token to this contract
    //     IERC1155(_idToItem[itemId].nftContract).safeTransferFrom(
    //         msg.sender,
    //         address(this),
    //         _idToItem[itemId].tokenId,
    //         1,
    //         ""
    //     );

    //     // Update MarketItem
    //     _idToItem[itemId].seller = payable(msg.sender);
    //     _idToItem[itemId].owner = payable(address(0));
    //     _idToItem[itemId].price = 0;
    //     _idToItem[itemId].marketFee = _marketFee;
    //     _idToItem[itemId].onSale = true;
    //     _idToItem[itemId].typeItem = TypeItem.Auction;

    //     // Create AuctionData
    //     uint256 deadline = (block.timestamp + numMinutes * 1 minutes);
    //     _idToAuctionData[itemId].deadline = deadline;
    //     _idToAuctionData[itemId].minBid = minBid;
    //     _idToAuctionData[itemId].highestBidder = address(0);
    //     _idToAuctionData[itemId].highestBid = 0;

    //     _onAuction.increment();

    //     emit MarketItemUpdate(
    //         itemId,
    //         _idToItem[itemId].nftContract,
    //         _idToItem[itemId].tokenId,
    //         msg.sender,
    //         msg.sender,
    //         0,
    //         _marketFee,
    //         TypeItem.Auction
    //     );
    // }

    /**
     * Adds bid to an active auction.
     */
    // function createBid(uint256 itemId) public payable {
    //     require(
    //         _idToItem[itemId].onSale &&
    //             _idToItem[itemId].typeItem == TypeItem.Auction &&
    //             _idToAuctionData[itemId].deadline >= block.timestamp,
    //         "SqwidMarketplace: There is no active auction for this item."
    //     );
    //     require(
    //         msg.value >= _idToAuctionData[itemId].minBid ||
    //             msg.sender == _idToAuctionData[itemId].highestBidder,
    //         "SqwidMarketplace: Bid value cannot be lower than minimum bid."
    //     );
    //     require(
    //         msg.value > _idToAuctionData[itemId].highestBid ||
    //             msg.sender == _idToAuctionData[itemId].highestBidder,
    //         "SqwidMarketplace: Bid value cannot be lower than highest bid."
    //     );

    //     // Update AuctionData
    //     if (msg.sender == _idToAuctionData[itemId].highestBidder) {
    //         // Highest bidder increases bid value
    //         _idToAuctionData[itemId].highestBid += msg.value;
    //     } else {
    //         if (_idToAuctionData[itemId].highestBidder != address(0)) {
    //             // Return bid amount to previous highest bidder, if exists
    //             payable(_idToAuctionData[itemId].highestBidder).transfer(
    //                 _idToAuctionData[itemId].highestBid
    //             );
    //         }
    //         _idToAuctionData[itemId].highestBid = msg.value;
    //         _idToAuctionData[itemId].highestBidder = msg.sender;
    //     }

    //     // Extend deadline if we are on last 10 minutes
    //     uint256 secsToDeadline = _idToAuctionData[itemId].deadline -
    //         block.timestamp;
    //     if (secsToDeadline < 600) {
    //         _idToAuctionData[itemId].deadline += (600 - secsToDeadline);
    //     }
    // }

    /**
     * Distributes NFT and bidded amount after auction deadline is reached.
     */
    // function endAuction(uint256 itemId) public nonReentrant {
    //     require(
    //         _idToItem[itemId].onSale &&
    //             _idToItem[itemId].typeItem == TypeItem.Auction,
    //         "SqwidMarketplace: There is no auction for this item."
    //     );
    //     require(
    //         _idToAuctionData[itemId].deadline < block.timestamp,
    //         "SqwidMarketplace: Auction deadline has not been reached yet."
    //     );

    //     // Update MarketItem
    //     _idToItem[itemId].onSale = false;
    //     _onAuction.decrement();

    //     if (_idToAuctionData[itemId].highestBid > 0) {
    //         // Create transaction
    //         _createItemTransaction(
    //             itemId,
    //             _idToAuctionData[itemId].highestBidder,
    //             _idToAuctionData[itemId].highestBid
    //         );

    //         // Update item in the mapping
    //         _idToItem[itemId].owner = payable(
    //             _idToAuctionData[itemId].highestBidder
    //         );
    //         _idToItem[itemId].sales.push(
    //             MarketItemSale(
    //                 _idToItem[itemId].seller,
    //                 _idToAuctionData[itemId].highestBidder,
    //                 _idToAuctionData[itemId].highestBid,
    //                 TypeItem.Auction
    //             )
    //         );

    //         emit MarketItemSold(
    //             itemId,
    //             _idToItem[itemId].nftContract,
    //             _idToItem[itemId].tokenId,
    //             _idToItem[itemId].seller,
    //             _idToAuctionData[itemId].highestBidder,
    //             _idToAuctionData[itemId].highestBid,
    //             TypeItem.Auction
    //         );
    //     } else {
    //         // Transfer ownership of the token back to seller
    //         IERC1155(_idToItem[itemId].nftContract).safeTransferFrom(
    //             address(this),
    //             _idToItem[itemId].seller,
    //             _idToItem[itemId].tokenId,
    //             1,
    //             ""
    //         );
    //         // Update item in the mapping
    //         _idToItem[itemId].owner = payable(_idToItem[itemId].seller);
    //     }

    //     delete _idToAuctionData[itemId];
    // }

    /**
     * Returns auction data.
     */
    // function fetchAuctionData(uint256 itemId)
    //     public
    //     view
    //     returns (AuctionData memory auctionData)
    // {
    //     require(
    //         _idToItem[itemId].onSale &&
    //             _idToItem[itemId].typeItem == TypeItem.Auction,
    //         "SqwidMarketplace: There is no auction open for this item."
    //     );
    //     return _idToAuctionData[itemId];
    // }

    /**
     * Returns active auctions.
     */
    // function fetchAuctions() public view returns (MarketItem[] memory) {
    //     uint256 currentIndex = 0;

    //     // Initialize array
    //     MarketItem[] memory items = new MarketItem[](_onAuction.current());

    //     // Fill array
    //     for (uint256 i = 0; i < _itemIds.current(); i++) {
    //         if (
    //             _idToItem[i + 1].onSale &&
    //             _idToItem[i + 1].typeItem == TypeItem.Auction
    //         ) {
    //             uint256 currentId = _idToItem[i + 1].itemId;
    //             MarketItem storage currentItem = _idToItem[currentId];
    //             items[currentIndex] = currentItem;
    //             currentIndex += 1;
    //         }
    //     }

    //     return items;
    // }

    /////////////////////////// RAFFLE ////////////////////////////////////

    /**
     * Creates a raffle for a new item.
     */
    // function createNewNftRaffle(
    //     address nftContract,
    //     uint256 tokenId,
    //     uint256 numMinutes
    // ) public {
    //     require(
    //         numMinutes <= 525600,
    //         "SqwidMarketplace: Number of minutes cannot be greater than 525,600."
    //     ); // 525,600 min = 1 year

    //     // Create market item
    //     uint256 itemId = createMarketItem(nftContract, tokenId);

    //     // Create raffle
    //     createMarketItemRaffle(itemId, numMinutes);
    // }

    /**
     * Creates a raffle from an existing market item.
     */
    // function createMarketItemRaffle(uint256 itemId, uint256 numMinutes) public {
    //     require(
    //         _idToItem[itemId].itemId > 0,
    //         "SqwidMarketplace: itemId does not exist."
    //     );
    //     require(
    //         !_idToItem[itemId].onSale,
    //         "SqwidMarketplace: This item is already on sale."
    //     );
    //     require(
    //         numMinutes <= 525600,
    //         "SqwidMarketplace: Number of minutes cannot be greater than 525,600."
    //     ); // 525,600 min = 1 year

    //     // Transfer ownership of the token to this contract
    //     IERC1155(_idToItem[itemId].nftContract).safeTransferFrom(
    //         msg.sender,
    //         address(this),
    //         _idToItem[itemId].tokenId,
    //         1,
    //         ""
    //     );

    //     // Update MarketItem
    //     _idToItem[itemId].seller = payable(msg.sender);
    //     _idToItem[itemId].owner = payable(address(0));
    //     _idToItem[itemId].price = 0;
    //     _idToItem[itemId].marketFee = _marketFee;
    //     _idToItem[itemId].onSale = true;
    //     _idToItem[itemId].typeItem = TypeItem.Raffle;

    //     // Create RaffleData
    //     uint256 deadline = (block.timestamp + numMinutes * 1 minutes);
    //     _idToRaffleData[itemId].deadline = deadline;

    //     _onRaffle.increment();

    //     emit MarketItemUpdate(
    //         itemId,
    //         _idToItem[itemId].nftContract,
    //         _idToItem[itemId].tokenId,
    //         msg.sender,
    //         msg.sender,
    //         0,
    //         _marketFee,
    //         TypeItem.Raffle
    //     );
    // }

    /**
     * Adds entry to an active raffle.
     */
    // function enterRaffle(uint256 itemId) public payable {
    //     require(
    //         _idToItem[itemId].onSale &&
    //             _idToItem[itemId].typeItem == TypeItem.Raffle,
    //         "SqwidMarketplace: There is no raffle active for this item."
    //     );
    //     require(
    //         msg.value >= 1 * (10**18),
    //         "SqwidMarketplace: Value of transaction must be at least 1 REEF."
    //     );

    //     uint256 value = msg.value / (10**18);

    //     // Update RaffleData
    //     if (!(_idToRaffleData[itemId].addressToAmount[msg.sender] > 0)) {
    //         _idToRaffleData[itemId].indexToAddress[
    //             _idToRaffleData[itemId].totalAddresses
    //         ] = payable(msg.sender);
    //         _idToRaffleData[itemId].totalAddresses += 1;
    //     }
    //     _idToRaffleData[itemId].addressToAmount[msg.sender] += value;
    //     _idToRaffleData[itemId].totalValue += value;
    // }

    /**
     * Ends open raffle.
     */
    // function endRaffle(uint256 itemId) public nonReentrant {
    //     require(
    //         _idToItem[itemId].onSale &&
    //             _idToItem[itemId].typeItem == TypeItem.Raffle,
    //         "SqwidMarketplace: There is no raffle open for this item."
    //     );
    //     require(
    //         _idToRaffleData[itemId].deadline < block.timestamp,
    //         "SqwidMarketplace: Raffle deadline has not been reached yet."
    //     );

    //     // Update MarketItem
    //     _idToItem[itemId].onSale = false;
    //     _onRaffle.decrement();

    //     // Check if there are participants in the raffle
    //     if (_idToRaffleData[itemId].totalAddresses == 0) {
    //         address payable seller = _idToItem[itemId].seller;
    //         // Transfer ownership back to seller
    //         IERC1155(_idToItem[itemId].nftContract).safeTransferFrom(
    //             address(this),
    //             seller,
    //             _idToItem[itemId].tokenId,
    //             1,
    //             ""
    //         );

    //         // Update item in the mapping
    //         _idToItem[itemId].owner = seller;

    //         delete _idToRaffleData[itemId];
    //     } else {
    //         // Choose winner for the raffle
    //         uint256 totalValue = _idToRaffleData[itemId].totalValue;
    //         uint256 indexWinner = _pseudoRand() % totalValue;
    //         uint256 lastIndex = 0;
    //         for (
    //             uint256 i = 0;
    //             i < _idToRaffleData[itemId].totalAddresses;
    //             i++
    //         ) {
    //             address currAddress = _idToRaffleData[itemId].indexToAddress[i];
    //             lastIndex += _idToRaffleData[itemId].addressToAmount[
    //                 currAddress
    //             ];
    //             if (indexWinner < lastIndex) {
    //                 address payable seller = _idToItem[itemId].seller;
    //                 _createItemTransaction(
    //                     itemId,
    //                     currAddress,
    //                     totalValue * (10**18)
    //                 );

    //                 // Update item in the mapping
    //                 _idToItem[itemId].owner = payable(currAddress);
    //                 _idToItem[itemId].sales.push(
    //                     MarketItemSale(
    //                         seller,
    //                         currAddress,
    //                         totalValue * (10**18),
    //                         TypeItem.Raffle
    //                     )
    //                 );

    //                 delete _idToRaffleData[itemId];

    //                 break;
    //             }
    //         }

    //         emit MarketItemSold(
    //             itemId,
    //             _idToItem[itemId].nftContract,
    //             _idToItem[itemId].tokenId,
    //             _idToItem[itemId].seller,
    //             msg.sender,
    //             totalValue,
    //             TypeItem.Raffle
    //         );
    //     }
    // }

    /**
     * Returns deadline of raffle and amount contributed by caller.
     */
    // function fetchRaffleData(uint256 itemId)
    //     public
    //     view
    //     returns (uint256 deadline, uint256 contribution)
    // {
    //     require(
    //         _idToItem[itemId].onSale &&
    //             _idToItem[itemId].typeItem == TypeItem.Raffle,
    //         "SqwidMarketplace: There is no raffle open for this item."
    //     );
    //     return (
    //         _idToRaffleData[itemId].deadline,
    //         _idToRaffleData[itemId].addressToAmount[msg.sender] * (10**18)
    //     );
    // }

    /**
     * Returns active raffles.
     */
    // function fetchRaffles() public view returns (MarketItem[] memory) {
    //     uint256 currentIndex = 0;

    //     // Initialize array
    //     MarketItem[] memory items = new MarketItem[](_onRaffle.current());

    //     // Fill array
    //     for (uint256 i = 0; i < _itemIds.current(); i++) {
    //         if (
    //             _idToItem[i + 1].onSale &&
    //             _idToItem[i + 1].typeItem == TypeItem.Raffle
    //         ) {
    //             uint256 currentId = _idToItem[i + 1].itemId;
    //             MarketItem storage currentItem = _idToItem[currentId];
    //             items[currentIndex] = currentItem;
    //             currentIndex += 1;
    //         }
    //     }
    //
    //     return items;
    // }

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

    // /**
    //  * Creates transaction of token and selling amount
    //  */
    function _createItemTransaction(
        uint256 positionId,
        address tokenRecipient,
        uint256 saleValue,
        uint256 amount
    ) internal {
        uint256 itemId = _idToPosition[positionId].itemId;
        // Pay royalties
        address nftContract = _idToItem[itemId].nftContract;
        uint256 tokenId = _idToItem[itemId].tokenId;
        address payable seller = _idToPosition[positionId].owner;
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
            _idToPosition[positionId].marketFee) / 10000;
        (bool successFee, ) = owner().call{value: marketFeeAmount}("");
        // require(successFee, "SqwidMarketplace: Market fee transfer failed.");
        // TODO To prevent malicious contract making the entire process fail, allow withdrawal in case the transaction fails

        uint256 netSaleValue = saleValue - marketFeeAmount;

        // Transfer value of the transaction to the seller
        (bool successTx, ) = seller.call{value: netSaleValue}("");
        // require(successTx, "SqwidMarketplace: Seller payment transfer failed.");
        // TODO To prevent malicious contract making the entire process fail, allow withdrawal in case the transaction fails

        // Transfer ownership of the token to buyer
        IERC1155(nftContract).safeTransferFrom(
            address(this),
            tokenRecipient,
            tokenId,
            amount,
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

    /**
     * Returns item positions of a certain item.
     */
    function _fetchPositionsByItemId(uint256 itemId)
        private
        view
        returns (Position[] memory)
    {
        // Initialize array
        Position[] memory items = new Position[](
            _idToItem[itemId].positionCount
        );

        // Fill array
        uint256 totalPositionCount = _positionIds.current();
        uint256 currentIndex = 0;
        for (uint256 i = 0; i < totalPositionCount; i++) {
            if (_idToPosition[i + 1].itemId == itemId) {
                items[currentIndex] = _idToPosition[i + 1];
                currentIndex++;
            }
        }

        return items;
    }

    /**
     * Returns item available position of a certain item and owner.
     */
    function _fetchAvalailablePosition(uint256 itemId, address tokenOwner)
        private
        view
        returns (Position memory)
    {
        uint256 totalPositionCount = _positionIds.current();
        for (uint256 i = 0; i < totalPositionCount; i++) {
            if (
                _idToPosition[i + 1].itemId == itemId &&
                _idToPosition[i + 1].owner == tokenOwner &&
                _idToPosition[i + 1].state == PositionState.Available
            ) {
                return _idToPosition[i + 1];
            }
        }

        Position memory emptyPosition;
        return emptyPosition;
    }

    /**
     * Returns amount of a certain token that an address has currently not avaiable
     * (on a sale, auction, raffle, or loan)
     */
    function _getOwnerUnavailableAmount(uint256 itemId, address owner)
        private
        view
        returns (uint256)
    {
        uint256 totalPositionCount = _positionIds.current();
        uint256 numItems = 0;
        for (uint256 i = 0; i < totalPositionCount; i++) {
            if (
                _idToPosition[i + 1].itemId == itemId &&
                _idToPosition[i + 1].owner == owner &&
                _idToPosition[i + 1].state != PositionState.Available
            ) {
                numItems++;
            }
        }

        return numItems;
    }
}
