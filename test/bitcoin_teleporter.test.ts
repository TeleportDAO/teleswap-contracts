// require('dotenv').config({path:"../../.env"});
//
// import { assert, expect, use } from "chai";
// import { deployments, ethers } from "hardhat";
// import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
// import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
// import { Contract } from "@ethersproject/contracts";
//
// import { solidity } from "ethereum-waffle";
//
// import { isBytesLike } from "ethers/lib/utils";
// import { BitcoinTeleporter } from "../src/types/BitcoinTeleporter";
// import { BitcoinTeleporter__factory } from "../src/types/factories/BitcoinTeleporter__factory";
// import { WrappedToken } from "../src/types/WrappedToken";
// import { WrappedToken__factory } from "../src/types/factories/WrappedToken__factory";
// import { ERC20 } from "../src/types/ERC20";
// import { ERC20__factory } from "../src/types/factories/ERC20__factory";
//
// import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";
//
// describe("BitcoinTeleporter", async () => {
//
//     let snapshotId: any;
//
//     // Constants
//     let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
//     let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
//     // Bitcoin public key (32 bytes)
//     let TELEPORTER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
//     let TELEPORTER2 = '0x03dbc6764b8884a92e871274b87583e6d5c2a58819473e17e107ef3f6aa5a61626';
//     let UNLOCK_FEE =  5; // percentage of bond that protocol receives
//     let UNLOCK_PERIOD = 2;
//     let REQUIRED_LOCKED_AMOUNT =  1000; // amount of required TDT
//
//     // Accounts
//     let deployer: Signer;
//     let signer1: Signer;
//     let deployerAddress: string;
//
//     // Contracts
//     let bitcoinTeleporter: BitcoinTeleporter
//     let teleBTC: WrappedToken;
//     let teleportDAOToken: ERC20;
//
//     // Mock contracts
//     let mockExchangeRouter: MockContract;
//
//     before(async () => {
//         // Sets accounts
//         [deployer, signer1] = await ethers.getSigners();
//         deployerAddress = await deployer.getAddress();
//
//         // Deploys teleBTC contract
//         const teleBTCFactory = new WrappedToken__factory(deployer);
//         teleBTC = await teleBTCFactory.deploy(
//             "teleBTC",
//             "teleBTC",
//             ONE_ADDRESS // ccTransferRouter
//         );
//
//         // Deploys teleportDAO token
//         const erc20Factory = new ERC20__factory(deployer);
//         teleportDAOToken = await erc20Factory.deploy(
//             "teleportDAOToken",
//             "TDT",
//             100000
//         );
//
//         // Mocks exchange router contract
//         const exchangeRouterContract = await deployments.getArtifact(
//             "IExchangeRouter"
//         );
//         mockExchangeRouter = await deployMockContract(
//             deployer,
//             exchangeRouterContract.abi
//         );
//
//         // Deploys bitcoinTeleporter contract
//         const bitcoinTeleporterFactory = new BitcoinTeleporter__factory(deployer);
//         bitcoinTeleporter = await bitcoinTeleporterFactory.deploy(
//             teleportDAOToken.address,
//             mockExchangeRouter.address,
//             UNLOCK_FEE,
//             UNLOCK_PERIOD,
//             REQUIRED_LOCKED_AMOUNT
//         );
//
//         // Sets ccBurnRouter address
//         await bitcoinTeleporter.setCCBurnRouter(deployerAddress);
//
//     });
//
//     async function addTeleporter(teleporterAddress: any, teleporterNumber: number) {
//         // Gives allowance to bitcoinTeleporter
//         await teleportDAOToken.approve(bitcoinTeleporter.address, REQUIRED_LOCKED_AMOUNT);
//
//         // Adds teleporter
//         expect(
//             await bitcoinTeleporter.addTeleporter(teleporterAddress)
//         ).to.emit(bitcoinTeleporter, 'AddTeleporter');
//
//         // Checks bitcoinTeleporter TDT balance
//         expect(
//             await teleportDAOToken.balanceOf(bitcoinTeleporter.address)
//         ).to.equal(teleporterNumber*REQUIRED_LOCKED_AMOUNT);
//
//         // Checks number of teleporters
//         expect(await bitcoinTeleporter.numberOfTeleporters()).to.equal(teleporterNumber);
//
//         return true;
//     }
//
//     describe("addTeleporter", async () => {
//
//         beforeEach(async () => {
//             // Takes snapshot
//             snapshotId = await takeSnapshot(deployer.provider);
//         });
//
//         afterEach(async () => {
//             // Reverts the state
//             await revertProvider(deployer.provider, snapshotId);
//         });
//
//         it("adds two teleporters", async function () {
//             // Adds first teleporter
//             expect(
//                 await addTeleporter(TELEPORTER1, 1)
//             ).to.equal(true);
//
//             // Adds second teleporter
//             expect(
//                 await addTeleporter(TELEPORTER2, 2)
//             ).to.equal(true);
//         })
//
//         it("reverts since teleporter TDT balance is not enough", async function () {
//             // Gives allowance to bitcoinTeleporter
//             await teleportDAOToken.approve(bitcoinTeleporter.address, REQUIRED_LOCKED_AMOUNT/2);
//
//             // Adds teleporter
//             await expect(
//                 bitcoinTeleporter.addTeleporter(TELEPORTER1)
//             ).to.revertedWith('ERC20: transfer amount exceeds allowance');
//         })
//
//         it("reverts since bitcoin address has been used before", async function () {
//             // Adds a teleporter
//             expect(
//                 await addTeleporter(TELEPORTER1, 1)
//             ).to.equal(true);
//
//             // Gives allowance to bitcoinTeleporter
//             await teleportDAOToken.approve(bitcoinTeleporter.address, REQUIRED_LOCKED_AMOUNT);
//
//             // TODO: revert if bitcoin address has been used before
//         })
//
//         it("reverts since bitcoin address is not valid", async function () {
//             // TODO: revert if bitcoin address is not valid
//         })
//
//     });
//
//     describe("removeTeleporter", async () => {
//
//         beforeEach(async () => {
//             // Takes snapshot
//             snapshotId = await takeSnapshot(deployer.provider);
//         });
//
//         afterEach(async () => {
//             // Reverts the state
//             await revertProvider(deployer.provider, snapshotId);
//         });
//
//         it("removes a teleporter", async function () {
//             // Adds a teleporter
//             expect(
//                 await addTeleporter(TELEPORTER1, 1)
//             ).to.equal(true);
//
//             // Records teleporter TDT balance
//             let oldTDTBalanceTeleporter = await teleportDAOToken.balanceOf(deployerAddress);
//
//             // Removes teleporter
//             expect(
//                 await bitcoinTeleporter.removeTeleporter(0)
//             ).to.emit(bitcoinTeleporter, 'RemoveTeleporter');
//
//             // Checks that teleporter receives its bond
//             expect(
//                 await teleportDAOToken.balanceOf(deployerAddress)
//             ).to.equal(oldTDTBalanceTeleporter.add(REQUIRED_LOCKED_AMOUNT*(100-UNLOCK_FEE)/100));
//
//             // Checks that the protocol receives the unlock fee
//             expect(
//                 await teleportDAOToken.balanceOf(bitcoinTeleporter.address)
//             ).to.equal(REQUIRED_LOCKED_AMOUNT*UNLOCK_FEE/100);
//
//             // Checks that total number of teleporters is updated
//             expect(await bitcoinTeleporter.numberOfTeleporters()).to.equal(0);
//         })
//
//         it("reverts since msg.sender is not authorized", async function () {
//             // Adds a teleporter
//             expect(
//                 await addTeleporter(TELEPORTER1, 1)
//             ).to.equal(true);
//
//             // Removes teleporter
//             let bitcoinTeleporterSigner1 = await bitcoinTeleporter.connect(signer1);
//             await expect(
//                 bitcoinTeleporterSigner1.removeTeleporter(0)
//             ).to.revertedWith('you are not allowed to remove teleporter');
//         })
//
//         it("reverts since unlock period has not passed yet", async function () {
//             // Adds two teleporters
//             expect(
//                 await addTeleporter(TELEPORTER1, 1)
//             ).to.equal(true);
//             expect(
//                 await addTeleporter(TELEPORTER2, 2)
//             ).to.equal(true);
//
//             // Removes teleporter
//             expect(
//                 await bitcoinTeleporter.removeTeleporter(0)
//             ).to.emit(bitcoinTeleporter, 'RemoveTeleporter');
//
//             // Removes another teleporter
//             await expect(
//                 bitcoinTeleporter.removeTeleporter(0)
//             ).to.revertedWith('too soon for new unlock');
//         })
//
//     });
//
//     describe("slashTeleporters", async () => {
//
//         it("slashes teleporters bond and buys teleBTC with slashed bond ", async function () {
//             // Mocks swapTokensForExactTokens of exchangeRouter
//             await mockExchangeRouter.mock.getAmountsIn.returns([100]);
//             await mockExchangeRouter.mock.swapTokensForExactTokens.returns([100, 100]);
//             // TODO: emit event when teleporters get slashed
//             await bitcoinTeleporter.slashTeleporters(100, deployerAddress);
//         })
//
//         it("reverts since msg.sender is not ccBurnRouter", async function () {
//             // Removes teleporter
//             let bitcoinTeleporterSigner1 = await bitcoinTeleporter.connect(signer1);
//             await expect(
//                 bitcoinTeleporterSigner1.slashTeleporters(100, deployerAddress)
//             ).to.revertedWith('message sender is not correct');
//         })
//
//     });
//
// });
