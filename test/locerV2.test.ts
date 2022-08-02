require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";
import { Address } from "hardhat-deploy/types";

import { solidity } from "ethereum-waffle";

import { isBytesLike } from "ethers/lib/utils";
import { LockersV2 } from "../src/types/LockersV2";
import { LockersV2__factory } from "../src/types/factories/LockersV2__factory";
import { TeleBTC } from "../src/types/TeleBTC";
import { TeleBTC__factory } from "../src/types/factories/TeleBTC__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";


import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";

describe("Locker", async () => {

    let snapshotId: any;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000);
    let requiredTDTLockedAmount = BigNumber.from(10).pow(18).mul(500);
    let btcAmountToSlash = BigNumber.from(10).pow(8).mul(1)
    let collateralRatio = 2;

    // Bitcoin public key (32 bytes)
    let TELEPORTER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
    let TELEPORTER1_PublicKeyHash = '0xe74e55c339726ee799877efc38cf43845b20ca5c';
    let TELEPORTER2 = '0x03dbc6764b8884a92e871274b87583e6d5c2a58819473e17e107ef3f6aa5a61626';
    let TELEPORTER2_PublicKeyHash = '0xd191dbef3fa0b30f433157748c11cb93f08e839c';
    let UNLOCK_FEE =  5; // percentage of bond that protocol receives
    let UNLOCK_PERIOD = 2;
    let REQUIRED_LOCKED_AMOUNT =  1000; // amount of required TDT

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let ccBurnSimulator: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;
    let signer2Address: Address;
    let ccBurnSimulatorAddress: Address;

    // Contracts
    let locker: LockersV2;
    let teleportDAOToken: ERC20;
    let teleBTC: TeleBTC;

    // Mock contracts
    let mockExchangeConnector: MockContract;
    let mockPriceOracle: MockContract;

    before(async () => {
        // Sets accounts
        [deployer, signer1, signer2,ccBurnSimulator] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();
        signer2Address = await signer2.getAddress();
        ccBurnSimulatorAddress = await ccBurnSimulator.getAddress();

        teleportDAOToken = await deployTelePortDaoToken()

        // Mocks exchange router contract
        const exchangeConnectorContract = await deployments.getArtifact(
            "IExchangeConnector"
        );
        mockExchangeConnector = await deployMockContract(
            deployer,
            exchangeConnectorContract.abi
        );

        const priceOracleContract = await deployments.getArtifact(
            "IPriceOracle"
        );
        mockPriceOracle = await deployMockContract(
            deployer,
            priceOracleContract.abi
        );

        await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

        // Deploys liquidityPoolFactory
        // const liquidityPoolFactoryFactory = new LiquidityPoolFactory__factory(deployer);
        // liquidityPoolFactory = await liquidityPoolFactoryFactory.deploy(
        //     deployerAddress
        // );

        // // Creates liquidityPool__factory object
        // liquidityPool__factory = new LiquidityPool__factory(deployer);

        // // Deploys exchangeRouter contract
        // const exchangeRouterFactory = new ExchangeRouter__factory(deployer);
        // exchangeRouter = await exchangeRouterFactory.deploy(
        //     liquidityPoolFactory.address,
        //     ZERO_ADDRESS // WAVAX
        // );

        // const exchangeConnectorFactory = new UniswapConnector__factory(deployer);
        // exchangeConnector = await exchangeConnectorFactory.deploy(
        //     "TheExchangeConnector",
        //     mockExchangeRouter.address,
        //     ZERO_ADDRESS // WAVAX
        // );

        // Deploys bitcoinTeleporter contract
        locker = await deployLocker()

        // Sets ccBurnRouter address
        await locker.setCCBurnRouter(ccBurnSimulatorAddress);

        teleBTC = await deployTeleBTC()

        await teleBTC.addMinter(locker.address)
        await teleBTC.addBurner(locker.address)

        await locker.setTeleBTC(teleBTC.address)

    });

    beforeEach(async () => {
        // Takes snapshot
        snapshotId = await takeSnapshot(deployer.provider);
    });

    afterEach(async () => {
        // Reverts the state
        await revertProvider(deployer.provider, snapshotId);
    });


    const deployTelePortDaoToken = async (
        _signer?: Signer
    ): Promise<ERC20> => {
        const erc20Factory = new ERC20__factory(
            _signer || deployer
        );

        const teleportDAOToken = await erc20Factory.deploy(
            "TelePortDAOToken",
            "TDT",
            telePortTokenInitialSupply
        );

        return teleportDAOToken;
    };

    const deployTeleBTC = async (
        _signer?: Signer
    ): Promise<TeleBTC> => {
        const teleBTCFactory = new TeleBTC__factory(
            _signer || deployer
        );

        const wrappedToken = await teleBTCFactory.deploy(
            "TeleBTC",
            "TBTC",
            ONE_ADDRESS,
            ONE_ADDRESS,
            ONE_ADDRESS
        );

        return wrappedToken;
    };

    const deployLocker = async (
        _signer?: Signer
    ): Promise<LockersV2> => {
        const lockerFactory = new LockersV2__factory(
            _signer || deployer
        );

        const locker = await lockerFactory.deploy(
            teleportDAOToken.address,
            mockExchangeConnector.address,
            mockPriceOracle.address,
            requiredTDTLockedAmount,
            0,
            collateralRatio
        );

        return locker;
    };

    // async function addTeleporter(teleporterAddress: any, teleporterNumber: number) {
    //     // Gives allowance to bitcoinTeleporter

    //     let teleportDAOTokenSigner1 = await teleportDAOToken.connect(signer1);
    //     await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount);
    //     await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount);

    //     // Adds teleporter
    //     expect(
    //         await bitcoinTeleporter.addTeleporter(teleporterAddress)
    //     ).to.emit(bitcoinTeleporter, 'AddTeleporter');

    //     // Checks bitcoinTeleporter TDT balance
    //     expect(
    //         await teleportDAOToken.balanceOf(bitcoinTeleporter.address)
    //     ).to.equal(teleporterNumber*REQUIRED_LOCKED_AMOUNT);

    //     // Checks number of teleporters
    //     expect(await bitcoinTeleporter.numberOfTeleporters()).to.equal(teleporterNumber);

    //     return true;
    // }

    describe("#requestToBecomeLocker", async () => {

        it("setting low TeleportDao token", async function () {
            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    requiredTDTLockedAmount.sub(1),
                    0
                )
            ).to.be.revertedWith("Locker: low locking TDT amount")
        })

        it("not approving TeleportDao token", async function () {
            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    requiredTDTLockedAmount,
                    0
                )
            ).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
        })

        it("successful request to become locker", async function () {

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    requiredTDTLockedAmount,
                    0
                )
            ).to.emit(locker, "RequestAddLocker")

            expect(
                await locker.totalNumberOfCandidates()
            ).to.equal(1)

            let theCandidateMapping = await locker.candidatesMapping(signer1Address)
            expect(
                theCandidateMapping[0]
            ).to.equal(TELEPORTER1)
        })

    });

    describe("#revokeRequest", async () => {

        it("trying to revoke a non existing request", async function () {
            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.revokeRequest()
            ).to.be.revertedWith("Locker: request doesn't exit or already accepted")
        })

        it("successful revoke", async function () {

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                requiredTDTLockedAmount,
                0
            )

            let theCandidateMapping = await locker.candidatesMapping(signer1Address)
            expect(
                theCandidateMapping[0]
            ).to.equal(TELEPORTER1)

            await lockerSigner1.revokeRequest()

            expect(
                await locker.totalNumberOfCandidates()
            ).to.equal(0)

            theCandidateMapping = await locker.candidatesMapping(signer1Address)
            expect(
                theCandidateMapping[0]
            ).to.equal("0x")
        })

    });

    describe("#addLocker", async () => {

        it("trying to add a non existing request as a locker", async function () {
            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.addLocker(signer1Address)
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("adding a locker", async function () {

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                requiredTDTLockedAmount,
                0
            )

            let theCandidateMapping = await locker.candidatesMapping(signer1Address)
            expect(
                theCandidateMapping[0]
            ).to.equal(TELEPORTER1)

            expect(
                await locker.addLocker(signer1Address)
            ).to.emit(locker, "LockerAdded")

            expect(
                await locker.totalNumberOfCandidates()
            ).to.equal(0)

            expect(
                await locker.totalNumberOfLockers()
            ).to.equal(1)

            let theLockerMapping = await locker.lockersMapping(signer1Address)
            expect(
                theLockerMapping[0]
            ).to.equal(TELEPORTER1)
        })

    });

    describe("#requestToRemoveLocker", async () => {

        it("trying to request to remove a non existing locker", async function () {
            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.requestToRemoveLocker()
            ).to.be.revertedWith("Locker: Msg sender is not locker")
        })

        it("successfully request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                requiredTDTLockedAmount,
                0
            )

            await locker.addLocker(signer1Address)

            expect(
                await lockerSigner1.requestToRemoveLocker()
            ).to.emit(locker, "RequestRemoveLocker")
        })

    });

    describe("#removeLocker", async () => {

        it("only admin can call remove locker function", async function () {
            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.removeLocker(signer1Address)
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("can't remove a locker if it doesn't request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                requiredTDTLockedAmount,
                0
            )

            await locker.addLocker(signer1Address)

            await expect(
                locker.removeLocker(signer1Address)
            ).to.be.revertedWith("Locker: locker didn't request to be removed")
        })

        it("can't remove a locker if it doesn't request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                requiredTDTLockedAmount,
                0
            )

            await locker.addLocker(signer1Address)

            await lockerSigner1.requestToRemoveLocker()

            expect(
                await locker.removeLocker(signer1Address)
            ).to.emit(locker, "LockerRemoved")

            expect(
                await locker.totalNumberOfLockers()
            ).to.equal(0)
        })

    });

    describe("#selfRemoveLocker", async () => {

        it("only admin can call remove locker function", async function () {
            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Locker: no locker with this address")
        })

    });


    describe("#slashLocker", async () => {

        it("only admin can call slash locker function", async function () {
            let lockerSigner1 = locker.connect(signer1)

            await expect(
                lockerSigner1.slashLocker(
                    signer1Address,
                    btcAmountToSlash,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Locker: Caller can't slash")
        })

        it("slash locker reverts when the target address is not locker", async function () {
            let lockerCCBurnSimulator = locker.connect(ccBurnSimulator)

            await expect(
                lockerCCBurnSimulator.slashLocker(
                    signer1Address,
                    btcAmountToSlash,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Locker: target is not locker")
        })

        it("only admin can slash a locker", async function () {

            await mockExchangeConnector.mock.getInputAmount.returns(true, requiredTDTLockedAmount.div(10))
            await mockExchangeConnector.mock.swap.returns(true, [2500, 5000])

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                requiredTDTLockedAmount,
                0
            )

            expect(
                await locker.addLocker(signer1Address)
            ).to.emit(locker, "LockerAdded")

            let lockerCCBurnSigner = await locker.connect(ccBurnSimulator)

            await lockerCCBurnSigner.slashLocker(signer1Address, 10000, ccBurnSimulatorAddress)

        })


    });

    describe("#mintAndBurnTeleBTC", async () => {

        await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

        it("minting tele BTC", async function () {

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                requiredTDTLockedAmount,
                0
            )

            await locker.addLocker(signer1Address)

            await locker.addMinter(signer2Address)

            let lockerSigner2 = locker.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, signer2Address, 1000)

            let theLockerMapping = await locker.lockersMapping(signer1Address)

            expect(
                theLockerMapping[4]
            ).to.equal(1000)
        })


        it("burning tele BTC", async function () {

            await teleportDAOToken.transfer(signer1Address, requiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(locker.address, requiredTDTLockedAmount)

            let lockerSigner1 = locker.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                requiredTDTLockedAmount,
                0
            )

            await locker.addLocker(signer1Address)


            await locker.addMinter(signer2Address)
            await locker.addBurner(signer2Address)

            let lockerSigner2 = locker.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, signer2Address, 1000)

            let theLockerMapping = await locker.lockersMapping(signer1Address)

            expect(
                theLockerMapping[4]
            ).to.equal(1000)


            let teleBTCSigner2 = teleBTC.connect(signer2)

            await teleBTCSigner2.mintTestToken()

            await teleBTCSigner2.transfer(locker.address, 900)

            await lockerSigner2.burn(TELEPORTER1_PublicKeyHash, 900)

            theLockerMapping = await locker.lockersMapping(signer1Address)

            expect(
                theLockerMapping[4]
            ).to.equal(100)
        })

    });

});
