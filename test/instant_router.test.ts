// const BitcoinRelay = artifacts.require("BitcoinRelay");
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";
import { Address } from "hardhat-deploy/types";

import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import {ERC20} from "../src/types/ERC20";
import {ERC20__factory} from "../src/types/factories/ERC20__factory";
import {WAVAX} from "../src/types/WAVAX";
import {WAVAX__factory} from "../src/types/factories/WAVAX__factory";
import {WrappedToken} from "../src/types/WrappedToken";
import {WrappedToken__factory} from "../src/types/factories/WrappedToken__factory";
import {InstantRouter} from "../src/types/InstantRouter";
import {InstantRouter__factory} from "../src/types/factories/InstantRouter__factory";
import {InstantPool} from "../src/types/InstantPool";
import {InstantPool__factory} from "../src/types/factories/InstantPool__factory";
import {LiquidityPool} from "../src/types/LiquidityPool";
import {LiquidityPool__factory} from "../src/types/factories/LiquidityPool__factory";


const {
    advanceBlockWithTime,
    takeSnapshot,
    revertProvider,
} = require("./block_utils");

describe("CC Exchange Router", async () => {
    let snapshotId: any;

    let deployer: Signer;
    let signer1: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;

    let TeleportDAOToken: ERC20;
    let WrappedBTC: WrappedToken;
    let wavax: WAVAX;
    let bitcoinInstantPool: InstantPool;
    let bitcoinInstantPoolAddress: Address;

    let mockCCTransferRouter: MockContract;
    let mockExchangeRouter: MockContract;
    let mockLiquidityPoolFactory: MockContract;
    let mockStaking: MockContract;
    let mockBitcoinRelay: MockContract;
    let mockLiquidityPool: MockContract;

    let instantRouter: InstantRouter;

    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000)
    let ten = BigNumber.from(10).pow(18).mul(10)
    let oneHundred = BigNumber.from(10).pow(18).mul(100)

    let punishReward = 5
    let payBackDeadLine = 10
    let collateralRatio = 200 // means 200%
    let instantFee = 5 // means 5%

    before(async () => {

        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress()
        signer1Address = await signer1.getAddress()

        // read block headers from file

        const ccTransferRouter = await deployments.getArtifact(
            "ICCTransferRouter"
        );
        mockCCTransferRouter = await deployMockContract(
            deployer,
            ccTransferRouter.abi
        )


        const exchangeRouter = await deployments.getArtifact(
            "IExchangeRouter"
        );
        mockExchangeRouter = await deployMockContract(
            deployer,
            exchangeRouter.abi
        )

        const liquidityPoolFactory = await deployments.getArtifact(
            "ILiquidityPoolFactory"
        );
        mockLiquidityPoolFactory = await deployMockContract(
            deployer,
            liquidityPoolFactory.abi
        )

        const liquidityPool = await deployments.getArtifact(
            "LiquidityPool"
        );
        mockLiquidityPool = await deployMockContract(
            deployer,
            liquidityPool.abi
        )

        const staking = await deployments.getArtifact(
            "IStaking"
        );
        mockStaking = await deployMockContract(
            deployer,
            staking.abi
        )

        const bitcoinRelay = await deployments.getArtifact(
            "IBitcoinRelay"
        );
        mockBitcoinRelay = await deployMockContract(
            deployer,
            bitcoinRelay.abi
        )

        TeleportDAOToken = await deployTelePortDaoToken()
        WrappedBTC = await deployWrappedBTC()
        wavax = await deployWAVAX()

    });

    beforeEach("deploy a new cc exchange router", async () => {
        snapshotId = await takeSnapshot(signer1.provider);

        instantRouter = await deployInstantRouter();
    });

    afterEach(async () => {
        await revertProvider(signer1.provider, snapshotId);
    });

    const deployWAVAX = async (
        _signer?: Signer
    ): Promise<WAVAX> => {
        const wavaxFactory = new WAVAX__factory(
            _signer || deployer
        );

        const wavax = await wavaxFactory.deploy(
            "WAVAX Token",
            "WAVAX"
        );

        return wavax;
    };

    const deployTelePortDaoToken = async (
        _signer?: Signer
    ): Promise<ERC20> => {
        const erc20Factory = new ERC20__factory(
            _signer || deployer
        );

        const wrappedToken = await erc20Factory.deploy(
            "WrappedBTC",
            "TBTC",
            telePortTokenInitialSupply
        );

        return wrappedToken;
    };


    const deployWrappedBTC = async (
        _signer?: Signer
    ): Promise<WrappedToken> => {
        const wrappedTokenFactory = new WrappedToken__factory(
            _signer || deployer
        );

        const wrappedToken = await wrappedTokenFactory.deploy(
            "WrappedBTC",
            "TBTC",
            mockCCTransferRouter.address
        );

        return wrappedToken;
    };

    const deployInstantRouter = async (
        _signer?: Signer
    ): Promise<InstantRouter> => {
        const instantRouterFactory = new InstantRouter__factory(
            _signer || deployer
        );

        await mockCCTransferRouter.mock.wrappedBitcoin.returns(
            WrappedBTC.address
        )

        await mockExchangeRouter.mock.WAVAX.returns(
            wavax.address
        )

        const instantRouter = await instantRouterFactory.deploy(
            mockCCTransferRouter.address,
            mockExchangeRouter.address,
            TeleportDAOToken.address,
            mockLiquidityPoolFactory.address,
            mockStaking.address,
            mockBitcoinRelay.address,
            punishReward,
            payBackDeadLine,
            collateralRatio,
            instantFee
        );

        bitcoinInstantPoolAddress = await instantRouter.bitcoinInstantPool()

        let bitcoinInstantPoolFactory = new InstantPool__factory(
            deployer
        )
        bitcoinInstantPool = await bitcoinInstantPoolFactory.attach(
            bitcoinInstantPoolAddress
        )

        return instantRouter;
    };

    describe("#addLiquidity", async () => {

        let theTestMintedAmount = oneHundred

        it("minting wrapped BTC for the user", async function () {

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            expect(
                await WrappedBTC.balanceOf(signer1Address)
            ).to.equal(theTestMintedAmount)
        })

        it("approving wrapped BTC for the instant pool", async function () {

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            await WrappedBTCSigner1.approve(
                instantRouter.address,
                theTestMintedAmount
            )

            expect(
                await WrappedBTC.allowance(signer1Address, instantRouter.address)
            ).to.equal(theTestMintedAmount)
        })

        it("adding liquidity to the instant pool and getting instant pool token", async function () {

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            await WrappedBTCSigner1.approve(
                instantRouter.address,
                theTestMintedAmount
            )

            let instantRouterSigner1 = await instantRouter.connect(signer1)

            await instantRouterSigner1.addLiquidity(
                signer1Address,
                theTestMintedAmount
            )

            expect(
                await bitcoinInstantPool.balanceOf(signer1Address)
            ).to.equal(theTestMintedAmount)
        })

    });


    describe("#removeLiquidity", async () => {

        let theTestMintedAmount = oneHundred

        it("insufficient funds to remove", async function () {

            let instantRouterSigner1 = await instantRouter.connect(signer1)

            await expect(
                instantRouterSigner1.removeLiquidity(
                    signer1Address,
                    theTestMintedAmount
                )
            ).to.revertedWith("instant pool token is not enough")
        })

        it("removing liquidity from the instant pool and get back wrapped BTC", async function () {

            let WrappedBTCSigner1 = await WrappedBTC.connect(signer1)

            await WrappedBTCSigner1.mintTestToken()

            await WrappedBTCSigner1.approve(
                instantRouter.address,
                theTestMintedAmount
            )

            let instantRouterSigner1 = await instantRouter.connect(signer1)

            await instantRouterSigner1.addLiquidity(
                signer1Address,
                theTestMintedAmount
            )

            expect(
                await WrappedBTC.balanceOf(bitcoinInstantPool.address)
            ).to.equal(theTestMintedAmount)

            expect(
                await WrappedBTC.balanceOf(signer1Address)
            ).to.equal(0)

            expect(
                await bitcoinInstantPool.balanceOf(signer1Address)
            ).to.equal(theTestMintedAmount)

            let bitcoinInstantPoolSigner1 = await bitcoinInstantPool.connect(signer1)

            await bitcoinInstantPoolSigner1.approve(
                instantRouter.address,
                theTestMintedAmount
            )

            expect(
                await instantRouterSigner1.removeLiquidity(
                    signer1Address,
                    theTestMintedAmount
                )
            ).to.emit(bitcoinInstantPool, "RemoveLiquidity")

            expect(
                await WrappedBTC.balanceOf(bitcoinInstantPool.address)
            ).to.equal(0)

            expect(
                await WrappedBTC.balanceOf(instantRouter.address)
            ).to.equal(theTestMintedAmount)

        })

    });

    describe("#instantCCTransfer", async () => {

        let reserve1 = oneHundred
        let reserve2 = oneHundred

        let theTestMintedAmount = oneHundred

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
                WrappedBTC.address,
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
            let numerator = reserve1.mul(ten).mul(1000);
            let  denominator = (reserve2.sub(ten)).mul(997);

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
                ten.mul(3)
            )

            await mockStaking.mock.unstake.withArgs(
                signer1Address,
                amountIn
            ).returns()

            let bitcoinInstantPoolAddress = await instantRouter.bitcoinInstantPool()

            await WrappedBTC.mintTestToken()
            await WrappedBTC.transfer(bitcoinInstantPoolAddress, theTestMintedAmount)

            expect(
                await WrappedBTC.balanceOf(bitcoinInstantPoolAddress)
            ).to.equal(theTestMintedAmount)


            await mockBitcoinRelay.mock.lastSubmittedHeight.returns(
                1234567
            )



            await instantRouterSigner1.instantCCTransfer(
                signer1Address,
                ten,
                theBlockNumber
            )
        });

    });
});