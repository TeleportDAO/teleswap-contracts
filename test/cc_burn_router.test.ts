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
    let userLockingScript = "0x76a91412ab8dc588ca9d5787dde7eb29569da63c3a238c88ac"
    let btcSegwitDecodedAddress = "0x751e76e8199196d454941c45d1b3a323f1433bd6"

    // The locker sends tokens to another wallet
    let btcLockerVersion =  "0x02000000"
    let btcLockerVin = "0x017b1eabe0209b1fe794124575ef807057c77ada2138ae4fa8d6c4de0398a14f3f000000004241044d05240cfbd8a2786eda9dadd520c1609b8593ff8641018d57703d02ba687cf2f187f0cee2221c3afb1b5ff7888caced2423916b61444666ca1216f26181398cffffffff"
    let btcLockerVout = "0x0200e1f505000000001976a9144062c8aeed4f81c2d73ff854a2957021191e20b688ac984f42060100000016001447ef833107e0ad9998f8711813075ac62ec1104b"
    let btcLockerLocktime = "0x00000000"
    let btcLockerInterMediateNodes = "0x7451e7cd7a5afcd93d5a3f84e4d7976fb3bd771dc6aeab416d818ea1d72c0476"
    let lockerRedeemScript = "0x044d05240cfbd8a2786eda9dadd520c1609b8593ff8641018d57703d02ba687cf2f187f0cee2221c3afb1b5ff7888caced2423916b61444666ca1216f26181398c"

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
        
        // Deploys contracts
        ccBurnRouter = await deployCCBurnRouter();
        teleBTC = await deployTeleBTC();
        await ccBurnRouter.setTeleBTC(teleBTC.address);

        // Mints TeleBTC for user
        TeleBTCSigner1 = await teleBTC.connect(signer1);
        await TeleBTCSigner1.mintTestToken();
        
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
            TRANSFER_DEADLINE,
            PROTOCOL_PERCENTAGE_FEE,
            SLASHER_PERCENTAGE_REWARD,
            BITCOIN_FEE
        );

        return ccBurnRouter;
    };

    async function setLockersSlashLockerReturn(): Promise<void> {
        await mockLockers.mock.slashLocker
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
        await TeleBTCSigner1.mintTestToken();
    }

    async function sendBurnRequest(
        theBlockNumber: number, 
        _userRequestedAmount: BigNumber
    ): Promise<number> {
        // Gives allowance to ccBurnRouter
        await TeleBTCSigner1.approve(
            ccBurnRouter.address,
            _userRequestedAmount
        );

        // Sets mock contracts outputs
        await setRelayLastSubmittedHeight(theBlockNumber);
        await setLockersIsLocker(true);
        let burntAmount: number;
        let protocolFee = Math.floor(_userRequestedAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
        burntAmount = _userRequestedAmount.toNumber() - BITCOIN_FEE - protocolFee;
        await setLockersBurnReturn(burntAmount);
        
        await setLockersGetLockerTargetAddress();

        // Burns eleBTC
        await ccBurnRouterSigner1.ccBurn(
            _userRequestedAmount,
            userLockingScript,
            LOCKER1_LOCKING_SCRIPT
        );

        return burntAmount;
    }

    async function provideProof(theBlockNumber: number) {

        // Get the locker target address
        // let LOCKER_TARGET_ADDRESS = await mockLockers.redeemScriptHash();
        

        // Set mock contracts outputs
        await setRelayCheckTxProofReturn(true);
        await setLockersIsLocker(true);

        let burntAmount: number;
        let protocolFee = Math.floor(userRequestedAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
        burntAmount = userRequestedAmount.toNumber() - BITCOIN_FEE - protocolFee;
        await setLockersBurnReturn(burntAmount);

        await setLockersGetLockerTargetAddress();

        // Provide proof that the locker has paid the burnt amount to the user(s)
        await expect(
            ccBurnRouterSigner2.burnProof(
                CC_BURN_REQUESTS.burnProof_valid.version,
                CC_BURN_REQUESTS.burnProof_valid.vin,
                CC_BURN_REQUESTS.burnProof_valid.vout,
                CC_BURN_REQUESTS.burnProof_valid.locktime,
                theBlockNumber,
                CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                1,
                LOCKER_TARGET_ADDRESS,
                0,
                0
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
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    userRequestedAmount,
                    userLockingScript,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.emit(ccBurnRouter, "CCBurn").withArgs(
                signer1Address,
                userLockingScript,
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
                    userLockingScript,
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
                    userLockingScript,
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
                    userLockingScript,
                    LOCKER1_LOCKING_SCRIPT
                )
            ).to.revertedWith("ERC20: transfer amount exceeds allowance")
        })

        it("Reverts since locker's locking script is not valid", async function () {

            await setLockersIsLocker(false);

            await expect(
                ccBurnRouterSigner1.ccBurn(
                    userRequestedAmount,
                    userLockingScript,
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
            burntAmount = await sendBurnRequest(burnReqBlockNumber, userRequestedAmount);
        });
    
        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Submits a valid burn proof", async function () {

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
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                    1,
                    LOCKER1_LOCKING_SCRIPT,
                    0,
                    0
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn").withArgs(
                signer1Address,
                userLockingScript,
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

        it("Submits a valid burn proof which doesn't have change vout", async function () {

            // Sets mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLocker(true);
            await setLockersGetLockerTargetAddress();

            await expect(
                ccBurnRouterSigner2.burnProof(
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.version,
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.vin,
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.vout,
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.locktime,
                    burnReqBlockNumber + 5,
                    CC_BURN_REQUESTS.burnProof_validWithoutChange.intermediateNodes,
                    1,
                    LOCKER1_LOCKING_SCRIPT,
                    0,
                    0
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn").withArgs(
                signer1Address,
                userLockingScript,
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
                    0,
                    0
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
                    0,
                    0
                )
            ).to.revertedWith("CCBurnRouter: given locking script is not locker")
        })

        it("Reverts if index range is not correct (wrong start or end index)", async function () {

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
                    1,
                    0
                )
            ).to.revertedWith("CCBurnRouter: wrong index")

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
                    0,
                    1
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
                    0,
                    0
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
                    0,
                    0
                )
            ).to.revertedWith("CCBurnRouter: transaction has not finalized yet");
        })

        it("Reverts if vout is null", async function () {
            // Sends a burn request
            await sendBurnRequest(burnReqBlockNumber, userRequestedAmount);

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
                    0,
                    0
                )
            ).to.revertedWith("TxHelper: vout is null")
        })

        it("Doesn't accept burn proof since the paid amount is not exact", async function () {
            let wrongUserRequestAmount = BigNumber.from(100080000)  
            let burnReqBlockNumber = 100;

            // Send a burn request
            await sendBurnRequest(burnReqBlockNumber, wrongUserRequestAmount);

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
                    1,
                    1
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
                0,
                0
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
                    0,
                    0
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
                    0,
                    0
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
                0,
                0
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

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });
    
        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Couldn't disputeBurn since lockers have paid before hand", async function () {
            let theBlockNumber = 100;

            // Find the locker target address
            // let LOCKER_TARGET_ADDRESS = await mockLockers.redeemScriptHash();
            

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(100, userRequestedAmount);

            // Locker pays the burnt amount and provides proof
            await provideProof(theBlockNumber + 5);

            // Set mock contracts outputs
            await setRelayLastSubmittedHeight(100);
            await setLockersIsLocker(true);
            await setLockersSlashLockerReturn();

            // Locker will not get slashed because it has paid the burnt amount to the user
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: request has been paid before")
        })

        it("Reverts when deadline hasn't reached", async function () {
            let thisBlockNumber = 100;

            // Find the locker target address
            // let LOCKER_TARGET_ADDRESS = await mockLockers.redeemScriptHash();
            

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(thisBlockNumber + 5, userRequestedAmount);

            // Set mock contracts outputs
            await setLockersIsLocker(true);

            // Locker will not get slashed because the deadline of transfer has not reached
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: payback deadline has not passed yet")
        })

        it("Reverts if the locker is not valid", async function () {
            let theBlockNumber = 100;

            // Find the locker target address
            // let LOCKER_TARGET_ADDRESS = await mockLockers.redeemScriptHash();
            

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, userRequestedAmount);

            // Locker pays the burnt amount and provides proof
            await provideProof(theBlockNumber + 5);

            // Set mock contracts outputs
            await setLockersIsLocker(false);

            // Reverts cuz locker address was not valid
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: given locking script is not locker")
        })

        it("Otherwise goes through", async function () {

            // Find the locker target address
            // let LOCKER_TARGET_ADDRESS = await mockLockers.redeemScriptHash();
            

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(100, userRequestedAmount);

            // Set the last height for relay so that it shows the deadline has passed
            await setRelayLastSubmittedHeight(100 + 23);
            await setLockersSlashLockerReturn();

            // Set mock contracts outputs
            await setLockersIsLocker(true);

            // Locker will not get slashed because the deadline of transfer has not reached
            expect(
                await ccBurnRouterSigner2.disputeBurn(
                    LOCKER_TARGET_ADDRESS,
                    [0]
                )
            );
        })

    });

    describe("#disputeLocker", async () => {

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });
    
        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });
        // it("Dispute the locker who has spent its BTC (without getting a burn request)", async function () {

        //     let thisBlockNumber = await signer1.provider?.getBlockNumber()
        //     let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

        //     // Find the locker target address
        //     // let LOCKER_TARGET_ADDRESS = await mockLockers.redeemScriptHash();
        //     

        //     let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

        //     // Set mock contracts outputs
        //     await setRelayCheckTxProofReturn(true);
        //     await setLockersIsLocker(true);
        //     await setLockersGetLockerRedeemScriptReturn(lockerRedeemScript);
        //     await setRelayLastSubmittedHeight(theBlockNumber.add(30));
        //     await setLockersGetLockerTargetAddress(LOCKER_TARGET_ADDRESS);
        //     await setLockersSlashLockerReturn();

        //     await expect(
        //         ccBurnRouterSigner2.disputeLocker(
        //             LOCKER1_LOCKING_SCRIPT,
        //             LOCKER1_REDEEM_SCRIPT,
        //             0,
        //             btcLockerVersion,
        //             btcLockerVin,
        //             btcLockerVout,
        //             btcLockerLocktime,
        //             theBlockNumber,
        //             btcLockerInterMediateNodes,
        //             1
        //         )
        //     ).to.emit(ccBurnRouter, "LockerDispute")
        // })
    });
});