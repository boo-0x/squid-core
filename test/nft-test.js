const { expect, assert } = require("chai");

describe("************ NFT ******************", () => {
    let nft,
        nftContractAddress,
        contractOwner,
        artist,
        creator,
        token1Id,
        token2Id,
        token3Id,
        royaltyValue,
        newTokenURI,
        salePrice,
        creatorAddress,
        artistAddress;

    before(async () => {
        // Deployed contract address (comment to deploy new contract)
        nftContractAddress = config.contracts.nft;

        // Get accounts
        contractOwner = await reef.getSignerByName("account1");
        creator = await reef.getSignerByName("account2");
        artist = await reef.getSignerByName("account3");
        recipient = await reef.getSignerByName("account4");

        // Get accounts addresses
        creatorAddress = await creator.getAddress();
        artistAddress = await artist.getAddress();
        recipientAddress = await recipient.getAddress();

        // Initialize global variables
        newTokenURI = "https://fake-uri-xyz.com";
        salePrice = ethers.utils.parseUnits("50", "ether");
        royaltyValue = 1000; // 10%

        if (!nftContractAddress) {
            // Deploy SqwidERC1155 contract
            console.log("\tdeploying NFT contract...");
            const NFT = await reef.getContractFactory("SqwidERC1155", contractOwner);
            nft = await NFT.deploy("0x0000000000000000000000000000000000000000");
            await nft.deployed();
            nftContractAddress = nft.address;
        } else {
            // Get deployed contract
            const NFT = await reef.getContractFactory("SqwidERC1155", contractOwner);
            nft = await NFT.attach(nftContractAddress);
        }
        console.log(`\tNFT contact deployed ${nftContractAddress}`);
    });

    it("Should get NFT contract data", async () => {
        const interfaceIdErc2981 = "0x2a55205a";
        const supportsErc2981 = await nft.supportsInterface(interfaceIdErc2981);

        expect(supportsErc2981).to.equal(true);
    });

    it("Should create tokens", async () => {
        // Create tokens
        console.log("\tcreating tokens...");

        const tx1 = await nft
            .connect(creator)
            .mint(creatorAddress, 1, "https://fake-uri-1.com", artistAddress, royaltyValue, true);
        const receipt1 = await tx1.wait();
        token1Id = receipt1.events[0].args[3].toNumber();

        const tx2 = await nft
            .connect(creator)
            .mint(creatorAddress, 99, "https://fake-uri-2.com", artistAddress, royaltyValue, false);
        const receipt2 = await tx2.wait();
        token2Id = receipt2.events[0].args[3].toNumber();

        const tx3 = await nft
            .connect(creator)
            .mint(creatorAddress, 10, "https://fake-uri-3.com", artistAddress, royaltyValue, false);
        const receipt3 = await tx3.wait();
        token3Id = receipt3.events[0].args[3].toNumber();

        console.log(`\tNFTs created with tokenIds ${token1Id}, ${token2Id} and ${token3Id}`);

        // End data
        const royaltyInfo = await nft.royaltyInfo(token1Id, salePrice);

        // Evaluate results
        expect(royaltyInfo.receiver).to.equal(artistAddress);
        expect(Number(royaltyInfo.royaltyAmount)).to.equal((salePrice * royaltyValue) / 10000);
        expect(Number(await nft.balanceOf(creatorAddress, token1Id))).to.equal(1);
        expect(Number(await nft.balanceOf(creatorAddress, token2Id))).to.equal(99);
        expect(await nft.hasMutableURI(token1Id)).to.equal(true);
        expect(await nft.hasMutableURI(token2Id)).to.equal(false);
        expect(await nft.uri(token1Id)).to.equal("https://fake-uri-1.com");
    });

    it("Should transfer single token", async () => {
        // Transfer token
        console.log("\ttransfering token...");
        await nft
            .connect(creator)
            .safeTransferFrom(creatorAddress, recipientAddress, token1Id, 1, []);
        console.log("\tToken transfered");

        expect(Number(await nft.balanceOf(creatorAddress, token1Id))).to.equal(0);
        expect(Number(await nft.balanceOf(recipientAddress, token1Id))).to.equal(1);
    });

    it("Should transfer multiple tokens", async () => {
        // Transfer token
        console.log("\ttransfering tokens...");
        await nft
            .connect(creator)
            .safeBatchTransferFrom(
                creatorAddress,
                recipientAddress,
                [token2Id, token3Id],
                [9, 3],
                []
            );
        console.log("\tTokens transfered");

        [
            creatorT2Amount,
            recipientT2Amount,
            creatorT3Amount,
            recipientT3Amount,
        ] = await nft.balanceOfBatch(
            [creatorAddress, recipientAddress, creatorAddress, recipientAddress],
            [token2Id, token2Id, token3Id, token3Id]
        );

        expect(Number(creatorT2Amount)).to.equal(90);
        expect(Number(recipientT2Amount)).to.equal(9);
        expect(Number(creatorT3Amount)).to.equal(7);
        expect(Number(recipientT3Amount)).to.equal(3);
    });

    // TODO
    it.skip("Should not change tokenURI if caller is not owner of total token supply", async () => {
        // Change tokenURI
        console.log("\tcontract owner changing tokenURI...");
        await throwsException(
            nft.connect(contractOwner).setTokenUri(token1Id, newTokenURI),
            "SqwidERC1155: Only token owner can set tokenURI."
        );
    });

    // TODO
    it.skip("Should not change tokenURI if token is not mutable", async () => {
        // Change tokenURI
        console.log("\tcontract owner changing tokenURI...");
        await throwsException(
            nft.connect(contractOwner).setTokenUri(token1Id, newTokenURI),
            "SqwidERC1155: Only token owner can set tokenURI."
        );
    });

    // TODO
    it.skip("Should not change tokenURI if sender is not owner of total supply", async () => {
        // Change tokenURI
        console.log("\tcontract owner changing tokenURI...");
        await throwsException(
            nft.connect(contractOwner).setTokenUri(token1Id, newTokenURI),
            "SqwidERC1155: Only the owner of the total supply can set token URI."
        );
    });

    // TODO
    it.skip("Should change tokenURI", async () => {
        // Initial data
        const iniTokenURI = await nft.uri(token2Id);

        // Change tokenURI
        console.log("\tcreator changing tokenURI...");
        await nft.connect(creator).setTokenUri(token2Id, newTokenURI);
        console.log("\ttokenURI changed.");

        // Final data
        const endTokenURI = await nft.uri(token2Id);

        expect(endTokenURI).to.not.equal(iniTokenURI);
        expect(endTokenURI).to.equal(newTokenURI);
    });

    // TODO
    it.skip("Should not change tokenURI if caller is not owner of total token supply", async () => {
        // Change tokenURI
        console.log("\tcontract owner changing tokenURI...");
        await throwsException(
            nft.connect(contractOwner).setTokenUri(token1Id, newTokenURI),
            "SqwidERC1155: Only token owner can set tokenURI."
        );
    });

    // TODO
    // burn
    // burnBatch
    // getOwners
    // getTokenSupply
    // getTokensByOwner

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
