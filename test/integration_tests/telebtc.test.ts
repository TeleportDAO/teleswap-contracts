import { expect, use } from "chai"
import { ethers } from "hardhat"
import { solidity } from "ethereum-waffle"
import * as fs from "fs"
const hre = require("hardhat");
import { deployFile, privateKey } from "../../helper-hardhat-config"
import { Wallet } from "@ethersproject/wallet";
import { BigNumber } from "@ethersproject/bignumber";

describe("telebtc (integration test)", async () => {
    const { network } = hre
    const oneUnit = BigNumber.from(10).pow(8)
    const deployJSON = JSON.parse(fs.readFileSync(deployFile + network.name + "/TeleBTC.json", "utf8"))
    const teleBTCAddress = deployJSON.address

    let signer : Wallet;
    let teleBTC;

    before(async () => {
        signer = new ethers.Wallet(privateKey, ethers.provider);

        // instance of telebtc
        teleBTC = await ethers.getContractAt("TeleBTC", teleBTCAddress, signer)
    })

    describe("#deployment checks", async () => { 
        it("deployment values are right", async () => {
            await expect(await teleBTC.name()).to.equal("TeleBitcoin")
            await expect(await teleBTC.symbol()).to.equal("TBTC")
        })
    })

    describe("#Mint", async () => { 
        it("mint teleBTC", async () => {
            let totalSupply = await teleBTC.totalSupply()
            let currentBalance = await teleBTC.balanceOf(signer.address)
            let mintAmount = oneUnit.mul(2)
            let tx;

            if (await teleBTC.minters(signer.address) == false) {
                tx = await teleBTC.addMinter(signer.address);
                await tx.wait(1)
            }

            tx = await teleBTC.mint(signer.address, mintAmount);
            await tx.wait(1)
            console.log('mint token hash: ', tx.hash)

            await expect(await teleBTC.totalSupply()).to.equal(totalSupply.add(mintAmount))
            await expect(await teleBTC.balanceOf(signer.address)).to.equal(currentBalance.add(mintAmount))
        })
    })

    describe("#Burn", async () => { 
        it("burn teleBTC", async () => {
            let totalSupply = await teleBTC.totalSupply()
            let currentBalance = await teleBTC.balanceOf(signer.address)
            let burnAmount = oneUnit.mul(2)
            let tx;

            if (await teleBTC.burners(signer.address) == false) {
                tx = await teleBTC.addBurner(signer.address);
                await tx.wait(1)
            }

            tx = await teleBTC.burn(burnAmount);
            await tx.wait(1)
            console.log('burn token hash: ', tx.hash)

            await expect(await teleBTC.totalSupply()).to.equal(totalSupply.sub(burnAmount))
            await expect(await teleBTC.balanceOf(signer.address)).to.equal(currentBalance.sub(burnAmount))
        })
    })
})