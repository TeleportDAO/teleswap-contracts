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
    let teleBTCSigner1: TeleBTC;
    let instantPoolSigner1: InstantPool;

    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";

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
        );

        // Mints teleBTC for deployer
        await teleBTC.addMinter(deployerAddress)
        await teleBTC.mint(deployerAddress, 10000000);

        // Deploys instant pool contract
        const instantPoolFactory = new InstantPool__factory(deployer);
        instantPool = await instantPoolFactory.deploy(
            teleBTC.address,
            deployerAddress,
            instantFee,
            name,
            symbol
        );

        // Connects signer1 to teleBTC and instant pool
        teleBTCSigner1 = await teleBTC.connect(signer1);
        instantPoolSigner1 = await instantPool.connect(signer1);
    });

    describe("#setInstantRouter", async () => {


        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Non owner accounts can't set instant router", async function () {
            await expect(
                instantPoolSigner1.setInstantRouter(
                    signer1Address
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("Owner can set instant router successfully", async function () {
            await expect( await instantPool.setInstantRouter(
                signer1Address
            )).to.emit(
                instantPool, "NewInstantRouter"
            ).withArgs(deployerAddress, signer1Address);

            expect(
                await instantPool.instantRouter()
            ).to.equal(signer1Address)

        })
    });

    describe("#setInstantPercentageFee", async () => {

        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Non owner accounts can't set instant router", async function () {
            await expect(
                instantPoolSigner1.setInstantPercentageFee(
                    5000
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("Owner can set instant router successfully", async function () {
            await expect (await instantPool.setInstantPercentageFee(
                5000
            )).to.emit(
                instantPool, "NewInstantPercentageFee"
            ).withArgs(instantFee, 5000);

            expect(
                await instantPool.instantPercentageFee()
            ).to.equal(5000)

        })
    });

    describe("#setTeleBTC", async () => {

        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Non owner accounts can't set instant router", async function () {
            await expect(
                instantPoolSigner1.setTeleBTC(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("Owner can set instant router successfully", async function () {
            await expect(await instantPool.setTeleBTC(
                ONE_ADDRESS
            )).to.emit(
                instantPool, "NewTeleBTC"
            ).withArgs(teleBTC.address, ONE_ADDRESS);

            expect(
                await instantPool.teleBTC()
            ).to.equal(ONE_ADDRESS)

        })
    });


    describe("#addLiquidity", async () => {

        let addedLiquidity = 100;

        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Mints instant pool token when instant pool is empty", async function () {

            await teleBTC.transfer(signer1Address, addedLiquidity);

            await teleBTCSigner1.approve(
                instantPool.address,
                addedLiquidity
            );

            await expect(
                await instantPoolSigner1.addLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "AddLiquidity");

            expect(
                await instantPool.balanceOf(signer1Address)
            ).to.equal(addedLiquidity);

            expect(
                await instantPool.totalAddedTeleBTC()
            ).to.equal(addedLiquidity);
        })

        it("Mints instant pool token when instant pool is non-empty", async function () {
            // Adds initial liquidity to instant pool
            await teleBTC.approve(
                instantPool.address,
                addedLiquidity
            );

            await instantPool.addLiquidity(
                deployerAddress,
                addedLiquidity
            );

            await teleBTC.transfer(signer1Address, addedLiquidity);

            await teleBTCSigner1.approve(
                instantPool.address,
                addedLiquidity
            );

            await expect(
                await instantPoolSigner1.addLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "AddLiquidity");

            expect(
                await instantPool.balanceOf(signer1Address)
            ).to.equal(addedLiquidity);

            expect(
                await instantPool.totalAddedTeleBTC()
            ).to.equal(addedLiquidity*2);
        })

        it("Mints instant pool token after some amount of teleBTC was transferred directly", async function () {
            // Transfers teleBTC  to instant pool
            await teleBTC.transfer(
                instantPool.address,
                addedLiquidity
            );

            await teleBTC.transfer(signer1Address, addedLiquidity);

            await teleBTCSigner1.approve(
                instantPool.address,
                addedLiquidity
            );

            await expect(
                await instantPoolSigner1.addLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "AddLiquidity");

            expect(
                await instantPool.balanceOf(signer1Address)
            ).to.equal(addedLiquidity);

            expect(
                await instantPool.totalAddedTeleBTC()
            ).to.equal(addedLiquidity);
        })

        it("Mints instant pool token after some amount of teleBTC was added using addLiquidityWithoutMint", async function () {
            // Adds teleBTC  to instant pool
            await teleBTC.approve(instantPool.address, addedLiquidity);
            await instantPool.addLiquidityWithoutMint(addedLiquidity);

            await teleBTC.transfer(signer1Address, addedLiquidity);

            await teleBTCSigner1.approve(
                instantPool.address,
                addedLiquidity
            );

            await expect(
                await instantPoolSigner1.addLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "AddLiquidity");

            expect(
                await instantPool.balanceOf(signer1Address)
            ).to.equal(addedLiquidity);

            expect(
                await instantPool.totalAddedTeleBTC()
            ).to.equal(addedLiquidity*2);
        })

        it("Reverts since input amount is zero", async function () {
            await expect(
                instantPoolSigner1.addLiquidity(
                    signer1Address,
                    0
                )
            ).to.revertedWith("InstantPool: input amount is zero")
        })

        it("Reverts since user balance is not enough", async function () {
            await expect(
                instantPoolSigner1.addLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.reverted;
        })

    });

    describe("#removeLiquidity", async () => {

        let addedLiquidity = 100;

        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Burns instant pool token to withdraw teleBTC", async function () {

            await teleBTC.transfer(signer1Address, addedLiquidity);

            await teleBTCSigner1.approve(
                instantPool.address,
                addedLiquidity
            );

            await instantPoolSigner1.addLiquidity(
                signer1Address,
                addedLiquidity
            );

            await expect(
                await instantPoolSigner1.removeLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "RemoveLiquidity")

            expect(
                await teleBTC.balanceOf(
                    signer1Address
                )
            ).to.equal(addedLiquidity);

            expect(
                await instantPool.balanceOf(
                    signer1Address
                )
            ).to.equal(0);
        })

        it("Burns instant pool token after some amount of teleBTC was transferred directly", async function () {

            await teleBTC.transfer(instantPool.address, addedLiquidity);

            await teleBTC.transfer(signer1Address, addedLiquidity);

            await teleBTCSigner1.approve(
                instantPool.address,
                addedLiquidity
            );

            await instantPoolSigner1.addLiquidity(
                signer1Address,
                addedLiquidity
            );

            await expect(
                await instantPoolSigner1.removeLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "RemoveLiquidity")

            expect(
                await teleBTC.balanceOf(
                    signer1Address
                )
            ).to.equal(addedLiquidity);

            expect(
                await instantPool.balanceOf(
                    signer1Address
                )
            ).to.equal(0);
        })

        it("Burns instant pool token after some amount of teleBTC was added using addLiquidityWithoutMint (before addLiquidity)", async function () {
            // Adds teleBTC  to instant pool
            await teleBTC.approve(instantPool.address, addedLiquidity);
            await instantPool.addLiquidityWithoutMint(addedLiquidity);

            await teleBTC.transfer(signer1Address, addedLiquidity);

            await teleBTCSigner1.approve(
                instantPool.address,
                addedLiquidity
            );

            await instantPoolSigner1.addLiquidity(
                signer1Address,
                addedLiquidity
            );

            await expect(
                await instantPoolSigner1.removeLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "RemoveLiquidity")

            expect(
                await teleBTC.balanceOf(
                    signer1Address
                )
            ).to.equal(addedLiquidity*2);

            expect(
                await instantPool.balanceOf(
                    signer1Address
                )
            ).to.equal(0);
        })

        it("Burns instant pool token after some amount of teleBTC was added using addLiquidityWithoutMint (after addLiquidity)", async function () {

            await teleBTC.transfer(signer1Address, addedLiquidity);

            await teleBTCSigner1.approve(
                instantPool.address,
                addedLiquidity
            );

            await instantPoolSigner1.addLiquidity(
                signer1Address,
                addedLiquidity
            );

            // Adds teleBTC  to instant pool
            await teleBTC.approve(instantPool.address, addedLiquidity);
            await instantPool.addLiquidityWithoutMint(addedLiquidity);

            await expect(
                await instantPoolSigner1.removeLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "RemoveLiquidity")

            expect(
                await teleBTC.balanceOf(
                    signer1Address
                )
            ).to.equal(addedLiquidity*2);

            expect(
                await instantPool.balanceOf(
                    signer1Address
                )
            ).to.equal(0);
        })

        it("Reverts since input amount is zero", async function () {
            await expect(
                instantPoolSigner1.removeLiquidity(
                    signer1Address,
                    0
                )
            ).to.revertedWith("InstantPool: input amount is zero")
        })

        it("Reverts since user balance is not enough", async function () {
            await expect(
                instantPoolSigner1.removeLiquidity(
                    signer1Address,
                    addedLiquidity
                )
            ).to.revertedWith("InstantPool: balance is not sufficient")
        })

    });

    describe("#getLoan", async () => {

        let addedLiquidity = 100;

        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
            await teleBTC.approve(instantPool.address, addedLiquidity);
            await instantPool.addLiquidity(
                deployerAddress,
                addedLiquidity
            );
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Gets loan from instant pool", async function () {
            await expect(
                instantPool.getLoan(
                    signer1Address,
                    addedLiquidity
                )
            ).to.emit(instantPool, "InstantLoan")
        })

        it("Reverts since message sender is not instant router", async function () {
            await expect(
                instantPoolSigner1.getLoan(
                    signer1Address,
                    addedLiquidity
                )
            ).to.revertedWith("InstantPool: sender is not allowed")
        })

        it("Reverts since available liquidity is not sufficient", async function () {
            // Gets a loan that makes instant pool empty
            await instantPool.getLoan(
                signer1Address,
                addedLiquidity
            );

            await expect(
                instantPool.getLoan(
                    signer1Address,
                    addedLiquidity
                )
            ).to.revertedWith("InstantPool: liquidity is not sufficient")
        })

    });

});