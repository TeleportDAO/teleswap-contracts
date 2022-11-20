# TeleportDAO Protocol V1

This repository contains the smart contracts for the TeleportDAO bridge, cross-chain transfer, and cross-chain exchange. The codes belong to connecting Bitcoin to EVM-based blockchains. The repository uses Hardhat as development environment for compilation, testing and deployment tasks.

## What is Teleport?

Teleport is a trustless and universal protocol that provides an infrastructure for developers to build cross-chain applications. In other words, Teleport helps blockchains communicate with each other. Applications on one blockchain can access the latest data on other blockchains using Teleport relay smart contract.

## Documentation

See the link below: 
- [Documentation](https://docs.teleportdao.xyz/introduction/what-is-teleportdao)

## Community

You can join the discord channel [here](https://discord.com/invite/6RSsgfQgcb).

## Getting Started

To start, clone the codes and install the needed packages using:

`yarn`

If you only want to compile the codes enter the below command:

`yarn clean`

`yarn build`

You can also run the full test suite with the following command:

`yarn test`


You can deploy the contracts on specified networks in package.json with the following command:

`yarn test`

After deployments, the contracts need some settlements, do them by the following commands:

`yarn settlement:mumbai`

`yarn collateral_pool_scripts:mumbai`

 (with a different private key than the deployer one)

`yarn lockers_settlement:mumbai`

If some contracts has changed, update their addresses in other contracts by the following command:

`yarn global_variables_settlement:mumbai`