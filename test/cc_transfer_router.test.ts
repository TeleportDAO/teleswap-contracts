const CC_REQUESTS = require('./test_fixtures/ccTransferRequests.json');
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";
import { Address } from "hardhat-deploy/types";

import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import { CCTransferRouter } from "../src/types/CCTransferRouter";
import { CCTransferRouter__factory } from "../src/types/factories/CCTransferRouter__factory";
import { Lockers } from "../src/types/Lockers";
import { Lockers__factory } from "../src/types/factories/Lockers__factory";
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

    // Bitcoin public key (32 bytes)
    let TELEPORTER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
    let TELEPORTER1_PublicKeyHash = '0xe74e55c339726ee799877efc38cf43845b20ca5c';
    let TELEPORTER2 = '0x03dbc6764b8884a92e871274b87583e6d5c2a58819473e17e107ef3f6aa5a61626';
    let TELEPORTER2_PublicKeyHash = '0xd191dbef3fa0b30f433157748c11cb93f08e839c';
    let UNLOCK_FEE =  5; // percentage of bond that protocol receives
    let UNLOCK_PERIOD = 2;
    let REQUIRED_LOCKED_AMOUNT =  1000; // amount of required TDT

    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000);
    let requiredTDTLockedAmount = BigNumber.from(10).pow(18).mul(500);
    let btcAmountToSlash = BigNumber.from(10).pow(8).mul(1)
    let collateralRatio = 2;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;
    let signer2Address: Address;

    // Contracts
    let ccTransferRouter: CCTransferRouter;
    let teleBTC: TeleBTC;
    let teleportDAOToken: ERC20;
    let locker: Lockers;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    // let mockLockers: MockContract;
    let mockInstantRouter: MockContract;
    let mockExchangeRouter: MockContract;
    let mockPriceOracle: MockContract;

    let beginning: any;

    before(async () => {
        // Sets accounts
        [deployer, signer1, signer2] = await ethers.getSigners();

        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();
        signer2Address = await signer2.getAddress();

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

        await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

        // Mocks teleporters contract
        // const lockersContract = await deployments.getArtifact(
        //     "ILockers"
        // );
        // mockLockers = await deployMockContract(
        //     deployer,
        //     lockersContract.abi
        // );

        // Mocks instant router contract
        const instantRouterContract = await deployments.getArtifact(
            "IInstantRouter"
        );
        mockInstantRouter = await deployMockContract(
            deployer,
            instantRouterContract.abi
        );

        await mockInstantRouter.mock.payBackLoan.returns(true);

        // Mocks exchange router contract
        const exchangeRouterContract = await deployments.getArtifact(
            "IExchangeRouter"
        );
        mockExchangeRouter = await deployMockContract(
            deployer,
            exchangeRouterContract.abi
        );


        // Deploys ccTransferRouter contract
        const ccTransferRouterFactory = new CCTransferRouter__factory(deployer);
        ccTransferRouter = await ccTransferRouterFactory.deploy(
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


        locker = await deployLocker()

        await locker.setTeleBTC(teleBTC.address)
        await locker.addMinter(ccTransferRouter.address)

        await teleBTC.addMinter(locker.address)
        await teleBTC.addBurner(locker.address)

        await ccTransferRouter.setLockers(locker.address)
        await ccTransferRouter.setInstantRouter(mockInstantRouter.address)
    });

    const deployLocker = async (
        _signer?: Signer
    ): Promise<Lockers> => {
        const lockerFactory = new Lockers__factory(
            _signer || deployer
        );

        const locker = await lockerFactory.deploy(
            teleportDAOToken.address,
            mockExchangeRouter.address,
            mockPriceOracle.address,
            requiredTDTLockedAmount,
            0,
            collateralRatio,
            LOCKER_PERCENTAGE_FEE
        );

        return locker;
    };

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

    async function setRelayReturn(request: any, isTrue: boolean): Promise<void> {
        // await mockBitcoinRelay.mock.checkTxProof.withArgs(
        //     request.txId,
        //     request.blockNumber,
        //     request.intermediateNodes,
        //     request.index,
        //     // false, // payWithTDT
        //     // NORMAL_CONFIRMATION_PARAMETER
        // ).returns(isTrue);

        await mockBitcoinRelay.mock.checkTxProof.returns(isTrue);
    }

    async function addALockerToLockers(): Promise<void> {

        await teleportDAOToken.transfer(signer2Address, requiredTDTLockedAmount)

        let teleportDAOTokenSigner2 = teleportDAOToken.connect(signer2)

        await teleportDAOTokenSigner2.approve(locker.address, requiredTDTLockedAmount)

        let lockerSigner2 = locker.connect(signer2)

        await lockerSigner2.requestToBecomeLocker(
            TELEPORTER1,
            // TELEPORTER1_PublicKeyHash,
            CC_REQUESTS.normalCCTransfer.desiredRecipient,
            requiredTDTLockedAmount,
            0
        )

        await locker.addLocker(signer2Address)
    }

    // async function setLockersReturn(request: any): Promise<void> {
    //     await mockLockers.mock.redeemScriptHash
    //         .returns(request.desiredRecipient);
    // }

    describe("#ccTransfer", async () => {
        it("mints teleBTC for normal cc transfer request", async function () {
            beginning = await takeSnapshot(signer1.provider);
            let prevSupply = await teleBTC.totalSupply();
            // Mocking that relay returns true for our request
            await setRelayReturn(CC_REQUESTS.normalCCTransfer, true);

            await addALockerToLockers();
            // Mocking that Locker returns the Lockers address on Bitcoin
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
            // TODO expects a teleBTC has been minted for locker
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
            ).to.revertedWith("CCTransferRouter: CC transfer request has been used before");
        })

        it("Reverts if the request has not been finalized on the relay", async function () {
            await revertProvider(signer1.provider, beginning);
            // Mocking that relay returns false for our request
            await setRelayReturn(CC_REQUESTS.normalCCTransfer, false);

            await addALockerToLockers();
            // Mocking that Locker returns the Lockers address on Bitcoin
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
            // // Mocking that Locker returns the Lockers address on Bitcoin
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
            // Mocking that Locker returns the Lockers address on Bitcoin
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

            // Mocking that Locker returns the Lockers address on Bitcoin
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