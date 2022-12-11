import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer} from "ethers";

import { CollateralPool } from "../src/types/CollateralPool";
import { CollateralPool__factory } from "../src/types/factories/CollateralPool__factory";
import { ERC20AsDot } from "../src/types/ERC20AsDot";
import { ERC20AsDot__factory } from "../src/types/factories/ERC20AsDot__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";

import { takeSnapshot, revertProvider } from "./block_utils";

describe("CollateralPool", async () => {

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let deployerAddress: string;
    let signer1Address: string;

    // Contracts
    let collateralPool: CollateralPool;
    let erc20: ERC20;

    let snapshotId: any;

    before(async () => {
        // Sets accounts
        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();

        // Deploys erc20 contract
        const erc20Factory = new ERC20AsDot__factory(deployer);
        erc20 = await erc20Factory.deploy(
            "TestToken",
            "TT",
            10000
        );
        
        // Deploys collateralPool contract
        const collateralPoolFactory = new CollateralPool__factory(deployer);
        collateralPool = await collateralPoolFactory.deploy(
            "Test-Collateral-Pool",
            "TCP",
            erc20.address,
            10000
        );

    });

    describe("#addCollateral", async () => {

        let addedCollateral = 100;

        beforeEach(async() => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async() => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Adds collateral when collateral pool is empty", async function () {
            // Gives allowance to collateralPool
            await erc20.approve(collateralPool.address, addedCollateral);

            // Adds collateral to collateral pool
            expect(
                await collateralPool.addCollateral(deployerAddress, addedCollateral)
            ).to.emit(collateralPool, "AddCollateral");

            // Checks enough collateral pool token is minted for user
            expect(
                await collateralPool.balanceOf(deployerAddress)
            ).to.equal(addedCollateral);  

            // Checks total added collateral
            expect(
                await collateralPool.totalAddedCollateral()
            ).to.equal(addedCollateral);  
        })

        it("Adds collateral when collateral pool is non-empty", async function () {
            // Transfers 100 collateral token to collateral pool
            await erc20.transfer(collateralPool.address, 100);
            let totalAddedCollateral = await collateralPool.totalAddedCollateral();

            // Adds collateral to collateral pool
            await erc20.approve(collateralPool.address, addedCollateral);
            expect(
                await collateralPool.addCollateral(deployerAddress, addedCollateral)
            ).to.emit(collateralPool, "AddCollateral"); 

            // Checks enough collateral pool token is minted for user
            expect(
                await collateralPool.balanceOf(deployerAddress)
            ).to.equal(addedCollateral);  

            // Checks total added collateral
            expect(
                await collateralPool.totalAddedCollateral()
            ).to.equal(addedCollateral + totalAddedCollateral.toNumber());  
        })

        it("Adds collateral after some fee was sent to collateral pool", async function () {
            // Transfers and adds 100 collateral token to collateral pool
            await erc20.transfer(collateralPool.address, 100);
            await erc20.transfer(signer1Address, 100);
            let erc20Signer1 = await erc20.connect(signer1);
            let collateralPoolSigner1 = await collateralPool.connect(signer1);
            await erc20Signer1.approve(collateralPool.address, 100);
            await collateralPoolSigner1.addCollateral(signer1Address, 100);
            let totalAddedCollateral = await collateralPool.totalAddedCollateral();
            let totalSupply = await collateralPool.totalSupply();

            // Adds collateral to collateral pool
            await erc20.approve(collateralPool.address, addedCollateral);
            expect(
                await collateralPool.addCollateral(deployerAddress, addedCollateral)
            ).to.emit(collateralPool, "AddCollateral");

            // Checks enough collateral pool token is minted for user
            let expectedResult = Math.floor(addedCollateral*totalSupply.toNumber()/totalAddedCollateral.toNumber());
            expect(
                await collateralPool.balanceOf(deployerAddress)
            ).to.equal(expectedResult);  

            // Checks total added collateral
            expect(
                await collateralPool.totalAddedCollateral()
            ).to.equal(addedCollateral + totalAddedCollateral.toNumber());  
        })

        it("Reverts since user hasn't given allowance to collateral pool", async function () {
            expect(
                collateralPool.addCollateral(deployerAddress, 100)
            ).to.reverted; 
        })

        it("Reverts since user address is zero", async function () {
            await expect(
                collateralPool.addCollateral(ZERO_ADDRESS, 100)
            ).to.revertedWith("CollateralPool: zero address"); 
        })

        it("Reverts since amount is zero", async function () {
            await expect(
                collateralPool.addCollateral(deployerAddress, 0)
            ).to.revertedWith("CollateralPool: zero value"); 
        })

    });

    describe("#removeCollateral", async () => {
        
        let addedCollateral = 100;
        
        beforeEach(async() => {
            snapshotId = await takeSnapshot(signer1.provider);

            // Adds collateral
            await erc20.approve(collateralPool.address, addedCollateral);
            await collateralPool.addCollateral(deployerAddress, addedCollateral);
        });

        afterEach(async() => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Removes collateral", async function () {
            // Removes collateral from collateral pool
            expect(
                await collateralPool.removeCollateral(addedCollateral)
            ).to.emit(collateralPool, "RemoveCollateral"); 
            
            // Checks total added collateral
            expect(
                await collateralPool.totalAddedCollateral()
            ).to.equal(0); 
        })

        it("Removes collateral after some fee was sent to collateral pool", async function () {
            // Transfers fee
            await erc20.transfer(collateralPool.address, 100);
            let prevBalance = await erc20.balanceOf(deployerAddress);

            // Removes collateral from collateral pool
            expect(
                await collateralPool.removeCollateral(addedCollateral)
            ).to.emit(collateralPool, "RemoveCollateral");

            let newBalance = await erc20.balanceOf(deployerAddress);
            
            // Checks user balance
            expect(
                newBalance.toNumber() - prevBalance.toNumber()
            ).to.equal(100 + addedCollateral);

            // Checks total added collateral
            expect(
                await collateralPool.totalAddedCollateral()
            ).to.equal(0);
        })

        it("Reverts since amount is zero", async function () {
            // Removes collateral from collateral pool
            await expect(
                collateralPool.removeCollateral(0)
            ).to.revertedWith("CollateralPool: zero value"); 
        })

        it("Reverts since balance is not enough", async function () {
            // Removes collateral from collateral pool
            await expect(
                collateralPool.removeCollateral(addedCollateral*2)
            ).to.revertedWith("CollateralPool: balance is not enough"); 
        })

    });

    describe("#equivalentCollateralToken", async () => {
        let addedCollateral = 100;
        
        beforeEach(async() => {
            snapshotId = await takeSnapshot(signer1.provider);

            // Adds collateral
            await erc20.approve(collateralPool.address, addedCollateral);
            await collateralPool.addCollateral(deployerAddress, addedCollateral);
        });

        afterEach(async() => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Converts collateral pool token to collateral token", async function () {
            expect(
                await collateralPool.equivalentCollateralToken(100)
            ).to.equal(100); 
        })

        it("Converts collateral pool token to collateral token after transferring some amounts", async function () {
            await erc20.transfer(collateralPool.address, addedCollateral)
            expect(
                await collateralPool.equivalentCollateralToken(100)
            ).to.equal(200); 
        })

        it("Reverts since liquidity is not enough", async function () {
            await expect(
                collateralPool.equivalentCollateralToken(200)
            ).to.revertedWith("CollateralPool: liquidity is not sufficient"); 
        })

        it("Reverts since collateral pool is empty", async function () {
            await collateralPool.removeCollateral(addedCollateral);
            await expect(
                collateralPool.equivalentCollateralToken(100)
            ).to.revertedWith("CollateralPool: collateral pool is empty"); 
        })
    });

    describe("#equivalentCollateralPoolToken", async () => {
        let addedCollateral = 100;
        
        beforeEach(async() => {
            snapshotId = await takeSnapshot(signer1.provider);

            // Adds collateral
            await erc20.approve(collateralPool.address, addedCollateral);
            await collateralPool.addCollateral(deployerAddress, addedCollateral);
        });

        afterEach(async() => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Converts collateral pool token to collateral token", async function () {
            expect(
                await collateralPool.equivalentCollateralPoolToken(100)
            ).to.equal(100); 
        })

        it("Converts collateral pool token to collateral token after transferring some amounts", async function () {
            await erc20.transfer(collateralPool.address, addedCollateral)
            expect(
                await collateralPool.equivalentCollateralPoolToken(200)
            ).to.equal(100); 
        })

        it("Reverts since liquidity is not enough", async function () {
            await expect(
                collateralPool.equivalentCollateralPoolToken(200)
            ).to.revertedWith("CollateralPool: liquidity is not sufficient"); 
        })

        it("Reverts since collateral pool is empty", async function () {
            await collateralPool.removeCollateral(addedCollateral);
            await expect(
                collateralPool.equivalentCollateralPoolToken(100)
            ).to.revertedWith("CollateralPool: collateral pool is empty"); 
        })
    });

    describe("#setCollateralizationRatio", async () => {

        beforeEach(async() => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async() => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Sets new collateralization ratio", async function () {
            await expect (
                await collateralPool.setCollateralizationRatio(20000)
            ).to.emit(
                collateralPool, "NewCollateralizationRatio"
            ).withArgs(10000, 20000);
            
            expect(
                await collateralPool.collateralizationRatio()
            ).to.equal(20000); 
        })

        it("Reverts since given ratio is zero", async function () {
            await expect(
                collateralPool.setCollateralizationRatio(0)
            ).to.revertedWith("CollateralPool: zero value")
        })

    });

});