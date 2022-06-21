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
import {WrappedToken} from "../src/types/WrappedToken";
import {WrappedToken__factory} from "../src/types/factories/WrappedToken__factory";
import {CCBurnRouter} from "../src/types/CCBurnRouter";
import {CCBurnRouter__factory} from "../src/types/factories/CCBurnRouter__factory";

import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";

describe("CC Exchange Router", async () => {
    let snapshotId: any;

    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;
    let signer2Address: Address;

    let TeleportDAOToken: ERC20;
    let WrappedBTC: WrappedToken;

    let mockBitcoinRelay: MockContract;
    let mockBitcoinTeleporter: MockContract;

    let ccBurnRouter: CCBurnRouter;

    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000)
    let ten = BigNumber.from(10).pow(18).mul(10)
    let oneHundred = BigNumber.from(10).pow(18).mul(100)

    let confirmationParameter = 6
    let transferDeadline = 10
    let burningFee = 5 // means 5%


    let btcPublicKey = "03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd"
    let btcAddress = "mmPPsxXdtqgHFrxZdtFCtkwhHynGTiTsVh"
    let btcDecodedAddress = "0x6f4062c8aeed4f81c2d73ff854a2957021191e20b682c197a8"


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

        const bitcoinTeleporter = await deployments.getArtifact(
            "BitcoinTeleporter"
        );
        mockBitcoinTeleporter = await deployMockContract(
            deployer,
            bitcoinTeleporter.abi
        )

        TeleportDAOToken = await deployTelePortDaoToken()
        WrappedBTC = await deployWrappedBTC()

    });

    beforeEach("deploy a new cc exchange router", async () => {
        snapshotId = await takeSnapshot(signer1.provider);

        ccBurnRouter = await deployCCBurnRouter();

        await ccBurnRouter.setWrappedBitcoin(WrappedBTC.address)
    });

    afterEach(async () => {
        await revertProvider(signer1.provider, snapshotId);
    });

    const deployTelePortDaoToken = async (
        _signer?: Signer
    ): Promise<ERC20> => {
        const erc20Factory = new ERC20__factory(
            _signer || deployer
        );

        const wrappedToken = await erc20Factory.deploy(
            // TODO: change to the correct name
            "WrappedBTC",
            "TBTC",
            telePortTokenInitialSupply
        );

        return wrappedToken;
    };

    const deployWrappedBTC = async (
        _signer?: Signer
    ): Promise<WrappedToken> => {
        const wrappedTokenFactory = new WrappedToken__factory(
            _signer || deployer
        );

        const wrappedToken = await wrappedTokenFactory.deploy(
            "WrappedBTC",
            "TBTC",
            ZERO_ADDRESS
        );

        return wrappedToken;
    };

    const deployCCBurnRouter = async (
        _signer?: Signer
    ): Promise<CCBurnRouter> => {
        const ccBurnRouterFactory = new CCBurnRouter__factory(
            _signer || deployer
        );


        const ccBurnRouter = await ccBurnRouterFactory.deploy(
            mockBitcoinRelay.address,
            mockBitcoinTeleporter.address,
            TeleportDAOToken.address,
            confirmationParameter,
            transferDeadline,
            burningFee
        );

        return ccBurnRouter;
    };

    describe("#ccBurn", async () => {

        let theTestMintedAmount = ten

        it("burning wrapped BTC by ccBurn function", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            await WrappedBTCSigner1.approve(
                ccBurnRouter.address,
                theTestMintedAmount
            )

            expect(
                await WrappedBTC.allowance(signer1Address, ccBurnRouter.address)
            ).to.equal(theTestMintedAmount)


            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                theBlockNumber
            )


            expect(
                await ccBurnRouterSigner1.ccBurn(
                    theTestMintedAmount,
                    btcDecodedAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")

            let theUnWrapRequest = await ccBurnRouter.unWrapRequests(0)

            expect(
                theUnWrapRequest.amount
            ).to.equal(theTestMintedAmount)
        })

    });

    describe("#burnProof", async () => {

        let theTestMintedAmount = BigNumber.from(100000000)

        it("providing the btc transfer proof by bunrProof function", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            await WrappedBTCSigner1.approve(
                ccBurnRouter.address,
                theTestMintedAmount
            )

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                theBlockNumber
            )

            expect(
                await ccBurnRouterSigner1.ccBurn(
                    theTestMintedAmount,
                    btcDecodedAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")


            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            await mockBitcoinRelay.mock.checkTxProof.returns(
                true
            )

            expect(
                await ccBurnRouterSigner2.burnProof(
                    btcVersion,
                    btcVin,
                    btcVout,
                    btcLocktime,
                    theBlockNumber.add(5),
                    btcInterMediateNodes,
                    1,
                    false,
                    0
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn")
        })

    });

    describe("#disputeBurn", async () => {

        let theTestMintedAmount = BigNumber.from(100000000)

        it("couldn't disputeBurn since lockers have paid before hand", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            await WrappedBTCSigner1.approve(
                ccBurnRouter.address,
                theTestMintedAmount
            )

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                theBlockNumber
            )

            expect(
                await ccBurnRouterSigner1.ccBurn(
                    theTestMintedAmount,
                    btcDecodedAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")


            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            await mockBitcoinRelay.mock.checkTxProof.returns(
                true
            )

            expect(
                await ccBurnRouterSigner2.burnProof(
                    btcVersion,
                    btcVin,
                    btcVout,
                    btcLocktime,
                    theBlockNumber.add(5),
                    btcInterMediateNodes,
                    1,
                    false,
                    0
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn")


            await expect(
                ccBurnRouterSigner1.disputeBurn(
                    0,
                    signer1Address
                )
            ).to.revertedWith("Request has been paid before")
        })

        it("deadline hasn't reached", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            await WrappedBTCSigner1.approve(
                ccBurnRouter.address,
                theTestMintedAmount
            )

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                theBlockNumber
            )

            console.log("theBlockNumber: ", theBlockNumber)

            expect(
                await ccBurnRouterSigner1.ccBurn(
                    theTestMintedAmount,
                    btcDecodedAddress
                )
            ).to.emit(ccBurnRouter, "CCBurn")


            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                theBlockNumber.add(15)
            )

            await mockBitcoinTeleporter.mock.slashTeleporters.returns()

            await ccBurnRouterSigner1.disputeBurn(
                0,
                signer1Address
            )
        })

    });

});