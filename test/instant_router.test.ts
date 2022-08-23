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
            "TBTC"
        );

        // Deploys instant router
        let instantRouterFactory = new InstantRouter__factory(deployer);
        instantRouter = await instantRouterFactory.deploy(
            teleBTC.address,
            mockBitcoinRelay.address,
            mockPriceOracle.address,
            mockCollateralPoolFactory.address,
            slasherPercentageReward,
            paybackDeadline,
            mockExchangeConnector.address
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
            true,
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
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
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
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
            await mockFunctionsExchangeConnector(swapResult, [], 0);

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

        it("Paybacks a debt", async function () {

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
            await teleBTC.mintTestToken()
            let instantFee = Math.floor(loanAmount*instantPercentageFee/10000);
            await teleBTC.approve(instantRouter.address, loanAmount + instantFee)

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);

            await expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount + instantFee
                )
            ).to.emit(instantRouter, "PaybackLoan");

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(0);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(0);
        });

        it("Paybacks a debt when user has two active debts", async function () {

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
            await teleBTC.mintTestToken()
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

            await expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount + instantFee
                )
            ).to.emit(instantRouter, "PaybackLoan");

            // User only paybacks one of debts
            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(1);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(loanAmount + instantFee);
        });

        it("Paybacks a debt and sends remained amount to user when user has two active debts", async function () {

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
            await teleBTC.mintTestToken()
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

            await expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount + instantFee
                )
            ).to.emit(instantRouter, "PaybackLoan");

            // User only paybacks one of debts
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

        it("Paybacks debts when user has two active debts", async function () {

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
            await teleBTC.mintTestToken()
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

            await expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    2*(loanAmount + instantFee)
                )
            ).to.emit(instantRouter, "PaybackLoan");

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

        it("Gives teleBTC to user since deadline has passed", async function () {

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
            await teleBTC.mintTestToken()
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
            await expect(
                await teleBTC.balanceOf(
                    deployerAddress
                )
            ).to.equal(deployerBalance);
        });

        it("Gives teleBTC to user since payback amount is not enough", async function () {

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
            await teleBTC.mintTestToken();
            await teleBTC.approve(instantRouter.address, loanAmount - 1);

            let deployerBalance = await teleBTC.balanceOf(
                deployerAddress
            );

            await expect(
                await instantRouter.payBackLoan(
                    deployerAddress,
                    loanAmount - 1
                )
            ).to.not.emit(instantRouter, "PaybackLoan");

            // Checks that deployer receives its teleBTC
            await expect(
                await teleBTC.balanceOf(
                    deployerAddress
                )
            ).to.equal(deployerBalance);
        });
    });

    describe("#slashUser", async () => {
        // Parameters
        let loanAmount: number;
        let equivalentCollateralToken: number;
        let requiredCollateralPoolToken: number;
        let requiredCollateralToken: number;
        let totalCollateralToken: number;
        let lastSubmittedHeight: number;
        let isCollateral: boolean;
        let swapResult: boolean;

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);

            // Set parameters
            loanAmount = 100;
            equivalentCollateralToken = 50; // Assumes that: 1 collateralToken = 2 teleBTC
            requiredCollateralToken = 25;
            totalCollateralToken = 100;
            requiredCollateralPoolToken = equivalentCollateralToken*collateralizationRatio; // Assumes that: 1 collateralToken = 1 collateralPoolToken
            lastSubmittedHeight = 100;
            isCollateral = true;
            swapResult = true;

            // Mocks functions
            await mockFunctionsCollateralPoolFactory(isCollateral, mockCollateralPool.address);
            await mockFunctionsCollateralPool(collateralizationRatio, requiredCollateralPoolToken, totalCollateralToken);
            await mockFunctionsPriceOracle(equivalentCollateralToken);
            await mockFunctionsBitcoinRelay(lastSubmittedHeight);
            await mockFunctionsExchangeConnector(swapResult, [], requiredCollateralToken);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Slashes user", async function () {

            // Gets last block timestamp
            let lastBlockTimestamp = await getTimestamp();

            /* Sends totalCollateralToken to instant router since collateral pool was mocked:
                ICollateralPool(collateralPool).removeCollateral(lockedCollateralPoolTokenAmount);
            */
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

            await expect(
                await instantRouter.slashUser(
                    deployerAddress,
                    0
                )
            ).to.emit(instantRouter, "SlashUser");

            /* Sends paybackAmount to instant router since exchange connector was mocked:
                IExchangeConnector(_exchangeConnector).swap(
                    requiredCollateralToken,
                    paybackAmount,
                    path,
                    teleBTCInstantPool,
                    block.timestamp + 1,
                    false
                );
            */
            await teleBTC.transfer(teleBTCInstantPool.address, loanAmount + instantFee);

            expect(
                await instantRouter.getUserRequestsLength(
                    deployerAddress
                )
            ).to.equal(0);

            expect(
                await teleBTCInstantPool.totalUnpaidLoan()
            ).to.equal(0);
        });
    });
});