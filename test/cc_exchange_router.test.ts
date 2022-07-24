const CC_EXCHANGE_REQUESTS = require('./test_fixtures/ccExchangeRequests.json');
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";

import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import { LiquidityPool } from "../src/types/LiquidityPool";
import { LiquidityPool__factory } from "../src/types/factories/LiquidityPool__factory";
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

import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";

describe("CCExchangeRouter", async () => {

    let snapshotId: any;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let DUMMY_ADDRESS = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
    let NORMAL_CONFIRMATION_PARAMETER = 6;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let deployerAddress: string;

    // Contracts
    let exchangeRouter: ExchangeRouter;
    let liquidityPool: LiquidityPool;
    let liquidityPoolFactory: LiquidityPoolFactory;
    let ccExchangeRouter: CCExchangeRouter;
    let ccTransferRouter: CCTransferRouter;
    let teleBTC: WrappedToken;
    let exchangeToken: ERC20;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockLockers: MockContract;
    // let mockBitcoinTeleporter: MockContract;
    let mockInstantRouter: MockContract;

    //
    let liquidityPool__factory: LiquidityPool__factory;

    before(async () => {
        // Sets accounts
        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();

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
        // const bitcoinTeleporterContract = await deployments.getArtifact(
        //     "IBitcoinTeleporter"
        // );
        // mockBitcoinTeleporter = await deployMockContract(
        //     deployer,
        //     bitcoinTeleporterContract.abi
        // );

        // Mocks teleporters contract
        const lockersContract = await deployments.getArtifact(
            "ILockers"
        );
        mockLockers = await deployMockContract(
            deployer,
            lockersContract.abi
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
            mockLockers.address,
            ZERO_ADDRESS
        );

        // Deploys teleBTC contract
        const teleBTCFactory = new WrappedToken__factory(deployer);
        console.log("cc transfer router address: ", ccTransferRouter.address)
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "teleBTC",
            ccTransferRouter.address
        );

        // Sets teleBTC address in ccTransferRouter
        await ccTransferRouter.setTeleBTC(teleBTC.address);

        // Deploys liquidityPoolFactory
        const liquidityPoolFactoryFactory = new LiquidityPoolFactory__factory(deployer);
        liquidityPoolFactory = await liquidityPoolFactoryFactory.deploy(
            deployerAddress
        );

        // Creates liquidityPool__factory object
        liquidityPool__factory = new LiquidityPool__factory(deployer);

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
            mockLockers.address,
            mockBitcoinRelay.address,
            teleBTC.address
        );

        // Sets teleBTC address in ccExchangeRouter
        // await ccExchangeRouter.setWrappedBitcoin(teleBTC.address);

        // Sets ccExchangeRouter address in ccTransferRouter
        await ccExchangeRouter.setExchangeRouter(exchangeRouter.address);

    });

    describe("ccExchange", async () => {
        let oldReserveTeleBTC: BigNumber;
        let oldReserveExchangeToken: BigNumber;
        let oldDeployerBalanceTeleBTC: BigNumber;
        let oldUserBalanceTeleBTC: BigNumber;
        let oldDeployerBalanceTDT: BigNumber;
        let oldUserBalanceTDT: BigNumber;
        let oldTotalSupplyTeleBTC: BigNumber;

        async function checksWhenExchangeFails(request: any) {
            // Records new supply of teleBTC
            let newTotalSupplyTeleBTC = await teleBTC.totalSupply();

            // Records new teleBTC and TDT balances of user and teleporter
            let newUserBalanceTeleBTC = await teleBTC.balanceOf(
                request.recipientAddress
            );
            let newDeployerBalanceTeleBTC = await teleBTC.balanceOf(deployerAddress);
            let newUserBalanceTDT = await exchangeToken.balanceOf(
                request.recipientAddress
            );
            let newDeployerBalanceTDT = await exchangeToken.balanceOf(deployerAddress);

            // Checks enough teleBTC has been minted for user
            expect(newUserBalanceTeleBTC).to.equal(
                oldUserBalanceTeleBTC.add(
                    request.bitcoinAmount -
                    request.teleporterFee
                )
            );

            // Checks that enough teleBTC has been minted for teleporter
            expect(newDeployerBalanceTeleBTC).to.equal(
                oldDeployerBalanceTeleBTC.add(request.teleporterFee)
            );

            // Checks that user and deployer TDT balance hasn't changed
            expect(newUserBalanceTDT).to.equal(
                oldUserBalanceTDT
            );
            expect(newDeployerBalanceTDT).to.equal(
                oldDeployerBalanceTDT
            );

            // Checks extra teleBTC hasn't been minted
            expect(newTotalSupplyTeleBTC).to.equal(
                oldTotalSupplyTeleBTC.add(request.bitcoinAmount)
            );
            return true;
        }

        beforeEach("adds liquidity to liquidity pool", async () => {
            // Takes snapshot before adding liquidity
            snapshotId = await takeSnapshot(deployer.provider);

            // Adds liquidity to teleBTC-TDT liquidity pool
            await teleBTC.mintTestToken();
            await teleBTC.approve(exchangeRouter.address, 10000);
            await exchangeToken.approve(exchangeRouter.address, 10000);
            let addedLiquidityA = 10000;
            let addedLiquidityB = 10000;
            await exchangeRouter.addLiquidity(
                teleBTC.address,
                exchangeToken.address,
                addedLiquidityA,
                addedLiquidityB,
                0, // Minimum added liquidity for first token
                0, // Minimum added liquidity for second token
                deployerAddress,
                1000000000, // Long deadline
            );
            let liquidityPoolAddress = await liquidityPoolFactory.getLiquidityPool(
                teleBTC.address,
                exchangeToken.address
            );

            // Records total supply of teleBTC
            oldTotalSupplyTeleBTC = await teleBTC.totalSupply();

            // Loads teleBTC-TDT liquidity pool
            liquidityPool = await liquidityPool__factory.attach(liquidityPoolAddress);

            // Records current reserves of teleBTC and TDT
            if (await liquidityPool.token0() == teleBTC.address) {
                [oldReserveTeleBTC, oldReserveExchangeToken] = await liquidityPool.getReserves();
            } else {
                [oldReserveExchangeToken, oldReserveTeleBTC] = await liquidityPool.getReserves()
            }

            // Records current teleBTC and TDT balances of user and teleporter
            oldUserBalanceTeleBTC = await teleBTC.balanceOf(
                CC_EXCHANGE_REQUESTS.normalCCExchange.recipientAddress
            );
            oldDeployerBalanceTeleBTC = await teleBTC.balanceOf(deployerAddress);
            oldUserBalanceTDT = await exchangeToken.balanceOf(
                CC_EXCHANGE_REQUESTS.normalCCExchange.recipientAddress
            );
            oldDeployerBalanceTDT = await exchangeToken.balanceOf(deployerAddress);
        });

        afterEach(async () => {
            // Reverts the state to the before of adding liquidity
            await revertProvider(deployer.provider, snapshotId);
        });

        it("mints and exchanges teleBTC for desired exchange token (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            await mockLockers.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient
            );

            // Finds expected output amount that user receives
            let expectedOutputAmount = await exchangeRouter.getAmountOut(
                CC_EXCHANGE_REQUESTS.normalCCExchange.bitcoinAmount -
                CC_EXCHANGE_REQUESTS.normalCCExchange.teleporterFee,
                oldReserveTeleBTC,
                oldReserveExchangeToken
            );

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Mints and exchanges teleBTC for TDT
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.index,
                    // false // payWithTDT
                )
            ).to.emit(ccExchangeRouter, 'CCExchange');

            // Records new supply of teleBTC
            let newTotalSupplyTeleBTC = await teleBTC.totalSupply();

            // Records new teleBTC and TDT balances of user and teleporter
            let newUserBalanceTeleBTC = await teleBTC.balanceOf(
                CC_EXCHANGE_REQUESTS.normalCCExchange.recipientAddress
            );
            let newDeployerBalanceTeleBTC = await teleBTC.balanceOf(deployerAddress);
            let newUserBalanceTDT = await exchangeToken.balanceOf(
                CC_EXCHANGE_REQUESTS.normalCCExchange.recipientAddress
            );
            let newDeployerBalanceTDT = await exchangeToken.balanceOf(deployerAddress);

            // Checks that enough teleBTC has been minted for teleporter
            expect(newDeployerBalanceTeleBTC).to.equal(
                oldDeployerBalanceTeleBTC.add(CC_EXCHANGE_REQUESTS.normalCCExchange.teleporterFee)
            );

            // Checks that user received enough TDT
            expect(newUserBalanceTDT).to.equal(
                oldUserBalanceTDT.add(expectedOutputAmount)
            );

            // Checks that user teleBTC balance and deployer TDT balance hasn't changed
            expect(newUserBalanceTeleBTC).to.equal(
                oldUserBalanceTeleBTC
            );
            expect(newDeployerBalanceTDT).to.equal(
                oldDeployerBalanceTDT
            );

            // Checks extra teleBTC hasn't been minted
            expect(newTotalSupplyTeleBTC).to.equal(
                oldTotalSupplyTeleBTC.add(CC_EXCHANGE_REQUESTS.normalCCExchange.bitcoinAmount)
            );
            // expects z teleBTC has been minted for protocol
            // expects a teleBTC has been minted for locker
        })

        it("mints teleBTC since deadline has passed (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            await mockLockers.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.desiredRecipient
            );

            // Mints teleBTC
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.vin,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.index,
                    // false // payWithTDT
                )
            ).to.emit(teleBTC, 'Transfer').and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            expect(await checksWhenExchangeFails(CC_EXCHANGE_REQUESTS.normalCCExchangeExpired)).to.equal(true);

            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for locker
        })

        it("mints teleBTC since output amount is less than minimum expected amount (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            await mockLockers.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.desiredRecipient
            );

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Mints teleBTC
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.index,
                    // false // payWithTDT
                )
            ).to.emit(teleBTC, 'Transfer').and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            expect(await checksWhenExchangeFails(CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage)).to.equal(true);

            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for locker
        })

        it("mints teleBTC since exchange token doesn't exist (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            await mockLockers.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.desiredRecipient
            );

            // Mints teleBTC
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken.vin,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken.vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken.index,
                    // false // payWithTDT
                )
            ).to.emit(teleBTC, 'Transfer').and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            expect(await checksWhenExchangeFails(CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken)).to.equal(true);

            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for locker
        })

        it("reverts if the request has been used before", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            await mockLockers.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient
            );

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Mints and exchanges teleBTC for exchangeToken
            await ccExchangeRouter.ccExchange(
                CC_EXCHANGE_REQUESTS.normalCCExchange.version,
                CC_EXCHANGE_REQUESTS.normalCCExchange.vin,
                vout,
                CC_EXCHANGE_REQUESTS.normalCCExchange.locktime,
                CC_EXCHANGE_REQUESTS.normalCCExchange.blockNumber,
                CC_EXCHANGE_REQUESTS.normalCCExchange.intermediateNodes,
                CC_EXCHANGE_REQUESTS.normalCCExchange.index,
                // false // payWithTDT
            );

            // Reverts since the request has been used before
            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange.index,
                    // false // payWithTDT
                )
            ).to.revertedWith("Request has been used before");

        })

        it("reverts if teleporter fee is greater than bitcoin amount", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            await mockLockers.mock.redeemScriptHash.returns(
                CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient
            );

            // Reverts since the request has been used before
            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.vin,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.index,
                    // false // payWithTDT
                )
            ).to.revertedWith("CCExchangeRouter: request is transfer request");

        })

        it("reverts if the percentage fee is out of range [0,100)", async function () {

        })

        it("reverts if the request is not an exchange request", async function () {

        })

        it("reverts if the request data size is not 80 bytes", async function () {

        })

        it("reverts if the request belongs to another chain", async function () {

        })

        it("reverts if user has not sent BTC to lockers", async function () {

        })

        it("reverts if the request speed is out of range {0,1}", async function () {

        })

    });
});
