import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { Address } from "hardhat-deploy/types";

import {TeleBTC} from "../src/types/TeleBTC";
import {TeleBTC__factory} from "../src/types/factories/TeleBTC__factory";
import {InstantPool} from "../src/types/InstantPool";
import {InstantPool__factory} from "../src/types/factories/InstantPool__factory";

import { takeSnapshot, revertProvider } from "./block_utils";


describe("Instant pool", async () => {
    let snapshotId: any;

    let deployer: Signer;
    let signer1: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;

    let teleBTC: TeleBTC;
    let instantPool: InstantPool;

    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let ten = BigNumber.from(10).pow(18).mul(10)
    let oneHundred = BigNumber.from(10).pow(8).mul(100)

    let name = "InstantPoolToken"
    let symbol = "IPT"
    let instantFee = 5 // means 5%

    before(async () => {

        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();

        // Deploys teleBTC contract
        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "TBTC",
            ONE_ADDRESS,
            ONE_ADDRESS,
            ONE_ADDRESS
        );

        // Deploys instant pool contract
        const instantPoolFactory = new InstantPool__factory(deployer);
        instantPool = await instantPoolFactory.deploy(
            teleBTC.address,
            deployerAddress,
            instantFee,
            name,
            symbol  
        );
    });

    describe("#addLiquidity", async () => {

        let theTestMintedAmount = oneHundred;

        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });
    
        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Mints instant pool token in exchange of deposited teleBTC", async function () {

            let teleBTCSigner1 = await teleBTC.connect(signer1)

            await teleBTCSigner1.mintTestToken()

            expect(
                await teleBTC.balanceOf(signer1Address)
            ).to.equal(theTestMintedAmount)

            let instantPoolSigner1 = await instantPool.connect(signer1)

            await teleBTCSigner1.approve(
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

        let theTestMintedAmount = oneHundred;

        it("Burns instant pool token in exchange of withdrawing teleBTC", async function () {

            let teleBTCSigner1 = await teleBTC.connect(signer1);

            await teleBTCSigner1.mintTestToken();

            let instantPoolSigner1 = await instantPool.connect(signer1);

            await teleBTCSigner1.approve(
                instantPool.address,
                theTestMintedAmount
            );

            await instantPoolSigner1.addLiquidity(
                signer1Address,
                theTestMintedAmount
            )

            expect(
                await teleBTC.balanceOf(
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
                await teleBTC.balanceOf(
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