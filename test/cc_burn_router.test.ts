// const BitcoinRelay = artifacts.require("BitcoinRelay");
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";
import { Address } from "hardhat-deploy/types";

import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import {ERC20} from "../src/types/ERC20";
import {ERC20__factory} from "../src/types/factories/ERC20__factory";
import {TeleBTC} from "../src/types/TeleBTC";
import {TeleBTC__factory} from "../src/types/factories/TeleBTC__factory";
import {CCBurnRouter} from "../src/types/CCBurnRouter";
import {CCBurnRouter__factory} from "../src/types/factories/CCBurnRouter__factory";

import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";

describe("CC Burn Router", async () => {
    let snapshotId: any;

    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;
    let signer2Address: Address;

    let TeleportDAOToken: ERC20;
    let teleBTC: TeleBTC;

    let mockBitcoinRelay: MockContract;
    let mockLockers: MockContract; // TODO it's teleporter or now; change to locker
    let mockCCTransferRouter: MockContract;
    let mockCCExchangeRouter: MockContract;

    let ccBurnRouter: CCBurnRouter;

    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";

    // let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000)
    let ten = BigNumber.from(10).pow(8).mul(10)
    let oneHundred = BigNumber.from(10).pow(8).mul(100)

    // This one is set so that:
    // userRequestAmount * (1 - lockerFee / 10000 - protocolFee / 10000) - bitcoinFee = 100000000
    let userRequestAmount = BigNumber.from(100070042)

    let confirmationParameter = 6
    let transferDeadline = 20
    let protocolFee = 5 // means 0.05%
    let lockerFee = 1 // means 0.01%
    let bitcoinFee = 10000 // estimation of Bitcoin transaction fee in Satoshi


    let btcPublicKey = "03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd"
    let btcAddress = "mmPPsxXdtqgHFrxZdtFCtkwhHynGTiTsVh"
    let btcDecodedAddress = "0x4062c8aeed4f81c2d73ff854a2957021191e20b6"


    let btcVersion =  "0x02000000"
    let btcVin = "0x01df4a990ad3c3a225862465bb660f06d445914a038ada819ace235afb9f23cff30200000000feffffff"
    let btcVout = "0x0200e1f505000000001976a9144062c8aeed4f81c2d73ff854a2957021191e20b688ac984f42060100000016001447ef833107e0ad9998f8711813075ac62ec1104b"
    let btcLocktime = "0x00000000"
    let btcInterMediateNodes = "0x7451e7cd7a5afcd93d5a3f84e4d7976fb3bd771dc6aeab416d818ea1d72c0476"

    before(async () => {

        [deployer, signer1, signer2] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress()
        signer1Address = await signer1.getAddress()
        signer2Address = await signer2.getAddress()

        // read block headers from file

        const bitcoinRelay = await deployments.getArtifact(
            "IBitcoinRelay"
        );
        mockBitcoinRelay = await deployMockContract(
            deployer,
            bitcoinRelay.abi
        )

        const lockers = await deployments.getArtifact(
            "Lockers"
        );
        mockLockers = await deployMockContract(
            deployer,
            lockers.abi
        )

        const ccTransferRouter = await deployments.getArtifact(
            "CCTransferRouter"
        );
        mockCCTransferRouter = await deployMockContract(
            deployer,
            ccTransferRouter.abi
        )

        const ccExchangeRouter = await deployments.getArtifact(
            "BitcoinTeleporter"
        );
        mockCCExchangeRouter = await deployMockContract(
            deployer,
            ccExchangeRouter.abi
        )

        ccBurnRouter = await deployCCBurnRouter();

        teleBTC = await deployTeleBTC()

        await ccBurnRouter.setTeleBTC(teleBTC.address)
    });

    beforeEach("deploy a new cc exchange router", async () => {
        snapshotId = await takeSnapshot(signer1.provider);
    });

    afterEach(async () => {
        await revertProvider(signer1.provider, snapshotId);
    }); // TODO: why revert when we are deploying a new ccBurnRouter before each?

    const deployTeleBTC = async (
        _signer?: Signer
    ): Promise<TeleBTC> => {
        const teleBTCFactory = new TeleBTC__factory(
            _signer || deployer
        );

        const teleBTC = await teleBTCFactory.deploy(
            "Teleport Wrapped BTC",
            "TeleBTC",
            mockCCTransferRouter.address,
            mockCCExchangeRouter.address,
            ccBurnRouter.address
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
            ZERO_ADDRESS,
            transferDeadline,
            lockerFee,
            protocolFee,
            bitcoinFee
        );

        return ccBurnRouter;
    };

    async function setLockersReturn(): Promise<void> {
        await mockLockers.mock.redeemScriptHash
            .returns(ONE_ADDRESS);
    }

    async function setLockersSlashLockerReturn(): Promise<void> {
        await mockLockers.mock.slashLocker
            .returns(true);
    }

    async function setRelayLastSubmittedHeightReturn(theBlockNumber: BigNumber): Promise<void> {
        await mockBitcoinRelay.mock.lastSubmittedHeight
            .returns(theBlockNumber);
    }

    async function setRelayCheckTxProofReturn(isFinal: boolean): Promise<void> {
        await mockBitcoinRelay.mock.checkTxProof
        .returns(isFinal);
    }

    describe("#ccBurn", async () => {

        let theTestAmount = userRequestAmount;

        it("burning wrapped BTC by ccBurn function", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await TeleBTCSigner1.mintTestToken()

            expect(
                await TeleBTCSigner1.balanceOf(signer1Address)
            ).to.equal(oneHundred)
            
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                theTestAmount
            )

            // Give the allowance to the ccBurnRouter so that it could burn tokens
            expect(
                await teleBTC.allowance(signer1Address, ccBurnRouter.address)
            ).to.equal(theTestAmount)

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(theBlockNumber);
            await setLockersReturn();

            let lockerTargetAddress = await mockLockers.redeemScriptHash();

            let totalSupplyBefore = await TeleBTCSigner1.totalSupply();
            
            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    theTestAmount,
                    btcDecodedAddress,
                    false,
                    false,
                    lockerTargetAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")

            let totalSupplyAfter = await TeleBTCSigner1.totalSupply();

            // Get the burn request that has been saved in the contract
            let theBurnRequest = await ccBurnRouter.burnRequests(lockerTargetAddress, 0);
            
            expect(
                theBurnRequest.amount
            ).to.equal(theTestAmount)
            // Difference of total supply of tokens should be user input amount minus fees
            expect(
                totalSupplyBefore.sub(totalSupplyAfter)
            ).to.equal(theBurnRequest.remainedAmount);

        })

        it("ccBurn function works if user Bitcoin address is script hash and is segwit", async function () {
        
        })

        it("ccBurn function works if user Bitcoin address is script hash and is non-segwit", async function () {
        
        })

        it("ccBurn function works if user Bitcoin address is not script hash and is segwit", async function () {
        
        })
        
        it("ccBurn function reverts if enough allowance is not given", async function () {
        
        })

        it("ccBurn function reverts if user Bitcoin address is invalid", async function () {
        
        })

        it("ccBurn function reverts if input locker address is not a valid locker", async function () {
        
        })

    });

    describe("#burnProof", async () => {

        let theTestAmount = userRequestAmount;

        it("Providing the btc transfer proof by burnProof function", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await TeleBTCSigner1.mintTestToken()
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                theTestAmount
            )

            // Give the allowance to the ccBurnRouter so that it could burn tokens
            expect(
                await teleBTC.allowance(signer1Address, ccBurnRouter.address)
            ).to.equal(theTestAmount)

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(theBlockNumber);
            await setLockersReturn();

            let lockerTargetAddress = await mockLockers.redeemScriptHash();

            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    theTestAmount,
                    btcDecodedAddress,
                    false,
                    false,
                    lockerTargetAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            await setRelayCheckTxProofReturn(true);

            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcVersion,
                    btcVin,
                    btcVout,
                    btcLocktime,
                    theBlockNumber.add(5),
                    btcInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    0,
                    0
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn")
        })

        it("Reverts if index range is not correct (wrong start index)", async function () {
        
        })

        it("Reverts if index range is not correct (wrong end index)", async function () {
        
        })

        it("Reverts if index range is not correct (tx not in range)", async function () {
        
        })
        
        it("Reverts if locker is not valid", async function () {
        
        })

        it("Reverts if locker's tx has not been finalized on relay", async function () {
        
        })

        it("Reverts if provided tx doesn't exist", async function () {
        
        })

        it("Reverts if the paid amount is not exact", async function () {

        })
    });

    describe("#disputeBurn", async () => {

        let theTestAmount = userRequestAmount;

        it("Couldn't disputeBurn since lockers have paid before hand", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await TeleBTCSigner1.mintTestToken()
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                theTestAmount
            )
            // Give the allowance to the ccBurnRouter so that it could burn tokens
            await teleBTC.allowance(signer1Address, ccBurnRouter.address)

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)
            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(theBlockNumber);
            await setLockersReturn();

            let lockerTargetAddress = await mockLockers.redeemScriptHash();

            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    theTestAmount,
                    btcDecodedAddress,
                    false,
                    false,
                    lockerTargetAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            await setRelayCheckTxProofReturn(true);

            // Provide proof that the locker has paid the burnt amount to the user(s)
            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcVersion,
                    btcVin,
                    btcVout,
                    btcLocktime,
                    theBlockNumber.add(5),
                    btcInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    0,
                    0
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn")

            // Locker will not get slashed because it has paid the burnt amount to the user
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    lockerTargetAddress,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: request has been paid before")
        })

        it("Reverts when deadline hasn't reached", async function () {
            let thisBlockNumber = BigNumber.from(await signer1.provider?.getBlockNumber())

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await TeleBTCSigner1.mintTestToken()
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                theTestAmount
            )
            // Give the allowance to the ccBurnRouter so that it could burn tokens
            await teleBTC.allowance(signer1Address, ccBurnRouter.address)

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)
            // Set mock contracts outputs
            // For Relay suppose 5 blocks has passed (transfer deadline is 20 blocks)
            // So the deadline has not passed yet
            await setRelayLastSubmittedHeightReturn(thisBlockNumber.add(5));
            await setLockersReturn();

            let lockerTargetAddress = await mockLockers.redeemScriptHash();

            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    theTestAmount,
                    btcDecodedAddress,
                    false,
                    false,
                    lockerTargetAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Locker will not get slashed because the deadline of transfer has not reached
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    lockerTargetAddress,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: payback deadline has not passed yet")
        })

        it("Reverts if the locker is not valid", async function () {

        })

        it("Otherwise goes through", async function () {
            let thisBlockNumber = BigNumber.from(await signer1.provider?.getBlockNumber())

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await TeleBTCSigner1.mintTestToken()
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                theTestAmount
            )
            // Give the allowance to the ccBurnRouter so that it could burn tokens
            await teleBTC.allowance(signer1Address, ccBurnRouter.address)

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)
            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(thisBlockNumber);
            await setLockersReturn();

            let lockerTargetAddress = await mockLockers.redeemScriptHash();

            // let ccBurnRouterDeployer = await ccBurnRouter.connect(deployer)
            // 
            // await ccBurnRouterDeployer.setTransferDeadline(0);

            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    theTestAmount,
                    btcDecodedAddress,
                    false,
                    false,
                    lockerTargetAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")

            // Set the last height for relay so that it shows the deadline has passed
            await setRelayLastSubmittedHeightReturn(thisBlockNumber.add(23));
            await setLockersSlashLockerReturn();

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Locker will not get slashed because the deadline of transfer has not reached
            expect(
                await ccBurnRouterSigner2.disputeBurn(
                    lockerTargetAddress,
                    [0]
                )
            );
        })

    });

});