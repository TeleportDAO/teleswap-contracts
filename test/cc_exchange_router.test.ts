const CC_EXCHANGE_REQUESTS = require('./test_fixtures/ccExchangeRequests.json');
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";

import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import { LiquidityPoolFactory } from "../src/types/LiquidityPoolFactory";
import { LiquidityPoolFactory__factory } from "../src/types/factories/LiquidityPoolFactory__factory";
import { ExchangeRouter } from "../src/types/ExchangeRouter";
import { ExchangeRouter__factory } from "../src/types/factories/ExchangeRouter__factory";
import { CCExchangeRouter } from "../src/types/CCExchangeRouter";
import { CCExchangeRouter__factory } from "../src/types/factories/CCExchangeRouter__factory";
import { CCTransferRouter } from "../src/types/CCTransferRouter";
import { CCTransferRouter__factory } from "../src/types/factories/CCTransferRouter__factory";
import { WrappedToken } from "../src/types/WrappedToken";
import { WrappedToken__factory } from "../src/types/factories/WrappedToken__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";

const {
    advanceBlockWithTime,
    takeSnapshot,
    revertProvider,
} = require("./block_utils");

describe("CCExchangeRouter", async () => {

    let snapshotId: any;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let NORMAL_CONFIRMATION_PARAMETER = 6;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;

    // Contracts
    let exchangeRouter: ExchangeRouter;
    let liquidityPoolFactory: LiquidityPoolFactory;
    let ccExchangeRouter: CCExchangeRouter;
    let ccTransferRouter: CCTransferRouter;
    let teleBTC: WrappedToken;
    let exchangeToken: ERC20;

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
    
        // Mocks checkTxProof of bitcoinRelay 
        // We don't pass arguments since the request was modified and the txId is not valid
        await mockBitcoinRelay.mock.checkTxProof.returns(true);

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
            "IInstantRouter"
        );
        mockInstantRouter = await deployMockContract(
            deployer,
            instantRouterContract.abi
        );

        // Deploys ccTransferRouter contract
        const ccTransferRouterFactory = new CCTransferRouter__factory(deployer);
        ccTransferRouter = await ccTransferRouterFactory.deploy(
            mockBitcoinRelay.address,
            mockBitcoinTeleporter.address, 
            NORMAL_CONFIRMATION_PARAMETER
        );

        // Deploys teleBTC contract
        const teleBTCFactory = new WrappedToken__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "teleBTC", 
            ccTransferRouter.address
        );

        // Sets teleBTC address in ccTransferRouter
        await ccTransferRouter.setWrappedBitcoin(teleBTC.address);

        // Deploys liquidityPoolFactory
        const liquidityPoolFactoryFactory = new LiquidityPoolFactory__factory(deployer);
        liquidityPoolFactory = await liquidityPoolFactoryFactory.deploy(
            await deployer.getAddress()
        );

        // Deploys exchangeRouter contract
        const exchangeRouterFactory = new ExchangeRouter__factory(deployer);
        exchangeRouter = await exchangeRouterFactory.deploy(
            liquidityPoolFactory.address,
            ZERO_ADDRESS // WAVAX
        );

        // Deploys exchange token
        // We replace the exchangeToken address in ccExchangeRequests
        const erc20Factory = new ERC20__factory(deployer);
        exchangeToken = await erc20Factory.deploy(
            "exchangeToken", 
            "TDT", 
            100000
        );
        // console.log(exchangeToken.address);

        // Deploys ccExchangeRouter contract
        const ccExchangeRouterFactory = new CCExchangeRouter__factory(deployer);
        ccExchangeRouter = await ccExchangeRouterFactory.deploy(
            exchangeRouter.address,
            mockBitcoinTeleporter.address, 
            ccTransferRouter.address
        );

        // Sets teleBTC address in ccExchangeRouter
        await ccExchangeRouter.setWrappedBitcoin(teleBTC.address);

        // Sets ccExchangeRouter address in ccTransferRouter
        await ccTransferRouter.setCCExchangeRouter(ccExchangeRouter.address);

    });

    describe("ccExchange", async () => {

        beforeEach("adds liquidity to liquidity pool", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
            // Adds liquidity to teleBTC-TDT liquidity pool
            await teleBTC.mintTestToken();
            await teleBTC.approve(exchangeRouter.address, 1000000000);
            await exchangeToken.approve(exchangeRouter.address, 5000);
            let addedLiquidityA = 1000000000;
            let addedLiquidityB = 5000;
            await exchangeRouter.addLiquidity(
                teleBTC.address,
                exchangeToken.address,
                addedLiquidityA,
                addedLiquidityB,
                0,
                0,
                await deployer.getAddress(),
                1000000000, // big enough deadline
            );
        });
    
        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("mints and exchanges teleBTC for desired exchange token (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            await mockBitcoinTeleporter.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient
            );
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.vin,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.index,
                    false // payWithTDT
                )
            ).to.emit(ccExchangeRouter, 'CCExchange');
            // Checks enough teleBTC has been minted for user
            // expect(
            //     await teleBTC.balanceOf(CC_EXCHANGE_REQUESTS.normalCCExchange.recipientAddress)
            // ).to.equal();
            // Checks enough teleBTC has been minted for teleporter
            // expect(
            //     await teleBTC.balanceOf(await deployer.getAddress())
            // ).to.equal();
            // expects z teleBTC has been minted for protocol
            // expect(
            //     await teleBTC.balanceOf()
            // ).to.equal();
            // expects a teleBTC has been minted for locker
            // expect(
            //     await teleBTC.balanceOf()
            // ).to.equal();
        })

        it("mints teleBTC since deadline has passed (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            await mockBitcoinTeleporter.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.desiredRecipient
            );
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.vin,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.index,
                    false // payWithTDT
                )
            ).to.emit(teleBTC, 'Transfer');
            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for locker
        })

        it("mints teleBTC since output amount is less than minimum expected amount (normal cc exchange request)", async function () {
            await mockBitcoinTeleporter.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.desiredRecipient
            );
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.vin,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.index,
                    false // payWithTDT
                )
            ).to.emit(teleBTC, 'Transfer');
            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for locker
        })

        it("errors if teleBTC has been minted before for the request", async function () {

        })

        it("errors if the request has not been finalized on the relay", async function () {

        })

        it("errors if the percentage fee is out of range [0,100)", async function () {

        })

        it("errors if the request is not an exchange request", async function () {

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