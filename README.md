# Sqwid Marketplace Core

This project has been created using the [Hardhat-reef-template](https://github.com/reef-defi/hardhat-reef-template).

## Contract addresses

|             | Marketplace contract                                                                                                           | NFT contract                                                                                                                   | Loan contract                                                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| **Mainnet** | [0x79a46FCDAF4989960219843989dAC9FAf35d3489](https://reefscan.com/contract/0x79a46FCDAF4989960219843989dAC9FAf35d3489)         | [0xa12b4607090E8dB9F1F7B07754eEf89A493cF746](https://reefscan.com/contract/0xa12b4607090E8dB9F1F7B07754eEf89A493cF746)         | [0xB9EfC4Eb306e2BDD1F21246B7e2CEE075dDf1663](https://reefscan.com/contract/0xB9EfC4Eb306e2BDD1F21246B7e2CEE075dDf1663)         |
| **Testnet** | [0x17b1C987520dE98B85c9cF9c8cE92333228034Bb](https://testnet.reefscan.com/contract/0x17b1C987520dE98B85c9cF9c8cE92333228034Bb) | [0x02C7921BaB3054FCcd62c987aeB7d303D66b300E](https://testnet.reefscan.com/contract/0x02C7921BaB3054FCcd62c987aeB7d303D66b300E) | [0xC8e7e2F541D1BED81d70D4f216b7D06A688E53a8](https://testnet.reefscan.com/contract/0xC8e7e2F541D1BED81d70D4f216b7D06A688E53a8) |

## Installing

Install all dependencies with `yarn`.

## Deploy contracts

Deploy in testnet:

```bash
yarn hardhat run scripts/deploy.js
```

Deploy in mainnet:

```bash
yarn hardhat run scripts/deploy.js --network reef_mainnet
```

## Run tests

```bash
yarn test
```

## Use account seeds

In order to use your Reef account to deploy the contracts or run the tests, you have to rename the _seeds.example.json_ file to _seeds.json_ and write your set your seed words there.

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.
