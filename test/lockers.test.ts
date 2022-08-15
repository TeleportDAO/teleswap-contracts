require('dotenv').config({path:"../../.env"});

import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";
import { Address } from "hardhat-deploy/types";

import { LockersProxy } from "../src/types/LockersProxy";
import { LockersProxy__factory } from "../src/types/factories/LockersProxy__factory";

import { LockersLogic } from "../src/types/LockersLogic";
import { LockersLogic__factory } from "../src/types/factories/LockersLogic__factory";

import { TeleBTC } from "../src/types/TeleBTC";
import { TeleBTC__factory } from "../src/types/factories/TeleBTC__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";


import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";

describe("Lockers", async () => {

    let snapshotId: any;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000);
    let minRequiredTDTLockedAmount = BigNumber.from(10).pow(18).mul(500);
    let minRequiredNativeTokenLockedAmount = BigNumber.from(10).pow(18).mul(5);
    let btcAmountToSlash = BigNumber.from(10).pow(8).mul(1)
    let collateralRatio = 20000;
    let liquidationRatio = 15000;
    const LOCKER_PERCENTAGE_FEE = 20; // Means %0.2

    // Bitcoin public key (32 bytes)
    let TELEPORTER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
    let TELEPORTER1_PublicKeyHash = '0x4062c8aeed4f81c2d73ff854a2957021191e20b6';
    // let TELEPORTER2 = '0x03dbc6764b8884a92e871274b87583e6d5c2a58819473e17e107ef3f6aa5a61626';
    // let TELEPORTER2_PublicKeyHash = '0x41fb108446d66d1c049e30cc7c3044e7374e9856';
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
    let lockers: Contract;
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

        // Deploys lockers contract
        lockers = await deployLockers();

        // Sets ccBurnRouter address
        await lockers.setCCBurnRouter(ccBurnSimulatorAddress);

        teleBTC = await deployTeleBTC()

        await teleBTC.addMinter(lockers.address)
        await teleBTC.addBurner(lockers.address)

        await lockers.setTeleBTC(teleBTC.address)

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
            // ONE_ADDRESS,
            // ONE_ADDRESS,
            // ONE_ADDRESS
        );

        return wrappedToken;
    };

    const deployLockers = async (
        _signer?: Signer
    ): Promise<Contract> => {

        // Deploys lockers logic
        const lockersLogicFactory = new LockersLogic__factory(
            _signer || deployer
        );
        const lockersLogic = await lockersLogicFactory.deploy();

        // Deploys lockers proxy
        const lockersProxyFactory = new LockersProxy__factory(
            _signer || deployer
        );
        const lockersProxy = await lockersProxyFactory.deploy(
            lockersLogic.address
        )

        // Initializes lockers proxy
        await lockersProxy.initialize(
            teleportDAOToken.address,
            mockExchangeConnector.address,
            mockPriceOracle.address,
            minRequiredTDTLockedAmount,
            minRequiredNativeTokenLockedAmount,
            collateralRatio,
            liquidationRatio,
            LOCKER_PERCENTAGE_FEE
        )

        const lockers = await lockersLogic.attach(
            lockersProxy.address
        );

        return lockers;
    };

    describe("#requestToBecomeLocker", async () => {

        it("setting low TeleportDao token", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount.sub(1),
                    minRequiredNativeTokenLockedAmount,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("Lockers: low locking TDT amount")
        })

        it("not approving TeleportDao token", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
        })

        it("successful request to become locker", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.emit(lockers, "RequestAddLocker")

            expect(
                await lockers.totalNumberOfCandidates()
            ).to.equal(1)

        })

    });

    describe("#revokeRequest", async () => {

        it("trying to revoke a non existing request", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.revokeRequest()
            ).to.be.revertedWith("Lockers: request doesn't exist or already accepted")
        })

        it("successful revoke", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockerSigner1.revokeRequest()

            expect(
                await lockers.totalNumberOfCandidates()
            ).to.equal(0)

        })

    });

    describe("#addLocker", async () => {

        it("trying to add a non existing request as a locker", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.addLocker(signer1Address)
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("adding a locker", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            )

            expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            expect(
                await lockers.totalNumberOfCandidates()
            ).to.equal(0)

            expect(
                await lockers.totalNumberOfLockers()
            ).to.equal(1)

            let theLockerMapping = await lockers.lockersMapping(signer1Address)
            expect(
                theLockerMapping[0]
            ).to.equal(TELEPORTER1)
        })

    });

    describe("#requestToRemoveLocker", async () => {

        it("trying to request to remove a non existing locker", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToRemoveLocker()
            ).to.be.revertedWith("Lockers: Msg sender is not locker")
        })

        it("successfully request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            expect(
                await lockerSigner1.requestToRemoveLocker()
            ).to.emit(lockers, "RequestRemoveLocker")
        })

    });

    describe("#removeLocker", async () => {

        it("only admin can call remove locker function", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.removeLocker(signer1Address)
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("can't remove a locker if it doesn't request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await expect(
                lockers.removeLocker(signer1Address)
            ).to.be.revertedWith("Lockers: locker didn't request to be removed")
        })

        it("can't remove a locker if it doesn't request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await lockerSigner1.requestToRemoveLocker()

            expect(
                await lockers.removeLocker(signer1Address)
            ).to.emit(lockers, "LockerRemoved")

            expect(
                await lockers.totalNumberOfLockers()
            ).to.equal(0)
        })

    });

    describe("#selfRemoveLocker", async () => {

        it("only admin can call remove locker function", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Lockers: no locker with this address")
        })

    });


    describe("#slashLocker", async () => {

        it("only admin can call slash locker function", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.slashLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    btcAmountToSlash,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Lockers: Caller can't slash")
        })

        it("slash locker reverts when the target address is not locker", async function () {
            let lockerCCBurnSimulator = lockers.connect(ccBurnSimulator)

            await expect(
                lockerCCBurnSimulator.slashLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    btcAmountToSlash,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Lockers: target address is not locker")
        })

        it("only admin can slash a locker", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)
            await mockExchangeConnector.mock.getInputAmount.returns(true, minRequiredTDTLockedAmount.div(10))
            await mockExchangeConnector.mock.swap.returns(true, [2500, 5000])

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            )

            expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await lockerCCBurnSigner.slashLocker(
                signer1Address,
                0,
                deployerAddress,
                10000,
                ccBurnSimulatorAddress
            );

        })

    });

    describe("#mint", async () => {

        let amount;

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Mints tele BTC", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            amount = 1000;
            let lockerFee = Math.floor(amount*LOCKER_PERCENTAGE_FEE/10000);

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, ONE_ADDRESS, amount);

            let theLockerMapping = await lockers.lockersMapping(signer1Address);

            expect(
                theLockerMapping[4]
            ).to.equal(1000);

            // Checks that enough teleBTC has been minted for user
            expect(
                await teleBTC.balanceOf(ONE_ADDRESS)
            ).to.equal(amount - lockerFee);

            // Checks that enough teleBTC has been minted for locker
            expect(
                await teleBTC.balanceOf(signer1Address)
            ).to.equal(lockerFee);
        })


        it("can't mint tele BTC above capacity", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await expect(
                lockerSigner2.mint(TELEPORTER1_PublicKeyHash, ONE_ADDRESS, 5001)
            ).to.be.revertedWith("Lockers: this locker hasn't sufficient capacity")

        })

    });

    describe("#burn", async () => {

        let amount;

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("Burns tele BTC", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await lockers.addMinter(signer2Address)
            await lockers.addBurner(signer2Address)

            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, signer2Address, 1000)

            let theLockerMapping = await lockers.lockersMapping(signer1Address);

            expect(
                theLockerMapping[4]
            ).to.equal(1000);

            let teleBTCSigner2 = teleBTC.connect(signer2)

            await teleBTCSigner2.mintTestToken()

            amount = 900;
            let lockerFee = Math.floor(amount*LOCKER_PERCENTAGE_FEE/10000);

            await teleBTCSigner2.approve(lockers.address, amount);

            await lockerSigner2.burn(TELEPORTER1_PublicKeyHash, amount);

            theLockerMapping = await lockers.lockersMapping(signer1Address);

            expect(
                theLockerMapping[4]
            ).to.equal(1000 - amount + lockerFee);


        })

    });

    describe("#liquidateLocker", async () => {

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("can't liquidate because it's above liquidation ratio", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, ONE_ADDRESS, 5000);

            await expect(
                lockerSigner2.liquidateLocker(signer1Address, 5000)
            ).to.be.revertedWith("Lockers: this locker is above luquidation ratio")

        });

        it("can't liquidate because it's above the liquidated amount", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, ONE_ADDRESS, 5000);

            await mockPriceOracle.mock.equivalentOutputAmount.returns(6000);

            await expect(
                lockerSigner2.liquidateLocker(signer1Address, 5000)
            ).to.be.revertedWith("Lockers: above the locker's luquidation penalty")

        });

        it("successfully liquidate the locker", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, signer2Address, 5000);

            await mockPriceOracle.mock.equivalentOutputAmount.returns(6000);

            let teleBTCSigner2 = await teleBTC.connect(signer2);

            await teleBTCSigner2.approve(lockers.address, 3500)

            // let nativeTokenBalanceOfSigner2BeforeLiquidatingLocker =

            await lockerSigner2.liquidateLocker(signer1Address, 3500)

        });

    });

})
