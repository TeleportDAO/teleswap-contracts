import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Address } from "hardhat-deploy/types";

import {ERC20} from "../src/types/ERC20";
import {ERC20__factory} from "../src/types/factories/ERC20__factory";
import {TeleBTC} from "../src/types/TeleBTC";
import {TeleBTC__factory} from "../src/types/factories/TeleBTC__factory";
import {InstantRouter} from "../src/types/InstantRouter";
import {InstantRouter__factory} from "../src/types/factories/InstantRouter__factory";
import {InstantPool} from "../src/types/InstantPool";
import {InstantPool__factory} from "../src/types/factories/InstantPool__factory";

import { takeSnapshot, revertProvider } from "./block_utils";

describe("Instant Router", async () => {
    let snapshotId: any;

	// Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
	let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let slasherPercentageReward = 5;
    let paybackDeadline = 10; // Means 10 Bitcoin blocks
    let instantFee = 5; // Means 5%

	// Accounts
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;

	// Contracts
    let TeleportDAOToken: ERC20;
    let teleBTC: TeleBTC;
    let bitcoinInstantPool: InstantPool;
	let instantRouter: InstantRouter;

	// Mock contracts
	let mockExchangeConnector: MockContract;
    let mockBitcoinRelay: MockContract;
	let mockPriceOracle: MockContract;
	let mockCollateralPoolFactory: MockContract;

    before(async () => {
		// Sets accounts
        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();

		// Mocks contracts
        const bitcoinRelay = await deployments.getArtifact(
            "IBitcoinRelay"
        );
        mockBitcoinRelay = await deployMockContract(
            deployer,
            bitcoinRelay.abi
        );

        const priceOracle = await deployments.getArtifact(
            "IPriceOracle"
        );
        mockPriceOracle = await deployMockContract(
            deployer,
            priceOracle.abi
        );

        const collateralPoolFactory = await deployments.getArtifact(
            "ICollateralPoolFactory"
        );
        mockCollateralPoolFactory = await deployMockContract(
            deployer,
            collateralPoolFactory.abi
        );

		// Deploys TeleBTC and TeleportDAOToken contract
        const erc20Factory = new ERC20__factory(deployer);
        TeleportDAOToken = await erc20Factory.deploy(
            "TeleportDAOToken",
            "TDT",
            1000
        );
        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "TBTC",
            ONE_ADDRESS,
			ONE_ADDRESS,
			ONE_ADDRESS
        );
		
		// Deploys instant router
        let instantRouterFactory = new InstantRouter__factory(deployer);
        instantRouter = await instantRouterFactory.deploy(
            teleBTC.address,
            mockBitcoinRelay.address,
            mockPriceOracle.address,
            mockCollateralPoolFactory.address,
            slasherPercentageReward,
            paybackDeadline
        );

    });

    beforeEach("deploy a new cc exchange router", async () => {
        snapshotId = await takeSnapshot(signer1.provider);

        instantRouter = await deployInstantRouter();
    });

    afterEach(async () => {
        await revertProvider(signer1.provider, snapshotId);
    });

    describe("#instantCCTransfer", async () => {

        let reserve1 = 100
        let reserve2 = 100

        let theTestMintedAmount = 100

        it("low deadline", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(2)

            let instantRouterSigner1 = instantRouter.connect(signer1)

            await expect(
                instantRouterSigner1.instantCCTransfer(
                    signer1Address,
                    0,
                    theBlockNumber
                )
            ).to.revertedWith("deadline has passed")
        });


        it("proper deadline", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).add(10)

            let instantRouterSigner1 = instantRouter.connect(signer1)

            // console.log("mockLiquidityPoolFactory address: ", mockLiquidityPoolFactory.address)

            await mockLiquidityPoolFactory.mock.getLiquidityPool.withArgs(
                teleBTC.address,
                TeleportDAOToken.address
            ).returns(
                mockLiquidityPool.address
            )

            await mockLiquidityPool.mock.getReserves.returns(
                reserve1,
                reserve2,
                thisBlockNumber
            )

            // simulation of getAmountIn function in TeleportDAOLibrary
            let numerator = reserve1.mul(10).mul(1000);
            let  denominator = (reserve2.sub(10)).mul(997);

            console.log("numerator: ", numerator)
            console.log("denominator: ", denominator)

            let amountIn = (numerator.div(denominator)).add(1);
            // FIXME: why must multiple by 2
            amountIn = amountIn.mul(2)

            console.log("amountIn in test.ts: ", amountIn)

            await mockStaking.mock.equivalentStakingShare.withArgs(
                amountIn
            ).returns(
                amountIn
            )

            await mockStaking.mock.stakingShare.withArgs(
                signer1Address
            ).returns(
                10.mul(3)
            )

            await mockStaking.mock.unstake.withArgs(
                signer1Address,
                amountIn
            ).returns()

            let bitcoinInstantPoolAddress = await instantRouter.bitcoinInstantPool()

            await teleBTC.mintTestToken()
            await teleBTC.transfer(bitcoinInstantPoolAddress, theTestMintedAmount)

            expect(
                await teleBTC.balanceOf(bitcoinInstantPoolAddress)
            ).to.equal(theTestMintedAmount)


            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                BigNumber.from(thisBlockNumber).sub(5)
            )

            await instantRouterSigner1.instantCCTransfer(
                signer1Address,
                10,
                theBlockNumber
            )
        });

    });

    describe("#instantCCExchange", async () => {

        let reserve1 = 100
        let reserve2 = 100

        let theTestMintedAmount = 100

        it("low deadline", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(2)

            let instantRouterSigner1 = instantRouter.connect(signer1)

            let thePath = [
                teleBTC.address,
                wavax.address
            ]

            await expect(
                instantRouterSigner1.instantCCExchange(
                    0,
                    0,
                    thePath,
                    signer1Address,
                    theBlockNumber
                )
            ).to.revertedWith("deadline has passed")
        });


        it("proper deadline", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).add(10)

            let instantRouterSigner1 = instantRouter.connect(signer1)

            // console.log("mockLiquidityPoolFactory address: ", mockLiquidityPoolFactory.address)

            await mockLiquidityPoolFactory.mock.getLiquidityPool.withArgs(
                teleBTC.address,
                TeleportDAOToken.address
            ).returns(
                mockLiquidityPool.address
            )

            await mockLiquidityPool.mock.getReserves.returns(
                reserve1,
                reserve2,
                thisBlockNumber
            )

            // simulation of getAmountIn function in TeleportDAOLibrary
            let numerator = reserve1.mul(10).mul(1000);
            let  denominator = (reserve2.sub(10)).mul(997);

            console.log("numerator: ", numerator)
            console.log("denominator: ", denominator)

            let amountIn = (numerator.div(denominator)).add(1);
            // FIXME: why must multiple by 2
            amountIn = amountIn.mul(2)

            console.log("amountIn in test.ts: ", amountIn)

            await mockStaking.mock.equivalentStakingShare.withArgs(
                amountIn
            ).returns(
                amountIn
            )

            await mockStaking.mock.stakingShare.withArgs(
                signer1Address
            ).returns(
                10.mul(3)
            )

            await mockStaking.mock.unstake.withArgs(
                signer1Address,
                amountIn
            ).returns()

            let bitcoinInstantPoolAddress = await instantRouter.bitcoinInstantPool()

            await teleBTC.mintTestToken()
            await teleBTC.transfer(bitcoinInstantPoolAddress, theTestMintedAmount)

            expect(
                await teleBTC.balanceOf(bitcoinInstantPoolAddress)
            ).to.equal(theTestMintedAmount)


            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                BigNumber.from(thisBlockNumber).sub(5)
            )

            let thePath = [
                teleBTC.address,
                wavax.address
            ]

            let theAmounts = [
                10,
                10
            ]

            let modifiedAmountIn = 10.mul(100 - instantFee).div(100)

            await mockExchangeRouter.mock.swapExactTokensForAVAX.withArgs(
                modifiedAmountIn,
                10,
                thePath,
                signer1Address,
                theBlockNumber
            ).returns(theAmounts, true)


            await instantRouterSigner1.instantCCExchange(
                10,
                10,
                thePath,
                signer1Address,
                theBlockNumber
            )
        });

    });

    describe("#payBackInstantTransfer", async () => {

        let reserve1 = 100
        let reserve2 = 100

        let theTestMintedAmount = 100

        it("without any debt", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(2)

            let instantRouterSigner1 = instantRouter.connect(signer1)

            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                BigNumber.from(thisBlockNumber).sub(5)
            )


            expect(
                await instantRouterSigner1.payBackInstantTransfer(
                    0,
                    signer1Address
                )
            ).to.emit(instantRouter, "PaybackInstantLoan")
        });


        it("payback one debt", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).add(10)

            let instantRouterSigner1 = instantRouter.connect(signer1)

            // console.log("mockLiquidityPoolFactory address: ", mockLiquidityPoolFactory.address)

            await mockLiquidityPoolFactory.mock.getLiquidityPool.withArgs(
                teleBTC.address,
                TeleportDAOToken.address
            ).returns(
                mockLiquidityPool.address
            )

            await mockLiquidityPool.mock.getReserves.returns(
                reserve1,
                reserve2,
                thisBlockNumber
            )

            // simulation of getAmountIn function in TeleportDAOLibrary
            let numerator = reserve1.mul(10).mul(1000);
            let  denominator = (reserve2.sub(10)).mul(997);

            console.log("numerator: ", numerator)
            console.log("denominator: ", denominator)

            let amountIn = (numerator.div(denominator)).add(1);
            // FIXME: why must multiple by 2
            amountIn = amountIn.mul(2)

            console.log("amountIn in test.ts: ", amountIn)

            await mockStaking.mock.equivalentStakingShare.withArgs(
                amountIn
            ).returns(
                amountIn
            )

            await mockStaking.mock.stakingShare.withArgs(
                signer1Address
            ).returns(
                10.mul(3)
            )

            await mockStaking.mock.unstake.withArgs(
                signer1Address,
                amountIn
            ).returns()

            let bitcoinInstantPoolAddress = await instantRouter.bitcoinInstantPool()

            await teleBTC.mintTestToken()
            await teleBTC.transfer(bitcoinInstantPoolAddress, theTestMintedAmount)

            expect(
                await teleBTC.balanceOf(bitcoinInstantPoolAddress)
            ).to.equal(theTestMintedAmount)


            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                BigNumber.from(thisBlockNumber).sub(5)
            )

            await instantRouterSigner1.instantCCTransfer(
                signer1Address,
                10,
                theBlockNumber
            )

            // the above code adds a debt for the user

            // the following code payback the user's debt

            await teleBTC.mintTestToken()
            await teleBTC.transfer(signer1Address, theTestMintedAmount)

            let teleBTCSigner1 = await teleBTC.connect(signer1)
            await teleBTCSigner1.approve(instantRouter.address, 10)

            await mockStaking.mock.stake.withArgs(
                signer1Address,
                amountIn
            ).returns()

            expect(
                await instantRouterSigner1.payBackInstantTransfer(
                    10,
                    signer1Address
                )
            ).to.emit(instantRouter, "PaybackInstantLoan")

        });

    });

    describe("#punishUser", async () => {

        let reserve1 = 100
        let reserve2 = 100
        let theTestMintedAmount = 100

        it("deadline has not passed", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).add(10)

            let instantRouterSigner1 = instantRouter.connect(signer1)

            // console.log("mockLiquidityPoolFactory address: ", mockLiquidityPoolFactory.address)

            await mockLiquidityPoolFactory.mock.getLiquidityPool.withArgs(
                teleBTC.address,
                TeleportDAOToken.address
            ).returns(
                mockLiquidityPool.address
            )

            await mockLiquidityPool.mock.getReserves.returns(
                reserve1,
                reserve2,
                thisBlockNumber
            )

            // simulation of getAmountIn function in TeleportDAOLibrary
            let numerator = reserve1.mul(10).mul(1000);
            let  denominator = (reserve2.sub(10)).mul(997);

            console.log("numerator: ", numerator)
            console.log("denominator: ", denominator)

            let amountIn = (numerator.div(denominator)).add(1);
            // FIXME: why must multiple by 2
            amountIn = amountIn.mul(2)

            console.log("amountIn in test.ts: ", amountIn)

            await mockStaking.mock.equivalentStakingShare.withArgs(
                amountIn
            ).returns(
                amountIn
            )

            await mockStaking.mock.stakingShare.withArgs(
                signer1Address
            ).returns(
                10.mul(3)
            )

            await mockStaking.mock.unstake.withArgs(
                signer1Address,
                amountIn
            ).returns()

            let bitcoinInstantPoolAddress = await instantRouter.bitcoinInstantPool()

            await teleBTC.mintTestToken()
            await teleBTC.transfer(bitcoinInstantPoolAddress, theTestMintedAmount)

            expect(
                await teleBTC.balanceOf(bitcoinInstantPoolAddress)
            ).to.equal(theTestMintedAmount)


            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                BigNumber.from(thisBlockNumber).sub(5)
            )

            await instantRouterSigner1.instantCCTransfer(
                signer1Address,
                10,
                theBlockNumber
            )

            // the above code adds a debt for the user

            // the following code payback the user's debt

            let instantRouterSigner2 = instantRouter.connect(signer2)

            let theDebtIndexes = [
                0
            ]

            await expect(
                instantRouterSigner2.punishUser(
                    signer1Address,
                    theDebtIndexes
                )
            ).to.revertedWith("deadline has not passed")

        });

        it("payback one debt", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).add(10)

            let instantRouterSigner1 = instantRouter.connect(signer1)

            // console.log("mockLiquidityPoolFactory address: ", mockLiquidityPoolFactory.address)

            await mockLiquidityPoolFactory.mock.getLiquidityPool.withArgs(
                teleBTC.address,
                TeleportDAOToken.address
            ).returns(
                mockLiquidityPool.address
            )

            await mockLiquidityPool.mock.getReserves.returns(
                reserve1,
                reserve2,
                thisBlockNumber
            )

            // simulation of getAmountIn function in TeleportDAOLibrary
            let numerator = reserve1.mul(10).mul(1000);
            let  denominator = (reserve2.sub(10)).mul(997);

            console.log("numerator: ", numerator)
            console.log("denominator: ", denominator)

            let amountIn = (numerator.div(denominator)).add(1);
            // FIXME: why must multiple by 2
            amountIn = amountIn.mul(2)

            console.log("amountIn in test.ts: ", amountIn)

            await mockStaking.mock.equivalentStakingShare.withArgs(
                amountIn
            ).returns(
                amountIn
            )

            await mockStaking.mock.stakingShare.withArgs(
                signer1Address
            ).returns(
                10.mul(3)
            )

            await mockStaking.mock.unstake.withArgs(
                signer1Address,
                amountIn
            ).returns()

            let bitcoinInstantPoolAddress = await instantRouter.bitcoinInstantPool()

            await teleBTC.mintTestToken()
            await teleBTC.transfer(bitcoinInstantPoolAddress, theTestMintedAmount)

            expect(
                await teleBTC.balanceOf(bitcoinInstantPoolAddress)
            ).to.equal(theTestMintedAmount)


            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                BigNumber.from(thisBlockNumber).sub(5)
            )

            await instantRouterSigner1.instantCCTransfer(
                signer1Address,
                10,
                theBlockNumber
            )

            // the above code adds a debt for the user

            // the following code payback the user's debt

            let instantRouterSigner2 = instantRouter.connect(signer2)

            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                BigNumber.from(thisBlockNumber).add(15)
            )


            let thePaths = [
                TeleportDAOToken.address,
                teleBTC.address
            ]

            let theAmounts = [
                10,
                10
            ]

            await mockExchangeRouter.mock.swapExactTokensForTokens.returns(theAmounts, true)

            let theDebtIndexes = [
                0
            ]

            await TeleportDAOToken.transfer(instantRouter.address, 10)

            await instantRouterSigner2.punishUser(
                signer1Address,
                theDebtIndexes
            )

        });

    });
});