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

import { TeleBTC } from "../src/types/TeleBTC";
import { TeleBTC__factory } from "../src/types/factories/TeleBTC__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";

import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";

describe("CCTransferRouter", async () => {

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    const CHAIN_ID = 1;
    const APP_ID = 0;
    const PROTOCOL_PERCENTAGE_FEE = 10; // Means %0.1
    const LOCKER_PERCENTAGE_FEE = 20; // Means %0.2
    const STARTING_BLOCK_NUMBER = 0;

    // Bitcoin public key (32 bytes)
    let TELEPORTER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
    let TELEPORTER1_PublicKeyHash = '0x4062c8aeed4f81c2d73ff854a2957021191e20b6';
    // let TELEPORTER2 = '0x03dbc6764b8884a92e871274b87583e6d5c2a58819473e17e107ef3f6aa5a61626';
    // let TELEPORTER2_PublicKeyHash = '0x41fb108446d66d1c049e30cc7c3044e7374e9856';
    let REQUIRED_LOCKED_AMOUNT =  1000; // amount of required TDT

    let teleportTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000);
    let requiredTDTLockedAmount = BigNumber.from(10).pow(18).mul(500);
    let minRequiredNativeTokenLockedAmount = BigNumber.from(10).pow(18).mul(5);
    let btcAmountToSlash = BigNumber.from(10).pow(8).mul(1)
    let collateralRatio = 20000;
    let liquidationRatio = 15000;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let locker: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;
    let lockerAddress: Address;

    // Contracts
    let ccTransferRouter: CCTransferRouter;
    let teleBTC: TeleBTC;
    let teleportDAOToken: ERC20;
    // let lockers: Lockers;
    let lockers: Contract;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockInstantRouter: MockContract;
    let mockPriceOracle: MockContract;

    let beginning: any;

    before(async () => {
        // Sets accounts
        [deployer, signer1, locker] = await ethers.getSigners();

        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();
        lockerAddress = await locker.getAddress();

        teleportDAOToken = await deployTeleportDaoToken();

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

        // Mocks instant router contract
        const instantRouterContract = await deployments.getArtifact(
            "IInstantRouter"
        );
        mockInstantRouter = await deployMockContract(
            deployer,
            instantRouterContract.abi
        );

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
            ZERO_ADDRESS,
            ONE_ADDRESS // Treasury address
        );

        // Deploys teleBTC contract
        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "teleBTC",
            ccTransferRouter.address,
            ONE_ADDRESS,
            ONE_ADDRESS
        );

        // Set teleBTC address in ccTransferRouter
        await ccTransferRouter.setTeleBTC(teleBTC.address);

        await teleBTC.setCCTransferRouter(ccTransferRouter.address)


        // lockers = await deployLocker()
        lockers = await deployLockers();

        await lockers.setTeleBTC(teleBTC.address)
        await lockers.addMinter(ccTransferRouter.address)

        await teleBTC.addMinter(lockers.address)
        await teleBTC.addBurner(lockers.address)

        await ccTransferRouter.setLockers(lockers.address)
        await ccTransferRouter.setInstantRouter(mockInstantRouter.address)
    });

    const deployLockers = async (
        _signer?: Signer
    ): Promise<Contract> => {

        // Deploys lockers logic
        const lockersLogicFactory = new LockersLogic__factory(
            _signer || deployer
        );
        const lockersLogic = await lockersLogicFactory.deploy();
        
        // Deploys lockers proxy
        const lockersProxyFactory = new LockersProxy__factory(
            _signer || deployer
        );
        const lockersProxy = await lockersProxyFactory.deploy(
            lockersLogic.address
        )
        
        // Initializes lockers proxy
        await lockersProxy.initialize(
            teleportDAOToken.address,
            ONE_ADDRESS,
            mockPriceOracle.address,
            requiredTDTLockedAmount,
            0,
            collateralRatio,
            liquidationRatio,
            LOCKER_PERCENTAGE_FEE
        )

        const lockers = await lockersLogic.attach(
            lockersProxy.address
        );

        return lockers;
    };

    const deployTeleportDaoToken = async (
        _signer?: Signer
    ): Promise<ERC20> => {
        const erc20Factory = new ERC20__factory(
            _signer || deployer
        );

        const teleportDAOToken = await erc20Factory.deploy(
            "TelePortDAOToken",
            "TDT",
            teleportTokenInitialSupply
        );

        return teleportDAOToken;
    };

    async function setRelayReturn(request: any, isTrue: boolean): Promise<void> {
        await mockBitcoinRelay.mock.getBlockHeaderFee.returns(0); // Fee of relay
        await mockBitcoinRelay.mock.checkTxProof.returns(isTrue); // Result of check tx proof
    }

    async function addALockerToLockers(): Promise<void> {

        await teleportDAOToken.transfer(lockerAddress, requiredTDTLockedAmount)

        let teleportDAOTokenlocker = teleportDAOToken.connect(locker)

        await teleportDAOTokenlocker.approve(lockers.address, requiredTDTLockedAmount)

        let lockerlocker = lockers.connect(locker)

        await lockerlocker.requestToBecomeLocker(
            TELEPORTER1,
            // TELEPORTER1_PublicKeyHash,
            CC_REQUESTS.normalCCTransfer.desiredRecipient,
            requiredTDTLockedAmount,
            minRequiredNativeTokenLockedAmount,
            {value: minRequiredNativeTokenLockedAmount}
        )

        await lockers.addLocker(lockerAddress)
    }

    describe("#ccTransfer", async () => {
        it("mints teleBTC for normal cc transfer request", async function () {
            beginning = await takeSnapshot(signer1.provider);
            let prevSupply = await teleBTC.totalSupply();
            // Mocking that relay returns true for our request
            await setRelayReturn(CC_REQUESTS.normalCCTransfer, true);

            await addALockerToLockers();
            // Mocking that lockers returns the Lockers address on Bitcoin
            // await setLockersReturn(CC_REQUESTS.normalCCTransfer);
            // Check that ccTransfer performs successfully when everything is valid
            expect(
                await ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    // false // payWithTDT
                    // TELEPORTER1_PublicKeyHash
                    CC_REQUESTS.normalCCTransfer.desiredRecipient,
                )
            ).to.emit(ccTransferRouter, 'CCTransfer');

            // Calculates fees
            let lockerFee = Math.floor(CC_REQUESTS.normalCCTransfer.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000);
            let teleporterFee = Math.floor(CC_REQUESTS.normalCCTransfer.bitcoinAmount*CC_REQUESTS.normalCCTransfer.teleporterFee/100);
            let protocolFee = Math.floor(CC_REQUESTS.normalCCTransfer.bitcoinAmount*PROTOCOL_PERCENTAGE_FEE/10000);

            // Checks enough teleBTC has been minted for user
            expect(
                await teleBTC.balanceOf(CC_REQUESTS.normalCCTransfer.recipientAddress)
            ).to.equal(CC_REQUESTS.normalCCTransfer.bitcoinAmount - lockerFee - teleporterFee - protocolFee);

            // Checks enough teleBTC has been minted for teleporter
            expect(
                await teleBTC.balanceOf(await deployer.getAddress())
            ).to.equal((CC_REQUESTS.normalCCTransfer.bitcoinAmount * CC_REQUESTS.normalCCTransfer.teleporterFee)/100);

            // Check correct amount of teleBTC has been minted in total
            expect(
                await teleBTC.totalSupply()
            ).to.equal(prevSupply + CC_REQUESTS.normalCCTransfer.bitcoinAmount)
            // TODO expects z teleBTC has been minted for protocol
            // expect(
            //     await teleBTC.balanceOf()
            // ).to.equal();
            // TODO expects a teleBTC has been minted for lockers
            // expect(
            //     await teleBTC.balanceOf()
            // ).to.equal();
        })

        it("Reverts if the request has been used before", async function () {
            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    // false // payWithTDT,
                    TELEPORTER1_PublicKeyHash
                )
            ).to.revertedWith("CCTransferRouter: request has been used before");
        })

        it("Reverts if the request has not been finalized on the relay", async function () {
            await revertProvider(signer1.provider, beginning);
            // Mocking that relay returns false for our request
            await setRelayReturn(CC_REQUESTS.normalCCTransfer, false);

            await addALockerToLockers();
            // Mocking that lockers returns the Lockers address on Bitcoin
            // await setLockersReturn(CC_REQUESTS.normalCCTransfer);
            // Check that ccTransfer reverts when tx is not finalized on source chain
            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    // false // payWithTDT
                    CC_REQUESTS.normalCCTransfer.desiredRecipient,
                )
            ).to.revertedWith("CCTransferRouter: transaction has not been finalized yet");
        })

        it("Reverts if the percentage fee is out of range [0,100)", async function () {
            // TODO
        })

        it("Reverts if the request is an exchange request", async function () {
            // TODO
        })

        it("Reverts if the request data size is not 80 bytes", async function () {
            // TODO
        })

        it("Reverts if the request belongs to another chain", async function () {
            // TODO
        })

        it("Reverts if user has not sent BTC to lockers", async function () {
            // TODO
        })

        it("Reverts if the request speed is out of range {0,1}", async function () {
            // TODO uncomment when it is added to the contract and put a correct revert msg
            // await revertProvider(signer1.provider, beginning);
            // // Mocking that relay returns true for our request
            // await setRelayReturn(CC_REQUESTS.normalCCTransfer_invalidSpeed, true);
            // // Mocking that lockers returns the Lockers address on Bitcoin
            // await setBitcoinTeleporterReturn(CC_REQUESTS.normalCCTransfer_invalidSpeed);
            // // Check that ccTransfer reverts when tx is not finalized on source chain
            // await expect(
            //     ccTransferRouter.ccTransfer(
            //         CC_REQUESTS.normalCCTransfer_invalidSpeed.version,
            //         CC_REQUESTS.normalCCTransfer_invalidSpeed.vin,
            //         CC_REQUESTS.normalCCTransfer_invalidSpeed.vout,
            //         CC_REQUESTS.normalCCTransfer_invalidSpeed.locktime,
            //         CC_REQUESTS.normalCCTransfer_invalidSpeed.blockNumber,
            //         CC_REQUESTS.normalCCTransfer_invalidSpeed.intermediateNodes,
            //         CC_REQUESTS.normalCCTransfer_invalidSpeed.index,
            //         false // payWithTDT
            //     )
            // ).to.revertedWith("TODO");
        })

    });

    describe("#Instant CCTransfer ", async () => {
        it("mints teleBTC for instant cc transfer request", async function () {
            beginning = await takeSnapshot(signer1.provider);
            let prevSupply = await teleBTC.totalSupply();
            // Mocking that relay returns true for our request
            await setRelayReturn(CC_REQUESTS.instantCCTransfer, true);

            // await addALockerToLockers();
            // Mocking that lockers returns the Lockers address on Bitcoin
            // await setLockersReturn(CC_REQUESTS.normalCCTransfer);
            // Check that ccTransfer performs successfully when everything is valid
            expect(
                await ccTransferRouter.ccTransfer(
                    CC_REQUESTS.instantCCTransfer.version,
                    CC_REQUESTS.instantCCTransfer.vin,
                    CC_REQUESTS.instantCCTransfer.vout,
                    CC_REQUESTS.instantCCTransfer.locktime,
                    CC_REQUESTS.instantCCTransfer.blockNumber,
                    CC_REQUESTS.instantCCTransfer.intermediateNodes,
                    CC_REQUESTS.instantCCTransfer.index,
                    // false // payWithTDT
                    // TELEPORTER1_PublicKeyHash
                    CC_REQUESTS.instantCCTransfer.desiredRecipient,
                )
            ).to.emit(ccTransferRouter, 'CCTransfer');

            // Calculates fees
            let lockerFee = Math.floor(CC_REQUESTS.normalCCTransfer.bitcoinAmount*LOCKER_PERCENTAGE_FEE/10000);
            let teleporterFee = Math.floor(CC_REQUESTS.normalCCTransfer.bitcoinAmount*CC_REQUESTS.normalCCTransfer.teleporterFee/100);
            let protocolFee = Math.floor(CC_REQUESTS.normalCCTransfer.bitcoinAmount*PROTOCOL_PERCENTAGE_FEE/10000);

            // Checks enough teleBTC has been minted and approved for instant router
            expect(
                await teleBTC.allowance(ccTransferRouter.address, mockInstantRouter.address)
            ).to.equal(CC_REQUESTS.instantCCTransfer.bitcoinAmount - lockerFee - teleporterFee - protocolFee);

            // Check correct amount of teleBTC has been minted in total
            expect(
                await teleBTC.totalSupply()
            ).to.equal(prevSupply + CC_REQUESTS.instantCCTransfer.bitcoinAmount)
        })

    });

    describe("#isRequestUsed", async () => {

        it("checks if the request has been used before (unused)", async function () {
            await revertProvider(signer1.provider, beginning);
            expect(
                await ccTransferRouter.isRequestUsed(CC_REQUESTS.normalCCTransfer.txId)
            ).to.equal(false);
        })

        it("checks if the request has been used before (used)", async function () {
            // Mocking that relay returns true for our request
            await setRelayReturn(CC_REQUESTS.normalCCTransfer, true);

            // Mocking that lockers returns the Lockers address on Bitcoin
            // await setLockersReturn(CC_REQUESTS.normalCCTransfer);
            // send ccTransfer request
            await expect(
                ccTransferRouter.ccTransfer(
                    CC_REQUESTS.normalCCTransfer.version,
                    CC_REQUESTS.normalCCTransfer.vin,
                    CC_REQUESTS.normalCCTransfer.vout,
                    CC_REQUESTS.normalCCTransfer.locktime,
                    CC_REQUESTS.normalCCTransfer.blockNumber,
                    CC_REQUESTS.normalCCTransfer.intermediateNodes,
                    CC_REQUESTS.normalCCTransfer.index,
                    // false // payWithTDT
                    CC_REQUESTS.normalCCTransfer.desiredRecipient
                )
            ).to.emit(ccTransferRouter, 'CCTransfer');

            expect(
                await ccTransferRouter.isRequestUsed(CC_REQUESTS.normalCCTransfer.txId)
            ).to.equal(true);
        })

    });
});