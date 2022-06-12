// const BitcoinRelay = artifacts.require("BitcoinRelay");
require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";

import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import {CCExchangeRouter} from "../src/types/CCExchangeRouter";
import {CCExchangeRouter__factory} from "../src/types/factories/CCExchangeRouter__factory";

const {
    advanceBlockWithTime,
    takeSnapshot,
    revertProvider,
} = require("./block_utils");

describe("CC Exchange Router", async () => {
    let snapshotId: any;

    let ccExchangeRouter: CCExchangeRouter;
    let deployer: Signer;
    let signer1: Signer;

    let mockExchangeRouter: MockContract;

    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    before(async () => {

        [deployer, signer1] = await ethers.getSigners();

        // read block headers from file

        const exchangeContract = await deployments.getArtifact(
            "IExchangeRouter"
        );

        // console.log("the ABI: ", exchangeContract.abi)

        mockExchangeRouter = await deployMockContract(
            deployer,
            exchangeContract.abi
        )

    });

    beforeEach("deploy a new cc exchange router", async () => {
        snapshotId = await takeSnapshot(signer1.provider);

        ccExchangeRouter = await deployCCExchangeRouter();
    });

    afterEach(async () => {
        await revertProvider(signer1.provider, snapshotId);
    });

    const deployCCExchangeRouter = async (
        _signer?: Signer
    ): Promise<CCExchangeRouter> => {
        const ccExchangeRouterFactory = new CCExchangeRouter__factory(
            _signer || deployer
        );

        await mockExchangeRouter.mock.liquidityPoolFactory.returns(
            ZERO_ADDRESS
        );

        await mockExchangeRouter.mock.WAVAX.returns(
            ZERO_ADDRESS
        );

        const ccExchangeRouter = await ccExchangeRouterFactory.deploy(
            mockExchangeRouter.address,
            ZERO_ADDRESS,
            ZERO_ADDRESS
        );

        return ccExchangeRouter;
    };

    describe("a sample function", async () => {

        it("first scenario", async function () {
            expect(
                await ccExchangeRouter.bitcoinTeleporter()
            ).to.equal(ZERO_ADDRESS)
        })

        it("second scenario", async function () {
            expect(
                await ccExchangeRouter.exchangeRouter()
            ).to.equal(mockExchangeRouter.address)
        })

    });
});