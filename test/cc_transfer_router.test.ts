const CC_REQUESTS = require('./test_fixtures/ccRequests.json');
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";

import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import { CCTransferRouter } from "../src/types/CCTransferRouter";
import { CCTransferRouter__factory } from "../src/types/factories/CCTransferRouter__factory";
import { WrappedToken } from "../src/types/WrappedToken";
import { WrappedToken__factory } from "../src/types/factories/WrappedToken__factory";

const {
    advanceBlockWithTime,
    takeSnapshot,
    revertProvider,
} = require("./block_utils");

describe("CCTransferRouter", async () => {
    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let NORMAL_CONFIRMATION_PARAMETER = 6;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;

    // Contracts
    let ccTransferRouter: CCTransferRouter;
    let teleBTC: WrappedToken;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockBitcoinTeleporter: MockContract;
    let mockInstantRouter: MockContract;

    before(async () => {
        // Sets accounts
        [deployer, signer1] = await ethers.getSigners();

        // Mocks relay contract
        const bitcoinRelayContract = await deployments.getArtifact(
            "IBitcoinRelay"
        );
        mockBitcoinRelay = await deployMockContract(
            deployer,
            bitcoinRelayContract.abi
        );

        // Mocks teleporters contract
        const bitcoinTeleporterContract = await deployments.getArtifact(
            "IBitcoinTeleporter"
        );
        mockBitcoinTeleporter = await deployMockContract(
            deployer,
            bitcoinTeleporterContract.abi
        );

        // Mocks instant router contract
        const instantRouterContract = await deployments.getArtifact(
            "IInstantRouterContract"
        );
        mockInstantRouter = await deployMockContract(
            deployer,
            instantRouterContract.abi
        );

        // Deploys teleBTC contract
        const teleBTCFactory = new WrappedToken__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            mockBitcoinRelay.address,
            mockBitcoinTeleporter.address, 
            NORMAL_CONFIRMATION_PARAMETER
        );

        // Deploys ccTransferRouter contract
        const ccTransferRouterFactory = new CCTransferRouter__factory(deployer);
        ccTransferRouter = await ccTransferRouterFactory.deploy(
            mockBitcoinRelay.address,
            mockBitcoinTeleporter.address, 
            NORMAL_CONFIRMATION_PARAMETER
        );

    });

    describe("ccTransfer", async () => {

        it("mints teleBTC for normal cc transfer request", async function () {
            expect(
                await ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    false // payWithTDT
                )
            ).to.equal(true);
            // Checks enough teleBTC has been minted for user
            expect(
                await teleBTC.balanceOf(CC_REQUESTS.normalCCTransfer.recipientAddress)
            ).to.equal();
            // Checks enough teleBTC has been minted for teleporter
            expect(
                await teleBTC.balanceOf(deployer)
            ).to.equal();
            // expects z teleBTC has been minted for protocol
            // expect(
            //     await teleBTC.balanceOf()
            // ).to.equal();
            // expects a teleBTC has been minted for locker
            // expect(
            //     await teleBTC.balanceOf()
            // ).to.equal();
        })

        it("mints teleBTC for instant cc transfer request", async function () {
            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for locker
        })

        // it("checks if the request has been used before", async function () {

        // })

        it("errors if teleBTC has been minted before for the request", async function () {

        })

        it("errors if the request has not been finalized on the relay", async function () {

        })

        it("errors if the percentage fee is out of range [0,100)", async function () {

        })

        it("errors if the request is an exchange request", async function () {

        })

        it("errors if the request data size is not 80 bytes", async function () {

        })

        it("errors if the request belongs to another chain", async function () {

        })

        it("errors if user has not sent BTC to lockers", async function () {

        })

        it("errors if the request speed is out of range {0,1}", async function () {

        })


    });
});