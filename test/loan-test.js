const { expect, assert } = require("chai");
const ReefAbi = require("./ReefToken.json");

describe("************ Loans ******************", () => {
    let market,
        marketContractAddress,
        loanContract,
        loanContractAddress,
        nft,
        nftContractAddress,
        owner,
        borrower,
        lender,
        loanAmount,
        feeAmount,
        loanDuration,
        ownerAddress,
        borrowerAddress,
        lenderAddress,
        reefToken,
        token1Id,
        token2Id,
        loan1Id,
        loan2Id,
        royaltyValue,
        maxGasFee,
        deadline,
        item1Id,
        item2Id;

    before(async () => {
        // Deployed contract addresses (comment to deploy new contracts)
        marketContractAddress = config.contracts.market;
        loanContractAddress = config.contracts.loan;
        nftContractAddress = config.contracts.nft;

        // Get accounts
        owner = await reef.getSignerByName("account1");
        borrower = await reef.getSignerByName("account3");
        lender = await reef.getSignerByName("account2");

        // Get accounts addresses
        ownerAddress = await owner.getAddress();
        borrowerAddress = await borrower.getAddress();
        lenderAddress = await lender.getAddress();

        // Initialize and connect to Reef token
        const ReefToken = new ethers.Contract(config.contracts.reef, ReefAbi, owner);
        reefToken = ReefToken.connect(owner);

        // Initialize global variables
        maxGasFee = ethers.utils.parseUnits("10", "ether");
        loanAmount = ethers.utils.parseUnits("300", "ether");
        feeAmount = ethers.utils.parseUnits("30", "ether");
        loanDuration = 1; // For testing, in the Loan contract days have been changed by minutes
        royaltyValue = 1000; // 10%

        if (!marketContractAddress) {
            // Deploy CoralMarketplace contract
            console.log("\tdeploying Market contract...");
            await getBalance(ownerAddress, "owner");
            const Market = await reef.getContractFactory("CoralMarketplace", owner);
            market = await Market.deploy(250);
            await market.deployed();
            marketContractAddress = market.address;
            await getBalance(ownerAddress, "owner");
        } else {
            // Get deployed contract
            const Market = await reef.getContractFactory("CoralMarketplace", owner);
            market = await Market.attach(marketContractAddress);
        }
        console.log(`\tMarket contract deployed in ${marketContractAddress}`);

        if (!loanContractAddress) {
            // Deploy Loan contract
            console.log("\tdeploying Loan contract...");
            await getBalance(ownerAddress, "owner");
            const Loan = await reef.getContractFactory("CoralLoan", owner);
            loanContract = await Loan.deploy(marketContractAddress);
            await loanContract.deployed();
            loanContractAddress = loanContract.address;
            // Set loan contract address in CoralMarketplace
            console.log("\tsetting Loan contract address in Marketplace contract...");
            await market.connect(owner).setLoanAddress(loanContractAddress);
            await getBalance(ownerAddress, "owner");
        } else {
            // Get deployed contract
            const Loan = await reef.getContractFactory("CoralLoan", owner);
            loanContract = await Loan.attach(loanContractAddress);
        }
        console.log(`\tLoan contact deployed ${loanContractAddress}`);

        if (!nftContractAddress) {
            // Deploy CoralNFT contract
            console.log("\tdeploying NFT contract...");
            await getBalance(ownerAddress, "owner");
            const NFT = await reef.getContractFactory("CoralNFT", owner);
            nft = await NFT.deploy(marketContractAddress, loanContractAddress);
            await nft.deployed();
            nftContractAddress = nft.address;
            await getBalance(ownerAddress, "owner");
        } else {
            // Get deployed contract
            const NFT = await reef.getContractFactory("CoralNFT", owner);
            nft = await NFT.attach(nftContractAddress);
        }
        console.log(`\tNFT contact deployed ${nftContractAddress}`);

        // Create NFTs
        await getBalance(borrowerAddress, "borrower");
        console.log("\tborrower creating NFTs...");

        const tx1 = await nft
            .connect(borrower)
            .createToken("https://fake-uri-1.com", 1, borrowerAddress, royaltyValue, false);
        const receipt1 = await tx1.wait();
        token1Id = receipt1.events[0].args[2].toNumber();

        const tx2 = await nft
            .connect(borrower)
            .createToken("https://fake-uri-2.com", 1, borrowerAddress, royaltyValue, false);
        const receipt2 = await tx2.wait();
        token2Id = receipt2.events[0].args[2].toNumber();

        console.log(`\tNFTs created with tokenIds ${token1Id} and ${token2Id}`);

        // Create market items
        console.log("\tborrower creating market items...");

        const tx3 = await market.connect(borrower).createMarketItem(nftContractAddress, token1Id);
        const receipt3 = await tx3.wait();
        item1Id = receipt3.events[0].args[0].toNumber();

        const tx4 = await market.connect(borrower).createMarketItem(nftContractAddress, token2Id);
        const receipt4 = await tx4.wait();
        item2Id = receipt4.events[0].args[0].toNumber();

        console.log(`\tmarket items created with itemIds ${item1Id} and ${item2Id}`);

        await getBalance(borrowerAddress, "borrower");
    });

    it("Should create loan proposal", async () => {
        // Initial data
        const iniLoans = await loanContract.fetchAll();
        const iniTokenOwner = await nft.ownerOf(token1Id);
        const iniMarketItem = await market.fetchItem(item1Id);
        const iniMarketitemOwner = iniMarketItem.owner;

        // Check if Loan contract is approved by this account (setApprovalForAll links an address
        // to operate on behalf of a certain owner, if the ownership changes, the approval does not
        // work for the new owner)
        const loanApproved = await nft
            .connect(borrower)
            .isApprovedForAll(borrowerAddress, loanContractAddress);
        if (!loanApproved) {
            // Approve Loan contract for this address
            console.log("\tcreating approval for Loan contract...");
            await nft.connect(borrower).setApprovalForAll(loanContractAddress, true);
            console.log("\tapproval created");
        }

        // Create loan proposal
        console.log("\tborrower creating loan proposal...");
        await getBalance(borrowerAddress, "borrower");
        await loanContract.connect(borrower).create(item1Id, loanAmount, feeAmount, loanDuration);
        console.log("\tloan proposal created");
        await getBalance(borrowerAddress, "borrower");

        // Final data
        const loans = await loanContract.fetchAll();
        const loan = loans[loans.length - 1];
        loan1Id = Number(loan.loanId);
        const endTokenOwner = await nft.ownerOf(token1Id);
        const endMarketItem = await market.fetchItem(item1Id);
        const endMarketitemOwner = endMarketItem.owner;

        // Evaluate results
        expect(iniTokenOwner).to.equal(borrowerAddress);
        expect(endTokenOwner).to.equal(loanContractAddress);
        expect(iniMarketitemOwner).to.equal(borrowerAddress);
        expect(endMarketitemOwner).to.equal(loanContractAddress);
        expect(loans.length).to.equal(iniLoans.length + 1);
        expect(loan.borrower).to.equal(borrowerAddress);
        expect(loan.nftContract).to.equal(nftContractAddress);
        expect(Number(loan.tokenId)).to.equal(token1Id);
        expect(Number(loan.loanAmount)).to.equal(Number(loanAmount));
        expect(Number(loan.feeAmount)).to.equal(Number(feeAmount));
        expect(Number(loan.minutesDuration)).to.equal(loanDuration);
        expect(parseInt(loan.lender, 16)).to.equal(0);
        expect(Number(loan.repayByTimestamp)).to.equal(0);
        expect(loan.state).to.equal(0);
    });

    it("Should only allow to unlist loan to creator", async () => {
        console.log(`\tlender unlisting loan proposal ${loan1Id}...`);
        await throwsException(
            loanContract.connect(lender).unlist(loan1Id),
            "CoralLoan: Only creator can unlist loan proposal"
        );

        console.log("\tborrower unlisting loan proposal...");
        await loanContract.connect(borrower).unlist(loan1Id);
        console.log("\tLoan proposal unlisted.");

        const loan = await loanContract.fetch(loan1Id);
        expect(loan.state).to.equal(4);
        expect(await nft.ownerOf(token1Id)).to.equal(borrowerAddress);
    });

    it("Should fund loan", async () => {
        // Create loan proposal
        console.log("\tborrower creating loan proposal...");
        await getBalance(borrowerAddress, "borrower");
        await loanContract.connect(borrower).create(item1Id, loanAmount, feeAmount, loanDuration);
        console.log("\tloan proposal created");
        await getBalance(borrowerAddress, "borrower");
        const iniLoans = await loanContract.fetchAll();
        const iniLoan = iniLoans[iniLoans.length - 1];
        loan2Id = Number(iniLoan.loanId);

        // Initial data
        const iniLenderBalance = await getBalance(lenderAddress, "lender");
        const iniBorrowerBalance = await getBalance(borrowerAddress, "borrower");

        // Fund proposal
        console.log("\tlender funding loan...");
        await loanContract.connect(lender).fund(loan2Id, { value: loanAmount });
        console.log("\tloan proposal created");

        // Final data
        const loan = await loanContract.fetch(loan2Id);
        const endLenderBalance = await getBalance(lenderAddress, "lender");
        const endBorrowerBalance = await getBalance(borrowerAddress, "borrower");
        deadline = new Date(loan.repayByTimestamp * 1000);

        // Evaluate results
        expect(Math.round(endBorrowerBalance)).to.equals(
            Math.round(iniBorrowerBalance + formatBigNumber(loanAmount))
        );
        expect(endLenderBalance)
            .to.lte(iniLenderBalance - formatBigNumber(loanAmount))
            .gt(iniLenderBalance - formatBigNumber(loanAmount) - formatBigNumber(maxGasFee));
        expect(loan.lender).to.equal(lenderAddress);
        expect(loan.state).to.equal(1);
        expect(deadline)
            .to.lt(new Date(new Date().getTime() + 90000))
            .to.gt(new Date(new Date().getTime() + 30000)); // +/- 30 secs. margin for timestamp calculation
    });

    it("Should not allow to unlist funded loan", async () => {
        await throwsException(
            loanContract.connect(borrower).unlist(loan2Id),
            "CoralLoan: There is no loan open for funding with this id"
        );
    });

    it("Should not liquidate loan before deadline", async () => {
        console.log("\tliquidating loan...");
        await throwsException(
            loanContract.connect(lender).liquidate(loan2Id),
            "CoralLoan: There is no loan to be liquidated for this id."
        );
    });

    it("Should liquidate loan", async () => {
        // Initial data
        const iniLenderBalance = await getBalance(lenderAddress, "lender");
        const iniBorrowerBalance = await getBalance(borrowerAddress, "borrower");
        const iniTokenOwner = await nft.ownerOf(token1Id);
        const iniMarketItem = await market.fetchItem(item1Id);
        const iniMarketitemOwner = iniMarketItem.owner;

        // Wait until deadline
        const timeUntilDeadline = deadline - new Date();
        console.log(`\ttime until deadline: ${timeUntilDeadline / 1000} secs.`);
        if (timeUntilDeadline > 0) {
            console.log("\twaiting for deadline...");
            await delay(timeUntilDeadline + 15000);
            console.log("\tdeadline reached.");
        }

        // Liquidate loan
        console.log("\tliquidating loan...");
        await loanContract.connect(lender).liquidate(loan2Id);
        console.log("\tloan liquidated...");

        // Final data
        const endLenderBalance = await getBalance(lenderAddress, "lender");
        const endBorrowerBalance = await getBalance(borrowerAddress, "borrower");
        const endTokenOwner = await nft.ownerOf(token1Id);
        const endMarketItem = await market.fetchItem(item1Id);
        const endMarketitemOwner = endMarketItem.owner;
        const endLoan = await loanContract.fetch(loan2Id);

        // Evaluate results
        expect(endBorrowerBalance).to.equals(iniBorrowerBalance);
        expect(endLenderBalance)
            .to.lte(iniLenderBalance)
            .gt(iniLenderBalance - formatBigNumber(maxGasFee));
        expect(iniTokenOwner).to.equal(loanContractAddress);
        expect(endTokenOwner).to.equal(lenderAddress);
        expect(iniMarketitemOwner).to.equal(loanContractAddress);
        expect(endMarketitemOwner).to.equal(lenderAddress);
        expect(endLoan.state).to.equal(3);
    });

    it("Should not repay loan if value sent is not enough", async () => {
        // Create loan proposal
        console.log("\tborrower creating loan proposal...");
        await loanContract.connect(borrower).create(item2Id, loanAmount, feeAmount, loanDuration);
        console.log("\tloan proposal created.");
        const loans = await loanContract.fetchAll();
        loan2Id = Number(loans[loans.length - 1].loanId);

        // Fund proposal
        console.log("\tlender funding loan...");
        await loanContract.connect(lender).fund(loan2Id, { value: loanAmount });
        console.log("\tloan funded.");

        // Repay loan
        console.log("\tborrower repaying loan...");
        await throwsException(
            loanContract.connect(borrower).repay(loan2Id, { value: loanAmount }),
            "CoralLoan: Value sent is less than loan amount plus fee."
        );
    });

    it("Should repay loan", async () => {
        // Initial data
        const iniTokenOwner = await nft.ownerOf(token2Id);
        const iniMarketItem = await market.fetchItem(item2Id);
        const iniMarketitemOwner = iniMarketItem.owner;
        const iniLenderBalance = await getBalance(lenderAddress, "lender");
        const iniBorrowerBalance = await getBalance(borrowerAddress, "borrower");

        // Repay loan
        console.log("\tborrower repaying loan...");
        await loanContract.connect(borrower).repay(loan2Id, { value: loanAmount.add(feeAmount) });
        console.log("\tloan repayed.");

        // Final data
        const loan = await loanContract.fetch(loan2Id);
        const endTokenOwner = await nft.ownerOf(token2Id);
        const endMarketItem = await market.fetchItem(item2Id);
        const endMarketitemOwner = endMarketItem.owner;
        const endLenderBalance = await getBalance(lenderAddress, "lender");
        const endBorrowerBalance = await getBalance(borrowerAddress, "borrower");

        // Evaluate results
        expect(Math.round(endLenderBalance)).to.equals(
            Math.round(iniLenderBalance + formatBigNumber(loanAmount)) + formatBigNumber(feeAmount)
        );
        expect(endBorrowerBalance)
            .to.lte(iniBorrowerBalance - formatBigNumber(loanAmount) - formatBigNumber(feeAmount))
            .gt(
                iniBorrowerBalance -
                    formatBigNumber(loanAmount) -
                    formatBigNumber(feeAmount) -
                    formatBigNumber(maxGasFee)
            );
        expect(iniTokenOwner).to.equal(loanContractAddress);
        expect(endTokenOwner).to.equal(borrowerAddress);
        expect(iniMarketitemOwner).to.equal(loanContractAddress);
        expect(endMarketitemOwner).to.equal(borrowerAddress);
        expect(loan.state).to.equal(2);
    });

    async function getBalance(address, name) {
        const balance = await reefToken.balanceOf(address);
        const balanceFormatted = formatBigNumber(balance);
        console.log(`\t\tBalance of ${name}:`, balanceFormatted);

        return balanceFormatted;
    }

    function formatBigNumber(bigNumber) {
        return Number(Number(ethers.utils.formatUnits(bigNumber.toString(), "ether")).toFixed(4));
    }

    async function throwsException(promise, message) {
        try {
            const tx = await promise;
            const receipt = await tx.wait();
            console.log("Promise did NOT throw exception!");
            console.log("event", receipt.events[0].args);
            assert(false);
        } catch (error) {
            console.log(error.message);
            expect(error.message).contains(message);
        }
    }

    const delay = (ms) => new Promise((res) => setTimeout(res, ms));

    async function logEvents(promise) {
        const tx = await promise;
        const receipt = await tx.wait();

        let msg = "No events for this tx";
        if (receipt.events) {
            const eventsArgs = [];
            receipt.events.forEach((event) => {
                if (event.args) {
                    eventsArgs.push(event.args);
                }
            });
            msg = eventsArgs;
        }
        console.log(msg);
    }
});
