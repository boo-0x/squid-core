const { expect, assert } = require('chai');
const ReefAbi = require('./ReefToken.json');

describe('************ Marketplace ******************', ()  => {
  let market, nft, owner, seller, artist, buyer1, buyer2, marketFee, marketContractAddress, 
    nftContractAddress, salePrice, ownerAddress, sellerAddress, artistAddress, buyer1Address, 
    buyer2Address, reefToken, token1Id, token2Id, item1Id, royaltyValue, maxGasFee;

  before(async () => {
    // Deployed contract addresses (comment to deploy new contracts)
    marketContractAddress = config.contracts.market;
    nftContractAddress = config.contracts.nft;

    // Get accounts
    owner = await reef.getSignerByName('account1');
    seller = await reef.getSignerByName('account2');
    buyer1 = await reef.getSignerByName('account3');
    buyer2 = await reef.getSignerByName('account4');
    artist = await reef.getSignerByName('account5');
    helper = await reef.getSignerByName('account6');

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
    maxGasFee = ethers.utils.parseUnits('10', 'ether');
    salePrice = ethers.utils.parseUnits('50', 'ether');
    royaltyValue = 1000; // 10%
    
    if (!marketContractAddress) {
      // Deploy CoralMarketplace contract
      console.log('\tdeploying Market contract...');
      await getBalance(ownerAddress, 'owner');
      const Market = await reef.getContractFactory('CoralMarketplace', owner);
      market = await Market.deploy(marketFee);
      await market.deployed();
      marketContractAddress = market.address;
      await getBalance(ownerAddress, 'owner');
    } else {
      // Get deployed contract
      const Market = await reef.getContractFactory('CoralMarketplace', owner);
      market = await Market.attach(marketContractAddress);
    }
    console.log(`\tMarket contract deployed in ${marketContractAddress}`);
    
    if (!nftContractAddress) {
      // Deploy CoralNFT contract
      console.log('\tdeploying NFT contract...');
      await getBalance(ownerAddress, 'owner');
      const NFT = await reef.getContractFactory('CoralNFT', owner);
      const loanContractAddress = config.contracts.loan ? config.contracts.loan : '0x0000000000000000000000000000000000000000';
      nft = await NFT.deploy(marketContractAddress, loanContractAddress);
      await nft.deployed();
      nftContractAddress = nft.address;
      await getBalance(ownerAddress, 'owner');
    } else {
      // Get deployed contract
      const NFT = await reef.getContractFactory('CoralNFT', owner);
      nft = await NFT.attach(nftContractAddress);
    }
    console.log(`\tNFT contact deployed ${nftContractAddress}`);
  });


  it('Should get NFT contract data', async () => {
    const name = await nft.name();
    const interfaceIdErc2981 = '0x2a55205a';
    const supportsErc2981 = await nft.supportsInterface(interfaceIdErc2981);

    expect(name).to.equal('Coral NFT');
    expect(supportsErc2981).to.equal(true);
  });


  it('Should only allow change market fee to owner', async () => {
    await throwsException(market.connect(seller).setMarketFee(350),
      'Ownable: caller is not the owner'
    );
    
    await market.connect(owner).setMarketFee(350);
    let fetchedMarketFee = await market.connect(owner).getMarketFee();
    expect(Number(fetchedMarketFee)).to.equal(Number(350));

    await market.connect(owner).setMarketFee(250);
    fetchedMarketFee = await market.connect(owner).getMarketFee();
    expect(Number(fetchedMarketFee)).to.equal(Number(250));
  });


  it('Should put new NFT for sale', async () => {
    // Create NFTs
    console.log('\tseller creating NFTs...');
    await getBalance(sellerAddress, 'seller');

    const tx1 = await nft.connect(seller).createToken('https://fake-uri-1.com', 1, artistAddress, royaltyValue, false);
    const receipt1 = await tx1.wait();
    token1Id = receipt1.events[0].args[2].toNumber();

    const tx2 = await nft.connect(seller).createToken('https://fake-uri-2.com', 1, artistAddress, royaltyValue, false);
    const receipt2 = await tx2.wait();
    token2Id = receipt2.events[0].args[2].toNumber();

    console.log(`\tNFTs created with tokenIds ${token1Id} and ${token2Id}`);
    await getBalance(sellerAddress, 'seller');

    // Initial data
    const iniItems = await market.fetchItemsOnSale();
    const iniTokenOwner = await nft.ownerOf(token1Id);

    // Put NFT for sale
    console.log('\tseller creating NFT sale...');
    await getBalance(sellerAddress, 'seller');
    await market.connect(seller).putNewNftOnSale(nftContractAddress, token1Id, salePrice);
    console.log('\tNFT sale created');
    await getBalance(sellerAddress, 'seller');

    // Final data
    const items = await market.fetchItemsOnSale();
    console.log(items);
    const item1 = items[items.length - 1];
    console.log(item1)
    const item1Uri = await nft.tokenURI(item1.tokenId);
    const endTokenOwner = await nft.ownerOf(token1Id);
    item1Id = Number(item1.itemId);
      
    // Evaluate results
    expect(iniTokenOwner).to.equal(sellerAddress);
    expect(endTokenOwner).to.equal(marketContractAddress);
    expect(items.length).to.equal(iniItems.length + 1);
    expect(item1Uri).to.equal('https://fake-uri-1.com');
    expect(item1.nftContract).to.equal(nftContractAddress);
    expect(Number(item1.tokenId)).to.equal(token1Id);
    expect(item1.seller).to.equal(sellerAddress);
    expect(parseInt(item1.owner, 16)).to.equal(0);
    expect(item1.creator).to.equal(sellerAddress);
    expect(Number(item1.price)).to.equal(Number(salePrice));
    expect(Number(item1.marketFee)).to.equal(Number(marketFee));
    expect(item1.onSale).to.equal(true);
    expect(item1.typeItem).to.equal(0);
  });


  it('Should get created items', async () => {
    // Get items created by seller
    console.log('\tgetting seller creations...');
    const items = await market.connect(seller).fetchMyItemsCreated();
    console.log('\tseller creations retrieved...');

    // Evaluate results
    expect(items[0].creator).to.equal(sellerAddress);
  });


  it('Should create NFT sale', async () => {
    // Initial data
    const iniSellerBalance = await getBalance(sellerAddress, 'seller');
    const iniBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const iniArtistBalance = await getBalance(artistAddress, 'artist');
    const iniOwnerBalance = await getBalance(ownerAddress, 'marketOwner');
    const iniTokenOwner = await nft.ownerOf(token1Id);

    // Buy NFT
    console.log('\tbuyer1 buying NFT from seller...');
    await market.connect(buyer1).createMarketSale(item1Id, { value: salePrice });
    console.log('\tNFT bought');

    // Final data
    const endSellerBalance = await getBalance(sellerAddress, 'seller');
    const endBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const endArtistBalance = await getBalance(artistAddress, 'artist');
    const endOwnerBalance = await getBalance(ownerAddress, 'marketOwner');
    const endTokenOwner = await nft.ownerOf(token1Id);
    const royaltiesAmount = salePrice * royaltyValue / 10000;
    const marketFeeAmount = (salePrice - royaltiesAmount) * marketFee / 10000;
    const item = await market.fetchItem(item1Id);

    // Evaluate results
    expect(iniTokenOwner).to.equal(marketContractAddress);
    expect(endTokenOwner).to.equal(buyer1Address);
    expect(Math.round(endBuyer1Balance)).to.lte(Math.round(iniBuyer1Balance - formatBigNumber(salePrice)))
      .gt(Math.round(iniBuyer1Balance - formatBigNumber(salePrice) - formatBigNumber(maxGasFee)));
    expect(Math.round(endArtistBalance)).to.equal(Math.round(iniArtistBalance + formatBigNumber(royaltiesAmount)));
    expect(Math.round(endOwnerBalance)).to.equal(Math.round(iniOwnerBalance + formatBigNumber(marketFeeAmount)));
    expect(Math.round(endSellerBalance)).to.equal(Math.round(iniSellerBalance + formatBigNumber(salePrice) 
      - formatBigNumber(royaltiesAmount) - formatBigNumber(marketFeeAmount)));
    
    expect(item.nftContract).to.equal(nftContractAddress);
    expect(Number(item.tokenId)).to.equal(token1Id);
    expect(item.sales[0].seller).to.equal(sellerAddress);
    expect(item.sales[0].buyer).to.equal(buyer1Address);
    expect(Number(item.sales[0].price)).to.equal(Number(salePrice));
  });


  it('Should put NFT for sale again and create new sale', async () => {
    // Initial data
    const iniTokenOwner = await nft.ownerOf(token1Id);
    const newSalePrice = ethers.utils.parseUnits('30', 'ether'); // 30 REEF
    
    // Check if market contract is approved by this account (setApprovalForAll links an address
    // to operate on behalf of a certain owner, if the ownership changes, the approval does not
    // work for the new owner)
    const marketApproved = await nft.isApprovedForAll(buyer1Address, marketContractAddress);
    if (!marketApproved) {
      // Approve market contract for this address
      console.log('\tcreating approval for market contract...');
      await nft.connect(buyer1).setApprovalForAll(marketContractAddress, true);
      console.log('\tapproval created');
    }

    // Put market item on sale
    console.log('\tbuyer1 putting NFT on sale...');
    await market.connect(buyer1).putMarketItemOnSale(item1Id, newSalePrice);
    console.log('\tNFT sale created');

    // Initial data
    const iniSellerBalance = await getBalance(sellerAddress, 'seller');
    const iniBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const iniBuyer2Balance = await getBalance(buyer2Address, 'buyer2');
    const iniArtistBalance = await getBalance(artistAddress, 'artist');
    const iniOwnerBalance = await getBalance(ownerAddress, 'marketOwner');

    // Buy NFT
    console.log('\tbuyer2 buying NFT from buyer1...');
    await market.connect(buyer2).createMarketSale(item1Id, { value: newSalePrice });
    console.log('\tNFT bought');

    // Final data
    const endSellerBalance = await getBalance(sellerAddress, 'seller');
    const endBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const endBuyer2Balance = await getBalance(buyer2Address, 'buyer2');
    const endArtistBalance = await getBalance(artistAddress, 'artist');
    const endOwnerBalance = await getBalance(ownerAddress, 'marketOwner');
    const endTokenOwner = await nft.ownerOf(token1Id);
    const royaltiesAmount = newSalePrice * royaltyValue / 10000;
    const marketFeeAmount = (newSalePrice - royaltiesAmount) * marketFee / 10000;
    const item = await market.fetchItem(item1Id);

    // Evaluate results
    expect(iniTokenOwner).to.equal(buyer1Address);
    expect(endTokenOwner).to.equal(buyer2Address);
    expect(iniSellerBalance).to.equal(endSellerBalance);
    expect(Math.round(endBuyer2Balance)).to.lte(Math.round(iniBuyer2Balance - formatBigNumber(newSalePrice)))
      .gt(Math.round(iniBuyer2Balance - formatBigNumber(newSalePrice) - formatBigNumber(maxGasFee)));
    expect(Math.round(endArtistBalance)).to.equal(Math.round(iniArtistBalance + formatBigNumber(royaltiesAmount)));
    expect(Math.round(endOwnerBalance)).to.equal(Math.round(iniOwnerBalance + formatBigNumber(marketFeeAmount)));
    expect(Math.round(endBuyer1Balance)).to.equal(Math.round(iniBuyer1Balance + formatBigNumber(newSalePrice) 
      - formatBigNumber(royaltiesAmount) - formatBigNumber(marketFeeAmount)));
    expect(item.nftContract).to.equal(nftContractAddress);
    expect(Number(item.tokenId)).to.equal(token1Id);
    expect(item.creator).to.equal(sellerAddress);
    expect(item.sales[1].seller).to.equal(buyer1Address);
    expect(item.sales[1].buyer).to.equal(buyer2Address);
    expect(Number(item.sales[1].price)).to.equal(Number(newSalePrice));
    expect(item.onSale).to.equal(false);
  });

  
  it('Should allow to end sale only to seller', async () => {    
    // Create new market item
    console.log('\tseller creating new market item...');
    const tx = await market.connect(seller).createMarketItem(nftContractAddress, token2Id);
    const receipt = await tx.wait();
    const item2Id = receipt.events[0].args[0];
    console.log(`\tmarket item created with itemId ${item2Id}.`);

    // Put market item on sale
    console.log('\tseller putting NFT on sale...');
    await market.connect(seller).putMarketItemOnSale(item2Id, salePrice);
    console.log('\tNFT sale created');

    // Initial data
    const iniTokenOwner = await nft.ownerOf(token2Id);
    const iniItem = await market.fetchItem(item2Id);

    // End sale by buyer1
    console.log('\tbuyer1 ending sale...');
    await throwsException(market.connect(buyer1).unlistMarketItem(item2Id), 
      'CoralMarketplace: Only seller can unlist item.');

    // End sale by seller
    console.log('\tseller ending sale...');
    await market.connect(seller).unlistMarketItem(item2Id);
    console.log('\tsale ended.');

    // Final data
    const endTokenOwner = await nft.ownerOf(token2Id);
    const endItem = await market.fetchItem(item2Id);

    // Evaluate results
    expect(iniTokenOwner).to.equal(marketContractAddress);
    expect(endTokenOwner).to.equal(sellerAddress);
    expect(iniItem.onSale).to.equal(true);
    expect(endItem.onSale).to.equal(false);
  });


  async function getBalance(address, name) {
    const balance = await reefToken.balanceOf(address);
    const balanceFormatted = formatBigNumber(balance);
    console.log(`\t\tBalance of ${name}:`, balanceFormatted);
  
    return balanceFormatted;
  }
  
  function formatBigNumber(bigNumber) {
    return Number(Number(ethers.utils.formatUnits(bigNumber.toString(), 'ether')).toFixed(2));
  }

  async function throwsException(promise, message) {
    try {
      await promise;
      assert(false);
    } catch (error) {
      expect(error.message).contains(message);
    }
  };

});
