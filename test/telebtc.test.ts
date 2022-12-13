import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { Address } from "hardhat-deploy/types";
import {TeleBTC} from "../src/types/TeleBTC";
import {TeleBTC__factory} from "../src/types/factories/TeleBTC__factory";
import { network } from "hardhat"


describe("TeleBTC", async () => {
    // Constants
    const ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    const maxMintLimit = 200 * 10 ** 8;
    const epochLength = 2000;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;
    let signer2Address: Address;

    // Contracts
    let teleBTC: TeleBTC;


    before(async () => {
        // Sets accounts
        [deployer, signer1, signer2] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();
        signer2Address = await signer2.getAddress();

        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "TBTC"
        );


        await teleBTC.addMinter(signer2Address)
    });

  
    describe("#mint rate limit", async () => {

        it("can't mint more than maximum mint limit in one transaction", async function () {
            await expect(
                teleBTC.connect(signer2).mint(ONE_ADDRESS, maxMintLimit * 2)
            ).to.be.revertedWith(
                "TeleBTC: mint amount is more than maximum mint limit"
            )
        })  
        
        it("can't mint more than maximum mint limit in one epoch", async function () {
            await teleBTC.connect(signer2).mint(ONE_ADDRESS, maxMintLimit - 10)
            await expect(
                await teleBTC.lastMintLimit()
            ).to.be.equal(
                10
            )
            await expect(
                teleBTC.connect(signer2).mint(ONE_ADDRESS, 11)
            ).to.be.revertedWith(
                "TeleBTC: reached maximum mint limit"
            )
        })  

        it("after an epoch, mint rate limit will be reset", async function () {
            await moveBlocks(epochLength)

            await teleBTC.connect(signer2).mint(ONE_ADDRESS, maxMintLimit - 10)
            await expect(
                await teleBTC.lastMintLimit()
            ).to.be.equal(
                10
            )

            await teleBTC.connect(signer2).mint(ONE_ADDRESS, 5)
            await expect(
                await teleBTC.lastMintLimit()
            ).to.be.equal(
                5
            )

            await expect(
                teleBTC.connect(signer2).mint(ONE_ADDRESS, 10)
            ).to.be.revertedWith(
                "TeleBTC: reached maximum mint limit"
            )

            await moveBlocks(epochLength)
            await teleBTC.connect(signer2).mint(ONE_ADDRESS, 10)
            await expect(
                await teleBTC.lastMintLimit()
            ).to.be.equal(
                maxMintLimit - 10
            )
        })  

        async function moveBlocks(amount: number) {
            for (let index = 0; index < amount; index++) {
              await network.provider.request({
                method: "evm_mine",
                params: [],
              })
            }
        }

    });

    describe("#minter", async () => {

        it("add minter", async function () {
            await expect(
                await teleBTC.addMinter(ONE_ADDRESS)
            ).to.emit(
                teleBTC, "MinterAdded"
            ).withArgs(ONE_ADDRESS);
        })

        it("remove minter", async function () {
            await expect(
                await teleBTC.removeMinter(ONE_ADDRESS)
            ).to.emit(
                teleBTC, "MinterRemoved"
            ).withArgs(ONE_ADDRESS);
        })

    });

    describe("#burner", async () => {

        it("add burner", async function () {
            await expect(
                await teleBTC.addBurner(ONE_ADDRESS)
            ).to.emit(
                teleBTC, "BurnerAdded"
            ).withArgs(ONE_ADDRESS);
        })

        it("remove burner", async function () {
            await expect(
                await teleBTC.removeBurner(ONE_ADDRESS)
            ).to.emit(
                teleBTC, "BurnerRemoved"
            ).withArgs(ONE_ADDRESS);
        })

    });

    describe("Setters", async () => {

        it("none owner accounts can't change maximum mint limit", async function () {
            await expect(
                teleBTC.connect(signer1).setMaxMintLimit(10)
            ).to.be.revertedWith(
                "Ownable: caller is not the owner"
            )
        })

        it("owner account can change maximum mint limit", async function () {
            await expect(
                await teleBTC.setMaxMintLimit(10)
            ).to.emit(
                teleBTC, "NewMintLimit"
            ).withArgs(
                maxMintLimit, 10
            )

            await expect(
                await teleBTC.maxMintLimit()
            ).to.equal(10)

        })

        it("none owner accounts can't change epoch length", async function () {
            await expect(
                teleBTC.connect(signer1).setEpochLength(10)
            ).to.be.revertedWith (
                "Ownable: caller is not the owner"
            )
        })

        it("owner account can change epoch length", async function () {
            await expect(
                await teleBTC.setEpochLength(10)
            ).to.emit(
                teleBTC, "NewEpochLength"
            ).withArgs(
                epochLength, 10
            )

            await expect(
                await teleBTC.epochLength()
            ).to.equal(10)

        })

        it("can't change epoch length to zero", async function () {
            await expect(
                teleBTC.setEpochLength(0)
            ).to.be.revertedWith(
                "TeleBTC: value is zero"
            )
        })
    })
    

})