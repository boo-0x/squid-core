const { expect, assert } = require("chai");
const ReefAbi = require("./ReefToken.json");

describe("************ Marketplace ******************", () => {
    let market,
        nft,
        owner,
        seller,
        artist,
        buyer1,
        buyer2,
        marketFee,
        marketContractAddress,
        nftContractAddress,
        salePrice,
        ownerAddress,
        sellerAddress,
        artistAddress,
        buyer1Address,
        reefToken,
        token1Id,
        token2Id,
        item1Id,
        item2Id,
        position1Id,
        position2Id,
        royaltyValue,
        maxGasFee;

    before(async () => {
        // Deployed contract addresses (comment to deploy new contracts)
        marketContractAddress = config.contracts.market;
        nftContractAddress = config.contracts.nft;

        // Get accounts
        owner = await reef.getSignerByName("account1");
        seller = await reef.getSignerByName("account2");
        buyer1 = await reef.getSignerByName("account3");
        buyer2 = await reef.getSignerByName("account4");
        artist = await reef.getSignerByName("account5");
        helper = await reef.getSignerByName("account6");

        // Get accounts addresses
        ownerAddress = await owner.getAddress();
        sellerAddress = await seller.getAddress();
        buyer1Address = await buyer1.getAddress();
        buyer2Address = await buyer2.getAddress();
        artistAddress = await artist.getAddress();

        // Initialize and connect to Reef token
        const ReefToken = new ethers.Contract(config.contracts.reef, ReefAbi, owner);
        reefToken = ReefToken.connect(owner);

        // Initialize global variables
        marketFee = 250; // 2.5%
        maxGasFee = ethers.utils.parseUnits("10", "ether");
        salePrice = ethers.utils.parseUnits("50", "ether");
        royaltyValue = 1000; // 10%

        if (!marketContractAddress) {
            // Deploy SqwidMarketplace contract
            console.log("\tdeploying Market contract...");
            await getBalance(ownerAddress, "owner");
            const Market = await reef.getContractFactory("SqwidMarketplace", owner);
            market = await Market.deploy(marketFee);
            await market.deployed();
            marketContractAddress = market.address;
            await getBalance(ownerAddress, "owner");

            if (nftContractAddress) {
                const NFT = await reef.getContractFactory("SqwidERC1155", owner);
                nft = await NFT.attach(nftContractAddress);
                await nft.connect(owner).setMarketplaceAddress(marketContractAddress);
            }
        } else {
            // Get deployed contract
            const Market = await reef.getContractFactory("SqwidMarketplace", owner);
            market = await Market.attach(marketContractAddress);
        }
        console.log(`\tMarket contract deployed in ${marketContractAddress}`);

        if (!nftContractAddress) {
            // Deploy SqwidERC1155 contract
            console.log("\tdeploying NFT contract...");
            await getBalance(ownerAddress, "owner");
            const NFT = await reef.getContractFactory("SqwidERC1155", owner);
            const loanContractAddress = config.contracts.loan
                ? config.contracts.loan
                : "0x0000000000000000000000000000000000000000";
            nft = await NFT.deploy(marketContractAddress, loanContractAddress);
            await nft.deployed();
            nftContractAddress = nft.address;
            await getBalance(ownerAddress, "owner");
        } else if (!nft) {
            // Get deployed contract
            const NFT = await reef.getContractFactory("SqwidERC1155", owner);
            nft = await NFT.attach(nftContractAddress);
        }
        console.log(`\tNFT contact deployed ${nftContractAddress}`);
    });

    it("Should only allow change market fee to owner", async () => {
        await throwsException(
            market.connect(seller).setMarketFee(350),
            "Ownable: caller is not the owner"
        );

        await market.connect(owner).setMarketFee(350);
        let fetchedMarketFee = await market.connect(owner).getMarketFee();
        expect(Number(fetchedMarketFee)).to.equal(Number(350));

        await market.connect(owner).setMarketFee(250);
        fetchedMarketFee = await market.connect(owner).getMarketFee();
        expect(Number(fetchedMarketFee)).to.equal(Number(250));
    });

    it("Should create market item", async () => {
        // Create token
        console.log("\tcreating token...");
        const tx1 = await nft
            .connect(seller)
            .mint(sellerAddress, 1, "https://fake-uri-1.com", artistAddress, royaltyValue, true);
        const receipt1 = await tx1.wait();
        token1Id = receipt1.events[0].args[3].toNumber();
        console.log(`\tNFTs created with tokenId ${token1Id}`);

        // Create market item
        const tx2 = await market.connect(seller).createItem(nftContractAddress, token1Id);
        const receipt2 = await tx2.wait();
        item1Id = receipt2.events[0].args[0].toNumber();

        // Results
        const item = await market.fetchItem(item1Id);

        // Evaluate results
        expect(Number(item.itemId)).to.equal(item1Id);
        expect(item.nftContract).to.equal(nftContractAddress);
        expect(Number(item.tokenId)).to.equal(token1Id);
        expect(item.creator).to.equal(sellerAddress);
    });

    it("Should put existing market item on sale", async () => {
        // Puts item on sale
        console.log("\tputting market item on sale...");
        const tx1 = await market.connect(seller).putItemOnSale(item1Id, 1, salePrice);
        const receipt1 = await tx1.wait();
        position1Id = receipt1.events[1].args[0].toNumber();
        console.log(`\tPosition created with id ${position1Id}`);

        // Results
        const position = await market.fetchPosition(position1Id);
        const item = await market.fetchItem(item1Id);

        // Evaluate results
        expect(Number(position.positionId)).to.equal(position1Id);
        expect(Number(position.item.itemId)).to.equal(item1Id);
        expect(position.owner).to.equal(sellerAddress);
        expect(Number(position.amount)).to.equal(1);
        expect(Number(position.price)).to.equal(Number(salePrice));
        expect(Number(position.marketFee)).to.equal(Number(marketFee));
        expect(Number(position.state)).to.equal(1); // PositionState.RegularSale = 1
        expect(Number(item.positions[0].positionId)).to.equal(position1Id);
    });

    it("Should put new nft on sale", async () => {
        // Initial data
        const iniPositionsOnRegSale = await market.fetchAllOnRegularSale();

        // Create token
        console.log("\tcreating token...");
        const tx1 = await nft
            .connect(seller)
            .mint(sellerAddress, 10, "https://fake-uri-1.com", artistAddress, royaltyValue, true);
        const receipt1 = await tx1.wait();
        token2Id = receipt1.events[0].args[3].toNumber();
        console.log(`\tNFTs created with tokenId ${token2Id}`);

        // Creates market item and puts it on sale in the same call
        console.log("\tputting new market item on sale...");
        const tx2 = await market
            .connect(seller)
            .putNewItemOnSale(nftContractAddress, token2Id, 10, salePrice);
        const receipt2 = await tx2.wait();
        item2Id = receipt2.events[0].args[0].toNumber();
        console.log(`\tItem created with id ${item2Id}`);
        position2Id = receipt2.events[2].args[0].toNumber();
        console.log(`\tPosition created with id ${position2Id}`);

        // Results
        const position = await market.fetchPosition(position2Id);
        const item = await market.fetchItem(item2Id);
        const endPositionsOnRegSale = await market.fetchAllOnRegularSale();

        // Evaluate results
        expect(Number(position.positionId)).to.equal(position2Id);
        expect(Number(position.item.itemId)).to.equal(item2Id);
        expect(position.owner).to.equal(sellerAddress);
        expect(Number(position.amount)).to.equal(10);
        expect(Number(position.price)).to.equal(Number(salePrice));
        expect(Number(position.marketFee)).to.equal(Number(marketFee));
        expect(Number(position.state)).to.equal(1); // RegularSale = 1
        expect(Number(item.positions[0].positionId)).to.equal(position2Id);
        expect(endPositionsOnRegSale.length - iniPositionsOnRegSale.length).to.equal(1);
        expect(Number(endPositionsOnRegSale.at(-1).positionId)).to.equal(position2Id);
    });

    it("Should get address created items", async () => {
        // Get items created by seller
        console.log("\tgetting seller creations...");
        const items = await market.connect(seller).fetchMyItemsCreated();
        console.log("\tseller creations retrieved...");

        // Evaluate results
        expect(items[0].creator).to.equal(sellerAddress);
        expect(items[0].positions.length).to.equal(1);
    });

    it("Should create sale", async () => {
        // Initial data
        const iniSellerBalance = await getBalance(sellerAddress, "seller");
        const iniBuyer1Balance = await getBalance(buyer1Address, "buyer1");
        const iniArtistBalance = await getBalance(artistAddress, "artist");
        const iniOwnerBalance = await getBalance(ownerAddress, "marketOwner");
        const iniBuyer1TokenAmount = await nft.balanceOf(buyer1Address, token1Id);

        // Buy NFT
        console.log("\tbuyer1 buying NFT from seller...");
        await market.connect(buyer1).createSale(position1Id, 1, { value: salePrice });
        console.log("\tNFT bought");

        // Final data
        const endSellerBalance = await getBalance(sellerAddress, "seller");
        const endBuyer1Balance = await getBalance(buyer1Address, "buyer1");
        const endArtistBalance = await getBalance(artistAddress, "artist");
        const endOwnerBalance = await getBalance(ownerAddress, "marketOwner");
        const endBuyer1TokenAmount = await nft.balanceOf(buyer1Address, token1Id);
        const royaltiesAmount = (salePrice * royaltyValue) / 10000;
        const marketFeeAmount = ((salePrice - royaltiesAmount) * marketFee) / 10000;
        const item = await market.fetchItem(item1Id);

        // Evaluate results
        expect(endBuyer1TokenAmount - iniBuyer1TokenAmount).to.equal(1);
        expect(Math.round(endBuyer1Balance))
            .to.lte(Math.round(iniBuyer1Balance - formatBigNumber(salePrice)))
            .gt(
                Math.round(
                    iniBuyer1Balance - formatBigNumber(salePrice) - formatBigNumber(maxGasFee)
                )
            );
        expect(Math.round(endArtistBalance)).to.equal(
            Math.round(iniArtistBalance + formatBigNumber(royaltiesAmount))
        );
        expect(Math.round(endOwnerBalance)).to.equal(
            Math.round(iniOwnerBalance + formatBigNumber(marketFeeAmount))
        );
        expect(Math.round(endSellerBalance)).to.equal(
            Math.round(
                iniSellerBalance +
                    formatBigNumber(salePrice) -
                    formatBigNumber(royaltiesAmount) -
                    formatBigNumber(marketFeeAmount)
            )
        );

        expect(item.nftContract).to.equal(nftContractAddress);
        expect(Number(item.tokenId)).to.equal(token1Id);
        expect(item.sales[0].seller).to.equal(sellerAddress);
        expect(item.sales[0].buyer).to.equal(buyer1Address);
        expect(Number(item.sales[0].price)).to.equal(Number(salePrice));
    });

    it("Should allow to end sale only to seller", async () => {
        // Initial data
        const iniTokenBalance = await nft.balanceOf(sellerAddress, token2Id);
        const iniItem = await market.fetchItem(item2Id);
        const iniOnsale = iniItem.positions.filter((pos) => pos.state == 1).length;

        // End sale by buyer1
        console.log("\tbuyer1 ending sale...");
        await throwsException(
            market.connect(buyer1).unlistPositionOnSale(position2Id),
            "SqwidMarketplace: Only seller can unlist item."
        );

        // End sale by seller
        console.log("\tseller ending sale...");
        await market.connect(seller).unlistPositionOnSale(position2Id);
        console.log("\tsale ended.");

        // Final data
        const endTokenBalance = await nft.balanceOf(sellerAddress, token2Id);
        const endItem = await market.fetchItem(item2Id);
        const endOnsale = endItem.positions.filter((pos) => pos.state == 1).length;

        // Evaluate results
        expect(endTokenBalance - iniTokenBalance).to.equal(10);
        expect(iniOnsale - endOnsale).to.equal(1);
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
            await promise;
            assert(false);
        } catch (error) {
            expect(error.message).contains(message);
        }
    }

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
