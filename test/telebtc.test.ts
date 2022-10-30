import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { Address } from "hardhat-deploy/types";
import {TeleBTC} from "../src/types/TeleBTC";
import {TeleBTC__factory} from "../src/types/factories/TeleBTC__factory";

describe("TeleBTC", async () => {
    // Constants
    const ONE_ADDRESS = "0x0000000000000000000000000000000000000011";

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;

    // Contracts
    let teleBTC: TeleBTC;


    before(async () => {
        // Sets accounts
        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();

        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "TBTC"
        );
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
})