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

import {WrappedToken} from "../src/types/WrappedToken";
import {WrappedToken__factory} from "../src/types/factories/WrappedToken__factory";
import {InstantPool} from "../src/types/InstantPool";
import {InstantPool__factory} from "../src/types/factories/InstantPool__factory";

import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";


describe("Instant pool", async () => {
    let snapshotId: any;

    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;
    let signer2Address: Address;

    let WrappedBTC: WrappedToken;
    let instantPool: InstantPool;
    let instantPoolAddress: Address;

    let mockInstantRouter: MockContract;

    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000)
    let ten = BigNumber.from(10).pow(18).mul(10)
    let oneHundred = BigNumber.from(10).pow(18).mul(100)

    let name = "InstantPoolToken"
    let symbol = "IPT"
    let instantFee = 5 // means 5%

    before(async () => {

        [deployer, signer1, signer2] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress()
        signer1Address = await signer1.getAddress()
        signer2Address = await signer2.getAddress()

        // read block headers from file

        const instantRouterABI = await deployments.getArtifact(
            "InstantRouter"
        );
        mockInstantRouter = await deployMockContract(
            deployer,
            instantRouterABI.abi
        )

        WrappedBTC = await deployWrappedBTC()

    });

    beforeEach("deploy a new cc exchange router", async () => {
        snapshotId = await takeSnapshot(signer1.provider);

        instantPool = await deployInstantPool();
    });

    afterEach(async () => {
        await revertProvider(signer1.provider, snapshotId);
    });


    const deployInstantPool = async (
        _signer?: Signer
    ): Promise<InstantPool> => {
        const instantPoolFactory = new InstantPool__factory(
            _signer || deployer
        );

        const instantPool = await instantPoolFactory.deploy(
            mockInstantRouter.address,
            WrappedBTC.address,
            name,
            symbol,
            deployerAddress,
            instantFee
        );

        return instantPool;
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
            ONE_ADDRESS
        );

        return wrappedToken;
    };

    describe("#addLiquidity", async () => {

        let theTestMintedAmount = oneHundred

        it("minting instant pool token in exchange of wrapped BTC", async function () {

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            expect(
                await WrappedBTC.balanceOf(signer1Address)
            ).to.equal(theTestMintedAmount)

            let instantPoolSigner1 = await instantPool.connect(signer1)

            await WrappedBTCSigner1.approve(
                instantPool.address,
                theTestMintedAmount
            )

            expect(
                await instantPoolSigner1.addLiquidity(
                    signer1Address,
                    theTestMintedAmount
                )
            ).to.emit(instantPool, "AddLiquidity")


            expect(
                await instantPool.balanceOf(signer1Address)
            ).to.equal(theTestMintedAmount)
        })

    });

    describe("#removeLiquidity", async () => {

        let theTestMintedAmount = oneHundred

        it("minting instant pool token in exchange of wrapped BTC", async function () {

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            let instantPoolSigner1 = await instantPool.connect(signer1)

            await WrappedBTCSigner1.approve(
                instantPool.address,
                theTestMintedAmount
            )

            await instantPoolSigner1.addLiquidity(
                signer1Address,
                theTestMintedAmount
            )

            expect(
                await WrappedBTC.balanceOf(
                    signer1Address
                )
            ).to.equal(0)

            expect(
                await instantPoolSigner1.removeLiquidity(
                    signer1Address,
                    theTestMintedAmount
                )
            ).to.emit(instantPool, "RemoveLiquidity")

            expect(
                await WrappedBTC.balanceOf(
                    signer1Address
                )
            ).to.equal(theTestMintedAmount)

            expect(
                await instantPool.balanceOf(
                    signer1Address
                )
            ).to.equal(0)

        })

    });
});