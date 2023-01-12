import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer} from "ethers";

import { CollateralPoolFactory } from "../src/types/CollateralPoolFactory";
import { CollateralPoolFactory__factory } from "../src/types/factories/CollateralPoolFactory__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";

import { takeSnapshot, revertProvider } from "./block_utils";

describe("CollateralPoolFactory", async () => {

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let deployerAddress: string;

    // Contracts
    let collateralPoolFactory: CollateralPoolFactory;
    let erc20: ERC20;
    let _erc20: ERC20;

    let snapshotId: any;

    before(async () => {
        // Sets accounts
        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        // Deploys collateralPoolFactory contract
        const collateralPoolFactoryFactory = new CollateralPoolFactory__factory(deployer);
        collateralPoolFactory = await collateralPoolFactoryFactory.deploy();

        // Deploys erc20 contract
        const erc20Factory = new ERC20__factory(deployer);
        erc20 = await erc20Factory.deploy(
            "TestToken",
            "TT"
        );
        _erc20 = await erc20Factory.deploy(
            "AnotherTestToken",
            "ATT"
        );

    });

    describe("#createCollateralPool", async () => {

        beforeEach(async() => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async() => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Creates a collateral pool", async function () {
            // Checks thta address is equal to zero
            expect(
                await collateralPoolFactory.getCollateralPoolByToken(erc20.address)
            ).to.equal(ZERO_ADDRESS);

            // Creates a collateral pool
            expect(
                await collateralPoolFactory.createCollateralPool(
                    erc20.address,
                    10000
                )
            ).to.emit(collateralPoolFactory, 'CreateCollateralPool');
            
            // Checks total number of collateral pools
            expect(
                await collateralPoolFactory.allCollateralPoolsLength()
            ).to.equal(1);

            // Gets address of collateral pool
            let collateralPool = await collateralPoolFactory.allCollateralPools(0);

            // Checks correctness of collateral pool address
            expect(
                await collateralPoolFactory.getCollateralPoolByToken(erc20.address)
            ).to.equal(collateralPool);

            // Checks that collateral pool exists
            expect(
                await collateralPoolFactory.isCollateral(erc20.address)
            ).to.equal(true);
        })

        //TODO hard code number
        it("Reverts since _collateralizationRatio is less than 10000", async function () {
            // Checks thta address is equal to zero
            expect(
                await collateralPoolFactory.getCollateralPoolByToken(erc20.address)
            ).to.equal(ZERO_ADDRESS);

            // Creates a collateral pool
            await expect(
                collateralPoolFactory.createCollateralPool(
                    erc20.address,
                    9999
                )
            ).to.be.revertedWith("CollateralPoolFactory: low amount")
        })

        it("Reverts since collateral pool has been already created", async function () {
            await collateralPoolFactory.createCollateralPool(
                erc20.address,
                10000
            );

            await expect(
                collateralPoolFactory.createCollateralPool(
                    erc20.address,
                    50
                )
            ).to.revertedWith("CollateralPoolFactory: collateral pool already exists");
        })

        it("Reverts since non-owner account calls the function", async function () {
            await revertProvider(signer1.provider, snapshotId);
            let collateralPoolFactorySigner1 = collateralPoolFactory.connect(signer1)
            await expect(
                collateralPoolFactorySigner1.createCollateralPool(
                    erc20.address,
                    100
                )
            ).to.reverted;
        })

        it("Reverts since collateral token address is zero", async function () {
            await revertProvider(signer1.provider, snapshotId);
            await expect(
                collateralPoolFactory.createCollateralPool(
                    ZERO_ADDRESS,
                    100
                )
            ).to.revertedWith("CollateralPoolFactory: zero address");
        })

        it("Reverts since collateralization ratio is zero", async function () {
            await revertProvider(signer1.provider, snapshotId);
            await expect(
                collateralPoolFactory.createCollateralPool(
                    erc20.address,
                    0
                )
            ).to.revertedWith("CollateralPoolFactory: zero value");
        })

    });

    describe("#removeCollateralPool", async () => {

        beforeEach(async() => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async() => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Removes a collateral pool", async function () {

            // Creates two collateral pools
            await collateralPoolFactory.createCollateralPool(erc20.address, 10000);
            await collateralPoolFactory.createCollateralPool(_erc20.address, 20000);
            
            // Removes collateral pool
            expect(
                await collateralPoolFactory.removeCollateralPool(erc20.address, 0)
            ).to.emit(collateralPoolFactory, "RemoveCollateralPool");

            // Checks that collateral pool address is equal to zero
            expect(
                await collateralPoolFactory.getCollateralPoolByToken(erc20.address)
            ).to.equal(ZERO_ADDRESS);

            // Checks total number of collateral pools
            expect(
                await collateralPoolFactory.allCollateralPoolsLength()
            ).to.equal(1);

            // Checks that collateral pool doesn't exist
            expect(
                await collateralPoolFactory.isCollateral(erc20.address)
            ).to.equal(false);
        })

        it("Reverts since the index is out of range", async function () {
            // Creates a collateral pool
            await collateralPoolFactory.createCollateralPool(erc20.address, 10000);
            
            // Removes collateral pool
            await expect(
                collateralPoolFactory.removeCollateralPool(erc20.address, 2)
            ).to.revertedWith("CollateralPoolFactory: index is out of range");
        })

        it("Reverts since the index doesn't belong to collateral token", async function () {     
            // Creates two collateral pools
            await collateralPoolFactory.createCollateralPool(erc20.address, 10000);
            await collateralPoolFactory.createCollateralPool(_erc20.address, 20000);

            // Removes collateral pool
            await expect(
                collateralPoolFactory.removeCollateralPool(await erc20.address, 1)
            ).to.revertedWith("CollateralPoolFactory: index is not correct");
        })

        it("Reverts since the collateral pool doesn't exist", async function () {    
            await collateralPoolFactory.createCollateralPool(_erc20.address, 20000);

            // Removes collateral pool
            await expect(
                collateralPoolFactory.removeCollateralPool(erc20.address, 0)
            ).to.revertedWith("CollateralPoolFactory: collateral pool does not exist");
        })

        it("Reverts since non-owner account calls the function", async function () {
            let collateralPoolFactorySigner1 = collateralPoolFactory.connect(signer1)
            await expect(
                collateralPoolFactorySigner1.removeCollateralPool(erc20.address, 0)
            ).to.reverted;
        })

    });

    describe("#renounce ownership", async () => {
        it("owner can't renounce ownership", async function () {
            await collateralPoolFactory.renounceOwnership()
            await expect(
                await collateralPoolFactory.owner()
            ).to.equal(deployerAddress);
        })
    });

});