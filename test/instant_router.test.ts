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
    let instantPercentageFee = 5; // Means 0.05%
    let collateralizationRatio = 200; // Means 200%

	// Accounts
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;

	// Contracts
    let collateralToken: ERC20;
    let teleBTC: TeleBTC;
    let teleBTCInstantPool: InstantPool;
	let instantRouter: InstantRouter;

	// Mock contracts
	let mockExchangeConnector: MockContract;
    let mockBitcoinRelay: MockContract;
	let mockPriceOracle: MockContract;
	let mockCollateralPool: MockContract;
    let mockCollateralPoolFactory: MockContract;

    // Parameters
    let addedLiquidity: number;

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

        const collateralPool = await deployments.getArtifact(
            "ICollateralPool"
        );
        mockCollateralPool = await deployMockContract(
            deployer,
            collateralPool.abi
        );

        const collateralPoolFactory = await deployments.getArtifact(
            "ICollateralPoolFactory"
        );
        mockCollateralPoolFactory = await deployMockContract(
            deployer,
            collateralPoolFactory.abi
        );

        const exchangeConnector = await deployments.getArtifact(
            "IExchangeConnector"
        );
        mockExchangeConnector = await deployMockContract(
            deployer,
            exchangeConnector.abi
        );

		// Deploys collateralToken and TeleportDAOToken contract
        const erc20Factory = new ERC20__factory(deployer);
        collateralToken = await erc20Factory.deploy(
            "TestToken",
            "TT",
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

        // Deploys bitcoin instant pool
        let instantPoolFactory = new InstantPool__factory(deployer);
        teleBTCInstantPool = await instantPoolFactory.deploy(
            teleBTC.address,
            instantRouter.address,
            instantPercentageFee,
            "TeleBTC-Instant-Pool",
            "TBTCIP"
        );

        // Sets bitcoin instant pool in instant router
        await instantRouter.setTeleBTCInstantPool(teleBTCInstantPool.address);

        // Adds liquidity to instant pool
        addedLiquidity = 100;
        await teleBTC.mintTestToken();
        await teleBTC.approve(teleBTCInstantPool.address, addedLiquidity);
        await teleBTCInstantPool.addLiquidity(deployerAddress, addedLiquidity);

    });

    async function getTimestamp(): Promise<number> {
        let lastBlockNumber = await ethers.provider.getBlockNumber();
        let lastBlock = await ethers.provider.getBlock(lastBlockNumber);
        return lastBlock.timestamp;
    }

    async function mockFunctionsCollateralPoolFactory(        
        isCollateral: boolean,
        collateralPool: string,
    ): Promise<void> {
        await mockCollateralPoolFactory.mock.isCollateral.returns(
            isCollateral
        );
        await mockCollateralPoolFactory.mock.getCollateralPoolByToken.returns(
            collateralPool
        );
    }

    async function mockFunctionsCollateralPool(        
        collateralizationRatio: number,
        transferFromResult: boolean,
        requiredCollateralPoolToken: number
    ): Promise<void> {
        await mockCollateralPool.mock.collateralizationRatio.returns(
            collateralizationRatio
        );
        await mockCollateralPool.mock.transferFrom.returns(
            transferFromResult
        );
        await mockCollateralPool.mock.equivalentCollateralPoolToken.returns(
            requiredCollateralPoolToken
        );
    }

    async function mockFunctionsPriceOracle(        
        outputAmount: number,
    ): Promise<void> {
        await mockPriceOracle.mock.equivalentOutputAmount.returns(
            outputAmount
        );
    }

    async function mockFunctionsBitcoinRelay(        
        lastSubmittedHeight: number,
    ): Promise<void> {
        await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
            lastSubmittedHeight
        );
    }

    async function mockFunctionsExchangeConnector(       
        swapResult: boolean,
        amounts: Array<number>
    ): Promise<void> {
        await mockExchangeConnector.mock.swap.returns(
            swapResult, amounts
        );
    }

    describe("#instantCCTransfer", async () => {
        // Parameters
        let loanAmount: number;
        let equivalentCollateralToken: number;
        let requiredCollateralPoolToken: number;
        let lastSubmittedHeight: number;
        let isCollateral: boolean;
        let transferFromResult: boolean;

        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });
    
        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Gives instant loan to user", async function () {
            // Set parameters
            loanAmount = 100;
            equivalentCollateralToken = 50; // Assumes that: 1 collateralToken = 2 teleBTC
            requiredCollateralPoolToken = equivalentCollateralToken*collateralizationRatio; // Assumes that: 1 collateralToken = 1 collateralPoolToken
            lastSubmittedHeight = 100;
            isCollateral = true;
            transferFromResult = true;

            // Mocks functions
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);
            await mockFunctionsCollateralPool(collateralizationRatio, transferFromResult, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);

            // Gets last block timestamp 
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            await expect(
                instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp*2,
                    collateralToken.address
                )
            ).to.emit(instantRouter, "InstantTransfer").withArgs(
                deployerAddress,
                signer1Address,
                loanAmount,
                Math.floor(loanAmount*instantPercentageFee/10000),
                lastSubmittedHeight + paybackDeadline,
                collateralToken.address
            );
            
            // Checks that signer1 has received loan amount
            await expect(
                await teleBTC.balanceOf(signer1Address)
            ).to.equal(loanAmount);
        });

        it("Reverts since instant pool liquidity is not enough", async function () {
            // Set parameters
            loanAmount = 200;
            equivalentCollateralToken = 50; // Assumes that: 1 collateralToken = 2 teleBTC
            requiredCollateralPoolToken = equivalentCollateralToken*collateralizationRatio; // Assumes that: 1 collateralToken = 1 collateralPoolToken
            lastSubmittedHeight = 100;
            isCollateral = true;
            transferFromResult = true;

            // Mocks functions
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);
            await mockFunctionsCollateralPool(collateralizationRatio, transferFromResult, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);

            // Gets last block timestamp 
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            await expect(
                instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp*2,
                    collateralToken.address
                )
            ).to.revertedWith("InstantPool: liquidity is not sufficient")
        });

        it("Reverts since deadline has paased", async function () {
            // Gets last block timestamp 
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            await expect(
                instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp - 1,
                    collateralToken.address
                )
            ).to.revertedWith("InstantRouter: deadline has passed")
        });

        it("Reverts since collateral is not acceptable", async function () {
            // Mocks functions
            isCollateral = false;
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);

            // Gets last block timestamp 
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            await expect(
                instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp*2,
                    collateralToken.address
                )
            ).to.revertedWith("InstantRouter: collateral token is not acceptable")
        });

    });

    describe("#instantCCExchange", async () => {

        // Parameters
        let loanAmount: number;
        let amountOut: number;
        let path: Array<string>;
        let isFixedToken: boolean;
        let equivalentCollateralToken: number;
        let requiredCollateralPoolToken: number;
        let lastSubmittedHeight: number;
        let isCollateral: boolean;
        let transferFromResult: boolean;
        let swapResult: boolean;

        beforeEach("deploy a new cc exchange router", async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });
    
        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Gives loan to user and exchanges teleBTC to output token", async function () {
            // Set parameters
            loanAmount = 100;
            amountOut = 10;
            path = [teleBTC.address, collateralToken.address];
            isFixedToken = true;
            equivalentCollateralToken = 50; // Assumes that: 1 collateralToken = 2 teleBTC
            requiredCollateralPoolToken = equivalentCollateralToken*collateralizationRatio; // Assumes that: 1 collateralToken = 1 collateralPoolToken
            lastSubmittedHeight = 100;
            isCollateral = true;
            transferFromResult = true;
            swapResult = true;

            // Mocks functions
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);
            await mockFunctionsCollateralPool(collateralizationRatio, transferFromResult, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
            await mockFunctionsExchangeConnector(swapResult, [loanAmount, amountOut]);

            // Gets last block timestamp 
            let lastBlockTimestamp = await getTimestamp();

            await expect(
                instantRouter.instantCCExchange(
                    mockExchangeConnector.address,
                    signer1Address,
                    loanAmount,
                    amountOut,
                    path,
                    lastBlockTimestamp*2,
                    collateralToken.address,
                    isFixedToken
                )
            ).to.emit(instantRouter, "InstantExchange").withArgs(
                deployerAddress,
                signer1Address,
                loanAmount,
                Math.floor(loanAmount*instantPercentageFee/10000),
                amountOut,
                path,
                isFixedToken,
                lastSubmittedHeight + paybackDeadline,
                collateralToken.address
            );
        });

        it("Reverts since swap was not successful", async function () {
            // Set parameters
            loanAmount = 100;
            amountOut = 10;
            path = [teleBTC.address, collateralToken.address];
            isFixedToken = true;
            equivalentCollateralToken = 50; // Assumes that: 1 collateralToken = 2 teleBTC
            requiredCollateralPoolToken = equivalentCollateralToken*collateralizationRatio; // Assumes that: 1 collateralToken = 1 collateralPoolToken
            lastSubmittedHeight = 100;
            isCollateral = true;
            transferFromResult = true;
            swapResult = false;

            // Mocks functions
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);
            await mockFunctionsCollateralPool(collateralizationRatio, transferFromResult, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
            await mockFunctionsExchangeConnector(swapResult, []);

            // Gets last block timestamp 
            let lastBlockTimestamp = await getTimestamp();

            await expect(
                instantRouter.instantCCExchange(
                    mockExchangeConnector.address,
                    signer1Address,
                    loanAmount,
                    amountOut,
                    path,
                    lastBlockTimestamp*2,
                    collateralToken.address,
                    isFixedToken
                )
            ).to.revertedWith("InstantRouter: exchange was not successful");
        });

        it("Reverts since deadline has paased", async function () {
            // Gets last block timestamp 
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            await expect(
                instantRouter.instantCCExchange(
                    mockExchangeConnector.address,
                    signer1Address,
                    loanAmount,
                    amountOut,
                    path,
                    lastBlockTimestamp - 1,
                    collateralToken.address,
                    isFixedToken
                )
            ).to.revertedWith("InstantRouter: deadline has passed")
        });

        it("Reverts since collateral is not acceptable", async function () {
            // Mocks functions
            isCollateral = false;
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);

            // Gets last block timestamp 
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            await expect(
                instantRouter.instantCCExchange(
                    mockExchangeConnector.address,
                    signer1Address,
                    loanAmount,
                    amountOut,
                    path,
                    lastBlockTimestamp*2,
                    collateralToken.address,
                    isFixedToken
                )
            ).to.revertedWith("InstantRouter: collateral token is not acceptable")
        });
    });

    // describe("#payBackInstantTransfer", async () => {

    //     let reserve1 = 100
    //     let reserve2 = 100

    //     let theTestMintedAmount = 100

    //     it("without any debt", async function () {

    //         let thisBlockNumber = await signer1.provider?.getBlockNumber()
    //         let theBlockNumber = BigNumber.from(thisBlockNumber).sub(2)

    //         let instantRouterSigner1 = instantRouter.connect(signer1)

    //         await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
    //             BigNumber.from(thisBlockNumber).sub(5)
    //         )


    //         expect(
    //             await instantRouterSigner1.payBackInstantTransfer(
    //                 0,
    //                 signer1Address
    //             )
    //         ).to.emit(instantRouter, "PaybackInstantLoan")
    //     });


    //     it("payback one debt", async function () {

    //         let thisBlockNumber = await signer1.provider?.getBlockNumber()
    //         let theBlockNumber = BigNumber.from(thisBlockNumber).add(10)

    //         let instantRouterSigner1 = instantRouter.connect(signer1)

    //         // console.log("mockLiquidityPoolFactory address: ", mockLiquidityPoolFactory.address)

    //         await mockLiquidityPoolFactory.mock.getLiquidityPool.withArgs(
    //             teleBTC.address,
    //             TeleportDAOToken.address
    //         ).returns(
    //             mockLiquidityPool.address
    //         )

    //         await mockLiquidityPool.mock.getReserves.returns(
    //             reserve1,
    //             reserve2,
    //             thisBlockNumber
    //         )

    //         // simulation of getAmountIn function in TeleportDAOLibrary
    //         let numerator = reserve1.mul(10).mul(1000);
    //         let  denominator = (reserve2.sub(10)).mul(997);

    //         console.log("numerator: ", numerator)
    //         console.log("denominator: ", denominator)

    //         let amountIn = (numerator.div(denominator)).add(1);
    //         // FIXME: why must multiple by 2
    //         amountIn = amountIn.mul(2)

    //         console.log("amountIn in test.ts: ", amountIn)

    //         await mockStaking.mock.equivalentStakingShare.withArgs(
    //             amountIn
    //         ).returns(
    //             amountIn
    //         )

    //         await mockStaking.mock.stakingShare.withArgs(
    //             signer1Address
    //         ).returns(
    //             10.mul(3)
    //         )

    //         await mockStaking.mock.unstake.withArgs(
    //             signer1Address,
    //             amountIn
    //         ).returns()

    //         let teleBTCInstantPoolAddress = await instantRouter.teleBTCInstantPool()

    //         await teleBTC.mintTestToken()
    //         await teleBTC.transfer(teleBTCInstantPoolAddress, theTestMintedAmount)

    //         expect(
    //             await teleBTC.balanceOf(teleBTCInstantPoolAddress)
    //         ).to.equal(theTestMintedAmount)


    //         await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
    //             BigNumber.from(thisBlockNumber).sub(5)
    //         )

    //         await instantRouterSigner1.instantCCTransfer(
    //             signer1Address,
    //             10,
    //             theBlockNumber
    //         )

    //         // the above code adds a debt for the user

    //         // the following code payback the user's debt

    //         await teleBTC.mintTestToken()
    //         await teleBTC.transfer(signer1Address, theTestMintedAmount)

    //         let teleBTCSigner1 = await teleBTC.connect(signer1)
    //         await teleBTCSigner1.approve(instantRouter.address, 10)

    //         await mockStaking.mock.stake.withArgs(
    //             signer1Address,
    //             amountIn
    //         ).returns()

    //         expect(
    //             await instantRouterSigner1.payBackInstantTransfer(
    //                 10,
    //                 signer1Address
    //             )
    //         ).to.emit(instantRouter, "PaybackInstantLoan")

    //     });

    // });

    // describe("#punishUser", async () => {

    //     let reserve1 = 100
    //     let reserve2 = 100
    //     let theTestMintedAmount = 100

    //     it("deadline has not passed", async function () {

    //         let thisBlockNumber = await signer1.provider?.getBlockNumber()
    //         let theBlockNumber = BigNumber.from(thisBlockNumber).add(10)

    //         let instantRouterSigner1 = instantRouter.connect(signer1)

    //         // console.log("mockLiquidityPoolFactory address: ", mockLiquidityPoolFactory.address)

    //         await mockLiquidityPoolFactory.mock.getLiquidityPool.withArgs(
    //             teleBTC.address,
    //             TeleportDAOToken.address
    //         ).returns(
    //             mockLiquidityPool.address
    //         )

    //         await mockLiquidityPool.mock.getReserves.returns(
    //             reserve1,
    //             reserve2,
    //             thisBlockNumber
    //         )

    //         // simulation of getAmountIn function in TeleportDAOLibrary
    //         let numerator = reserve1.mul(10).mul(1000);
    //         let  denominator = (reserve2.sub(10)).mul(997);

    //         console.log("numerator: ", numerator)
    //         console.log("denominator: ", denominator)

    //         let amountIn = (numerator.div(denominator)).add(1);
    //         // FIXME: why must multiple by 2
    //         amountIn = amountIn.mul(2)

    //         console.log("amountIn in test.ts: ", amountIn)

    //         await mockStaking.mock.equivalentStakingShare.withArgs(
    //             amountIn
    //         ).returns(
    //             amountIn
    //         )

    //         await mockStaking.mock.stakingShare.withArgs(
    //             signer1Address
    //         ).returns(
    //             10.mul(3)
    //         )

    //         await mockStaking.mock.unstake.withArgs(
    //             signer1Address,
    //             amountIn
    //         ).returns()

    //         let teleBTCInstantPoolAddress = await instantRouter.teleBTCInstantPool()

    //         await teleBTC.mintTestToken()
    //         await teleBTC.transfer(teleBTCInstantPoolAddress, theTestMintedAmount)

    //         expect(
    //             await teleBTC.balanceOf(teleBTCInstantPoolAddress)
    //         ).to.equal(theTestMintedAmount)


    //         await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
    //             BigNumber.from(thisBlockNumber).sub(5)
    //         )

    //         await instantRouterSigner1.instantCCTransfer(
    //             signer1Address,
    //             10,
    //             theBlockNumber
    //         )

    //         // the above code adds a debt for the user

    //         // the following code payback the user's debt

    //         let instantRouterSigner2 = instantRouter.connect(signer2)

    //         let theDebtIndexes = [
    //             0
    //         ]

    //         await expect(
    //             instantRouterSigner2.punishUser(
    //                 signer1Address,
    //                 theDebtIndexes
    //             )
    //         ).to.revertedWith("deadline has not passed")

    //     });

    //     it("payback one debt", async function () {

    //         let thisBlockNumber = await signer1.provider?.getBlockNumber()
    //         let theBlockNumber = BigNumber.from(thisBlockNumber).add(10)

    //         let instantRouterSigner1 = instantRouter.connect(signer1)

    //         // console.log("mockLiquidityPoolFactory address: ", mockLiquidityPoolFactory.address)

    //         await mockLiquidityPoolFactory.mock.getLiquidityPool.withArgs(
    //             teleBTC.address,
    //             TeleportDAOToken.address
    //         ).returns(
    //             mockLiquidityPool.address
    //         )

    //         await mockLiquidityPool.mock.getReserves.returns(
    //             reserve1,
    //             reserve2,
    //             thisBlockNumber
    //         )

    //         // simulation of getAmountIn function in TeleportDAOLibrary
    //         let numerator = reserve1.mul(10).mul(1000);
    //         let  denominator = (reserve2.sub(10)).mul(997);

    //         console.log("numerator: ", numerator)
    //         console.log("denominator: ", denominator)

    //         let amountIn = (numerator.div(denominator)).add(1);
    //         // FIXME: why must multiple by 2
    //         amountIn = amountIn.mul(2)

    //         console.log("amountIn in test.ts: ", amountIn)

    //         await mockStaking.mock.equivalentStakingShare.withArgs(
    //             amountIn
    //         ).returns(
    //             amountIn
    //         )

    //         await mockStaking.mock.stakingShare.withArgs(
    //             signer1Address
    //         ).returns(
    //             10.mul(3)
    //         )

    //         await mockStaking.mock.unstake.withArgs(
    //             signer1Address,
    //             amountIn
    //         ).returns()

    //         let teleBTCInstantPoolAddress = await instantRouter.teleBTCInstantPool()

    //         await teleBTC.mintTestToken()
    //         await teleBTC.transfer(teleBTCInstantPoolAddress, theTestMintedAmount)

    //         expect(
    //             await teleBTC.balanceOf(teleBTCInstantPoolAddress)
    //         ).to.equal(theTestMintedAmount)


    //         await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
    //             BigNumber.from(thisBlockNumber).sub(5)
    //         )

    //         await instantRouterSigner1.instantCCTransfer(
    //             signer1Address,
    //             10,
    //             theBlockNumber
    //         )

    //         // the above code adds a debt for the user

    //         // the following code payback the user's debt

    //         let instantRouterSigner2 = instantRouter.connect(signer2)

    //         await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
    //             BigNumber.from(thisBlockNumber).add(15)
    //         )


    //         let thePaths = [
    //             TeleportDAOToken.address,
    //             teleBTC.address
    //         ]

    //         let theAmounts = [
    //             10,
    //             10
    //         ]

    //         await mockExchangeRouter.mock.swapExactTokensForTokens.returns(theAmounts, true)

    //         let theDebtIndexes = [
    //             0
    //         ]

    //         await TeleportDAOToken.transfer(instantRouter.address, 10)

    //         await instantRouterSigner2.punishUser(
    //             signer1Address,
    //             theDebtIndexes
    //         )

    //     });

    // });
});