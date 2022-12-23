const CC_EXCHANGE_REQUESTS = require('./test_fixtures/ccExchangeRequests.json');
require('dotenv').config({path:"../../.env"});

import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, Contract } from "ethers";
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

import { LockersProxy__factory } from "../src/types/factories/LockersProxy__factory";
import { LockersLogic__factory } from "../src/types/factories/LockersLogic__factory";
import { LockersLogicLibraryAddresses } from "../src/types/factories/LockersLogic__factory";

import { LockersLib } from "../src/types/LockersLib";
import { LockersLib__factory } from "../src/types/factories/LockersLib__factory";

import { TeleBTC } from "../src/types/TeleBTC";
import { TeleBTC__factory } from "../src/types/factories/TeleBTC__factory";
import { ERC20AsDot } from "../src/types/ERC20AsDot";
import { ERC20AsDot__factory } from "../src/types/factories/ERC20AsDot__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";
import { WETH } from "../src/types/WETH";
import { WETH__factory } from "../src/types/factories/WETH__factory";

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
    const PRICE_WITH_DISCOUNT_RATIO = 9500; // Means %95
    const INACTIVATION_DELAY = 0
    const STARTING_BLOCK_NUMBER = 1;
    const TREASURY = "0x0000000000000000000000000000000000000002";

    // Bitcoin public key (32 bytes)
    let LOCKER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
    let LOCKER1_LOCKING_SCRIPT = '0xa9144062c8aeed4f81c2d73ff854a2957021191e20b687';

    let LOCKER_RESCUE_SCRIPT_P2PKH = "0x12ab8dc588ca9d5787dde7eb29569da63c3a238c";
    let LOCKER_RESCUE_SCRIPT_P2PKH_TYPE = 1; // P2PKH

    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000);
    let minRequiredTDTLockedAmount = BigNumber.from(10).pow(18).mul(500);
    let minRequiredNativeTokenLockedAmount = BigNumber.from(10).pow(18).mul(5);
    let collateralRatio = 20000;
    let liquidationRatio = 15000;

    // Accounts
    let proxyAdmin: Signer;
    let deployer: Signer;
    let signer1: Signer;
    let locker: Signer;
    let proxyAdminAddress: string;
    let deployerAddress: string;
    let lockerAddress: string;

    // Contracts
    let exchangeConnector: UniswapV2Connector;
    let uniswapV2Router02: UniswapV2Router02;
    let uniswapV2Pair: UniswapV2Pair;
    let uniswapV2Factory: UniswapV2Factory;
    let ccExchangeRouter: CCExchangeRouter;
    let lockersLib: LockersLib;
    let lockers: Contract;
    let teleBTC: TeleBTC;
    let teleportDAOToken: ERC20;
    let exchangeToken: ERC20;
    let anotherExchangeToken: ERC20;
    let weth: WETH;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockInstantRouter: MockContract;
    let mockPriceOracle: MockContract;

    //
    let uniswapV2Pair__factory: UniswapV2Pair__factory;

    before(async () => {
        // Sets accounts
        [proxyAdmin, deployer, signer1, locker] = await ethers.getSigners();
        proxyAdminAddress = await proxyAdmin.getAddress();
        deployerAddress = await deployer.getAddress();
        lockerAddress = await locker.getAddress();

        teleportDAOToken = await deployTeleportDAOToken();

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

        // Deploys teleBTC contract
        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "TeleportDAO-BTC",
            "teleBTC"
        );

        // Deploys WETH contract
        const wethFactory = new WETH__factory(deployer);
        weth = await wethFactory.deploy(
            "WrappedEthereum",
            "WETH"
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
            weth.address // WETH
        );

        // Deploys uniswap connector
        const exchangeConnectorFactory = new UniswapV2Connector__factory(deployer);
        exchangeConnector = await exchangeConnectorFactory.deploy(
            "TheExchangeConnector",
            uniswapV2Router02.address
        );

        // Deploys exchange token
        // We replace the exchangeToken address in ccExchangeRequests
        const erc20Factory = new ERC20AsDot__factory(deployer);
        exchangeToken = await erc20Factory.deploy(
            "TestToken",
            "TT",
            100000
        );

        // Deploys an ERC20 token
        anotherExchangeToken = await erc20Factory.deploy(
            "AnotherTestToken",
            "ATT",
            100000
        );

        lockers = await deployLockers();

        // Deploys ccExchangeRouter contract
        const ccExchangeRouterFactory = new CCExchangeRouter__factory(deployer);
        ccExchangeRouter = await ccExchangeRouterFactory.deploy(
            STARTING_BLOCK_NUMBER,
            PROTOCOL_PERCENTAGE_FEE,
            CHAIN_ID,
            lockers.address,
            mockBitcoinRelay.address,
            teleBTC.address,
            TREASURY
        );

        // Sets exchangeConnector address in ccExchangeRouter
        await ccExchangeRouter.setExchangeConnector(APP_ID, exchangeConnector.address);


        await lockers.setTeleBTC(teleBTC.address)
        await lockers.addMinter(ccExchangeRouter.address)

        await teleBTC.addMinter(lockers.address)
        await teleBTC.addBurner(lockers.address)

        await ccExchangeRouter.setLockers(lockers.address)
        await ccExchangeRouter.setInstantRouter(mockInstantRouter.address)
    });

    const deployTeleportDAOToken = async (
        _signer?: Signer
    ): Promise<ERC20> => {
        const erc20Factory = new ERC20AsDot__factory(
            _signer || deployer
        );

        const teleportDAOToken = await erc20Factory.deploy(
            "TeleportDAOToken",
            "TDT",
            telePortTokenInitialSupply
        );

        return teleportDAOToken;
    };

    const deployLockersLib = async (
        _signer?: Signer
    ): Promise<LockersLib> => {
        const LockersLibFactory = new LockersLib__factory(
            _signer || deployer
        );

        const lockersLib = await LockersLibFactory.deploy(
        );

        return lockersLib;
    };

    const deployLockers = async (
        _signer?: Signer
    ): Promise<Contract> => {

        lockersLib = await deployLockersLib()

        let linkLibraryAddresses: LockersLogicLibraryAddresses;

        linkLibraryAddresses = {
            "contracts/libraries/LockersLib.sol:LockersLib": lockersLib.address,
        };

        // Deploys lockers logic
        const lockersLogicFactory = new LockersLogic__factory(
            linkLibraryAddresses,
            _signer || deployer
        );

        const lockersLogic = await lockersLogicFactory.deploy();

        // Deploys lockers proxy
        const lockersProxyFactory = new LockersProxy__factory(
            _signer || deployer
        );
        const lockersProxy = await lockersProxyFactory.deploy(
            lockersLogic.address,
            proxyAdminAddress,
            "0x"
        )

        const lockers = await lockersLogic.attach(
            lockersProxy.address
        );

        // Initializes lockers proxy
        await lockers.initialize(
            teleBTC.address,
            teleportDAOToken.address,
            ONE_ADDRESS,
            mockPriceOracle.address,
            ONE_ADDRESS,
            minRequiredTDTLockedAmount,
            0,
            collateralRatio,
            liquidationRatio,
            LOCKER_PERCENTAGE_FEE,
            PRICE_WITH_DISCOUNT_RATIO,
            INACTIVATION_DELAY
        )

        return lockers;
    };

    async function addLockerToLockers(): Promise<void> {

        await teleportDAOToken.transfer(lockerAddress, minRequiredTDTLockedAmount)

        let teleportDAOTokenlocker = teleportDAOToken.connect(locker)

        await teleportDAOTokenlocker.approve(lockers.address, minRequiredTDTLockedAmount)

        let lockerlocker = lockers.connect(locker)

        await lockerlocker.requestToBecomeLocker(
            LOCKER1_LOCKING_SCRIPT,
            minRequiredTDTLockedAmount,
            minRequiredNativeTokenLockedAmount,
            LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
            LOCKER_RESCUE_SCRIPT_P2PKH,
            {value: minRequiredNativeTokenLockedAmount}
        )

        await lockers.addLocker(lockerAddress)
    }

    describe("#ccExchange", async () => {
        let oldReserveTeleBTC: BigNumber;
        let oldReserveTT: BigNumber;
        let oldDeployerBalanceTeleBTC: BigNumber;
        let oldUserBalanceTeleBTC: BigNumber;
        let oldDeployerBalanceTT: BigNumber;
        let oldUserBalanceTT: BigNumber;
        let oldTotalSupplyTeleBTC: BigNumber;

        function calculateFees(request: any): [number, number, number] {
            // Calculates fees
            let lockerFee = Math.floor(
                request.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000
            );
            let teleporterFee = Math.floor(
                request.bitcoinAmount*
                request.teleporterFee/10000
            );
            let protocolFee = Math.floor(
                request.bitcoinAmount*PROTOCOL_PERCENTAGE_FEE/10000
            );

            return[lockerFee, teleporterFee, protocolFee]
        }

        async function checksWhenExchangeSucceed(
            _exchangeToken: any,
            isFixedToken: boolean,
            recipientAddress: string,
            bitcoinAmount: number,
            teleporterFee: number,
            protocolFee: number,
            lockerFee: number,
            expectedOutputAmount: number,
            requiredInputAmount?: number
        ) {
            // General checks

            // Records new supply of teleBTC
            let newTotalSupplyTeleBTC = await teleBTC.totalSupply();

            // Records new teleBTC and TT balances of user
            let newUserBalanceTeleBTC = await teleBTC.balanceOf(
                recipientAddress
            );
            let newUserBalanceTT = await _exchangeToken.balanceOf(
                recipientAddress
            );

            // Records new teleBTC and TDT balances of teleporter
            let newDeployerBalanceTeleBTC = await teleBTC.balanceOf(deployerAddress);
            let newDeployerBalanceTT = await _exchangeToken.balanceOf(deployerAddress);

            // Checks that extra teleBTC hasn't been minted
            expect(newTotalSupplyTeleBTC).to.equal(
                oldTotalSupplyTeleBTC.add(bitcoinAmount)
            );

            // Checks that enough teleBTC has been minted for teleporter
            expect(newDeployerBalanceTeleBTC).to.equal(
                oldDeployerBalanceTeleBTC.add(teleporterFee)
            );

            // Checks that teleporter TT balance hasn't changed
            expect(newDeployerBalanceTT).to.equal(
                oldDeployerBalanceTT
            );

            // Checks that correct amount of teleBTC has been minted for protocol
            expect(
                await teleBTC.balanceOf(TREASURY)
            ).to.equal(protocolFee);

            // Checks that correct amount of teleBTC has been minted for locker
            expect(
                await teleBTC.balanceOf(lockerAddress)
            ).to.equal(lockerFee);

            // Checks that user received enough TT
            expect(newUserBalanceTT).to.equal(
                oldUserBalanceTT.add(expectedOutputAmount)
            );

            if (isFixedToken == true) {
                // Checks that user teleBTC balance hasn't changed
                expect(newUserBalanceTeleBTC).to.equal(
                    oldUserBalanceTeleBTC
                );
            } else {
                // Checks that user received unused teleBTC
                if (requiredInputAmount != undefined) {
                    expect(newUserBalanceTeleBTC).to.equal(
                        oldUserBalanceTeleBTC.toNumber() +
                        bitcoinAmount -
                        teleporterFee -
                        lockerFee -
                        protocolFee -
                        requiredInputAmount
                    );
                }
            }
        }

        async function checksWhenExchangeFails(
            recipientAddress: string,
            bitcoinAmount: number,
            teleporterFee: number,
            protocolFee: number,
            lockerFee: number
        ) {
            // Records new supply of teleBTC
            let newTotalSupplyTeleBTC = await teleBTC.totalSupply();

            // Records new teleBTC and TDT balances of user
            let newUserBalanceTeleBTC = await teleBTC.balanceOf(
                recipientAddress
            );
            let newUserBalanceTT = await exchangeToken.balanceOf(
                recipientAddress
            );

            // Records new teleBTC and TDT balances of teleporter
            let newDeployerBalanceTeleBTC = await teleBTC.balanceOf(deployerAddress);
            let newDeployerBalanceTT = await exchangeToken.balanceOf(deployerAddress);

            // Checks enough teleBTC has been minted for user
            expect(newUserBalanceTeleBTC).to.equal(
                oldUserBalanceTeleBTC.add(
                    bitcoinAmount - lockerFee - teleporterFee - protocolFee
                )
            );

            // Checks that enough teleBTC has been minted for teleporter
            expect(newDeployerBalanceTeleBTC).to.equal(
                oldDeployerBalanceTeleBTC.add(teleporterFee)
            );

            // Checks that user TT balance hasn't changed
            expect(newUserBalanceTT).to.equal(
                oldUserBalanceTT
            );

            // Checks that correct amount of teleBTC has been minted for protocol
            expect(
                await teleBTC.balanceOf(TREASURY)
            ).to.equal(protocolFee);

            // Checks that correct amount of teleBTC has been minted for locker
            expect(
                await teleBTC.balanceOf(lockerAddress)
            ).to.equal(lockerFee);

            // Checks extra teleBTC hasn't been minted
            expect(newTotalSupplyTeleBTC).to.equal(
                oldTotalSupplyTeleBTC.add(bitcoinAmount)
            );
        }

        beforeEach("Adds liquidity to liquidity pool", async () => {
            // Takes snapshot before adding liquidity
            snapshotId = await takeSnapshot(deployer.provider);

            // Adds liquidity to teleBTC-TDT liquidity pool
            await teleBTC.addMinter(deployerAddress)
            await teleBTC.mint(deployerAddress, 10000000000);
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

            // Creates liquidity pool of TeleBTC-WETH and adds liquidity in it
            await teleBTC.approve(uniswapV2Router02.address, 10000);
            await uniswapV2Router02.addLiquidityETH(
                teleBTC.address,
                10000,
                0, // Minimum added liquidity for first token
                0, // Minimum added liquidity for second token
                deployerAddress,
                10000000000000, // Long deadline
                {value: 10000}
            );

            let liquidityPoolAddress = await uniswapV2Factory.getPair(
                teleBTC.address,
                exchangeToken.address
            );

            // Records total supply of teleBTC
            oldTotalSupplyTeleBTC = await teleBTC.totalSupply();

            // Loads teleBTC-TDT liquidity pool
            uniswapV2Pair = await uniswapV2Pair__factory.attach(liquidityPoolAddress);

            // Records current reserves of teleBTC and TT
            if (await uniswapV2Pair.token0() == teleBTC.address) {
                [oldReserveTeleBTC, oldReserveTT] = await uniswapV2Pair.getReserves();
            } else {
                [oldReserveTT, oldReserveTeleBTC] = await uniswapV2Pair.getReserves()
            }

            // Records current teleBTC and TT balances of user and teleporter
            oldUserBalanceTeleBTC = await teleBTC.balanceOf(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress
            );
            oldDeployerBalanceTeleBTC = await teleBTC.balanceOf(deployerAddress);
            oldUserBalanceTT = await exchangeToken.balanceOf(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress
            );
            oldDeployerBalanceTT = await exchangeToken.balanceOf(deployerAddress);


            await addLockerToLockers();
        });

        afterEach(async () => {
            // Reverts the state to the before of adding liquidity
            await revertProvider(deployer.provider, snapshotId);
        });

        it("Exchanges teleBTC for desired exchange token (fixed token = input)", async function () {

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Calculates fees
            let [lockerFee, teleporterFee, protocolFee] = calculateFees(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput
            );

            // Finds expected output amount that user receives (input token is fixed)
            let expectedOutputAmount = await uniswapV2Router02.getAmountOut(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount - teleporterFee - lockerFee - protocolFee,
                oldReserveTeleBTC,
                oldReserveTT
            );

            // Exchanges teleBTC for TT
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.emit(ccExchangeRouter, 'CCExchange').withArgs(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress,
                teleBTC.address,
                exchangeToken.address,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount - teleporterFee - lockerFee - protocolFee,
                expectedOutputAmount,
                0,
                deployerAddress,
                teleporterFee
            );

            await checksWhenExchangeSucceed(
                exchangeToken,
                true,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount,
                teleporterFee,
                protocolFee,
                lockerFee,
                expectedOutputAmount.toNumber()
            );
        })

        it("Exchanges teleBTC for desired exchange token (fixed token = output)", async function () {

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Calculates fees
            let [lockerFee, teleporterFee, protocolFee] = calculateFees(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput
            );

            // Finds required input amount that user receives (output token is fixed)
            let requiredInputAmount = await uniswapV2Router02.getAmountIn(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.exchangeAmount,
                oldReserveTeleBTC,
                oldReserveTT
            );

            // Exchanges teleBTC for TT
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.emit(ccExchangeRouter, 'CCExchange').withArgs(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.recipientAddress,
                teleBTC.address,
                exchangeToken.address,
                requiredInputAmount,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.exchangeAmount,
                0,
                deployerAddress,
                teleporterFee
            );

            await checksWhenExchangeSucceed(
                exchangeToken,
                false,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.bitcoinAmount,
                teleporterFee,
                protocolFee,
                lockerFee,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.exchangeAmount,
                requiredInputAmount.toNumber()
            );
        })

        it("Exchanges teleBTC for desired exchange token through wrapped native token", async function () {
            // Replaces dummy address in vout with another exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(
                DUMMY_ADDRESS,
                anotherExchangeToken.address.slice(2, anotherExchangeToken.address.length)
            );

            // Creates liquidity pool of WETH-ATT and adds liquidity in it
            await anotherExchangeToken.approve(uniswapV2Router02.address, 10000);
            await uniswapV2Router02.addLiquidityETH(
                anotherExchangeToken.address,
                10000,
                0, // Minimum added liquidity for first token
                0, // Minimum added liquidity for second token
                deployerAddress,
                10000000000000, // Long deadline
                {value: 10000}
            );
            // Calculates fees
            let [lockerFee, teleporterFee, protocolFee] = calculateFees(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput
            );

            // Finds expected output amount that user receives (input token is fixed)
            let expectedOutputAmount = await uniswapV2Router02.getAmountsOut(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount - teleporterFee - lockerFee - protocolFee,
                [teleBTC.address, weth.address, anotherExchangeToken.address]
            );

            // Exchanges teleBTC for ATT
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.emit(ccExchangeRouter, 'CCExchange').withArgs(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress,
                teleBTC.address,
                anotherExchangeToken.address,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount - teleporterFee - lockerFee - protocolFee,
                expectedOutputAmount[expectedOutputAmount.length - 1],
                0,
                deployerAddress,
                teleporterFee
            );;

            await checksWhenExchangeSucceed(
                anotherExchangeToken,
                true,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount,
                teleporterFee,
                protocolFee,
                lockerFee,
                expectedOutputAmount[expectedOutputAmount.length - 1].toNumber()
            );
        })

        it("Mints teleBTC since deadline has passed", async function () {

            // Calculates fees
            let [lockerFee, teleporterFee, protocolFee] = calculateFees(
                CC_EXCHANGE_REQUESTS.normalCCExchange_expired
            );

            // Mints teleBTC
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_expired.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_expired.vin,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_expired.vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_expired.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_expired.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_expired.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_expired.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.emit(ccExchangeRouter, 'FailedCCExchange').withArgs(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.bitcoinAmount - teleporterFee - protocolFee - lockerFee
            ).and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            await checksWhenExchangeFails(
                CC_EXCHANGE_REQUESTS.normalCCExchange_expired.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_expired.bitcoinAmount,
                teleporterFee,
                protocolFee,
                lockerFee
            );
        })

        it("Mints teleBTC since slippage is high (output amount < expected output amount)", async function () {
            // note: isFixedToken = true (input is fixed)

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Calculates fees
            let [lockerFee, teleporterFee, protocolFee] = calculateFees(
                CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage
            );

            // Mints teleBTC
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.emit(ccExchangeRouter, 'FailedCCExchange').withArgs(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.bitcoinAmount - teleporterFee - protocolFee - lockerFee
            ).and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            await checksWhenExchangeFails(
                CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_highSlippage.bitcoinAmount,
                teleporterFee,
                protocolFee,
                lockerFee
            );
        })

        it("Mints teleBTC since slippage is high (input amount < required output amount)", async function () {
            // note: isFixedToken = false (output is fixed)

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Calculates fees
            let [lockerFee, teleporterFee, protocolFee] = calculateFees(
                CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput
            );

            // Mints teleBTC
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.emit(ccExchangeRouter, 'FailedCCExchange').withArgs(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedOutput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.bitcoinAmount - teleporterFee - protocolFee - lockerFee
            ).and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            await checksWhenExchangeFails(
                CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_lowInput.bitcoinAmount,
                teleporterFee,
                protocolFee,
                lockerFee
            );
        })

        it("Mints teleBTC since exchange token doesn't exist", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, ONE_ADDRESS.slice(2, ONE_ADDRESS.length));

            // Calculates fees
            let [lockerFee, teleporterFee, protocolFee] = calculateFees(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput
            );

            // Mints teleBTC
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.emit(ccExchangeRouter, 'FailedCCExchange').withArgs(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount - teleporterFee - protocolFee - lockerFee
            ).and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            await checksWhenExchangeFails(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount,
                teleporterFee,
                protocolFee,
                lockerFee
            );
        })

        it("Mints teleBTC since exchange token is zero", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, ZERO_ADDRESS.slice(2, ZERO_ADDRESS.length));

            // Calculates fees
            let [lockerFee, teleporterFee, protocolFee] = calculateFees(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput
            );

            // Mints teleBTC
            expect(
                await ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.emit(ccExchangeRouter, 'FailedCCExchange').withArgs(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount - teleporterFee - protocolFee - lockerFee
            ).and.not.emit(ccExchangeRouter, 'CCExchange');

            // Checks needed conditions when exchange fails
            await checksWhenExchangeFails(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.recipientAddress,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.bitcoinAmount,
                teleporterFee,
                protocolFee,
                lockerFee
            );
        })

        it("Reverts since given appId doesn't exist", async function () {

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidAppId.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCExchangeRouter: app id doesn't exist");
        })

        it("Reverts if user hasn't sent BTC to locker", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCExchangeRouter: input amount is zero");
        })

        it("Reverts if locker doesn't exist", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.index,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongLocker.desiredRecipient
                )
            ).to.revertedWith("CCExchangeRouter: no locker with give script hash exists");
        })

        it("Reverts if the percentage fee is out of range [0,10000)", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_invalidFee.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidFee.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidFee.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidFee.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidFee.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidFee.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidFee.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCExchangeRouter: percentage fee is not correct");
        })

        it("Reverts if the request belongs to another chain", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_invalidChainId.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidChainId.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidChainId.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidChainId.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidChainId.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidChainId.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_invalidChainId.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.revertedWith("CCExchangeRouter: chain id is not correct");
        })

        it("Reverts if the request speed is out of range {0,1}", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_wrongSpeed.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongSpeed.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongSpeed.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongSpeed.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongSpeed.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongSpeed.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_wrongSpeed.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.revertedWith("CCExchangeRouter: speed is not correct");
        })

        it("Reverts if the request has been used before", async function () {

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            // Mints and exchanges teleBTC for exchangeToken
            await ccExchangeRouter.ccExchange(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                vout,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                LOCKER1_LOCKING_SCRIPT,
            );

            // Reverts since the request has been used before
            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.revertedWith("CCExchangeRouter: the request has been used before");

        })

        it("Reverts since request belongs to an old block header", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    STARTING_BLOCK_NUMBER - 1,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.revertedWith("CCExchangeRouter: request is too old");
        })

        it("Reverts since lock time is non-zero", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    '0x11111111',
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.revertedWith("CCExchangeRouter: lock time is non-zero");
        })

        it("Reverts if request has not been finalized yet", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await mockBitcoinRelay.mock.checkTxProof.returns(false);

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.revertedWith("CCExchangeRouter: transaction has not been finalized yet");
        })

        it("Reverts if paid fee is not sufficient", async function () {
            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            await mockBitcoinRelay.mock.getBlockHeaderFee.returns(1);

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.revertedWith("CCExchangeRouter: paid fee is not sufficient");
        })

        it("Pays back instant loan (instant cc exchange request)", async function () {

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
                    LOCKER1_LOCKING_SCRIPT
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
                oldDeployerBalanceTeleBTC.add(
                    CC_EXCHANGE_REQUESTS.instantCCExchange.bitcoinAmount*
                    CC_EXCHANGE_REQUESTS.instantCCExchange.teleporterFee/10000
                )
            );
        })
    });


    describe("#isRequestUsed", async () => {

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
            await addLockerToLockers();
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Checks if the request has been used before (unused)", async function () {
            expect(
                await ccExchangeRouter.isRequestUsed(CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.txId)
            ).to.equal(false);
        })

        it("Reverts since the request has been executed before", async function () {

            // Replaces dummy address in vout with exchange token address
            let vout = CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vout;
            vout = vout.replace(DUMMY_ADDRESS, exchangeToken.address.slice(2, exchangeToken.address.length));

            let tx = await ccExchangeRouter.ccExchange(
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                vout,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                LOCKER1_LOCKING_SCRIPT
            );

            await expect(
                ccExchangeRouter.ccExchange(
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.version,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.vin,
                    vout,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.locktime,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.blockNumber,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.intermediateNodes,
                    CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCExchangeRouter: the request has been used before");
        })

        expect(
            await ccExchangeRouter.isRequestUsed(CC_EXCHANGE_REQUESTS.normalCCExchange_fixedInput.txId)
        ).to.equal(true);

    });

    describe("#setters", async () => {

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Sets protocol percentage fee", async function () {
            await expect(
                ccExchangeRouter.setProtocolPercentageFee(100)
            ).to.emit(
                ccExchangeRouter, "NewProtocolPercentageFee"
            ).withArgs(PROTOCOL_PERCENTAGE_FEE, 100);

            expect(
                await ccExchangeRouter.protocolPercentageFee()
            ).to.equal(100);
        })

        it("Reverts since protocol percentage fee is greater than 10000", async function () {
            await expect(
                ccExchangeRouter.setProtocolPercentageFee(10001)
            ).to.revertedWith("CCExchangeRouter: fee is out of range");
        })

        it("Sets relay, lockers, instant router, teleBTC and treasury", async function () {
            await expect(
                ccExchangeRouter.setRelay(ONE_ADDRESS)
            ).to.emit(
                ccExchangeRouter, "NewRelay"
            ).withArgs(mockBitcoinRelay.address, ONE_ADDRESS);


            expect(
                await ccExchangeRouter.relay()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccExchangeRouter.setLockers(ONE_ADDRESS)
            ).to.emit(
                ccExchangeRouter, "NewLockers"
            ).withArgs(lockers.address, ONE_ADDRESS);

            expect(
                await ccExchangeRouter.lockers()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccExchangeRouter.setInstantRouter(ONE_ADDRESS)
            ).to.emit(
                ccExchangeRouter, "NewInstantRouter"
            ).withArgs(mockInstantRouter.address, ONE_ADDRESS);

            expect(
                await ccExchangeRouter.instantRouter()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccExchangeRouter.setTeleBTC(ONE_ADDRESS)
            ).to.emit(
                ccExchangeRouter, "NewTeleBTC"
            ).withArgs(teleBTC.address, ONE_ADDRESS);


            expect(
                await ccExchangeRouter.teleBTC()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccExchangeRouter.setTreasury(ONE_ADDRESS)
            ).to.emit(
                ccExchangeRouter, "NewTreasury"
            ).withArgs(TREASURY, ONE_ADDRESS);


            expect(
                await ccExchangeRouter.treasury()
            ).to.equal(ONE_ADDRESS);

        })

        it("Reverts since given address is zero", async function () {
            await expect(
                ccExchangeRouter.setRelay(ZERO_ADDRESS)
            ).to.revertedWith("CCExchangeRouter: address is zero");

            await expect(
                ccExchangeRouter.setLockers(ZERO_ADDRESS)
            ).to.revertedWith("CCExchangeRouter: address is zero");

            await expect(
                ccExchangeRouter.setInstantRouter(ZERO_ADDRESS)
            ).to.revertedWith("CCExchangeRouter: address is zero");

            await expect(
                ccExchangeRouter.setTeleBTC(ZERO_ADDRESS)
            ).to.revertedWith("CCExchangeRouter: address is zero");

            await expect(
                ccExchangeRouter.setTreasury(ZERO_ADDRESS)
            ).to.revertedWith("CCExchangeRouter: address is zero");
        })

    });
});