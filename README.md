# TeleportDAO Bitcoin<>EVM Bridge and TeleSwap Protocol V1

This repository contains the smart contracts for the TeleportDAO Bitcoin<>EVM bridge and TeleSwap protocol. The repository uses Hardhat as development environment for compilation, testing and deployment tasks.

## What is TeleportDAO Bitcoin<>EVM Bridge?

TeleportDAO Bitcoin<>EVM Bridge is a trustless protocol that makes Bitcoin data accessible on EVM chains. This is achieved by implementing the Bitcoin light client as a smart contract. The bridge can be leveraged to build cross-chain dApps between Bitcoin and EVM chains.

## What is TeleSwap?

TeleSwap is a fully decentralized cross-chain settlement protocol that facilitates the transfer or exchange of assets between Bitcoin and EVM chains quickly and securely.

## Documentation

See the links below: 
- [TeleportDAO documentation](https://docs.teleportdao.xyz/introduction/what-is-teleportdao)
- [TeleSwap documentation](https://docs.teleswap.xyz/teleswap/introduction)

## Audits
- [Quantstamp report](https://github.com/TeleportDAO/audits/blob/main/reports/Quantstamp-Bitcoin-EVM.pdf) (Feb 2023)

## Community
- Follow us on [Twitter](https://twitter.com/Teleport_DAO).
- Join our [discord channel](https://discord.com/invite/6RSsgfQgcb).

## Install Dependencies

To start, clone the codes and install the required packages using:

`yarn`

## Compile Contracts

If you want to compile the codes enter the below command:

`yarn clean` & `yarn build`

## Run Tests

You can run the full test suite with the following command:

`yarn test`

## Deploy Contracts

You can deploy the contracts on networks specified in package.json with the following command:

`yarn deploy:network`

## Set Variables

After deployment, certain variables need to be set using the following commands:

`yarn settlement:network` & `yarn collateral_pool_scripts:network`

 Run the below command with a different private key:

`yarn lockers_settlement:network`

If a contract address has been changed, update the address in other contracts by the following command:

`yarn global_variables_settlement:network`
