// const BitcoinRelay = artifacts.require("BitcoinRelay");
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";

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

const {
    advanceBlockWithTime,
    takeSnapshot,
    revertProvider,
} = require("./block_utils");

describe("CC Exchange Router", async () => {
    let snapshotId: any;

    let deployer: Signer;
    let signer1: Signer;

    let TeleportDAOToken: ERC20;
    let WrappedBTC: WrappedToken;
    let wavax: WAVAX;

    let mockCCTransferRouter: MockContract;
    let mockExchangeRouter: MockContract;
    let mockLiquidityPoolFactory: MockContract;
    let mockStaking: MockContract;
    let mockBitcoinRelay: MockContract;

    let instantRouter: InstantRouter;

    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000)

    before(async () => {

        [deployer, signer1] = await ethers.getSigners();

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
            0,
            0,
            0,
            0
        );

        return instantRouter;
    };

    describe("a sample function", async () => {

        it("first scenario", async function () {
            expect(
                await instantRouter.ccTransferRouter()
            ).to.equal(mockCCTransferRouter.address)
        })

        it("second scenario", async function () {
            expect(
                await instantRouter.exchangeRouter()
            ).to.equal(mockExchangeRouter.address)
        })

    });
});