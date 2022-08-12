const CC_EXCHANGE_REQUESTS = require('./test_fixtures/ccExchangeRequests.json');
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";

import { UniswapV2Pair } from "../src/types/UniswapV2Pair";
import { UniswapV2Pair__factory } from "../src/types/factories/UniswapV2Pair__factory";
import { UniswapV2Factory } from "../src/types/UniswapV2Factory";
import { UniswapV2Factory__factory } from "../src/types/factories/UniswapV2Factory__factory";
import { UniswapV2Router02 } from "../src/types/UniswapV2Router02";
import { UniswapV2Router02__factory } from "../src/types/factories/UniswapV2Router02__factory";
import { UniswapV2Connector } from "../src/types/UniswapV2Connector";
import { UniswapV2Connector__factory } from "../src/types/factories/UniswapV2Connector__factory";
import { CCExchangeRouter } from "../src/types/CCExchangeRouter";
import { CCExchangeRouter__factory } from "../src/types/factories/CCExchangeRouter__factory";
import { Lockers } from "../src/types/Lockers";
import { Lockers__factory } from "../src/types/factories/Lockers__factory";
import { TeleBTC } from "../src/types/TeleBTC";
import { TeleBTC__factory } from "../src/types/factories/TeleBTC__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";

import { takeSnapshot, revertProvider } from "./block_utils";

describe("CCExchangeRouter", async () => {

    let snapshotId: any;

    // Constants
    const ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    const ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    const DUMMY_ADDRESS = "XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
    const CHAIN_ID = 1;
    const APP_ID = 1;
    const PROTOCOL_PERCENTAGE_FEE = 10; // Means %0.1
    const LOCKER_PERCENTAGE_FEE = 20; // Means %0.2
    const STARTING_BLOCK_NUMBER = 0;

    // Bitcoin public key (32 bytes)
    let TELEPORTER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
    let TELEPORTER1_PublicKeyHash = '0x4062c8aeed4f81c2d73ff854a2957021191e20b6';
    // let TELEPORTER2 = '0x03dbc6764b8884a92e871274b87583e6d5c2a58819473e17e107ef3f6aa5a61626';
    // let TELEPORTER2_PublicKeyHash = '0x41fb108446d66d1c049e30cc7c3044e7374e9856';
    let REQUIRED_LOCKED_AMOUNT =  1000; // amount of required TDT

    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000);
    let requiredTDTLockedAmount = BigNumber.from(10).pow(18).mul(500);
    let minRequiredNativeTokenLockedAmount = BigNumber.from(10).pow(18).mul(5);
    let btcAmountToSlash = BigNumber.from(10).pow(8).mul(1)
    let collateralRatio = 20000;
    let liquidationRatio = 15000;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let locker: Signer;
    let deployerAddress: string;
    let signer1Address: string;
    let lockerAddress: string;

    // Contracts
    let exchangeConnector: UniswapV2Connector;
    let uniswapV2Router02: UniswapV2Router02;
    let uniswapV2Pair: UniswapV2Pair;
    let uniswapV2Factory: UniswapV2Factory;
    let ccExchangeRouter: CCExchangeRouter;
    let lockers: Lockers;
    let teleBTC: TeleBTC;
    let teleportDAOToken: ERC20;
    let exchangeToken: ERC20;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockInstantRouter: MockContract;
    let mockPriceOracle: MockContract;

    //
    let uniswapV2Pair__factory: UniswapV2Pair__factory;

    before(async () => {
        // Sets accounts
        [deployer, signer1, locker] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();
        lockerAddress = await locker.getAddress();

        teleportDAOToken = await deployTelePortDaoToken();

        // Mocks relay contract
        const bitcoinRelayContract = await deployments.getArtifact(
            "IBitcoinRelay"
        );
        mockBitcoinRelay = await deployMockContract(
            deployer,
            bitcoinRelayContract.abi
        );

        const priceOracleContract = await deployments.getArtifact(
            "IPriceOracle"
        );
        mockPriceOracle = await deployMockContract(
            deployer,
            priceOracleContract.abi
        );

        await mockPriceOracle.mock.equivalentOutputAmount.returns(100000)

        // Mocks checkTxProof of bitcoinRelay
        // We don't pass arguments since the request was modified and the txId is not valid
        await mockBitcoinRelay.mock.getBlockHeaderFee.returns(0); // Fee of relay
        await mockBitcoinRelay.mock.checkTxProof.returns(true);


        // Mocks instant router contract
        const instantRouterContract = await deployments.getArtifact(
            "IInstantRouter"
        );
        mockInstantRouter = await deployMockContract(
            deployer,
            instantRouterContract.abi
        );

        await mockInstantRouter.mock.payBackLoan.returns(true);

        lockers = await deployLocker()

        // Deploys teleBTC contract
        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "teleBTC",
            ONE_ADDRESS,
            ONE_ADDRESS,
            ONE_ADDRESS
        );

        // Deploys uniswapV2Factory
        const uniswapV2FactoryFactory = new UniswapV2Factory__factory(deployer);
        uniswapV2Factory = await uniswapV2FactoryFactory.deploy(
            deployerAddress
        );

        // Creates uniswapV2Pair__factory object
        uniswapV2Pair__factory = new UniswapV2Pair__factory(deployer);

        // Deploys uniswapV2Router02 contract
        const uniswapV2Router02Factory = new UniswapV2Router02__factory(deployer);
        uniswapV2Router02 = await uniswapV2Router02Factory.deploy(
            uniswapV2Factory.address,
            ZERO_ADDRESS // WETH
        );

        const exchangeConnectorFactory = new UniswapV2Connector__factory(deployer);
        exchangeConnector = await exchangeConnectorFactory.deploy(
            "TheExchangeConnector",
            uniswapV2Router02.address,
            ZERO_ADDRESS // WETH
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
            STARTING_BLOCK_NUMBER,
            PROTOCOL_PERCENTAGE_FEE,
            CHAIN_ID,
            lockers.address,
            mockBitcoinRelay.address,
            teleBTC.address,
            ONE_ADDRESS
        );

        // Sets teleBTC address in ccExchangeRouter
        // await ccExchangeRouter.setWrappedBitcoin(teleBTC.address);

        // Sets exchangeConnector address in ccExchangeRouter
        await ccExchangeRouter.setExchangeConnector(APP_ID, exchangeConnector.address);

        await teleBTC.setCCExchangeRouter(ccExchangeRouter.address);

        await lockers.setTeleBTC(teleBTC.address)
        await lockers.addMinter(ccExchangeRouter.address)

        await teleBTC.addMinter(lockers.address)
        await teleBTC.addBurner(lockers.address)

        await ccExchangeRouter.setLockers(lockers.address)
        await ccExchangeRouter.setInstantRouter(mockInstantRouter.address)
    });

    const deployTelePortDaoToken = async (
        _signer?: Signer
    ): Promise<ERC20> => {
        const erc20Factory = new ERC20__factory(
            _signer || deployer
        );

        const teleportDAOToken = await erc20Factory.deploy(
            "TelePortDAOToken",
            "TDT",
            telePortTokenInitialSupply
        );

        return teleportDAOToken;
    };

    const deployLocker = async (
        _signer?: Signer
    ): Promise<Lockers> => {
        const lockerFactory = new Lockers__factory(
            _signer || deployer
        );

        const lockers = await lockerFactory.deploy(
            teleportDAOToken.address,
            ONE_ADDRESS,
            mockPriceOracle.address,
            requiredTDTLockedAmount,
            0,
            collateralRatio,
            liquidationRatio,
            LOCKER_PERCENTAGE_FEE
        );

        return lockers;
    };

    async function addALockerToLockers(): Promise<void> {

        await teleportDAOToken.transfer(lockerAddress, requiredTDTLockedAmount)

        let teleportDAOTokenlocker = teleportDAOToken.connect(locker)

        await teleportDAOTokenlocker.approve(lockers.address, requiredTDTLockedAmount)

        let lockerlocker = lockers.connect(locker)

        await lockerlocker.requestToBecomeLocker(
            TELEPORTER1,
            // TELEPORTER1_PublicKeyHash,
            CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient,
            requiredTDTLockedAmount,
            minRequiredNativeTokenLockedAmount,
            {value: minRequiredNativeTokenLockedAmount}
        )

        await lockers.addLocker(lockerAddress)
    }

    describe("#ccExchange", async () => {
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

            // Calculates fees
            let lockerFee = Math.floor(request.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000);
            let teleporterFee = Math.floor(request.bitcoinAmount*request.teleporterFee/100);
            let protocolFee = Math.floor(request.bitcoinAmount*PROTOCOL_PERCENTAGE_FEE/10000);

            // Checks enough teleBTC has been minted for user
            expect(newUserBalanceTeleBTC).to.equal(
                oldUserBalanceTeleBTC.add(
                    request.bitcoinAmount - lockerFee - teleporterFee - protocolFee
                )
            );

            // Checks that enough teleBTC has been minted for teleporter
            expect(newDeployerBalanceTeleBTC).to.equal(
                oldDeployerBalanceTeleBTC.add(request.bitcoinAmount * request.teleporterFee / 100)
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
            await teleBTC.approve(uniswapV2Router02.address, 10000);
            await exchangeToken.approve(uniswapV2Router02.address, 10000);
            let addedLiquidityA = 10000;
            let addedLiquidityB = 10000;

            await uniswapV2Router02.addLiquidity(
                teleBTC.address,
                exchangeToken.address,
                addedLiquidityA,
                addedLiquidityB,
                0, // Minimum added liquidity for first token
                0, // Minimum added liquidity for second token
                deployerAddress,
                1000000000000000, // Long deadline
            );

            let liquidityPoolAddress = await uniswapV2Factory.getPair(
                teleBTC.address,
                exchangeToken.address
            );

            // Records total supply of teleBTC
            oldTotalSupplyTeleBTC = await teleBTC.totalSupply();

            // Loads teleBTC-TDT liquidity pool
            uniswapV2Pair = await uniswapV2Pair__factory.attach(liquidityPoolAddress);

            // Records current reserves of teleBTC and TDT
            if (await uniswapV2Pair.token0() == teleBTC.address) {
                [oldReserveTeleBTC, oldReserveExchangeToken] = await uniswapV2Pair.getReserves();
            } else {
                [oldReserveExchangeToken, oldReserveTeleBTC] = await uniswapV2Pair.getReserves()
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


            await addALockerToLockers()
        });

        afterEach(async () => {
            // Reverts the state to the before of adding liquidity
            await revertProvider(deployer.provider, snapshotId);
        });

        it("mints and exchanges teleBTC for desired exchange token (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            // await mockLockers.mock.redeemScriptHash.returns(
            //     CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient
            // );

            // Finds expected output amount that user receives
            let expectedOutputAmount = await uniswapV2Router02.getAmountOut(
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
                    CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient,
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

            // Checks extra teleBTC hasn't been minted
            expect(newTotalSupplyTeleBTC).to.equal(
                oldTotalSupplyTeleBTC.add(CC_EXCHANGE_REQUESTS.normalCCExchange.bitcoinAmount)
            );

            // Checks that enough teleBTC has been minted for teleporter
            expect(newDeployerBalanceTeleBTC).to.equal(
                oldDeployerBalanceTeleBTC.add(CC_EXCHANGE_REQUESTS.normalCCExchange.bitcoinAmount * CC_EXCHANGE_REQUESTS.normalCCExchange.teleporterFee / 100)
            );

            // FIXME: make modifications on the code to fix this expect
            // Checks that user received enough TDT
            // expect(newUserBalanceTDT).to.equal(
            //     oldUserBalanceTDT.add(expectedOutputAmount)
            // );

            // Checks that user teleBTC balance and deployer TDT balance hasn't changed
            expect(newUserBalanceTeleBTC).to.equal(
                oldUserBalanceTeleBTC
            );

            expect(newDeployerBalanceTDT).to.equal(
                oldDeployerBalanceTDT
            );
            // expects z teleBTC has been minted for protocol
            // expects a teleBTC has been minted for lockers
        })

        it("mints teleBTC since deadline has passed (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            // await mockLockers.mock.redeemScriptHash.returns(
            //     CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.desiredRecipient
            // );

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
                    CC_EXCHANGE_REQUESTS.normalCCExchangeExpired.desiredRecipient,
                )
            ).to.emit(teleBTC, 'Transfer').and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            expect(await checksWhenExchangeFails(CC_EXCHANGE_REQUESTS.normalCCExchangeExpired)).to.equal(true);

            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for lockers
        })

        it("mints teleBTC since output amount is less than minimum expected amount (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            // await mockLockers.mock.redeemScriptHash.returns(
            //     CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.desiredRecipient
            // );

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
                    CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.desiredRecipient,
                )
            ).to.emit(teleBTC, 'Transfer').and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            expect(await checksWhenExchangeFails(CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage)).to.equal(true);

            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for lockers
        })

        it("mints teleBTC since exchange token doesn't exist (normal cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            // await mockLockers.mock.redeemScriptHash.returns(
            //     CC_EXCHANGE_REQUESTS.normalCCExchangeHighSlippage.desiredRecipient
            // );

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
                    CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken.desiredRecipient,
                )
            ).to.emit(teleBTC, 'Transfer').and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            expect(await checksWhenExchangeFails(CC_EXCHANGE_REQUESTS.normalCCExchangeWrongToken)).to.equal(true);

            // expects x teleBTC has been minted for instant pool
            // expects y teleBTC has been minted for teleporter
            // expects z teleBTC has been minted for user
            // expects a teleBTC has been minted for protocol
            // expects b teleBTC has been minted for lockers
        })

        it("reverts if the request has been used before", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            // await mockLockers.mock.redeemScriptHash.returns(
            //     CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient
            // );

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
                CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient,
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
                    CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient,
                )
            ).to.revertedWith("CCExchangeRouter: the request has been used before");

        })

        it("mints and exchanges teleBTC for desired exchange token (instant cc exchange request)", async function () {
            // Mocks reedemScriptHash of bitcoinTeleporter
            // await mockLockers.mock.redeemScriptHash.returns(
            //     CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient
            // );

            // Finds expected output amount that user receives
            let expectedOutputAmount = await uniswapV2Router02.getAmountOut(
                CC_EXCHANGE_REQUESTS.instantCCExchange.bitcoinAmount -
                CC_EXCHANGE_REQUESTS.instantCCExchange.teleporterFee,
                oldReserveTeleBTC,
                oldReserveExchangeToken
            );

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.instantCCExchange.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Mints and exchanges teleBTC for TDT
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.instantCCExchange.version,
                    CC_EXCHANGE_REQUESTS.instantCCExchange.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.instantCCExchange.locktime,
                    CC_EXCHANGE_REQUESTS.instantCCExchange.blockNumber,
                    CC_EXCHANGE_REQUESTS.instantCCExchange.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.instantCCExchange.index,
                    // false // payWithTDT
                    CC_EXCHANGE_REQUESTS.instantCCExchange.desiredRecipient,
                )
            ).to.emit(ccExchangeRouter, 'CCExchange');

            // Records new supply of teleBTC
            let newTotalSupplyTeleBTC = await teleBTC.totalSupply();

            // Records new teleBTC and TDT balances of user and teleporter
            let newUserBalanceTeleBTC = await teleBTC.balanceOf(
                CC_EXCHANGE_REQUESTS.instantCCExchange.recipientAddress
            );
            let newDeployerBalanceTeleBTC = await teleBTC.balanceOf(deployerAddress);
            let newUserBalanceTDT = await exchangeToken.balanceOf(
                CC_EXCHANGE_REQUESTS.instantCCExchange.recipientAddress
            );
            let newDeployerBalanceTDT = await exchangeToken.balanceOf(deployerAddress);

            // Checks extra teleBTC hasn't been minted
            expect(newTotalSupplyTeleBTC).to.equal(
                oldTotalSupplyTeleBTC.add(CC_EXCHANGE_REQUESTS.instantCCExchange.bitcoinAmount)
            );

            // Checks that enough teleBTC has been minted for teleporter
            expect(newDeployerBalanceTeleBTC).to.equal(
                oldDeployerBalanceTeleBTC.add(CC_EXCHANGE_REQUESTS.instantCCExchange.bitcoinAmount * CC_EXCHANGE_REQUESTS.instantCCExchange.teleporterFee / 100)
            );
        })

        // TODO: this test doesn't passed because now fee is percentage not absolute value, then make a new test
        // it("reverts if teleporter fee is greater than bitcoin amount", async function () {
        //     // Mocks reedemScriptHash of bitcoinTeleporter
        //     await mockLockers.mock.redeemScriptHash.returns(
        //         CC_EXCHANGE_REQUESTS.normalCCExchange.desiredRecipient
        //     );

        //     // Reverts since the request has been used before
        //     await expect(
        //         ccExchangeRouter.ccExchange(
        //             CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.version,
        //             CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.vin,
        //             CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.vout,
        //             CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.locktime,
        //             CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.blockNumber,
        //             CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.intermediateNodes,
        //             CC_EXCHANGE_REQUESTS.normalCCExchangeHighFee.index,
        //             // false // payWithTDT
        //         )
        //     ).to.revertedWith("");
        //     // ).to.revertedWith("CCExchangeRouter: request is transfer request");

        // })

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
