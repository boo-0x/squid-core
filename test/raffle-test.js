const { expect, assert } = require('chai');
const ReefAbi = require('./ReefToken.json');

describe('************ Raffles ******************', ()  => {
  let market, nft, owner, seller, artist, buyer1, buyer2, helper, marketFee, marketContractAddress, nftContractAddress,
    ownerAddress, sellerAddress, artistAddress, buyer1Address, buyer2Address, helperAddress, reefToken, tokenId, itemId, 
    royaltyValue, maxGasFee, numMinutes, buyer1RaffleAmount, buyer2RaffleAmount;

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
    helperAddress = await helper.getAddress();

    // Initialize and connect to Reef token
    const ReefToken = new ethers.Contract(config.contracts.reef, ReefAbi, owner);
    reefToken = ReefToken.connect(owner);

    // Initialize global variables
    marketFee = 250; // 2.5%
    maxGasFee = ethers.utils.parseUnits('10', 'ether');
    numMinutes = 1;
    buyer1RaffleAmount = ethers.utils.parseUnits('100', 'ether');
    buyer2RaffleAmount = ethers.utils.parseUnits('50', 'ether');
    royaltyValue = 1000; // 10%
    
    if (!marketContractAddress || marketContractAddress == '') {
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
    
    if (!nftContractAddress || nftContractAddress == '') {
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

    // Create NFT
    console.log('\tseller creating NFTs...');
    await getBalance(sellerAddress, 'seller');
    const tx = await nft.connect(seller).createToken('https://fake-uri.com', 1, artistAddress, royaltyValue, false);
    const receipt = await tx.wait();
		tokenId = receipt.events[0].args[2].toNumber();
    console.log(`\tNFT created with tokenId ${tokenId}`);
    await getBalance(sellerAddress, 'seller');
  });


  it('Should create raffle', async () => {
    // Initial data
    const iniItems = await market.fetchRaffles();
    const iniTokenOwner = await nft.ownerOf(tokenId);

    // Create raffle
    console.log('\tseller creating raffle...');
    await getBalance(sellerAddress, 'seller');
    await market.connect(seller).createNewNftRaffle(nftContractAddress, tokenId, numMinutes);
    console.log('\traffle created.');
    await getBalance(sellerAddress, 'seller');

    // Final data
    const items = await market.fetchRaffles();
    const item = items[items.length - 1];
    const itemUri = await nft.tokenURI(item.tokenId);
    const endTokenOwner = await nft.ownerOf(tokenId);
    itemId = Number(item.itemId);
    const raffleData = await market.fetchRaffleData(itemId);
    deadline = new Date(raffleData.deadline * 1000);

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
    expect(item.typeItem).to.equal(2);
    expect(deadline).to.lt(new Date(new Date().getTime() + 120000)).gt(new Date());
  });


  it('Should add entries to the raffle', async () => {
    // Initial data
    const iniBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const iniBuyer2Balance = await getBalance(buyer2Address, 'buyer2');
    const iniMarketBalance = await getBalance(marketContractAddress, 'market');

    // Add entries
    console.log('\tbuyer1 enters NFT raffle...');
    await market.connect(buyer1).enterRaffle(itemId, { value: buyer1RaffleAmount });
    console.log('\tbuyer1 entry created');
    console.log('\tbuyer2 enters NFT raffle...');
    await market.connect(buyer2).enterRaffle(itemId, { value: buyer2RaffleAmount });
    console.log('\tbuyer2 entry created');

    // Final data
    const endBuyer1Balance = await getBalance(buyer1Address, 'buyer1');
    const endBuyer2Balance = await getBalance(buyer2Address, 'buyer2');
    const endMarketBalance = await getBalance(marketContractAddress, 'market');

    // Evaluate results
    expect(Math.round(endBuyer1Balance)).to.lte(Math.round(iniBuyer1Balance - formatBigNumber(buyer1RaffleAmount)))
      .gt(Math.round(iniBuyer1Balance - formatBigNumber(buyer1RaffleAmount) - formatBigNumber(maxGasFee)));
    expect(Math.round(endBuyer2Balance)).to.lte(Math.round(iniBuyer2Balance - formatBigNumber(buyer2RaffleAmount)))
      .gt(Math.round(iniBuyer2Balance - formatBigNumber(buyer2RaffleAmount) - formatBigNumber(maxGasFee)));
    expect(endMarketBalance).to.gte(iniMarketBalance + formatBigNumber(buyer1RaffleAmount) + formatBigNumber(buyer2RaffleAmount))
      .lt(iniMarketBalance + formatBigNumber(buyer1RaffleAmount) + formatBigNumber(buyer2RaffleAmount) + 1)
  });


  it('Should get amount sent to raffle', async () => {
    const raffleData = await market.connect(buyer1).fetchRaffleData(itemId);
    expect(Number(raffleData.contribution)).to.equal(Number(buyer1RaffleAmount));
  });


  it('Should not end raffle before deadline', async () => {
    console.log('\tending raffle...');
    await throwsException(market.connect(seller).endRaffle(itemId), 
      'CoralMarketplace: Raffle deadline has not been reached yet.');
  });


  it('Should end raffle and send NFT to winner', async () => {
    // Initial data
    const iniSellerBalance = await getBalance(sellerAddress, 'seller');
    const iniArtistBalance = await getBalance(artistAddress, 'artist');
    const iniOwnerBalance = await getBalance(ownerAddress, 'marketOwner');
    const iniTokenOwner = await nft.ownerOf(tokenId);
    const iniMarketBalance = await getBalance(marketContractAddress, 'market');
    await getBalance(helperAddress, 'helper');

    // Wait until deadline
    const timeUntilDeadline = deadline - new Date();
    console.log(`\ttime until deadline: ${timeUntilDeadline/1000} secs.`);
    if (timeUntilDeadline > 0) {
      console.log('\twaiting for deadline...');
      await delay(timeUntilDeadline + 15000);
      console.log('\tdeadline reached.');
    }

    // End raffle
    console.log('\tending raffle...');
    await market.connect(helper).endRaffle(itemId);
    console.log('\traffle ended.');

    // Final data
    const endItem = await market.fetchItem(itemId);
    const endSellerBalance = await getBalance(sellerAddress, 'seller');
    const endArtistBalance = await getBalance(artistAddress, 'artist');
    const endOwnerBalance = await getBalance(ownerAddress, 'marketOwner');
    const endTokenOwner = await nft.ownerOf(tokenId);
    const endMarketBalance = await getBalance(marketContractAddress, 'market');
    const royaltiesAmount = ethers.utils.parseUnits('150', 'ether') * royaltyValue / 10000;
    const marketFeeAmount = (ethers.utils.parseUnits('150', 'ether') - royaltiesAmount) * marketFee / 10000;
    await getBalance(helperAddress, 'helper');

    // Evaluate results
    expect(iniTokenOwner).to.equal(marketContractAddress);
    expect(endTokenOwner).to.be.oneOf([buyer1Address, buyer2Address]);
    expect(Math.round(endArtistBalance)).to.equal(Math.round(iniArtistBalance + formatBigNumber(royaltiesAmount)));
    expect(Math.round(endOwnerBalance)).to.equal(Math.round(iniOwnerBalance + formatBigNumber(marketFeeAmount)));
    expect(Math.round(endSellerBalance)).to.equal(Math.round(iniSellerBalance + formatBigNumber(buyer1RaffleAmount) + formatBigNumber(buyer2RaffleAmount) 
      - formatBigNumber(royaltiesAmount) - formatBigNumber(marketFeeAmount)));
    expect(endMarketBalance).to.gte(iniMarketBalance - formatBigNumber(buyer1RaffleAmount) - formatBigNumber(buyer2RaffleAmount))
      .lt(iniMarketBalance - formatBigNumber(buyer1RaffleAmount) - formatBigNumber(buyer2RaffleAmount) + 1)
    expect(endItem.sales[0].seller).to.equal(sellerAddress);
    expect(endItem.sales[0].buyer).to.be.oneOf([buyer1Address, buyer2Address]);
    expect(Number(endItem.sales[0].price)).to.equal(Number(buyer1RaffleAmount) + Number(buyer2RaffleAmount));
    expect(endItem.owner).to.be.oneOf([buyer1Address, buyer2Address]);
    expect(endItem.onSale).to.equal(false);
  });


  it('Create new raffle with existing market item', async () => {
    // Initial data
    const iniItem = await market.fetchItem(itemId);
    expect(iniItem.onSale).to.equal(false);
    const signer = iniItem.owner == buyer1Address ? buyer1 : buyer2;

    // Approve market contract for this address
    console.log('\tcreating approval for market contract...');
    await nft.connect(signer).setApprovalForAll(marketContractAddress, true);
    console.log('\tApproval created');

    // Create raffle
    console.log('\tcreating NFT raffle...');
    await market.connect(signer).createMarketItemRaffle(itemId, numMinutes);
    console.log('\tNFT raffle created');
    
    // Final data
    const endItem = await market.fetchItem(itemId);

    // Evaluate result
    expect(endItem.onSale).to.equal(true);
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

});
