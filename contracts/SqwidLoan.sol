// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "../@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "../@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "../@openzeppelin/contracts/utils/Counters.sol";
import "./interface/ISqwidMarketplace.sol";

contract SqwidLoan {
    enum LoanState {
        Open,
        Borrowed,
        Repayed,
        Liquidated,
        Removed
    }

    struct Loan {
        uint256 loanId;
        address borrower;
        uint256 itemId;
        address nftContract;
        uint256 tokenId;
        uint256 loanAmount;
        uint256 feeAmount;
        uint256 minutesDuration;
        address lender;
        uint256 repayByTimestamp;
        LoanState state;
    }

    using Counters for Counters.Counter;
    Counters.Counter private loanIds;
    address private marketplaceAddress;

    mapping(uint256 => Loan) private idToLoan;

    event LoanCreated(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 indexed itemId,
        address nftContract,
        uint256 tokenId,
        uint256 loanAmount,
        uint256 feeAmount,
        uint256 minutesDuration
    );

    event LoanFunded(
        uint256 indexed loanId,
        address indexed lender,
        uint256 repayByTimestamp
    );

    event LoanFinished(uint256 indexed loanId, LoanState state);

    constructor(address _marketplaceAddress) {
        marketplaceAddress = _marketplaceAddress;
    }

    /**
     * Borrower creates a loan proposal.
     */
    function create(
        uint256 _itemId,
        uint256 _loanAmount,
        uint256 _feeAmount,
        uint256 _minutesDuration
    ) public {
        require(
            _loanAmount >= 1 * (10**18),
            "SqwidLoan: Minimum loan amount is 1 REEF."
        );
        require(
            _feeAmount >= 1 * (10**18),
            "SqwidLoan: Minimum fee amount is 1 REEF."
        );
        require(
            _minutesDuration > 0 && _minutesDuration <= 2628000,
            "SqwidLoan: Minutes of duration must be between 1 and 2,628,000."
        ); // 2,628,000 min = 5 years

        ISqwidMarketplace.MarketItem memory marketItem = ISqwidMarketplace(
            marketplaceAddress
        ).fetchItem(_itemId);

        // Transfer ownership of the token to this contract
        IERC1155(marketItem.nftContract).safeTransferFrom(
            msg.sender,
            address(this),
            marketItem.tokenId,
            1,
            ""
        );

        // Map new Loan
        loanIds.increment();
        uint256 loanId = loanIds.current();
        idToLoan[loanId] = Loan(
            loanId,
            msg.sender,
            _itemId,
            marketItem.nftContract,
            marketItem.tokenId,
            _loanAmount,
            _feeAmount,
            _minutesDuration,
            address(0),
            0,
            LoanState.Open
        );

        // Update owner in market contract
        ISqwidMarketplace(marketplaceAddress).updateMarketItemOwner(
            _itemId,
            address(this)
        );

        emit LoanCreated(
            loanId,
            msg.sender,
            _itemId,
            marketItem.nftContract,
            marketItem.tokenId,
            _loanAmount,
            _feeAmount,
            _minutesDuration
        );
    }

    /**
     * Borrower unlists loan proposal, if it has not been funded/borrowed yet.
     */
    function unlist(uint256 _loanId) public {
        require(
            idToLoan[_loanId].state == LoanState.Open,
            "SqwidLoan: There is no loan open for funding with this id."
        );
        require(
            msg.sender == idToLoan[_loanId].borrower,
            "SqwidLoan: Only creator can unlist loan proposal."
        );

        // Update loan
        idToLoan[_loanId].state = LoanState.Removed;

        // Transfer NFT back to borrower
        IERC1155(idToLoan[_loanId].nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            idToLoan[_loanId].tokenId,
            1,
            ""
        );

        // Update owner in market contract
        ISqwidMarketplace(marketplaceAddress).updateMarketItemOwner(
            idToLoan[_loanId].itemId,
            msg.sender
        );
    }

    /**
     * Lender funds a loan proposal.
     */
    function fund(uint256 _loanId) public payable {
        require(
            idToLoan[_loanId].state == LoanState.Open,
            "SqwidLoan: There is no loan open for funding with this id."
        );
        require(
            msg.value == idToLoan[_loanId].loanAmount,
            "SqwidLoan: Value sent must be equal to loan amount."
        );

        // Update loan
        idToLoan[_loanId].lender = msg.sender;
        idToLoan[_loanId].repayByTimestamp =
            block.timestamp +
            idToLoan[_loanId].minutesDuration *
            1 minutes;
        idToLoan[_loanId].state = LoanState.Borrowed;

        // Transfer funds to borrower
        payable(idToLoan[_loanId].borrower).transfer(msg.value);

        emit LoanFunded(
            _loanId,
            msg.sender,
            idToLoan[_loanId].repayByTimestamp
        );
    }

    /**
     * Borrower repays loan.
     */
    function repay(uint256 _loanId) public payable {
        require(
            idToLoan[_loanId].state == LoanState.Borrowed,
            "SqwidLoan: There is no loan to be repay for this id."
        );
        require(
            msg.value >=
                idToLoan[_loanId].loanAmount + idToLoan[_loanId].feeAmount,
            "SqwidLoan: Value sent is less than loan amount plus fee."
        );

        // Update loan
        idToLoan[_loanId].state = LoanState.Repayed;

        // Transfer funds to lender
        payable(idToLoan[_loanId].lender).transfer(msg.value);

        // Transfer NFT back to borrower
        IERC1155(idToLoan[_loanId].nftContract).safeTransferFrom(
            address(this),
            idToLoan[_loanId].borrower,
            idToLoan[_loanId].tokenId,
            1,
            ""
        );

        // Update owner in market contract
        ISqwidMarketplace(marketplaceAddress).updateMarketItemOwner(
            idToLoan[_loanId].itemId,
            idToLoan[_loanId].borrower
        );

        emit LoanFinished(_loanId, LoanState.Repayed);
    }

    /**
     * Funder liquidates expired loan.
     */
    function liquidate(uint256 _loanId) public {
        require(
            idToLoan[_loanId].state == LoanState.Borrowed &&
                idToLoan[_loanId].repayByTimestamp < block.timestamp,
            "SqwidLoan: There is no loan to be liquidated for this id."
        );
        require(
            msg.sender == idToLoan[_loanId].lender,
            "SqwidLoan: Only lender can liquidate the loan."
        );

        // Update loan
        idToLoan[_loanId].state = LoanState.Liquidated;

        // Transfer NFT to lender
        IERC1155(idToLoan[_loanId].nftContract).safeTransferFrom(
            address(this),
            idToLoan[_loanId].lender,
            idToLoan[_loanId].tokenId,
            1,
            ""
        );

        // Update owner in market contract
        ISqwidMarketplace(marketplaceAddress).updateMarketItemOwner(
            idToLoan[_loanId].itemId,
            idToLoan[_loanId].lender
        );

        emit LoanFinished(_loanId, LoanState.Liquidated);
    }

    /**
     * Returns list of loans.
     */
    function fetchAll() public view returns (Loan[] memory) {
        // Initialize array
        Loan[] memory items = new Loan[](loanIds.current());

        // Fill array
        for (uint256 i = 0; i < loanIds.current(); i++) {
            items[i] = idToLoan[i + 1];
        }

        return items;
    }

    /**
     * Returns data of a loan.
     */
    function fetch(uint256 _loanId) public view returns (Loan memory) {
        return idToLoan[_loanId];
    }
}
