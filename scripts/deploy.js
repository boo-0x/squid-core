// We require the Hardhat Runtime Environment explicitly here. This is optional 
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `yarn hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
const hre = require("hardhat");

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile 
  // manually to make sure everything is compiled
  // await hre.run('compile');

  console.log('starting deployment...');

  const ownerAccount = await hre.reef.getSignerByName('account');

  // Deploy CoralMarketplace
  const NFTMarketplace = await hre.reef.getContractFactory('CoralMarketplace', ownerAccount);
  const marketFee = 250; // 2.5%
  const nftMarketplace = await NFTMarketplace.deploy(marketFee);
  await nftMarketplace.deployed();
  console.log(`CoralMarketplace deployed in ${nftMarketplace.address}`);

  // Deploy CoralLoan
  const Loan = await hre.reef.getContractFactory('CoralLoan', ownerAccount);
  const loan = await Loan.deploy(nftMarketplace.address);
  await loan.deployed();
  console.log(`CoralLoan deployed in ${loan.address}`);

  // Deploy CoralNFT
  const NFT = await hre.reef.getContractFactory('CoralNFT', ownerAccount);
  const nft = await NFT.deploy(nftMarketplace.address, loan.address);
  await nft.deployed();
  console.log(`CoralNFT deployed to ${nft.address}`);

  // Set loan contract address in CoralMarketplace
  await nftMarketplace.connect(ownerAccount).setLoanAddress(loan.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
