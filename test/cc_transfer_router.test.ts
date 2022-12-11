const CC_REQUESTS = require('./test_fixtures/ccTransferRequests.json');
require('dotenv').config({path:"../../.env"});

import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";
import { Address } from "hardhat-deploy/types";

import { CCTransferRouter } from "../src/types/CCTransferRouter";
import { CCTransferRouter__factory } from "../src/types/factories/CCTransferRouter__factory";

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

import { takeSnapshot, revertProvider } from "./block_utils";

describe("CCTransferRouter", async () => {

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000001";
    let TWO_ADDRESS = "0x0000000000000000000000000000000000000002";
    const CHAIN_ID = 1;
    const APP_ID = 0;
    const PROTOCOL_PERCENTAGE_FEE = 10; // Means %0.1
    const LOCKER_PERCENTAGE_FEE = 20; // Means %0.2
    const PRICE_WITH_DISCOUNT_RATIO = 9500; // Means %95
    const MIN_LEAVING_INTERVAL_TIMESTAMP = 0
    const STARTING_BLOCK_NUMBER = 1;
    const TREASURY = "0x0000000000000000000000000000000000000002";

    let LOCKER1_LOCKING_SCRIPT = '0xa9144062c8aeed4f81c2d73ff854a2957021191e20b687';

    let LOCKER_RESCUE_SCRIPT_P2PKH = "0x12ab8dc588ca9d5787dde7eb29569da63c3a238c";
    let LOCKER_RESCUE_SCRIPT_P2PKH_TYPE = 1; // P2PKH

    let teleportTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000);
    let minRequiredTDTLockedAmount = BigNumber.from(10).pow(18).mul(500);
    let minRequiredNativeTokenLockedAmount = BigNumber.from(10).pow(18).mul(5);
    let collateralRatio = 20000;
    let liquidationRatio = 15000;

    // Accounts
    let proxyAdmin: Signer;
    let deployer: Signer;
    let signer1: Signer;
    let locker: Signer;
    let proxyAdminAddress: Address;
    let lockerAddress: Address;

    // Contracts
    let ccTransferRouter: CCTransferRouter;
    let teleBTC: TeleBTC;
    let teleportDAOToken: ERC20;
    let lockersLib: LockersLib;
    let lockers: Contract;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockInstantRouter: MockContract;
    let mockPriceOracle: MockContract;

    let beginning: any;

    before(async () => {
        // Sets accounts
        [proxyAdmin, deployer, signer1, locker] = await ethers.getSigners();

        proxyAdminAddress = await proxyAdmin.getAddress();
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

        // Mocks price oracle contract
        const priceOracleContract = await deployments.getArtifact(
            "IPriceOracle"
        );
        mockPriceOracle = await deployMockContract(
            deployer,
            priceOracleContract.abi
        );
        // Sets equivalentOutputAmount to return 100000
        await mockPriceOracle.mock.equivalentOutputAmount.returns(100000)

        // Mocks instant router contract
        const instantRouterContract = await deployments.getArtifact(
            "IInstantRouter"
        );
        mockInstantRouter = await deployMockContract(
            deployer,
            instantRouterContract.abi
        );
        // Sets payBackLoan to return true
        await mockInstantRouter.mock.payBackLoan.returns(true);

        // Deploys ccTransferRouter contract
        const ccTransferRouterFactory = new CCTransferRouter__factory(deployer);
        ccTransferRouter = await ccTransferRouterFactory.deploy(
            STARTING_BLOCK_NUMBER,
            PROTOCOL_PERCENTAGE_FEE,
            CHAIN_ID,
            APP_ID,
            mockBitcoinRelay.address,
            ONE_ADDRESS,
            TWO_ADDRESS,
            TREASURY
        );

        // Deploys teleBTC contract
        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "TeleportDAO-BTC",
            "teleBTC"
        );

        // Set teleBTC address in ccTransferRouter
        await ccTransferRouter.setTeleBTC(teleBTC.address);

        // Deploys lockers contract
        lockers = await deployLockers();
        await lockers.setTeleBTC(teleBTC.address)
        await lockers.addMinter(ccTransferRouter.address)

        // Adds lockers contract as minter and burner in teleBTC
        await teleBTC.addMinter(lockers.address)
        await teleBTC.addBurner(lockers.address)

        await ccTransferRouter.setLockers(lockers.address)
        await ccTransferRouter.setInstantRouter(mockInstantRouter.address)
    });

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
            MIN_LEAVING_INTERVAL_TIMESTAMP
        )

        return lockers;
    };

    const deployTeleportDAOToken = async (
        _signer?: Signer
    ): Promise<ERC20> => {
        const erc20Factory = new ERC20AsDot__factory(
            _signer || deployer
        );

        const teleportDAOToken = await erc20Factory.deploy(
            "TelePortDAOToken",
            "TDT",
            teleportTokenInitialSupply
        );

        return teleportDAOToken;
    };

    async function setRelayReturn(isTrue: boolean): Promise<void> {
        await mockBitcoinRelay.mock.getBlockHeaderFee.returns(0); // Sets fee of using relay
        await mockBitcoinRelay.mock.checkTxProof.returns(isTrue); // Sets result of checking tx proof
    }

    async function addLockerToLockers(): Promise<void> {
        // Sends minRequiredTDTLockedAmount from deployer to locker
        await teleportDAOToken.transfer(lockerAddress, minRequiredTDTLockedAmount)

        let teleportDAOTokenLocker = teleportDAOToken.connect(locker)

        await teleportDAOTokenLocker.approve(lockers.address, minRequiredTDTLockedAmount)

        let lockerLocker = lockers.connect(locker)

        await lockerLocker.requestToBecomeLocker(
            // LOCKER1, // Public key of locker
            LOCKER1_LOCKING_SCRIPT, // Public key hash of locker
            minRequiredTDTLockedAmount,
            minRequiredNativeTokenLockedAmount,
            LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
            LOCKER_RESCUE_SCRIPT_P2PKH,
            {value: minRequiredNativeTokenLockedAmount}
        )

        // Deployer (owner of lockers) adds locker to lockers
        await lockers.addLocker(lockerAddress)
    }

    async function checkFees(
        recipientAddress: string,
        receivedAmount: number,
        teleporterFee: number,
        protocolFee: number,
        lockerFee: number,
        prevSupply: number,
        bitcoinAmount: number
    ): Promise<void> {
        // Checks that enough teleBTC has been minted for user
        expect(
            await teleBTC.balanceOf(recipientAddress)
        ).to.equal(receivedAmount);

        // Checks that enough teleBTC has been minted for teleporter
        expect(
            await teleBTC.balanceOf(await deployer.getAddress())
        ).to.equal(teleporterFee);

        // Checks that correct amount of teleBTC has been minted for protocol
        expect(
            await teleBTC.balanceOf(TREASURY)
        ).to.equal(protocolFee);

        // Checks that correct amount of teleBTC has been minted for locker
        expect(
            await teleBTC.balanceOf(lockerAddress)
        ).to.equal(lockerFee);

        // Checks that correct amount of teleBTC has been minted in total
        expect(
            await teleBTC.totalSupply()
        ).to.equal(prevSupply + bitcoinAmount);
    }

    describe("#ccTransfer", async () => {

        beforeEach(async () => {
            beginning = await takeSnapshot(signer1.provider);
            await addLockerToLockers();
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, beginning);
        });

        it("Mints teleBTC for normal cc transfer request (relay fee is zero)", async function () {
            let prevSupply = await teleBTC.totalSupply();
            // Mocks relay to return true after checking tx proof
            await setRelayReturn(true);

            // Calculates fees
            let lockerFee = Math.floor(
                CC_REQUESTS.normalCCTransfer.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000
            );
            let teleporterFee = Math.floor(
                CC_REQUESTS.normalCCTransfer.bitcoinAmount*CC_REQUESTS.normalCCTransfer.teleporterFee/10000
            );
            let protocolFee = Math.floor(
                CC_REQUESTS.normalCCTransfer.bitcoinAmount*PROTOCOL_PERCENTAGE_FEE/10000
            );

            // Calculates amount that user should have received
            let receivedAmount = CC_REQUESTS.normalCCTransfer.bitcoinAmount - lockerFee - teleporterFee - protocolFee;

            // Checks that ccTransfer is executed successfully
            expect(
                await ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.emit(ccTransferRouter, 'CCTransfer').withArgs(
                CC_REQUESTS.normalCCTransfer.recipientAddress,
                CC_REQUESTS.normalCCTransfer.value,
                receivedAmount,
                CC_REQUESTS.normalCCTransfer.speed,
                await deployer.getAddress(),
                teleporterFee
            );

            await checkFees(
                CC_REQUESTS.normalCCTransfer.recipientAddress,
                receivedAmount,
                teleporterFee,
                protocolFee,
                lockerFee,
                prevSupply.toNumber(),
                CC_REQUESTS.normalCCTransfer.bitcoinAmount
            );
        })

        it("Mints teleBTC for normal cc transfer request (relay fee is non-zero)", async function () {
            let prevSupply = await teleBTC.totalSupply();

            let relayFee = 1;
            let msgValue = 1;

            // Mocks relay to return true after checking tx proof
            await setRelayReturn(true);
            // Sets fee of using relay
            await mockBitcoinRelay.mock.getBlockHeaderFee.returns(relayFee);

            // Calculates fees
            let lockerFee = Math.floor(
                CC_REQUESTS.normalCCTransfer.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000
            );
            let teleporterFee = Math.floor(
                CC_REQUESTS.normalCCTransfer.bitcoinAmount*CC_REQUESTS.normalCCTransfer.teleporterFee/10000
            );
            let protocolFee = Math.floor(
                CC_REQUESTS.normalCCTransfer.bitcoinAmount*PROTOCOL_PERCENTAGE_FEE/10000
            );

            // Calculates amount that user should have received
            let receivedAmount = CC_REQUESTS.normalCCTransfer.bitcoinAmount - lockerFee - teleporterFee - protocolFee;

            // Gets deployer ETH balance before sending request
            let prevETHBalance = await deployer.getBalance();

            // Checks that ccTransfer is executed successfully

            let tx = await ccTransferRouter.ccTransfer(
                CC_REQUESTS.normalCCTransfer.version,
                CC_REQUESTS.normalCCTransfer.vin,
                CC_REQUESTS.normalCCTransfer.vout,
                CC_REQUESTS.normalCCTransfer.locktime,
                CC_REQUESTS.normalCCTransfer.blockNumber,
                CC_REQUESTS.normalCCTransfer.intermediateNodes,
                CC_REQUESTS.normalCCTransfer.index,
                LOCKER1_LOCKING_SCRIPT,
                {value: msgValue}
            );

            expect(
                tx
            ).to.emit(ccTransferRouter, 'CCTransfer').withArgs(
                CC_REQUESTS.normalCCTransfer.recipientAddress,
                CC_REQUESTS.normalCCTransfer.value,
                receivedAmount,
                CC_REQUESTS.normalCCTransfer.speed,
                await deployer.getAddress(),
                teleporterFee
            );

            // Finds tx cost
            const receipt = await tx.wait();
            const txCost = receipt.cumulativeGasUsed.mul(receipt.effectiveGasPrice);

            // Gets deployer ETH balance after sending request
            let newETHBalance = await deployer.getBalance();

            expect(
                newETHBalance
            ).to.equal(
                prevETHBalance.sub(txCost).sub(relayFee),
                "Wrong ETH balance"
            );

            await checkFees(
                CC_REQUESTS.normalCCTransfer.recipientAddress,
                receivedAmount,
                teleporterFee,
                protocolFee,
                lockerFee,
                prevSupply.toNumber(),
                CC_REQUESTS.normalCCTransfer.bitcoinAmount
            );
        })

        it("Mints teleBTC for normal cc transfer request (zero teleporter fee)", async function () {
            let prevSupply = await teleBTC.totalSupply();
            // Mocks relay to return true after checking tx proof
            await setRelayReturn(true);

            // Calculates fees
            let lockerFee = Math.floor(
                CC_REQUESTS.normalCCTransfer_zeroFee.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000
            );
            let teleporterFee = Math.floor(
                CC_REQUESTS.normalCCTransfer_zeroFee.bitcoinAmount*CC_REQUESTS.normalCCTransfer_zeroFee.teleporterFee/10000
            );
            let protocolFee = Math.floor(
                CC_REQUESTS.normalCCTransfer_zeroFee.bitcoinAmount*PROTOCOL_PERCENTAGE_FEE/10000
            );

            // Calculates amount that user should have received
            let receivedAmount = CC_REQUESTS.normalCCTransfer_zeroFee.bitcoinAmount - lockerFee - teleporterFee - protocolFee;

            // Checks that ccTransfer is executed successfully
            expect(
                await ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer_zeroFee.version,
                    CC_REQUESTS.normalCCTransfer_zeroFee.vin,
                    CC_REQUESTS.normalCCTransfer_zeroFee.vout,
                    CC_REQUESTS.normalCCTransfer_zeroFee.locktime,
                    CC_REQUESTS.normalCCTransfer_zeroFee.blockNumber,
                    CC_REQUESTS.normalCCTransfer_zeroFee.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer_zeroFee.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.emit(ccTransferRouter, 'CCTransfer').withArgs(
                CC_REQUESTS.normalCCTransfer_zeroFee.recipientAddress,
                CC_REQUESTS.normalCCTransfer_zeroFee.value,
                receivedAmount,
                CC_REQUESTS.normalCCTransfer_zeroFee.speed,
                await deployer.getAddress(),
                teleporterFee
            );

            await checkFees(
                CC_REQUESTS.normalCCTransfer_zeroFee.recipientAddress,
                receivedAmount,
                teleporterFee,
                protocolFee,
                lockerFee,
                prevSupply.toNumber(),
                CC_REQUESTS.normalCCTransfer_zeroFee.bitcoinAmount
            );
        })

        it("Mints teleBTC for normal cc transfer request (zero protocol fee)", async function () {
            let prevSupply = await teleBTC.totalSupply();

            // Sets protocol fee
            await ccTransferRouter.setProtocolPercentageFee(0);

            // Mocks relay to return true after checking tx proof
            await setRelayReturn(true);

            // Calculates fees
            let lockerFee = Math.floor(
                CC_REQUESTS.normalCCTransfer.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000
            );
            let teleporterFee = Math.floor(
                CC_REQUESTS.normalCCTransfer.bitcoinAmount*CC_REQUESTS.normalCCTransfer.teleporterFee/10000
            );
            let protocolFee = 0;

            // Calculates amount that user should have received
            let receivedAmount = CC_REQUESTS.normalCCTransfer.bitcoinAmount - lockerFee - teleporterFee - protocolFee;

            // Checks that ccTransfer is executed successfully
            expect(
                await ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    LOCKER1_LOCKING_SCRIPT,
                )
            ).to.emit(ccTransferRouter, 'CCTransfer').withArgs(
                CC_REQUESTS.normalCCTransfer.recipientAddress,
                CC_REQUESTS.normalCCTransfer.value,
                receivedAmount,
                CC_REQUESTS.normalCCTransfer.speed,
                await deployer.getAddress(),
                teleporterFee
            );

            await checkFees(
                CC_REQUESTS.normalCCTransfer.recipientAddress,
                receivedAmount,
                teleporterFee,
                protocolFee,
                lockerFee,
                prevSupply.toNumber(),
                CC_REQUESTS.normalCCTransfer.bitcoinAmount
            );
        })

        it("Reverts since request belongs to an old block header", async function () {
            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    STARTING_BLOCK_NUMBER - 1,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: request is too old");
        })

        it("Reverts if the request has been used before", async function () {
            await setRelayReturn(true);

            await ccTransferRouter.ccTransfer(
                CC_REQUESTS.normalCCTransfer.version,
                CC_REQUESTS.normalCCTransfer.vin,
                CC_REQUESTS.normalCCTransfer.vout,
                CC_REQUESTS.normalCCTransfer.locktime,
                CC_REQUESTS.normalCCTransfer.blockNumber,
                CC_REQUESTS.normalCCTransfer.intermediateNodes,
                CC_REQUESTS.normalCCTransfer.index,
                LOCKER1_LOCKING_SCRIPT,
            );

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: request has been used before");
        })

        it("Reverts if the request has not been finalized on the relay", async function () {

            // Sets relay to return false after checking tx proof
            await setRelayReturn(false);

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: transaction has not been finalized yet");
        })

        it("Reverts if the percentage fee is out of range [0,10000)", async function () {
            await setRelayReturn(true);

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer_invalidFee.version,
                    CC_REQUESTS.normalCCTransfer_invalidFee.vin,
                    CC_REQUESTS.normalCCTransfer_invalidFee.vout,
                    CC_REQUESTS.normalCCTransfer_invalidFee.locktime,
                    CC_REQUESTS.normalCCTransfer_invalidFee.blockNumber,
                    CC_REQUESTS.normalCCTransfer_invalidFee.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer_invalidFee.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: percentage fee is out of range");
        })

        it("Reverts if chain id is invalid", async function () {
            await setRelayReturn(true);

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer_invalidChainId.version,
                    CC_REQUESTS.normalCCTransfer_invalidChainId.vin,
                    CC_REQUESTS.normalCCTransfer_invalidChainId.vout,
                    CC_REQUESTS.normalCCTransfer_invalidChainId.locktime,
                    CC_REQUESTS.normalCCTransfer_invalidChainId.blockNumber,
                    CC_REQUESTS.normalCCTransfer_invalidChainId.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer_invalidChainId.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: chain id is not correct");
        })

        it("Reverts if app id is invalid", async function () {
            await setRelayReturn(true);

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer_invalidAppId.version,
                    CC_REQUESTS.normalCCTransfer_invalidAppId.vin,
                    CC_REQUESTS.normalCCTransfer_invalidAppId.vout,
                    CC_REQUESTS.normalCCTransfer_invalidAppId.locktime,
                    CC_REQUESTS.normalCCTransfer_invalidAppId.blockNumber,
                    CC_REQUESTS.normalCCTransfer_invalidAppId.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer_invalidAppId.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: app id is not correct");
        })

        it("Reverts if user sent BTC to invalid locker", async function () {
            await setRelayReturn(true);

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer_invalidLocker.version,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.vin,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.vout,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.locktime,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.blockNumber,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.index,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.desiredRecipient
                )
            ).to.revertedWith("CCTransferRouter: no locker with the given locking script exists");
        })

        it("Reverts if no BTC has been sent to locker", async function () {
            await setRelayReturn(true);

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer_invalidLocker.version,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.vin,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.vout,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.locktime,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.blockNumber,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer_invalidLocker.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: input amount is zero");
        })

        it("Reverts if speed is wrong", async function () {
            await setRelayReturn(true);

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer_invalidSpeed.version,
                    CC_REQUESTS.normalCCTransfer_invalidSpeed.vin,
                    CC_REQUESTS.normalCCTransfer_invalidSpeed.vout,
                    CC_REQUESTS.normalCCTransfer_invalidSpeed.locktime,
                    CC_REQUESTS.normalCCTransfer_invalidSpeed.blockNumber,
                    CC_REQUESTS.normalCCTransfer_invalidSpeed.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer_invalidSpeed.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: speed is out of range");
        })

        it("Reverts if msg.value is lower than relay fee", async function () {
            await setRelayReturn(true);
            await mockBitcoinRelay.mock.getBlockHeaderFee.returns(1); // Sets fee of using relay

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: paid fee is not sufficient");
        })

        it("Mints teleBTC for instant cc transfer request", async function () {
            let prevSupply = await teleBTC.totalSupply();
            // Mocks relay to return true after checking tx proof
            await setRelayReturn(true);

            // Calculates fees
            let lockerFee = Math.floor(
                CC_REQUESTS.instantCCTransfer.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000
            );
            let teleporterFee = Math.floor(
                CC_REQUESTS.instantCCTransfer.bitcoinAmount*CC_REQUESTS.normalCCTransfer.teleporterFee/10000
            );
            let protocolFee = Math.floor(
                CC_REQUESTS.instantCCTransfer.bitcoinAmount*PROTOCOL_PERCENTAGE_FEE/10000
            );

            let receivedAmount = CC_REQUESTS.instantCCTransfer.bitcoinAmount - lockerFee - teleporterFee - protocolFee;

            expect(
                await ccTransferRouter.ccTransfer(
                    CC_REQUESTS.instantCCTransfer.version,
                    CC_REQUESTS.instantCCTransfer.vin,
                    CC_REQUESTS.instantCCTransfer.vout,
                    CC_REQUESTS.instantCCTransfer.locktime,
                    CC_REQUESTS.instantCCTransfer.blockNumber,
                    CC_REQUESTS.instantCCTransfer.intermediateNodes,
                    CC_REQUESTS.instantCCTransfer.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.emit(ccTransferRouter, 'CCTransfer').withArgs(
                CC_REQUESTS.instantCCTransfer.recipientAddress,
                CC_REQUESTS.instantCCTransfer.value,
                receivedAmount,
                CC_REQUESTS.instantCCTransfer.speed,
                await deployer.getAddress(),
                teleporterFee
            );

            // Checks that enough teleBTC allowance has been given to instant router
            expect(
                await teleBTC.allowance(ccTransferRouter.address, mockInstantRouter.address)
            ).to.equal(receivedAmount);

            // Checks that enough teleBTC has been minted for teleporter
            expect(
                await teleBTC.balanceOf(await deployer.getAddress())
            ).to.equal(teleporterFee);

            // Checks that correct amount of teleBTC has been minted for protocol
            expect(
                await teleBTC.balanceOf(TREASURY)
            ).to.equal(protocolFee);

            // Checks that correct amount of teleBTC has been minted for locker
            expect(
                await teleBTC.balanceOf(lockerAddress)
            ).to.equal(lockerFee);

            // Checks that correct amount of teleBTC has been minted in total
            expect(
                await teleBTC.totalSupply()
            ).to.equal(prevSupply + CC_REQUESTS.instantCCTransfer.bitcoinAmount)
        })

    });

    describe("#isRequestUsed", async () => {

        beforeEach(async () => {
            beginning = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, beginning);
        });

        it("Checks if the request has been used before (unused)", async function () {
            expect(
                await ccTransferRouter.isRequestUsed(CC_REQUESTS.normalCCTransfer.txId)
            ).to.equal(false);
        })

        it("Reverts since the request has been executed before", async function () {
            await setRelayReturn(true);
            await addLockerToLockers();
            await ccTransferRouter.ccTransfer(
                CC_REQUESTS.normalCCTransfer.version,
                CC_REQUESTS.normalCCTransfer.vin,
                CC_REQUESTS.normalCCTransfer.vout,
                CC_REQUESTS.normalCCTransfer.locktime,
                CC_REQUESTS.normalCCTransfer.blockNumber,
                CC_REQUESTS.normalCCTransfer.intermediateNodes,
                CC_REQUESTS.normalCCTransfer.index,
                LOCKER1_LOCKING_SCRIPT
            );

            expect(
                await ccTransferRouter.isRequestUsed(CC_REQUESTS.normalCCTransfer.txId)
            ).to.equal(true);

            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCTransferRouter: request has been used before");
        })

    });

    describe("#setters", async () => {

        beforeEach(async () => {
            beginning = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, beginning);
        });

        it("Sets protocol percentage fee", async function () {
            await expect(
                ccTransferRouter.setProtocolPercentageFee(100)
            ).to.emit(
                ccTransferRouter, "NewProtocolPercentageFee"
            ).withArgs(PROTOCOL_PERCENTAGE_FEE, 100);

            expect(
                await ccTransferRouter.protocolPercentageFee()
            ).to.equal(100);
        })

        it("Reverts since protocol percentage fee is greater than 10000", async function () {
            await expect(
                ccTransferRouter.setProtocolPercentageFee(10001)
            ).to.revertedWith("CCTransferRouter: protocol fee is out of range");
        })

        it("Sets relay, lockers, instant router, teleBTC and treasury", async function () {
            await expect(
                ccTransferRouter.setRelay(ONE_ADDRESS)
            ).to.emit(
                ccTransferRouter, "NewRelay"
            ).withArgs(mockBitcoinRelay.address, ONE_ADDRESS);


            expect(
                await ccTransferRouter.relay()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccTransferRouter.setLockers(ONE_ADDRESS)
            ).to.emit(
                ccTransferRouter, "NewLockers"
            ).withArgs(lockers.address, ONE_ADDRESS);


            expect(
                await ccTransferRouter.lockers()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccTransferRouter.setInstantRouter(ONE_ADDRESS)
            ).to.emit(
                ccTransferRouter, "NewInstantRouter"
            ).withArgs(mockInstantRouter.address, ONE_ADDRESS);


            expect(
                await ccTransferRouter.instantRouter()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccTransferRouter.setTeleBTC(ONE_ADDRESS)
            ).to.emit(
                ccTransferRouter, "NewTeleBTC"
            ).withArgs(teleBTC.address, ONE_ADDRESS);


            expect(
                await ccTransferRouter.teleBTC()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccTransferRouter.setTreasury(ONE_ADDRESS)
            ).to.emit(
                ccTransferRouter, "NewTreasury"
            ).withArgs(TREASURY, ONE_ADDRESS);


            expect(
                await ccTransferRouter.treasury()
            ).to.equal(ONE_ADDRESS);

        })

        it("Reverts since given address is zero", async function () {
            await expect(
                ccTransferRouter.setRelay(ZERO_ADDRESS)
            ).to.revertedWith("CCTransferRouter: address is zero");

            await expect(
                ccTransferRouter.setLockers(ZERO_ADDRESS)
            ).to.revertedWith("CCTransferRouter: address is zero");

            await expect(
                ccTransferRouter.setInstantRouter(ZERO_ADDRESS)
            ).to.revertedWith("CCTransferRouter: address is zero");

            await expect(
                ccTransferRouter.setTeleBTC(ZERO_ADDRESS)
            ).to.revertedWith("CCTransferRouter: address is zero");

            await expect(
                ccTransferRouter.setTreasury(ZERO_ADDRESS)
            ).to.revertedWith("CCTransferRouter: address is zero");
        })

    });
});