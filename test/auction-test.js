const { expect, assert } = require('chai');
const ReefAbi = require('./ReefToken.json');

describe('************ Auctions ******************', ()  => {
  let market, nft, owner, seller, artist, buyer1, buyer2, marketFee, marketContractAddress, nftContractAddress,
    ownerAddress, sellerAddress, artistAddress, buyer1Address, buyer2Address, reefToken, deadline, tokenId, itemId, 
    royaltyValue, maxGasFee, numMinutes, minBid, bid1Amount, bid2Amount, bid3Amount, bid4Amount;

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
    numMinutes = 11;
    minBid = ethers.utils.parseUnits('50', 'ether');
    bid1Amount = ethers.utils.parseUnits('49', 'ether');
    bid2Amount = ethers.utils.parseUnits('60', 'ether');
    bid3Amount = ethers.utils.parseUnits('1', 'ether');
    bid4Amount = ethers.utils.parseUnits('62', 'ether');
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
      nft = await NFT.deploy(marketContractAddress, '0x0000000000000000000000000000000000000000');
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


  it('Should create auction', async () => {
    // Create NFT
    console.log('\tseller creating NFTs...');
    await getBalance(sellerAddress, 'seller');
    const tx = await nft.connect(seller).createToken('https://fake-uri.com', 1, artistAddress, royaltyValue, false);
    const receipt = await tx.wait();
    tokenId = receipt.events[0].args[2].toNumber();
    console.log(`\tNFT created with tokenId ${tokenId}`);
    await getBalance(sellerAddress, 'seller');

    // Initial data
    const iniItems = await market.fetchAuctions();
    const iniTokenOwner = await nft.ownerOf(tokenId);

    // Create auction
    console.log('\tseller creating auction...');
    await getBalance(sellerAddress, 'seller');
    await market.connect(seller).createNewNftAuction(nftContractAddress, tokenId, numMinutes, minBid);
    console.log('\tauction created.');
    await getBalance(sellerAddress, 'seller');

    // Final data
    const items = await market.fetchAuctions();
    const item = items[items.length - 1];
    const itemUri = await nft.tokenURI(item.tokenId);
    const endTokenOwner = await nft.ownerOf(tokenId);
    itemId = Number(item.itemId);
    const auctionData = await market.fetchAuctionData(itemId);
    deadline = new Date(auctionData.deadline * 1000);

    // Evaluate results
    expect(iniTokenOwner).to.equal(sellerAddress);
    expect(endTokenOwner).to.equal(marketContractAddress);
    expect(items.length).to.equal(iniItems.length + 1);
    expect(itemUri).to.equal('https://fake-uri.com');
    expect(item.nftContract).to.equal(nftContractAddress);
    expect(Number(item.tokenId)).to.equal(tokenId);
    expect(item.seller).to.equal(sellerAddress);
    expect(parseInt(item.owner, 16)).to.equal(0);
    expect(item.creator).to.equal(sellerAddress);
    expect(Number(item.marketFee)).to.equal(Number(marketFee));
    expect(item.onSale).to.equal(true);
    expect(item.typeItem).to.equal(1);
    expect(deadline).to.lt(new Date(new Date().getTime() + (1000 * 60 * 11))).gt(new Date());
    expect(Number(auctionData.minBid)).equals(Number(minBid));
  });


  it('Should not allow bids lower than minimum bid', async () => {
    console.log('\tbuyer1 creating bid...');
    await throwsException(market.connect(buyer1).createBid(itemId, { value: bid1Amount }), 
      'CoralMarketplace: Bid value cannot be lower than minimum bid.');
  });


  it('Should create bid', async () => {
    // Initial data
    const iniBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const iniMarketBalance = await getBalance(marketContractAddress, 'market');

    // Creates bid
    console.log('\tbuyer1 creating bid...');
    await market.connect(buyer1).createBid(itemId, { value: bid2Amount });
    console.log('\tbid created');

    // Final data
    const endBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const endMarketBalance = await getBalance(marketContractAddress, 'market');
    const oldDeadline = deadline;
    const auctionData = await market.fetchAuctionData(itemId);
    deadline = new Date(auctionData.deadline * 1000);

    // Evaluate results
    expect(deadline.getTime()).equals(oldDeadline.getTime());
    expect(Number(auctionData.highestBid)).equals(Number(bid2Amount));
    expect(auctionData.highestBidder).equals(buyer1Address);
    expect(Math.round(endBuyer1Balance)).to.lte(Math.round(iniBuyer1Balance - formatBigNumber(bid2Amount)))
      .gt(Math.round(iniBuyer1Balance - formatBigNumber(bid2Amount) - formatBigNumber(maxGasFee)));
    expect(endMarketBalance).to.gte(iniMarketBalance + formatBigNumber(bid2Amount))
      .lt(iniMarketBalance + formatBigNumber(bid2Amount) + 1)
  });


  it('Should not allow bids equal or lower than highest bid', async () => {
    console.log('\tbuyer2 creating bid...');
    await throwsException(market.connect(buyer2).createBid(itemId, { value: bid2Amount }), 
      'CoralMarketplace: Bid value cannot be lower than highest bid.');
  });


  it('Should increase bid', async () => {
    // Creates bid
    console.log('\tbuyer1 creating bid...');
    await market.connect(buyer1).createBid(itemId, { value: bid3Amount });
    console.log('\tbid created');

    // Final data
    const oldDeadline = deadline;
    const auctionData = await market.fetchAuctionData(itemId);
    deadline = new Date(auctionData.deadline * 1000);

    // Evaluate results
    expect(deadline.getTime()).equals(oldDeadline.getTime());
    expect(Number(auctionData.highestBid)).equals(Number(bid2Amount.add(bid3Amount)));
    expect(auctionData.highestBidder).equals(buyer1Address);
  });


  it('Should extend auction deadline', async () => {
    // Initial data
    const iniBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const iniBuyer2Balance = await getBalance(buyer2Address, 'buyer2');
    const iniMarketBalance = await getBalance(marketContractAddress, 'market');

    // Wait until 10 minutes before deadline
    const timeUntilDeadline = deadline - new Date();
    console.log(`\ttime until deadline: ${timeUntilDeadline/60000} mins.`);
    if (timeUntilDeadline > 600000) {
      const timeToWait = timeUntilDeadline - 590000;
      console.log(`\twaiting for ${timeToWait/1000} seconds...`);
      await delay(timeToWait);
      console.log('\t10 minutes for deadline.');
    }

    // Creates bid
    console.log('\tbuyer2 creating bid...');
    await market.connect(buyer2).createBid(itemId, { value: bid4Amount });
    console.log('\tbid created');

    // Final data
    const endBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const endBuyer2Balance = await getBalance(buyer2Address, 'buyer2');
    const endMarketBalance = await getBalance(marketContractAddress, 'market');
    const oldDeadline = deadline;
    const auctionData = await market.fetchAuctionData(itemId);
    deadline = new Date(auctionData.deadline * 1000);
    const newDeadline = new Date(auctionData.deadline * 1000);
    const bidIncrease = formatBigNumber(bid4Amount) - formatBigNumber(bid2Amount) - formatBigNumber(bid3Amount);
    console.log(`\tdeadline extended by ${(newDeadline - deadline)/1000} secs.`);

    // Evaluate results
    expect(deadline.getTime()).gt(oldDeadline.getTime());
    expect(Number(auctionData.highestBid)).equals(Number(bid4Amount));
    expect(auctionData.highestBidder).equals(buyer2Address);
    expect(Math.round(endBuyer1Balance)).to.equals(Math.round(iniBuyer1Balance + formatBigNumber(bid2Amount) 
      + formatBigNumber(bid3Amount)));   // 2708 <= 2585
    expect(Math.round(endBuyer2Balance)).to.lte(Math.round(iniBuyer2Balance - formatBigNumber(bid4Amount)))
      .gt(Math.round(iniBuyer2Balance - formatBigNumber(bid4Amount) - formatBigNumber(maxGasFee)));
    expect(endMarketBalance).to.gte(iniMarketBalance + bidIncrease).lt(iniMarketBalance + bidIncrease + 1);
  });


  it.skip('Should end auction with bids', async () => {
    // Uncomment to run separately after the tests above.
    // Comment to run all tests together --> Increase timeout config to be more than 10 minutes
    const items = await market.fetchAuctions();
    const item = items[items.length - 1];
    itemId = Number(item.itemId);
    tokenId = item.tokenId;
    const auctionData = await market.fetchAuctionData(itemId);
    deadline = new Date(auctionData.deadline * 1000);
    // *****************************

    // Initial data
    const iniSellerBalance = await getBalance(sellerAddress, 'seller');
    const iniArtistBalance = await getBalance(artistAddress, 'artist');
    const iniOwnerBalance = await getBalance(ownerAddress, 'marketOwner');
    const iniTokenOwner = await nft.ownerOf(tokenId);
    const iniMarketBalance = await getBalance(marketContractAddress, 'market');
    await getBalance(buyer1Address, 'buyer1');

    // Wait until deadline
    const timeUntilDeadline = deadline - new Date();
    console.log(`\ttime until deadline: ${timeUntilDeadline/60000} mins.`);
    if (timeUntilDeadline > 0) {
      console.log('\twaiting for deadline...');
      await delay(timeUntilDeadline + 15000);
      console.log('\tdeadline reached.');
    }

    // End auction
    console.log('\tending auction...');
    await market.connect(buyer1).endAuction(itemId);
    console.log('\tauction ended.');

    // Final data
    const endItem = await market.fetchItem(itemId);
    const endSellerBalance = await getBalance(sellerAddress, 'seller');
    const endArtistBalance = await getBalance(artistAddress, 'artist');
    const endOwnerBalance = await getBalance(ownerAddress, 'marketOwner');
    const endTokenOwner = await nft.ownerOf(tokenId);
    const endMarketBalance = await getBalance(marketContractAddress, 'market');
    const royaltiesAmount = bid4Amount * royaltyValue / 10000;
    const marketFeeAmount = (bid4Amount - royaltiesAmount) * marketFee / 10000;
    await getBalance(buyer1Address, 'buyer1');

    // Evaluate results
    expect(iniTokenOwner).to.equal(marketContractAddress);
    expect(endTokenOwner).to.equal(buyer2Address);
    expect(Math.round(endArtistBalance)).to.equal(Math.round(iniArtistBalance + formatBigNumber(royaltiesAmount)));
    expect(Math.round(endOwnerBalance)).to.equal(Math.round(iniOwnerBalance + formatBigNumber(marketFeeAmount)));
    expect(Math.round(endSellerBalance)).to.equal(Math.round(iniSellerBalance + formatBigNumber(bid4Amount)
      - formatBigNumber(royaltiesAmount) - formatBigNumber(marketFeeAmount)));
    expect(endMarketBalance).to.gte(iniMarketBalance - formatBigNumber(bid4Amount))
      .lt(iniMarketBalance - formatBigNumber(bid4Amount) + 1)
    expect(endItem.sales[0].seller).to.equal(sellerAddress);
    expect(endItem.sales[0].buyer).to.equal(buyer2Address);
    expect(Number(endItem.sales[0].price)).to.equal(Number(bid4Amount));
    expect(endItem.owner).to.equal(buyer2Address);
    expect(endItem.onSale).to.equal(false);
  });


  it.skip('Should end auction without bids', async () => {
    // Initial data
    const iniBuyer2Balance = await getBalance(buyer2Address, 'buyer1'); 
    const iniItem = await market.fetchItem(itemId);
    const iniTokenOwner = await nft.ownerOf(tokenId);

    // Approve market contract for this address
    console.log('\tcreating approval for market contract...');
    await nft.connect(buyer2).setApprovalForAll(marketContractAddress, true);
    console.log('\tapproval created');
    
    // Create auction
    await market.connect(buyer2).createMarketItemAuction(itemId, 1, minBid);
    console.log('\tauction created.');
    await getBalance(buyer2Address, 'buyer2');

    // Wait until deadline
    const auctionData = await market.fetchAuctionData(itemId);
    deadline = new Date(auctionData.deadline * 1000);
    const timeUntilDeadline = deadline - new Date();
    console.log(`\ttime until deadline: ${timeUntilDeadline/1000} secs.`);
    if (timeUntilDeadline > 0) {
      console.log('\twaiting for deadline...');
      await delay(timeUntilDeadline + 15000);
      console.log('\tdeadline reached.');
    }

    // End auction
    console.log('\tending auction...');
    await market.connect(buyer2).endAuction(itemId);
    console.log('\tauction ended.');

    // Final data
    const endBuyer2Balance = await getBalance(buyer2Address, 'buyer2');
    const endItem = await market.fetchItem(itemId);
    const endTokenOwner = await nft.ownerOf(tokenId);

    // Evaluate results
    expect(endBuyer2Balance).to.lte(iniBuyer2Balance)
      .to.gt(iniBuyer2Balance - Number(maxGasFee));
    expect(iniTokenOwner).to.equal(buyer2Address);
    expect(endTokenOwner).to.equal(buyer2Address);
    expect(iniItem.owner).to.equal(buyer2Address);
    expect(endItem.owner).to.equal(buyer2Address);
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

  const delay = ms => new Promise(res => setTimeout(res, ms));

  async function logEvents(promise) {
    const tx = await promise;
    const receipt = await tx.wait();

    let msg = 'No events for this tx';
    if (receipt.events) {
      const eventsArgs = [];
      receipt.events.forEach(event => {
        if (event.args) { eventsArgs.push(event.args) }
      });
      msg = eventsArgs;
    }
    console.log(msg);
  }

});
