import { expect, use } from "chai"
import { ethers } from "hardhat"
import { solidity } from "ethereum-waffle"
import * as fs from "fs"
const hre = require("hardhat");
import { deployFile, privateKey } from "../../helper-hardhat-config"
import { Wallet } from "@ethersproject/wallet";
import { BigNumber } from "@ethersproject/bignumber";

describe.only("collateral pool and factory (integration test)", async () => {
    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    const oneUnit = BigNumber.from(10).pow(8)
    const ratio = 10000;

    const { network } = hre
    const factoryDeployJSON = JSON.parse(fs.readFileSync(deployFile + network.name + "/CollateralPoolFactory.json", "utf8"))
    const factoryAddress = factoryDeployJSON.address

    const erc20DeployJSON = JSON.parse(fs.readFileSync(deployFile + network.name + "/ERC20AsDot.json", "utf8"))
    const erc20Address = erc20DeployJSON.address


    let signer : Wallet;
    let factory;
    let collateralPool;
    let erc20;
    let collateralPoolAddress;

    before(async () => {
        signer = new ethers.Wallet(privateKey, ethers.provider);

        // instance of factory
        factory = await ethers.getContractAt("CollateralPoolFactory", factoryAddress, signer)
        erc20 = await ethers.getContractAt("ERC20", erc20Address, signer)
        collateralPoolAddress = await factory.getCollateralPoolByToken(erc20.address)
        let poolsCount = await factory.allCollateralPoolsLength()
        
        if (collateralPoolAddress != ZERO_ADDRESS) {
            console.log("using existing collateral pool at: ", collateralPoolAddress)
        }
        else {
            let tx = await factory.createCollateralPool(erc20.address, ratio);
            let rc = await tx.wait(1)
            collateralPoolAddress = rc.events[3].args[3]
            console.log("deploying new pool at: ", collateralPoolAddress)
            await expect (await factory.allCollateralPoolsLength()).to.equal(Number(poolsCount) + 1)
        }

        collateralPool = await ethers.getContractAt("CollateralPool", collateralPoolAddress, signer)

    })

    describe("#Create collateral pool", async () => { 
        it("add collateral", async () => {
            let tx;
            let currentCollateralPoolTokenAmount = await collateralPool.balanceOf(signer.address)
            let currentErc20TokenAmount = await erc20.balanceOf(signer.address)
            let collateralAmount = 10;
            if (await erc20.balanceOf(signer.address) < collateralAmount)
                erc20.mint(signer.address, collateralAmount)
            
            tx = await erc20.approve(collateralPoolAddress, collateralAmount);
            await tx.wait(1)

            tx = await collateralPool.addCollateral(signer.address, collateralAmount);
            await tx.wait(1)

            await expect(await collateralPool.balanceOf(signer.address)).to.equal(currentCollateralPoolTokenAmount + collateralAmount)
            await expect(await erc20.balanceOf(signer.address)).to.equal(currentErc20TokenAmount - collateralAmount)
        })

        it("remove collateral", async () => {
            let tx;
            let currentCollateralPoolTokenAmount = await collateralPool.balanceOf(signer.address)
            let currentErc20TokenAmount = await erc20.balanceOf(signer.address)
            let collateralAmount = 10;

            tx = await collateralPool.removeCollateral(collateralAmount);
            await tx.wait(1)

            await expect(await collateralPool.balanceOf(signer.address)).to.equal(currentCollateralPoolTokenAmount - collateralAmount)
            await expect(await erc20.balanceOf(signer.address)).to.equal(currentErc20TokenAmount + collateralAmount)
        })
    })

    // describe("#Burn", async () => { 
    //     it("burn teleBTC", async () => {
    //         let totalSupply = await teleBTC.totalSupply()
    //         let currentBalance = await teleBTC.balanceOf(signer.address)
    //         let burnAmount = oneUnit.mul(2)
    //         let tx;

    //         if (await teleBTC.burners(signer.address) == false) {
    //             tx = await teleBTC.addBurner(signer.address);
    //             await tx.wait(1)
    //         }

    //         tx = await teleBTC.burn(burnAmount);
    //         await tx.wait(1)
    //         console.log('burn token hash: ', tx.hash)

    //         await expect(await teleBTC.totalSupply()).to.equal(totalSupply.sub(burnAmount))
    //         await expect(await teleBTC.balanceOf(signer.address)).to.equal(currentBalance.sub(burnAmount))
    //     })
    // })
})