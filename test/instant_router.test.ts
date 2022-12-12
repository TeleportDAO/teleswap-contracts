import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Address } from "hardhat-deploy/types";
import { ERC20AsDot } from "../src/types/ERC20AsDot";
import { ERC20AsDot__factory } from "../src/types/factories/ERC20AsDot__factory";
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
    let TWO_ADDRESS = "0x0000000000000000000000000000000000000022";
    let slasherPercentageReward = 5;
    let paybackDeadline = 10; // Means 10 Bitcoin blocks
    let instantPercentageFee = 5; // Means 0.05%
    let collateralizationRatio = 200; // Means 200%

    let maxPriceDifferencePercent = 1000; // Means 10%
    let treasuaryAddress = ONE_ADDRESS;

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
        const erc20Factory = new ERC20AsDot__factory(deployer);
        collateralToken = await erc20Factory.deploy(
            "TestToken",
            "TT",
            1000
        );
        const teleBTCFactory = new TeleBTC__factory(deployer);
        teleBTC = await teleBTCFactory.deploy(
            "teleBTC",
            "TBTC"
        );

        // mock finalizationParameter
        await mockBitcoinRelay.mock.finalizationParameter.returns(0);

        // Deploys instant router
        let instantRouterFactory = new InstantRouter__factory(deployer);
        instantRouter = await instantRouterFactory.deploy(
            teleBTC.address,
            mockBitcoinRelay.address,
            mockPriceOracle.address,
            mockCollateralPoolFactory.address,
            slasherPercentageReward,
            paybackDeadline,
            mockExchangeConnector.address,
            maxPriceDifferencePercent,
            treasuaryAddress
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
        await teleBTC.addMinter(deployerAddress)
        await teleBTC.mint(deployerAddress, 10000000000);
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
        requiredCollateralPoolToken: number,
        totalCollateralToken?: number
    ): Promise<void> {
        await mockCollateralPool.mock.collateralizationRatio.returns(
            collateralizationRatio
        );
        await mockCollateralPool.mock.transferFrom.returns(
            true
        );
        await mockCollateralPool.mock.transfer.returns(
            true
        );
        await mockCollateralPool.mock.equivalentCollateralPoolToken.returns(
            requiredCollateralPoolToken
        );
        if (totalCollateralToken != undefined) {
            await mockCollateralPool.mock.equivalentCollateralToken.returns(
                totalCollateralToken
            );
        }
        await mockCollateralPool.mock.addCollateral.returns(
            true
        );
        await mockCollateralPool.mock.removeCollateral.returns(
            true
        );
    }

    async function mockFunctionsPriceOracle(
        outputAmount: number,
    ): Promise<void> {
        await mockPriceOracle.mock.equivalentOutputAmount.returns(
            outputAmount
        );
        // Adds an exchange connector to instant router
        await mockPriceOracle.mock.exchangeConnector.returns(
            mockExchangeConnector.address
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
        amounts: Array<number>,
        inputAmount: number
    ): Promise<void> {
        await mockExchangeConnector.mock.swap.returns(
            swapResult, amounts
        );
        await mockExchangeConnector.mock.getInputAmount.returns(
            swapResult,
            inputAmount
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

        beforeEach(async () => {
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
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            expect(
                await instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp*2,
                    collateralToken.address
                )
            ).to.emit(instantRouter, "InstantTransfer").withArgs(
                deployerAddress,
                signer1Address,
                loanAmount,
                Math.floor(loanAmount*instantPercentageFee/10000), // Instant fee
                lastSubmittedHeight + paybackDeadline,
                collateralToken.address,
                requiredCollateralPoolToken
            );

            // Checks that signer1 has received loan amount
            expect(
                await teleBTC.balanceOf(signer1Address)
            ).to.equal(loanAmount);

            expect(
                await instantRouter.getLockedCollateralPoolTokenAmount(deployerAddress, 0)
            ).to.equal(requiredCollateralPoolToken);

            expect(
                await instantRouter.getUserRequestDeadline(deployerAddress, 0)
            ).to.equal(lastSubmittedHeight + paybackDeadline);
            
            expect(
                instantRouter.getLockedCollateralPoolTokenAmount(deployerAddress, 1)
            ).to.revertedWith("InstantRouter: wrong index");

            expect(
                instantRouter.getUserRequestDeadline(deployerAddress, 1)
            ).to.revertedWith("InstantRouter: wrong index");
            
        });

        it("Reverts since contract is paused", async function () {

            await instantRouter.pause();

            expect(
                instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    0,
                    collateralToken.address
                )
            ).to.revertedWith("Pausable: paused")
        });

        it("Reverts since deadline has paased", async function () {
            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            expect(
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
            expect(
                instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp*2,
                    collateralToken.address
                )
            ).to.revertedWith("InstantRouter: collateral token is not acceptable")
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
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            expect(
                instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp*2,
                    collateralToken.address
                )
            ).to.revertedWith("InstantPool: liquidity is not sufficient")
        });


        it("Reverts because has reached to max loan number", async function () {
            // Set parameters
            loanAmount = 4;
            equivalentCollateralToken = 50; // Assumes that: 1 collateralToken = 2 teleBTC
            requiredCollateralPoolToken = equivalentCollateralToken*collateralizationRatio; // Assumes that: 1 collateralToken = 1 collateralPoolToken
            lastSubmittedHeight = 100;
            isCollateral = true;
            transferFromResult = true;

            // Mocks functions
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            for (var i = 0; i < 15; i++) {
                await instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp*2,
                    collateralToken.address
                )
            }

            // Checks that loan has been issued successfully
            await expect(
                instantRouter.instantCCTransfer(
                    signer1Address,
                    loanAmount,
                    lastBlockTimestamp*2,
                    collateralToken.address
                )
            ).to.revertedWith("InstantRouter: reached max loan number")
            
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

        beforeEach(async () => {
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
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
            await mockFunctionsExchangeConnector(swapResult, [loanAmount, amountOut], 0);

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            expect(
                await instantRouter.instantCCExchange(
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
                collateralToken.address,
                requiredCollateralPoolToken
            );
        });

        it("Reverts since contract is paused", async function () {

            await instantRouter.pause();

            expect(
                instantRouter.instantCCExchange(
                    mockExchangeConnector.address,
                    signer1Address,
                    loanAmount,
                    amountOut,
                    path,
                    0,
                    collateralToken.address,
                    isFixedToken
                )
            ).to.revertedWith("Pausable: paused")
        });

        it("Reverts since deadline has paased", async function () {
            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            expect(
                instantRouter.instantCCExchange(
                    mockExchangeConnector.address,
                    signer1Address,
                    loanAmount,
                    amountOut,
                    path,
                    lastBlockTimestamp -1,
                    collateralToken.address,
                    isFixedToken
                )
            ).to.revertedWith("InstantRouter: deadline has passed")
        });

        it("Reverts since path is invalid", async function () {
            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Path's first token is not teleBTC
            expect(
                instantRouter.instantCCExchange(
                    mockExchangeConnector.address,
                    signer1Address,
                    loanAmount,
                    amountOut,
                    [deployerAddress, collateralToken.address],
                    lastBlockTimestamp*2,
                    collateralToken.address,
                    isFixedToken
                )
            ).to.revertedWith("InstantRouter: path is invalid");
            
            // Path only has one token
            expect(
                instantRouter.instantCCExchange(
                    mockExchangeConnector.address,
                    signer1Address,
                    loanAmount,
                    amountOut,
                    [teleBTC.address],
                    lastBlockTimestamp*2,
                    collateralToken.address,
                    isFixedToken
                )
            ).to.revertedWith("InstantRouter: path is invalid");
        });

        it("Reverts since instant pool liquidity is not enough", async function () {
            // Set parameters
            loanAmount = 200;
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
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
            await mockFunctionsExchangeConnector(swapResult, [loanAmount, amountOut], 0);

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            expect(
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
            ).to.revertedWith("InstantPool: liquidity is not sufficient")
        });

        it("Reverts since collateral is not acceptable", async function () {
            // Mocks functions
            isCollateral = false;
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Checks that loan has been issued successfully
            expect(
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
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
            await mockFunctionsExchangeConnector(swapResult, [], 0);

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            expect(
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

    });

    describe("#payBackLoan", async () => {
        // Parameters
        let loanAmount: number;
        let equivalentCollateralToken: number;
        let requiredCollateralPoolToken: number;
        let lastSubmittedHeight: number;
        let isCollateral: boolean;
        let transferFromResult: boolean;

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);

            // Set parameters
            loanAmount = 100;
            equivalentCollateralToken = 50; // Assumes that: 1 collateralToken = 2 teleBTC
            requiredCollateralPoolToken = equivalentCollateralToken*collateralizationRatio; // Assumes that: 1 collateralToken = 1 collateralPoolToken
            lastSubmittedHeight = 100;
            isCollateral = true;
            transferFromResult = true;

            // Mocks functions
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Paybacks a debt when user has one unpaid debt", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Creates a debt for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            // Mints teleBTC for deployer to payback loan
            await teleBTC.mint(deployerAddress, 10000000000)
            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);
            await teleBTC.approve(instantRouter.address, loanAmount + instantFee)

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);
            
            // User has one unpaid loan
            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);

            expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount + instantFee
                )
            ).to.emit(instantRouter, "PaybackLoan").withArgs(
                deployerAddress,
                loanAmount + instantFee,
                collateralToken.address,
                requiredCollateralPoolToken
            );
            
            // User doesn't have any unpaid loan
            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(0);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(0);
        });

        it("Paybacks a debt when user has two unpaid debts", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Adds more liquidity to instant pool
            await teleBTC.approve(teleBTCInstantPool.address, addedLiquidity);
            await teleBTCInstantPool.addLiquidity(deployerAddress, addedLiquidity);

            // Creates two debts for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            // Mints teleBTC for deployer to payback loan
            await teleBTC.mint(deployerAddress, 10000000000)
            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);
            await teleBTC.approve(instantRouter.address, loanAmount + instantFee)

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(2);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal((loanAmount + instantFee)*2);

            expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount + instantFee
                )
            ).to.emit(instantRouter, "PaybackLoan").withArgs(
                deployerAddress,
                loanAmount + instantFee,
                collateralToken.address,
                requiredCollateralPoolToken  
            );

            // User only pays back one of debts
            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);
        });

        it("Paybacks a debt and sends remained amount to user when user has two unpaid debts", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Adds more liquidity to instant pool
            await teleBTC.approve(teleBTCInstantPool.address, addedLiquidity);
            await teleBTCInstantPool.addLiquidity(deployerAddress, addedLiquidity);

            // Creates two debts for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            // Mints teleBTC for deployer to payback loan
            await teleBTC.mint(deployerAddress, 10000000000)
            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);
            await teleBTC.approve(instantRouter.address, loanAmount + loanAmount + instantFee);
            let deployerBalance: BigNumber;
            deployerBalance = await teleBTC.balanceOf(deployerAddress);

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(2);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + loanAmount + instantFee);

            expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount + instantFee
                )
            ).to.emit(instantRouter, "PaybackLoan").withArgs(
                deployerAddress,
                loanAmount + instantFee,
                collateralToken.address,
                requiredCollateralPoolToken
            );

            // User only pays back one of debts
            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);

            expect(
                await teleBTC.balanceOf(deployerAddress)
            ).to.equal(deployerBalance.toNumber() - loanAmount - instantFee);
        });

        it("Paybacks debts when user has two unpaid debts", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Adds more liquidity to instant pool
            await teleBTC.approve(teleBTCInstantPool.address, addedLiquidity);
            await teleBTCInstantPool.addLiquidity(deployerAddress, addedLiquidity);

            // Creates two debts for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            // Mints teleBTC for deployer to payback loan
            await teleBTC.mint(deployerAddress, 10000000000)
            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);
            await teleBTC.approve(instantRouter.address, 2*(loanAmount + instantFee));

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(2);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal((loanAmount + instantFee)*2);

            expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    2*(loanAmount + instantFee)
                )
            ).to.emit(instantRouter, "PaybackLoan").withArgs(
                deployerAddress,
                loanAmount + instantFee,
                collateralToken.address,
                requiredCollateralPoolToken
            )

            // User only paybacks one of debts
            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(0);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(0);
        });

        it("Sends teleBTC back to user since payback amount is not enough", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Creates a debt for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            // Mints teleBTC for deployer to payback loan
            await teleBTC.mint(deployerAddress, 10000000000);
            await teleBTC.approve(instantRouter.address, loanAmount - 1);

            let deployerBalance = await teleBTC.balanceOf(
                deployerAddress
            );

            await expect(
                instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount - 1
                )
            ).to.not.emit(instantRouter, "PaybackLoan");

            // Checks that deployer receives its teleBTC
            expect(
                await teleBTC.balanceOf(
                    deployerAddress
                )
            ).to.equal(deployerBalance);
        });

        it("Sends teleBTC back to user since deadline has passed", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            // Creates a debt for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            // Mints teleBTC for deployer to payback loan
            await teleBTC.mint(deployerAddress, 10000000000)
            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);
            await teleBTC.approve(instantRouter.address, loanAmount + instantFee);

            let deployerBalance = await teleBTC.balanceOf(
                deployerAddress
            );

            // Passes payback deadline
            await mockFunctionsBitcoinRelay(lastSubmittedHeight*2);

            await expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount + instantFee
                )
            ).to.not.emit(instantRouter, "PaybackLoan");

            // Checks that deployer receives its teleBTC
            expect(
                await teleBTC.balanceOf(
                    deployerAddress
                )
            ).to.equal(deployerBalance);
        });

    });

    describe("#slashUser", async () => {
        // Parameters
        let loanAmount: number;
        let loanAmount2: number | undefined;
        let equivalentCollateralToken: number;
        let requiredCollateralPoolToken: number;
        let requiredCollateralPoolToken2: number | undefined;
        let requiredCollateralToken: number;
        let totalCollateralToken: number;
        let lastSubmittedHeight: number;
        let isCollateral: boolean;
        let swapResult: boolean;

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);

            // Set parameters
            loanAmount = 100;
            loanAmount2 = loanAmount;
            equivalentCollateralToken = 50; // Assumes that: 1 collateralToken = 2 teleBTC
            requiredCollateralToken = 25;
            totalCollateralToken = 100;
            requiredCollateralPoolToken = equivalentCollateralToken*collateralizationRatio; // Assumes that: 1 collateralToken = 1 collateralPoolToken
            requiredCollateralPoolToken2 = requiredCollateralPoolToken;
            lastSubmittedHeight = 100;
            isCollateral = true;
            swapResult = true;

            // Mocks functions
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken, totalCollateralToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
            await mockFunctionsExchangeConnector(swapResult, [loanAmount2 , requiredCollateralPoolToken2], requiredCollateralToken);
            await teleBTC.transfer(instantRouter.address, requiredCollateralPoolToken);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Slash user reverted because big gap between dex and oracle", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            await collateralToken.transfer(instantRouter.address, totalCollateralToken);

            // Creates a debt for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);

            // Passes payback deadline
            await mockFunctionsBitcoinRelay(lastSubmittedHeight*2);

            await mockFunctionsPriceOracle(requiredCollateralToken * 12 / 100);

            await expect(
                instantRouter.slashUser(
                    deployerAddress,
                    0
                )
            ).to.be.revertedWith("InstantRouter: big gap between oracle and AMM price")

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);
        });

        it("Slashes user and pays instant loan fully", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            await collateralToken.transfer(instantRouter.address, totalCollateralToken);

            // Creates a debt for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);

            // Passes payback deadline
            await mockFunctionsBitcoinRelay(lastSubmittedHeight*2);

            await mockFunctionsPriceOracle(requiredCollateralToken);

            expect(
                await instantRouter.slashUser(
                    deployerAddress,
                    0
                )
            ).to.emit(instantRouter, "SlashUser").withArgs(
                deployerAddress, 
                collateralToken.address, 
                requiredCollateralToken, 
                loanAmount + instantFee,
                deployerAddress,
                Math.floor((totalCollateralToken-requiredCollateralToken)*slasherPercentageReward/100)
            )

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(0);
        });

        it("Slashes user and pays instant loan partially", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            await collateralToken.transfer(instantRouter.address, totalCollateralToken);

            // Creates a debt for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);

            // Passes payback deadline
            await mockFunctionsBitcoinRelay(lastSubmittedHeight*2);
            
            //
            await mockExchangeConnector.mock.getInputAmount.returns(
                true,
                totalCollateralToken + 1
            );

            await mockFunctionsPriceOracle(totalCollateralToken);

            expect(
                await instantRouter.slashUser(
                    deployerAddress,
                    0
                )
            ).to.emit(instantRouter, "SlashUser").withArgs(
                deployerAddress, 
                collateralToken.address, 
                totalCollateralToken, 
                loanAmount + instantFee,
                deployerAddress,
                0 // Slasher reward is zero
            );

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(0);
        });

        it("Reverts since request index is out of range", async function () {
            expect(
                instantRouter.slashUser(
                    deployerAddress,
                    0
                )
            ).to.revertedWith("InstantRouter: request index does not exist");
        });

        it("Reverts since payback deadline has not passed yet", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            await collateralToken.transfer(instantRouter.address, totalCollateralToken);

            // Creates a debt for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            await mockFunctionsBitcoinRelay(lastSubmittedHeight);

            expect(
                instantRouter.slashUser(
                    deployerAddress,
                    0
                )
            ).to.revertedWith("InstantRouter: deadline has not passed yet");
        });

        it("Reverts since liquidity pool doesn't exist", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            await collateralToken.transfer(instantRouter.address, totalCollateralToken);

            // Creates a debt for deployer
            await instantRouter.instantCCTransfer(
                signer1Address,
                loanAmount,
                lastBlockTimestamp*2,
                collateralToken.address
            );

            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);

            // Passes payback deadline
            await mockFunctionsBitcoinRelay(lastSubmittedHeight*2);
            await mockFunctionsExchangeConnector(false, [], requiredCollateralToken);

            expect(
                instantRouter.slashUser(
                    deployerAddress,
                    0
                )
            ).to.revertedWith("InstantRouter: liquidity pool doesn't exist");
        });

    });

    describe("#setters", async () => {

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Sets slasher percentage reward", async function () {
            await expect(
                instantRouter.setSlasherPercentageReward(100)
            ).to.emit(
                instantRouter, "NewSlasherPercentageReward"
            ).withArgs(slasherPercentageReward, 100);

            expect(
                await instantRouter.slasherPercentageReward()
            ).to.equal(100);
        })

        it("Reverts since slasher percentage reward is greater than 100", async function () {
            expect(
                instantRouter.setSlasherPercentageReward(101)
            ).to.revertedWith("InstantRouter: wrong slasher percentage reward");
        })

        it("Sets payback deadline", async function () {
            await mockBitcoinRelay.mock.finalizationParameter.returns(1);

            await expect(
                instantRouter.setPaybackDeadline(4)
            ).to.emit(
                instantRouter, "NewPaybackDeadline"
            ).withArgs(paybackDeadline, 4);

            expect(
                await instantRouter.paybackDeadline()
            ).to.equal(4);
        })

        it("Reverts since payback deadline is lower than relay finalization parameter", async function () {
            await mockBitcoinRelay.mock.finalizationParameter.returns(2);

            expect(
                instantRouter.setPaybackDeadline(3)
            ).to.revertedWith("InstantRouter: wrong payback deadline");
        })

        it("Reverts since payback deadline is lower than relay finalization parameter", async function () {
            await mockBitcoinRelay.mock.finalizationParameter.returns(2);

            expect(
                instantRouter.setPaybackDeadline(1)
            ).to.revertedWith("InstantRouter: wrong payback deadline");
        })

        it("Sets relay, lockers, instant router, teleBTC and treasury", async function () {
            await expect(
                instantRouter.setRelay(ONE_ADDRESS)
            ).to.emit(
                instantRouter, "NewRelay"
            ).withArgs(mockBitcoinRelay.address, ONE_ADDRESS);

            expect(
                await instantRouter.relay()
            ).to.equal(ONE_ADDRESS);

            await expect(
                instantRouter.setTeleBTC(ONE_ADDRESS)
            ).to.emit(
                instantRouter, "NewTeleBTC"
            ).withArgs(teleBTC.address, ONE_ADDRESS);

            expect(
                await instantRouter.teleBTC()
            ).to.equal(ONE_ADDRESS);

            await expect(
                instantRouter.setCollateralPoolFactory(ONE_ADDRESS)
            ).to.emit(
                instantRouter, "NewCollateralPoolFactory"
            ).withArgs(mockCollateralPoolFactory.address, ONE_ADDRESS);

            expect(
                await instantRouter.collateralPoolFactory()
            ).to.equal(ONE_ADDRESS);

            await expect(
                instantRouter.setPriceOracle(ONE_ADDRESS)
            ).to.emit(
                instantRouter, "NewPriceOracle"
            ).withArgs(mockPriceOracle.address, ONE_ADDRESS);

            expect(
                await instantRouter.priceOracle()
            ).to.equal(ONE_ADDRESS);

            await expect(
                instantRouter.setDefaultExchangeConnector(ONE_ADDRESS)
            ).to.emit(
                instantRouter, "NewDeafultExchangeConnector"
            ).withArgs(mockExchangeConnector.address, ONE_ADDRESS);

            expect(
                await instantRouter.defaultExchangeConnector()
            ).to.equal(ONE_ADDRESS);

            await expect(
                instantRouter.setTeleBTCInstantPool(ONE_ADDRESS)
            ).to.emit(
                instantRouter, "NewTeleBTCInstantPool"
            ).withArgs(teleBTCInstantPool.address, ONE_ADDRESS);

            expect(
                await instantRouter.teleBTCInstantPool()
            ).to.equal(ONE_ADDRESS);


            await expect(
                instantRouter.setTreasuaryAddress(TWO_ADDRESS)
            ).to.emit(
                instantRouter, "NewTreasuaryAddress"
            ).withArgs(ONE_ADDRESS, TWO_ADDRESS);

            expect(
                await instantRouter.treasuaryAddress()
            ).to.equal(TWO_ADDRESS);


            await expect(
                instantRouter.setMaxPriceDifferencePercent(2 * maxPriceDifferencePercent)
            ).to.emit(
                instantRouter, "NewMaxPriceDifferencePercent"
            ).withArgs(maxPriceDifferencePercent, 2 * maxPriceDifferencePercent);

            expect(
                await instantRouter.maxPriceDifferencePercent()
            ).to.equal(2 * maxPriceDifferencePercent);

        })

        it("Reverts since given address is zero", async function () {
            expect(
                instantRouter.setRelay(ZERO_ADDRESS)
            ).to.revertedWith("InstantRouter: zero address");

            expect(
                instantRouter.setTeleBTC(ZERO_ADDRESS)
            ).to.revertedWith("InstantRouter: zero address");

            expect(
                instantRouter.setPriceOracle(ZERO_ADDRESS)
            ).to.revertedWith("InstantRouter: zero address");

            expect(
                instantRouter.setTeleBTC(ZERO_ADDRESS)
            ).to.revertedWith("InstantRouter: zero address");

            expect(
                instantRouter.setTeleBTCInstantPool(ZERO_ADDRESS)
            ).to.revertedWith("InstantRouter: zero address");


            expect(
                instantRouter.setDefaultExchangeConnector(ZERO_ADDRESS)
            ).to.revertedWith("InstantRouter: zero address");

            expect(
                instantRouter.setCollateralPoolFactory(ZERO_ADDRESS)
            ).to.revertedWith("InstantRouter: zero address");

            expect(
                instantRouter.setTreasuaryAddress(ZERO_ADDRESS)
            ).to.revertedWith("InstantRouter: zero address");
        })

        it("Reverted because non-owner account is calling ", async function () {

            let instantRouterSigner1 = await instantRouter.connect(signer1);

            await expect(
                instantRouterSigner1.setRelay(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner");

            await expect(
                instantRouterSigner1.setTeleBTC(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner")

            await expect(
                instantRouterSigner1.setCollateralPoolFactory(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner")

            await expect(
                instantRouterSigner1.setPriceOracle(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner")

            await expect(
                instantRouterSigner1.setDefaultExchangeConnector(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner")

            await expect(
                instantRouterSigner1.setTeleBTCInstantPool(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner")

            await expect(
                instantRouterSigner1.setTreasuaryAddress(TWO_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner")


            await expect(
                instantRouterSigner1.setMaxPriceDifferencePercent(2 * maxPriceDifferencePercent)
            ).to.be.revertedWith("Ownable: caller is not the owner")

            await expect(
                instantRouterSigner1.setPaybackDeadline(2 * maxPriceDifferencePercent)
            ).to.be.revertedWith("Ownable: caller is not the owner")

            await expect(
                instantRouterSigner1.setSlasherPercentageReward(2 * maxPriceDifferencePercent)
            ).to.be.revertedWith("Ownable: caller is not the owner")

        })

    });

});