const CC_BURN_REQUESTS = require('./test_fixtures/ccBurnRequests.json');
require('dotenv').config({path:"../../.env"});

import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Address } from "hardhat-deploy/types";

import {TeleBTC} from "../src/types/TeleBTC";
import {TeleBTC__factory} from "../src/types/factories/TeleBTC__factory";
import {CCBurnRouter} from "../src/types/CCBurnRouter";
import {CCBurnRouter__factory} from "../src/types/factories/CCBurnRouter__factory";

import { takeSnapshot, revertProvider } from "./block_utils";

describe("CCBurnRouter", async () => {
    let snapshotId: any;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let signer1Address: Address;

    // Contracts
    let teleBTC: TeleBTC;
    let TeleBTCSigner1: TeleBTC;
    let ccBurnRouter: CCBurnRouter;
    let ccBurnRouterSigner1: CCBurnRouter;
    let ccBurnRouterSigner2: CCBurnRouter;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockLockers: MockContract;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let oneHundred = BigNumber.from(10).pow(8).mul(100)
    /*
        This one is set so that:
        userRequestedAmount * (1 - lockerFee / 10000 - PROTOCOL_PERCENTAGE_FEE / 10000) - BITCOIN_FEE = 100000000
    */
    let userRequestedAmount = BigNumber.from(100060030);
    let TRANSFER_DEADLINE = 20
    let PROTOCOL_PERCENTAGE_FEE = 5 // means 0.05%
    let SLASHER_PERCENTAGE_REWARD = 5 // means 0.05%
    let BITCOIN_FEE = 10000 // estimation of Bitcoin transaction fee in Satoshi
    let TREASURY = "0x0000000000000000000000000000000000000002";

    let LOCKER_TARGET_ADDRESS = ONE_ADDRESS;
    let LOCKER1_LOCKING_SCRIPT = '0x76a914748284390f9e263a4b766a75d0633c50426eb87587ac';

    let btcPublicKey = "03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd"
    let btcAddress = "mmPPsxXdtqgHFrxZdtFCtkwhHynGTiTsVh"

    let USER_SCRIPT_P2PKH = "0x12ab8dc588ca9d5787dde7eb29569da63c3a238c";
    let USER_SCRIPT_P2PKH_TYPE = 1; // P2PKH

    let USER_SCRIPT_P2WPKH = "0x751e76e8199196d454941c45d1b3a323f1433bd6";
    let USER_SCRIPT_P2WPKH_TYPE = 3; // P2WPKH

    before(async () => {

        [deployer, signer1, signer2] = await ethers.getSigners();
        signer1Address = await signer1.getAddress();

        // Mocks contracts
    
        const bitcoinRelay = await deployments.getArtifact(
            "IBitcoinRelay"
        );
        mockBitcoinRelay = await deployMockContract(
            deployer,
            bitcoinRelay.abi
        )

        const lockers = await deployments.getArtifact(
            "LockersLogic"
        );
        mockLockers = await deployMockContract(
            deployer,
            lockers.abi
        )

        // mock finalization parameter
        await mockBitcoinRelay.mock.finalizationParameter.returns(5);

        // Deploys contracts
        teleBTC = await deployTeleBTC();
        ccBurnRouter = await deployCCBurnRouter();

        // Mints TeleBTC for user
        await teleBTC.addMinter(signer1Address)
        TeleBTCSigner1 = await teleBTC.connect(signer1);
        await TeleBTCSigner1.mint(signer1Address, 10000000000);

        // Connects signer1 and signer2 to ccBurnRouter
        ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1);
        ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)
    });

    const deployTeleBTC = async (
        _signer?: Signer
    ): Promise<TeleBTC> => {
        const teleBTCFactory = new TeleBTC__factory(
            _signer || deployer
        );

        const teleBTC = await teleBTCFactory.deploy(
            "Teleport Wrapped BTC",
            "TeleBTC"
        );

        return teleBTC;
    };

    const deployCCBurnRouter = async (
        _signer?: Signer
    ): Promise<CCBurnRouter> => {
        const ccBurnRouterFactory = new CCBurnRouter__factory(
            _signer || deployer
        );

        const ccBurnRouter = await ccBurnRouterFactory.deploy(
            mockBitcoinRelay.address,
            mockLockers.address,
            TREASURY,
            teleBTC.address,
            TRANSFER_DEADLINE,
            PROTOCOL_PERCENTAGE_FEE,
            SLASHER_PERCENTAGE_REWARD,
            BITCOIN_FEE
        );

        return ccBurnRouter;
    };

    async function setLockersSlashIdleLockerReturn(): Promise<void> {
        await mockLockers.mock.slashIdleLocker
            .returns(true);
    }

    async function setLockersSlashThiefLockerReturn(): Promise<void> {
        await mockLockers.mock.slashThiefLocker
            .returns(true);
    }

    async function setLockersIsLocker(isLocker: boolean): Promise<void> {
        await mockLockers.mock.isLocker
            .returns(isLocker);
    }

    async function setLockersGetLockerTargetAddress(): Promise<void> {
        await mockLockers.mock.getLockerTargetAddress
            .returns(LOCKER_TARGET_ADDRESS);
    }

    async function setLockersBurnReturn(burntAmount: number): Promise<void> {
        await mockLockers.mock.burn
            .returns(burntAmount);
    }

    async function setRelayLastSubmittedHeight(blockNumber: number): Promise<void> {
        await mockBitcoinRelay.mock.lastSubmittedHeight.returns(blockNumber);
    }

    async function setRelayCheckTxProofReturn(isFinal: boolean, relayFee?: number): Promise<void> {
        await mockBitcoinRelay.mock.getBlockHeaderFee.returns(relayFee || 0); // Fee of relay
        await mockBitcoinRelay.mock.checkTxProof
            .returns(isFinal);
    }

    async function mintTeleBTCForTest(): Promise<void> {
        let TeleBTCSigner1 = await teleBTC.connect(signer1)
        await TeleBTCSigner1.mint(signer1Address, 10000000000);
    }

    async function sendBurnRequest(
        burnReqBlockNumber: number,
        _userRequestedAmount: BigNumber,
        USER_SCRIPT: any,
        USER_SCRIPT_TYPE: any
    ): Promise<number> {
        // Gives allowance to ccBurnRouter
        await TeleBTCSigner1.approve(
            ccBurnRouter.address,
            _userRequestedAmount
        );

        // Sets mock contracts outputs
        await setRelayLastSubmittedHeight(burnReqBlockNumber);
        await setLockersIsLocker(true);
        let burntAmount: number;
        let protocolFee = Math.floor(_userRequestedAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
        burntAmount = _userRequestedAmount.toNumber() - BITCOIN_FEE - protocolFee;
        await setLockersBurnReturn(burntAmount);

        await setLockersGetLockerTargetAddress();

        // Burns eleBTC
        await ccBurnRouterSigner1.ccBurn(
            _userRequestedAmount,
            USER_SCRIPT,
            USER_SCRIPT_TYPE,
            LOCKER1_LOCKING_SCRIPT
        );

        return burntAmount;
    }

    async function provideProof(burnReqBlockNumber: number) {

        // Set mocks contracts outputs
        await setRelayCheckTxProofReturn(true);
        await setLockersIsLocker(true);

        let burntAmount: number;
        let protocolFee = Math.floor(userRequestedAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
        burntAmount = userRequestedAmount.toNumber() - BITCOIN_FEE - protocolFee;
        await setLockersBurnReturn(burntAmount);

        await setLockersGetLockerTargetAddress();

        // Provide proof that the locker has paid the burnt amount to the user(s)
        await expect(
            await ccBurnRouterSigner2.burnProof(
                CC_BURN_REQUESTS.burnProof_valid.version,
                CC_BURN_REQUESTS.burnProof_valid.vin,
                CC_BURN_REQUESTS.burnProof_valid.vout,
                CC_BURN_REQUESTS.burnProof_valid.locktime,
                burnReqBlockNumber,
                CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                1,
                LOCKER1_LOCKING_SCRIPT,
                [0],
                [0]
            )
        ).to.emit(ccBurnRouter, "PaidCCBurn")
    }

    describe("#ccBurn", async () => {

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);

        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Burns teleBTC for user", async function () {
            let lastSubmittedHeight = 100;

            // Gives allowance to ccBurnRouter to burn tokens
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                userRequestedAmount
            );

            // Sets mock contracts outputs
            await setRelayLastSubmittedHeight(lastSubmittedHeight);
            await setLockersIsLocker(true);

            // Finds amount of teleBTC that user should receive on Bitcoin
            let protocolFee = Math.floor(userRequestedAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
            let burntAmount = userRequestedAmount.toNumber() - BITCOIN_FEE - protocolFee;
            await setLockersBurnReturn(burntAmount);

            ;
            await setLockersGetLockerTargetAddress();

            let prevBalanceSigner1 = await teleBTC.balanceOf(signer1Address);

            // Burns teleBTC
            expect(
                await ccBurnRouterSigner1.ccBurn(
                    userRequestedAmount,
                    USER_SCRIPT_P2PKH,
                    USER_SCRIPT_P2PKH_TYPE,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.emit(ccBurnRouter, "CCBurn").withArgs(
                signer1Address,
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                userRequestedAmount,
                burntAmount,
                ONE_ADDRESS,
                0,
                lastSubmittedHeight + TRANSFER_DEADLINE
            );

            let newBalanceSigner1 = await teleBTC.balanceOf(signer1Address);

            // Checks user's balance
            expect(
                await newBalanceSigner1
            ).to.equal(prevBalanceSigner1.sub(userRequestedAmount));

            // Checks that protocol fee has been received
            expect(
                await teleBTC.balanceOf(TREASURY)
            ).to.equal(protocolFee);

            // Checks that Bitcoin fee has been sent to locker
            expect(
                await teleBTC.balanceOf(LOCKER_TARGET_ADDRESS)
            ).to.equal(BITCOIN_FEE);

            // Gets the burn request that has been saved in the contract
            let theBurnRequest = await ccBurnRouter.burnRequests(LOCKER_TARGET_ADDRESS, 0);

            expect(
                theBurnRequest.burntAmount
            ).to.equal(burntAmount);

        })

        it("Reverts since user requested amount is zero", async function () {

            await expect(
                ccBurnRouterSigner1.ccBurn(
                    0,
                    USER_SCRIPT_P2PKH,
                    USER_SCRIPT_P2PKH_TYPE,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCBurnRouter: value is zero")
        })

        it("Reverts since requested amount doesn't cover Bitcoin fee", async function () {
            let lastSubmittedHeight = 100;

            // Gives allowance to ccBurnRouter to burn tokens
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                BITCOIN_FEE - 1
            );

            // Sets mock contracts outputs
            await setRelayLastSubmittedHeight(lastSubmittedHeight);
            await setLockersIsLocker(true);
            ;
            await setLockersGetLockerTargetAddress();

            // Burns teleBTC
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    BITCOIN_FEE - 1,
                    USER_SCRIPT_P2PKH,
                    USER_SCRIPT_P2PKH_TYPE,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCBurnRouter: amount is too low");

        })

        it("Reverts since allowance is not enough", async function () {

            // Sets mock contracts outputs
            await setLockersIsLocker(true);

            await setLockersGetLockerTargetAddress();

            await expect(
                ccBurnRouterSigner1.ccBurn(
                    userRequestedAmount,
                    USER_SCRIPT_P2PKH,
                    USER_SCRIPT_P2PKH_TYPE,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("ERC20: transfer amount exceeds allowance")
        })

        it("Reverts since locker's locking script is not valid", async function () {

            await setLockersIsLocker(false);

            await expect(
                ccBurnRouterSigner1.ccBurn(
                    userRequestedAmount,
                    USER_SCRIPT_P2PKH,
                    USER_SCRIPT_P2PKH_TYPE,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("CCBurnRouter: given locking script is not locker")
        })

    });

    describe("#burnProof", async () => {
        let burnReqBlockNumber = 100;

        let burntAmount: number;

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);

            // Mints TeleBTC for test
            await mintTeleBTCForTest();

            // Sends a burn request
            burntAmount = await sendBurnRequest(
                burnReqBlockNumber,
                userRequestedAmount,
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE
            );
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Submits a valid burn proof (for P2PKH)", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            expect(
                await ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER1_LOCKING_SCRIPT,
                    [0],
                    [0]
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn").withArgs(
                signer1Address,
                USER_SCRIPT_P2PKH,
                burntAmount,
                LOCKER_TARGET_ADDRESS,
                0
            );

            expect(
                await ccBurnRouter.isUsedAsBurnProof(
                    CC_BURN_REQUESTS.burnProof_valid.txId
                )
            ).to.equal(true);
        })

        it("Submits a valid burn proof (for P2WPKH)", async function () {

            // Sends a burn request
            burntAmount = await sendBurnRequest(
                burnReqBlockNumber,
                userRequestedAmount,
                USER_SCRIPT_P2WPKH,
                USER_SCRIPT_P2WPKH_TYPE
            );

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            expect(
                await ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_validP2WPKH.version,
                    CC_BURN_REQUESTS.burnProof_validP2WPKH.vin,
                    CC_BURN_REQUESTS.burnProof_validP2WPKH.vout,
                    CC_BURN_REQUESTS.burnProof_validP2WPKH.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_validP2WPKH.intermediateNodes,
                    1,
                    LOCKER1_LOCKING_SCRIPT,
                    [1], // Burn req index
                    [0]
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn").withArgs(
                signer1Address,
                USER_SCRIPT_P2WPKH,
                burntAmount,
                LOCKER_TARGET_ADDRESS,
                1
            );

            expect(
                await ccBurnRouter.isUsedAsBurnProof(
                    CC_BURN_REQUESTS.burnProof_validP2WPKH.txId
                )
            ).to.equal(true);
        })

        it("Submits a valid burn proof which doesn't have change vout", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            expect(
                await ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.version,
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.vin,
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.vout,
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.intermediateNodes,
                    1,
                    LOCKER1_LOCKING_SCRIPT,
                    [0],
                    [0]
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn").withArgs(
                signer1Address,
                USER_SCRIPT_P2PKH,
                burntAmount,
                LOCKER_TARGET_ADDRESS,
                0
            );

            expect(
                await ccBurnRouter.isUsedAsBurnProof(
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.txId
                )
            ).to.equal(true);
        })

        it("Reverts since locktime is non-zero", async function () {
            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    '0x00000001',
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER_TARGET_ADDRESS,
                    [0],
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: non-zero lock time")
        })

        it("Reverts if locking script is not valid", async function () {
            // Sets mock contracts outputs
            await setLockersIsLocker(false);

            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER_TARGET_ADDRESS,
                    [0],
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: given locking script is not locker")
        })

        it("Reverts if given indexes doesn't match", async function () {

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            // Should revert when start index is bigger than end index
            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER_TARGET_ADDRESS,
                    [0, 1],
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: wrong indexes")

            // Should revert when end index is bigger than total number of burn requests
            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER_TARGET_ADDRESS,
                    [0],
                    [0, 1]
                )
            ).to.revertedWith("CCBurnRouter: wrong index")
        })

        it("Reverts since paid fee is not enough", async function () {
            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true, 1);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER_TARGET_ADDRESS,
                    [0],
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: relay fee is not sufficient");
        })

        it("Reverts if locker's tx has not been finalized on relay", async function () {
            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(false);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER_TARGET_ADDRESS,
                    [0],
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: transaction has not finalized yet");
        })

        it("Reverts if vout is null", async function () {
            // Sends a burn request
            await sendBurnRequest(burnReqBlockNumber, userRequestedAmount, USER_SCRIPT_P2PKH, USER_SCRIPT_P2PKH_TYPE);

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            // Should revert with a wrong start index
            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    "0x0000",
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER_TARGET_ADDRESS,
                    [0],
                    [0]
                )
            ).to.revertedWith("BitcoinHelper: vout is null")
        })

        it("Doesn't accept burn proof since the paid amount is not exact", async function () {
            let wrongUserRequestAmount = BigNumber.from(100080000)
            let burnReqBlockNumber = 100;

            // Send a burn request
            await sendBurnRequest(burnReqBlockNumber, wrongUserRequestAmount, USER_SCRIPT_P2PKH, USER_SCRIPT_P2PKH_TYPE);

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            // Should revert with a wrong start index
            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER_TARGET_ADDRESS,
                    [1],
                    [1]
                )
            ).to.not.emit(ccBurnRouter, "PaidCCBurn");

            expect(
                await ccBurnRouterSigner2.isTransferred(LOCKER_TARGET_ADDRESS, 0)
            ).to.equal(false);
        })

        it("Doesn't accept burn proof since the proof has been submitted before", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            await ccBurnRouterSigner2.burnProof(
                CC_BURN_REQUESTS.burnProof_valid.version,
                CC_BURN_REQUESTS.burnProof_valid.vin,
                CC_BURN_REQUESTS.burnProof_valid.vout,
                CC_BURN_REQUESTS.burnProof_valid.locktime,
                burnReqBlockNumber + 5,
                CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                1,
                LOCKER1_LOCKING_SCRIPT,
                [0],
                [0]
            );

            expect(
                await ccBurnRouterSigner2.isTransferred(LOCKER_TARGET_ADDRESS, 0)
            ).to.equal(true);

            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER1_LOCKING_SCRIPT,
                    [0],
                    [0]
                )
            ).to.not.emit(ccBurnRouter, "PaidCCBurn");
        })

        it("Doesn't accept burn proof since deadline is passed", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_valid.version,
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.burnProof_valid.locktime,
                    burnReqBlockNumber + TRANSFER_DEADLINE + 1,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER1_LOCKING_SCRIPT,
                    [0],
                    [0]
                )
            ).to.not.emit(ccBurnRouter, "PaidCCBurn");

            expect(
                await ccBurnRouterSigner2.isTransferred(LOCKER_TARGET_ADDRESS, 0)
            ).to.equal(false);
        })

        it("Doesn't accept burn proof since change address is invalid", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            await ccBurnRouterSigner2.burnProof(
                CC_BURN_REQUESTS.burnProof_invalidChange.version,
                CC_BURN_REQUESTS.burnProof_invalidChange.vin,
                CC_BURN_REQUESTS.burnProof_invalidChange.vout,
                CC_BURN_REQUESTS.burnProof_invalidChange.locktime,
                burnReqBlockNumber + 5,
                CC_BURN_REQUESTS.burnProof_invalidChange.intermediateNodes,
                1,
                LOCKER1_LOCKING_SCRIPT,
                [0],
                [0]
            );

            expect(
                await ccBurnRouterSigner2.isTransferred(LOCKER_TARGET_ADDRESS, 0)
            ).to.equal(true);

            expect(
                await ccBurnRouter.isUsedAsBurnProof(
                    CC_BURN_REQUESTS.burnProof_invalidChange.txId
                )
            ).to.equal(false);

        })
    });

    describe("#disputeBurn", async () => {
        let burnReqBlockNumber = 100;

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
            // Mints TeleBTC for test
            await mintTeleBTCForTest();

            // Sends a burn request
            await sendBurnRequest(100, userRequestedAmount, USER_SCRIPT_P2PKH, USER_SCRIPT_P2PKH_TYPE);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Disputes locker successfully", async function () {
            // Sets mock contracts
            await setRelayLastSubmittedHeight(burnReqBlockNumber + TRANSFER_DEADLINE + 1);
            await setLockersSlashIdleLockerReturn();
            await setLockersIsLocker(true);

            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            ).to.not.reverted;
        })

        it("Reverts since locker has been slashed before", async function () {
            // Sets mock contracts
            await setRelayLastSubmittedHeight(burnReqBlockNumber + TRANSFER_DEADLINE + 1);
            await setLockersSlashIdleLockerReturn();
            await setLockersIsLocker(true);

            await ccBurnRouterSigner2.disputeBurn(
                LOCKER_TARGET_ADDRESS,
                [0]
            );

            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: request has been paid before")
        })

        it("Reverts since locking script is invalid", async function () {

            // Sets mock contracts outputs
            await setLockersIsLocker(false);

            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: given locking script is not locker")
        })

        it("Reverts since locker has paid before hand", async function () {

            // Sets mock contracts outputs
            await setLockersIsLocker(true);
            await setLockersSlashIdleLockerReturn();

            // Pays the burnt amount and provides proof
            await provideProof(burnReqBlockNumber + 5);

            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: request has been paid before")
        })

        it("Reverts since deadline hasn't reached", async function () {
            // Set mock contracts outputs
            await setLockersIsLocker(true);
            await setRelayLastSubmittedHeight(100);

            // Locker will not get slashed because the deadline of transfer has not reached
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: payback deadline has not passed yet")
        })

    });

    describe("#disputeLocker", async () => {
        let burnReqBlockNumber = 100;

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Dispute the locker who has sent its BTC to external account", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setRelayLastSubmittedHeight(burnReqBlockNumber + TRANSFER_DEADLINE + 1);
            await setLockersGetLockerTargetAddress();
            await setLockersSlashThiefLockerReturn();

            expect(
                await ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.disputeLocker_input.version, CC_BURN_REQUESTS.disputeLocker_output.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime, CC_BURN_REQUESTS.disputeLocker_output.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.emit(ccBurnRouter, "LockerDispute").withArgs(
                LOCKER_TARGET_ADDRESS,
                burnReqBlockNumber,
                CC_BURN_REQUESTS.disputeLocker_input.txId,
                CC_BURN_REQUESTS.disputeLocker_input.OutputValue +
                CC_BURN_REQUESTS.disputeLocker_input.OutputValue*SLASHER_PERCENTAGE_REWARD/100
            );
        })

        it("Reverts since inputs are not valid", async function () {

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.disputeLocker_input.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime, CC_BURN_REQUESTS.disputeLocker_output.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.revertedWith("CCBurnRouter: wrong inputs");

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.disputeLocker_input.version, CC_BURN_REQUESTS.disputeLocker_output.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.revertedWith("CCBurnRouter: wrong inputs");

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.disputeLocker_input.version, CC_BURN_REQUESTS.disputeLocker_output.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime, CC_BURN_REQUESTS.disputeLocker_output.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1]
                )
            ).to.revertedWith("CCBurnRouter: wrong inputs")
        })

        it("Reverts since locking script is not valid", async function () {

            // Sets mock contracts outputs
            await setLockersIsLocker(false);

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.disputeLocker_input.version, CC_BURN_REQUESTS.disputeLocker_output.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime, CC_BURN_REQUESTS.disputeLocker_output.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.revertedWith("CCBurnRouter: given locking script is not locker");
        })

        it("Reverts since input tx has not finalized", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(false);
            await setLockersIsLocker(true);

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.disputeLocker_input.version, CC_BURN_REQUESTS.disputeLocker_output.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime, CC_BURN_REQUESTS.disputeLocker_output.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.revertedWith("CCBurnRouter: input transaction is not finalized");
        })

        it("Reverts since input tx has been used as burn proof", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(false);
            await setLockersIsLocker(true);

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.disputeLocker_input.version, CC_BURN_REQUESTS.disputeLocker_output.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime, CC_BURN_REQUESTS.disputeLocker_output.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.revertedWith("CCBurnRouter: input transaction is not finalized");
        })

        it("Reverts since outpoint doesn't match with output tx", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setRelayLastSubmittedHeight(burnReqBlockNumber + TRANSFER_DEADLINE + 1);
            await setLockersGetLockerTargetAddress();
            await setLockersSlashIdleLockerReturn();

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.disputeLocker_input.version, CC_BURN_REQUESTS.disputeLocker_invalidOutput.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_invalidOutput.vin,
                    CC_BURN_REQUESTS.disputeLocker_invalidOutput.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime, CC_BURN_REQUESTS.disputeLocker_invalidOutput.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.revertedWith("CCBurnRouter: outpoint tx doesn't match with output tx");
        })

        it("Reverts since tx doesn't belong to locker", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setRelayLastSubmittedHeight(burnReqBlockNumber + TRANSFER_DEADLINE + 1);
            await setLockersGetLockerTargetAddress();
            await setLockersSlashIdleLockerReturn();

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    "0x76a914748284390f9e263a4b766a75d0633c50426eb87587ab",
                    [CC_BURN_REQUESTS.disputeLocker_input.version, CC_BURN_REQUESTS.disputeLocker_output.version],
                    CC_BURN_REQUESTS.disputeLocker_input.vin,
                    CC_BURN_REQUESTS.disputeLocker_input.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.disputeLocker_input.locktime, CC_BURN_REQUESTS.disputeLocker_output.locktime],
                    CC_BURN_REQUESTS.disputeLocker_input.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.revertedWith("CCBurnRouter: output tx doesn't belong to locker");
        })

        it("Reverts since locker may submit input tx as burn proof", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setRelayLastSubmittedHeight(burnReqBlockNumber);
            await setLockersGetLockerTargetAddress();
            await setLockersSlashIdleLockerReturn();

            // User sends a burn request and locker provides burn proof for it
            await sendBurnRequest(100, userRequestedAmount, USER_SCRIPT_P2PKH, USER_SCRIPT_P2PKH_TYPE);
            await provideProof(burnReqBlockNumber + 5);

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    LOCKER1_LOCKING_SCRIPT,
                    [CC_BURN_REQUESTS.burnProof_valid.version, CC_BURN_REQUESTS.disputeLocker_output.version],
                    CC_BURN_REQUESTS.burnProof_valid.vin,
                    CC_BURN_REQUESTS.burnProof_valid.vout,
                    CC_BURN_REQUESTS.disputeLocker_output.vin,
                    CC_BURN_REQUESTS.disputeLocker_output.vout,
                    [CC_BURN_REQUESTS.burnProof_valid.locktime, CC_BURN_REQUESTS.disputeLocker_output.locktime],
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    [0, 1, burnReqBlockNumber]
                )
            ).to.revertedWith("CCBurnRouter: transaction has been used as burn proof");
        })
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
                ccBurnRouter.setProtocolPercentageFee(100)
            ).to.emit(
                ccBurnRouter, "NewProtocolPercentageFee"
            ).withArgs(PROTOCOL_PERCENTAGE_FEE, 100);

            expect(
                await ccBurnRouter.protocolPercentageFee()
            ).to.equal(100);
        })

        it("Reverts since protocol percentage fee is greater than 10000", async function () {
            await expect(
                ccBurnRouter.setProtocolPercentageFee(10001)
            ).to.revertedWith("CCBurnRouter: protocol fee is out of range");
        })

        it("Sets transfer deadline", async function () {

            await mockBitcoinRelay.mock.finalizationParameter.returns(10);

            await expect(
                ccBurnRouter.setTransferDeadline(100)
            ).to.emit(
                ccBurnRouter, "NewTransferDeadline"
            ).withArgs(TRANSFER_DEADLINE, 100);


            expect(
                await ccBurnRouter.transferDeadline()
            ).to.equal(100);
        })

        it("Fixes transfer deadline", async function () {

            await mockBitcoinRelay.mock.finalizationParameter.returns(10);

            await expect(
                ccBurnRouter.fixTransferDeadline()
            ).to.emit(
                ccBurnRouter, "NewTransferDeadline"
            ).withArgs(TRANSFER_DEADLINE, 21);


            expect(
                await ccBurnRouter.transferDeadline()
            ).to.equal(21);
        })

        it("can't Fix transfer deadline if finalizationParameter is greater than current transfer deadline", async function () {
            await ccBurnRouter.setTransferDeadline(9);
            await mockBitcoinRelay.mock.finalizationParameter.returns(10);

            await expect(
                ccBurnRouter.fixTransferDeadline()
            ).to.revertedWith("CCBurnRouter: finalization parameter is not greater than transfer deadline");
        })

        it("Reverts since transfer deadline is smaller than relay finalizatio parameter", async function () {
            await mockBitcoinRelay.mock.finalizationParameter.returns(10);

            await expect(
                ccBurnRouter.setTransferDeadline(9)
            ).to.revertedWith("CCBurnRouter: transfer deadline is too low");

        })

        it("Reverts since transfer deadline is smaller than relay finalizatio parameter", async function () {
            await mockBitcoinRelay.mock.finalizationParameter.returns(10);

            await expect(
                ccBurnRouter.setTransferDeadline(10)
            ).to.revertedWith("CCBurnRouter: transfer deadline is too low");

        })

        it("Sets slasher reward", async function () {
            await expect(
                ccBurnRouter.setSlasherPercentageReward(100)
            ).to.emit(
                ccBurnRouter, "NewSlasherPercentageFee"
            ).withArgs(SLASHER_PERCENTAGE_REWARD, 100);

            expect(
                await ccBurnRouter.slasherPercentageReward()
            ).to.equal(100);
        })

        it("Reverts since slasher reward is greater than 100", async function () {
            await expect(
                ccBurnRouter.setSlasherPercentageReward(10001)
            ).to.revertedWith("CCBurnRouter: slasher percentage reward is out of range");
        })

        it("Sets bitcoin fee", async function () {
            await expect(
                ccBurnRouter.setBitcoinFee(100)
            ).to.emit(
                ccBurnRouter, "NewBitcoinFee"
            ).withArgs(BITCOIN_FEE, 100);


            expect(
                await ccBurnRouter.bitcoinFee()
            ).to.equal(100);
        })

        it("Sets relay, lockers, teleBTC and treasury", async function () {
            await expect(
                ccBurnRouter.setRelay(ONE_ADDRESS)
            ).to.emit(
                ccBurnRouter, "NewRelay"
            ).withArgs(mockBitcoinRelay.address, ONE_ADDRESS);

            expect(
                await ccBurnRouter.relay()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccBurnRouter.setLockers(ONE_ADDRESS)
            ).to.emit(
                ccBurnRouter, "NewLockers"
            ).withArgs(mockLockers.address, ONE_ADDRESS);

            expect(
                await ccBurnRouter.lockers()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccBurnRouter.setTeleBTC(ONE_ADDRESS)
            ).to.emit(
                ccBurnRouter, "NewTeleBTC"
            ).withArgs(teleBTC.address, ONE_ADDRESS);

            expect(
                await ccBurnRouter.teleBTC()
            ).to.equal(ONE_ADDRESS);

            await expect(
                ccBurnRouter.setTreasury(ONE_ADDRESS)
            ).to.emit(
                ccBurnRouter, "NewTreasury"
            ).withArgs(TREASURY, ONE_ADDRESS);


            expect(
                await ccBurnRouter.treasury()
            ).to.equal(ONE_ADDRESS);

        })

        it("Reverts since given address is zero", async function () {
            await expect(
                ccBurnRouter.setRelay(ZERO_ADDRESS)
            ).to.revertedWith("CCBurnRouter: address is zero");

            await expect(
                ccBurnRouter.setLockers(ZERO_ADDRESS)
            ).to.revertedWith("CCBurnRouter: address is zero");

            await expect(
                ccBurnRouter.setTeleBTC(ZERO_ADDRESS)
            ).to.revertedWith("CCBurnRouter: address is zero");

            await expect(
                ccBurnRouter.setTreasury(ZERO_ADDRESS)
            ).to.revertedWith("CCBurnRouter: address is zero");
        })

    });
});