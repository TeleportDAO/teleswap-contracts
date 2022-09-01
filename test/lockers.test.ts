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
    const PRICE_WITH_DISCOUNT_RATIO = 9500; // Means %95

    // Bitcoin public key (32 bytes)
    let TELEPORTER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
    let TELEPORTER1_PublicKeyHash = '0x4062c8aeed4f81c2d73ff854a2957021191e20b6';

    let LOCKER_RESCUE_SCRIPT_P2PKH = "0x12ab8dc588ca9d5787dde7eb29569da63c3a238c";
    let LOCKER_RESCUE_SCRIPT_P2PKH_TYPE = 1; // P2PKH

    // let TELEPORTER2 = '0x03dbc6764b8884a92e871274b87583e6d5c2a58819473e17e107ef3f6aa5a61626';
    // let TELEPORTER2_PublicKeyHash = '0x41fb108446d66d1c049e30cc7c3044e7374e9856';
    let REQUIRED_LOCKED_AMOUNT =  1000; // amount of required TDT

    // Accounts
    let proxyAdmin: Signer;
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let ccBurnSimulator: Signer;
    let proxyAdminAddress: Address;
    let deployerAddress: Address;
    let signer1Address: Address;
    let signer2Address: Address;
    let ccBurnSimulatorAddress: Address;

    // Contracts
    let lockers: Contract;
    let lockers2: Contract;
    let lockersAsAdmin: Contract;
    let teleportDAOToken: ERC20;
    let teleBTC: TeleBTC;

    // Mock contracts
    let mockExchangeConnector: MockContract;
    let mockPriceOracle: MockContract;
    let mockCCBurnRouter: MockContract;

    before(async () => {
        // Sets accounts
        [proxyAdmin, deployer, signer1, signer2,ccBurnSimulator] = await ethers.getSigners();
        proxyAdminAddress = await proxyAdmin.getAddress()
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

        const ccBurnRouterContract = await deployments.getArtifact(
            "ICCBurnRouter"
        );
        mockCCBurnRouter = await deployMockContract(
            deployer,
            ccBurnRouterContract.abi
        );

        // Deploys lockers contract
        lockers = await deployLockers();
        lockers2 = await deployLockers();

        // Initializes lockers proxy
        await lockers.initialize(
            teleportDAOToken.address,
            mockExchangeConnector.address,
            mockPriceOracle.address,
            minRequiredTDTLockedAmount,
            minRequiredNativeTokenLockedAmount,
            collateralRatio,
            liquidationRatio,
            LOCKER_PERCENTAGE_FEE,
            PRICE_WITH_DISCOUNT_RATIO
        )

        // Sets ccBurnRouter address
        await lockers.setCCBurnRouter(ccBurnSimulatorAddress);

        teleBTC = await deployTeleBTC()

        await teleBTC.addMinter(lockers.address)
        await teleBTC.addBurner(lockers.address)

        // lockersAsAdmin = await lockers.connect(proxyAdmin)

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
            lockersLogic.address,
            proxyAdminAddress,
            "0x"
        )

        const lockers = await lockersLogic.attach(
            lockersProxy.address
        );

        return lockers;
    };

    describe("#initialize", async () => {

        it("initialize can be called only once", async function () {
            await expect(
                lockers.initialize(
                    teleportDAOToken.address,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    collateralRatio,
                    liquidationRatio,
                    LOCKER_PERCENTAGE_FEE,
                    PRICE_WITH_DISCOUNT_RATIO
                )
            ).to.be.revertedWith("Initializable: contract is already initialized")
        })

        it("initialize cant be called with zero address", async function () {
            await expect(
                lockers2.initialize(
                    ZERO_ADDRESS,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    collateralRatio,
                    liquidationRatio,
                    LOCKER_PERCENTAGE_FEE,
                    PRICE_WITH_DISCOUNT_RATIO
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("initialize cant be called with zero amount", async function () {
            await expect(
                lockers2.initialize(
                    teleportDAOToken.address,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    0,
                    0,
                    collateralRatio,
                    liquidationRatio,
                    LOCKER_PERCENTAGE_FEE,
                    PRICE_WITH_DISCOUNT_RATIO
                )
            ).to.be.revertedWith("Lockers: amount is zero")
        })


        it("initialize cant be called LR greater than CR", async function () {
            await expect(
                lockers2.initialize(
                    teleportDAOToken.address,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    liquidationRatio,
                    collateralRatio,
                    LOCKER_PERCENTAGE_FEE,
                    PRICE_WITH_DISCOUNT_RATIO
                )
            ).to.be.revertedWith("Lockers: problem in CR and LR")
        })

        it("initialize cant be called with Price discount greater than 100%", async function () {
            await expect(
                lockers2.initialize(
                    teleportDAOToken.address,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    collateralRatio,
                    liquidationRatio,
                    LOCKER_PERCENTAGE_FEE,
                    PRICE_WITH_DISCOUNT_RATIO + 10000
                )
            ).to.be.revertedWith("Lockers: price discount ratio must be less than 100%")
        })

    })

    describe("#addMinter", async () => {

        it("can't add zero address as minter", async function () {
            await expect(
                lockers.addMinter(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("only owner can add a minter", async function () {

            let lockersSigner1 = await lockers.connect(signer1)

            await expect(
                lockersSigner1.addMinter(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("owner successfully adds a minter", async function () {

            await lockers.addMinter(
                ONE_ADDRESS
            )
        })

        it("can't add an account that already is minter", async function () {

            await lockers.addMinter(
                ONE_ADDRESS
            )

            await expect(
                lockers.addMinter(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Lockers: account already has role")
        })

    })

    describe("#removeMinter", async () => {

        it("can't remove zero address as minter", async function () {
            await expect(
                lockers.removeMinter(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("only owner can add a minter", async function () {

            let lockersSigner1 = await lockers.connect(signer1)

            await expect(
                lockersSigner1.removeMinter(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("owner can't remove an account from minter that it's not minter ATM", async function () {

            await expect(
                lockers.removeMinter(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Lockers: account does not have role")
        })

        it("owner successfully removes an account from minters", async function () {

            await lockers.addMinter(
                ONE_ADDRESS
            )

            await lockers.removeMinter(
                ONE_ADDRESS
            )
        })

    })

    describe("#addBurner", async () => {

        it("can't add zero address as burner", async function () {
            await expect(
                lockers.addBurner(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("only owner can add a burner", async function () {

            let lockersSigner1 = await lockers.connect(signer1)

            await expect(
                lockersSigner1.addBurner(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("owner successfully adds a burner", async function () {

            await lockers.addBurner(
                ONE_ADDRESS
            )
        })

        it("can't add an account that already is burner", async function () {

            await lockers.addBurner(
                ONE_ADDRESS
            )

            await expect(
                lockers.addBurner(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Lockers: account already has role")
        })

    })

    describe("#removeBurner", async () => {

        it("can't remove zero address as burner", async function () {
            await expect(
                lockers.removeBurner(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("only owner can add a burner", async function () {

            let lockersSigner1 = await lockers.connect(signer1)

            await expect(
                lockersSigner1.removeBurner(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("owner can't remove an account from burners that it's not burner ATM", async function () {

            await expect(
                lockers.removeBurner(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Lockers: account does not have role")
        })

        it("owner successfully removes an account from burner", async function () {

            await lockers.addBurner(
                ONE_ADDRESS
            )

            await lockers.removeBurner(
                ONE_ADDRESS
            )
        })

    })

    describe("#pauseLocker", async () => {

        it("only admin can pause locker", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.pauseLocker()
            ).to.be.revertedWith("Ownable: caller is not the owner")

        });

        it("contract paused successsfully", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await lockers.pauseLocker()

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Pausable: paused")

            await expect(
                lockerSigner1.slashLockerForCCBurn(
                    signer1Address,
                    0,
                    deployerAddress,
                    10000,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Pausable: paused")

            await expect(
                lockerSigner1.liquidateLocker(
                    signer1Address,
                    10000
                )
            ).to.be.revertedWith("Pausable: paused")

            await expect(
                lockerSigner1.mint(
                    signer1Address,
                    signer2Address,
                    10000
                )
            ).to.be.revertedWith("Pausable: paused")

            await expect(
                lockerSigner1.burn(
                    signer1Address,
                    10000
                )
            ).to.be.revertedWith("Pausable: paused")

        });

        it("can't pause when already paused", async function () {

            await lockers.pauseLocker()

            await expect(
                lockers.pauseLocker()
            ).to.be.revertedWith("Pausable: paused")

        });

    });

    describe("#unPauseLocker", async () => {

        it("only admin can un-pause locker", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.unPauseLocker()
            ).to.be.revertedWith("Ownable: caller is not the owner")

        });

        it("can't un-pause when already un-paused", async function () {

            await expect(
                lockers.unPauseLocker()
            ).to.be.revertedWith("Pausable: not paused")

        });

        it("contract un-paused successsfully", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await lockers.pauseLocker()

            await expect(
                lockerSigner1.liquidateLocker(
                    signer1Address,
                    10000
                )
            ).to.be.revertedWith("Pausable: paused")

            await lockers.unPauseLocker()

            await expect(
                lockerSigner1.liquidateLocker(
                    signer1Address,
                    10000
                )
            ).to.be.revertedWith("Lockers: target address is not locker")

        });

    });


    describe("#setMinRequiredTDTLockedAmount",async () => {
        it("non owners can't call setMinRequiredTDTLockedAmount", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setMinRequiredTDTLockedAmount(
                    REQUIRED_LOCKED_AMOUNT
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setMinRequiredTDTLockedAmount", async function () {

            await lockers.setMinRequiredTDTLockedAmount(
                REQUIRED_LOCKED_AMOUNT + 55
            )

            expect(
                await lockers.minRequiredTDTLockedAmount()
            ).to.equal(REQUIRED_LOCKED_AMOUNT + 55)
        })
    })

    describe("#setMinRequiredTNTLockedAmount",async () => {
        it("non owners can't call setMinRequiredTNTLockedAmount", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setMinRequiredTNTLockedAmount(
                    REQUIRED_LOCKED_AMOUNT
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setMinRequiredTNTLockedAmount", async function () {

            await lockers.setMinRequiredTNTLockedAmount(
                REQUIRED_LOCKED_AMOUNT + 55
            )

            expect(
                await lockers.minRequiredTNTLockedAmount()
            ).to.equal(REQUIRED_LOCKED_AMOUNT + 55)
        })
    })

    describe("#setPriceOracle",async () => {

        it("price oracle can't be zero address", async function () {

            await expect(
                lockers.setPriceOracle(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("non owners can't call setPriceOracle", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setPriceOracle(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setPriceOracle", async function () {

            await lockers.setPriceOracle(
                ONE_ADDRESS
            )

            expect(
                await lockers.priceOracle()
            ).to.equal(ONE_ADDRESS)
        })
    })


    describe("#setCCBurnRouter",async () => {

        it("cc burn router can't be zero address", async function () {

            await expect(
                lockers.setCCBurnRouter(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("non owners can't call setCCBurnRouter", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setCCBurnRouter(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setCCBurnRouter", async function () {

            await lockers.setCCBurnRouter(
                ONE_ADDRESS
            )

            expect(
                await lockers.ccBurnRouter()
            ).to.equal(ONE_ADDRESS)
        })
    })

    describe("#setExchangeConnector",async () => {

        it("exchange connector can't be zero address", async function () {

            await expect(
                lockers.setExchangeConnector(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("non owners can't call setExchangeConnector", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setExchangeConnector(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setExchangeConnector", async function () {

            await lockers.setExchangeConnector(
                ONE_ADDRESS
            )

            expect(
                await lockers.exchangeConnector()
            ).to.equal(ONE_ADDRESS)
        })
    })

    describe("#setTeleBTC",async () => {

        it("tele BTC can't be zero address", async function () {

            await expect(
                lockers.setTeleBTC(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("non owners can't call setTeleBTC", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setTeleBTC(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setTeleBTC", async function () {

            await lockers.setTeleBTC(
                ONE_ADDRESS
            )

            expect(
                await lockers.teleBTC()
            ).to.equal(ONE_ADDRESS)
        })
    })

    describe("#setCollateralRatio",async () => {

        it("non owners can't call setCollateralRatio", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setCollateralRatio(
                    1234
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setCollateralRatio", async function () {

            await lockers.setCollateralRatio(
                21000
            )

            expect(
                await lockers.collateralRatio()
            ).to.equal(21000)
        })
    })


    describe("#requestToBecomeLocker", async () => {

        it("setting low TeleportDao token", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount.sub(1),
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("Lockers: low locking TDT amount")
        })

        it("not approving TeleportDao token", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("ERC20: transfer amount exceeds allowance")
        })

        it("low message value", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount.sub(10)}
                )
            ).to.be.revertedWith("Lockers: low locking TNT amount")
        })

        it("successful request to become locker", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.emit(lockers, "RequestAddLocker")

            expect(
                await lockers.totalNumberOfCandidates()
            ).to.equal(1)

        })

        it("a locker can't requestToBecomeLocker twice", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("Lockers: user is already a candidate")

        })


        it("a redeem script hash can't be used twice", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            let lockerSigner2 = lockers.connect(signer2)

            await expect(
                lockerSigner2.requestToBecomeLocker(
                    // TELEPORTER1,
                    TELEPORTER1_PublicKeyHash,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("Lockers: locking script is used before")

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
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
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
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
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
            ).to.equal(TELEPORTER1_PublicKeyHash)
        })

    });

    describe("#requestToRemoveLocker", async () => {

        it("trying to request to remove a non existing locker", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToRemoveLocker()
            ).to.be.revertedWith("Lockers: msg sender is not locker")
        })

        it("successfully request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            expect(
                await lockerSigner1.requestToRemoveLocker()
            ).to.emit(lockers, "RequestRemoveLocker")
        })

    });

    describe("#ownerRemoveLocker", async () => {

        it("only admin can call remove locker function", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.ownerRemoveLocker(signer1Address)
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("a non-existing locker can't be removed", async function () {
            await expect(
                lockers.ownerRemoveLocker(signer1Address)
            ).to.be.revertedWith("Lockers: no locker with this address")
        })

        it("can't remove a locker if it doesn't request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await expect(
                lockers.ownerRemoveLocker(signer1Address)
            ).to.be.revertedWith("Lockers: locker didn't request to be removed")
        })


        it("the locker can't be removed because netMinted is not zero", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000);
            await lockers.addMinter(signer2Address);
            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, ONE_ADDRESS, 1000);

            await lockerSigner1.requestToRemoveLocker()

            await expect(
                lockers.ownerRemoveLocker(signer1Address)
            ).to.be.revertedWith("Lockers: net minted is not zero")
        })

        it("the locker is removed successfully", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await lockerSigner1.requestToRemoveLocker()

            expect(
                await lockers.ownerRemoveLocker(signer1Address)
            ).to.emit(lockers, "LockerRemoved")

            expect(
                await lockers.totalNumberOfLockers()
            ).to.equal(0)
        })

    });

    describe("#selfRemoveLocker", async () => {

        it("a locker can't remove itself when the contract is paused", async function () {
            await lockers.pauseLocker()

            let lockerSigner1 = await lockers.connect(signer1)

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Pausable: paused")
        })

        it("a non-existing locker can't be removed", async function () {

            let lockerSigner1 = await lockers.connect(signer1)

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Lockers: no locker with this address")
        })

        it("can't remove a locker if it doesn't request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Lockers: locker didn't request to be removed")
        })

        it("the locker can't be removed because netMinted is not zero", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000);
            await lockers.addMinter(signer2Address);
            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, ONE_ADDRESS, 1000);

            await lockerSigner1.requestToRemoveLocker()

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Lockers: net minted is not zero")
        })

        it("the locker is removed successfully", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await lockerSigner1.requestToRemoveLocker()

            expect(
                await lockerSigner1.selfRemoveLocker()
            ).to.emit(lockers, "LockerRemoved")

            expect(
                await lockers.totalNumberOfLockers()
            ).to.equal(0)
        })

    });


    describe("#slashLocker", async () => {

        it("only cc burn can call slash locker function", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.slashLockerForCCBurn(
                    signer1Address,
                    0,
                    deployerAddress,
                    btcAmountToSlash,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Lockers: caller can't slash")
        })

        it("slash locker reverts when the target address is not locker", async function () {
            let lockerCCBurnSimulator = lockers.connect(ccBurnSimulator)

            await expect(
                lockerCCBurnSimulator.slashLockerForCCBurn(
                    signer1Address,
                    0,
                    deployerAddress,
                    btcAmountToSlash,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Lockers: target address is not locker")
        })

        it("can't slash above collateral", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(
                BigNumber.from(10).pow(18).mul(6)
            )
            // await mockExchangeConnector.mock.getInputAmount.returns(true, minRequiredTDTLockedAmount.div(10))
            // await mockExchangeConnector.mock.swap.returns(true, [2500, 5000])

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await expect(
                lockerCCBurnSigner.slashLockerForCCBurn(
                    signer1Address,
                    0,
                    deployerAddress,
                    10000,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Lockers: insufficient native token collateral")

        })


        it("cc burn can slash a locker", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)
            // await mockExchangeConnector.mock.getInputAmount.returns(true, minRequiredTDTLockedAmount.div(10))
            // await mockExchangeConnector.mock.swap.returns(true, [2500, 5000])

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await lockerCCBurnSigner.slashLockerForCCBurn(
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
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
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
                theLockerMapping[5]
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
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
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
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await lockers.addMinter(signer2Address)
            await lockers.addBurner(signer2Address)

            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, signer2Address, 1000)

            let theLockerMapping = await lockers.lockersMapping(signer1Address);

            expect(
                theLockerMapping[5]
            ).to.equal(1000);

            let teleBTCSigner2 = teleBTC.connect(signer2)

            await teleBTCSigner2.mintTestToken()

            amount = 900;
            let lockerFee = Math.floor(amount*LOCKER_PERCENTAGE_FEE/10000);

            await teleBTCSigner2.approve(lockers.address, amount);

            await lockerSigner2.burn(TELEPORTER1_PublicKeyHash, amount);

            theLockerMapping = await lockers.lockersMapping(signer1Address);

            expect(
                theLockerMapping[5]
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

        it("liquidate locker reverts when the target address is not locker", async function () {
            let lockerCCBurnSimulator = lockers.connect(ccBurnSimulator)

            await expect(
                lockerCCBurnSimulator.liquidateLocker(
                    signer1Address,
                    1000
                )
            ).to.be.revertedWith("Lockers: target address is not locker")
        })

        it("can't liquidate because it's above liquidation ratio", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, ONE_ADDRESS, 5000000);

            await expect(
                lockerSigner2.liquidateLocker(signer1Address, 5000)
            ).to.be.revertedWith("Lockers: locker's collateral is healthy")

        });

        it("can't liquidate because it's above the liquidated amount", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(50000000);
            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, ONE_ADDRESS, 25000000);

            await mockPriceOracle.mock.equivalentOutputAmount.returns(7000000);

            await expect(
                lockerSigner2.liquidateLocker(
                    signer1Address,
                    BigNumber.from(10).pow(18).mul(3)
                )
            ).to.be.revertedWith("Lockers: more than maximum buyable")

        });

        it("successfully liquidate the locker", async function () {

            await lockers.setCCBurnRouter(mockCCBurnRouter.address);
            await mockCCBurnRouter.mock.ccBurn.returns(8000);

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(50000000);
            await lockerSigner2.mint(TELEPORTER1_PublicKeyHash, signer2Address, 25000000);


            let teleBTCSigner2 = await teleBTC.connect(signer2);

            await teleBTCSigner2.approve(lockers.address, 13300000)

            let signer2NativeTokenBalanceBefore = await teleBTC.provider.getBalance(signer2Address)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(7000000);

            await lockerSigner2.liquidateLocker(
                signer1Address,
                BigNumber.from(10).pow(18).mul(2)
            )

            let signer2NativeTokenBalanceAfter = await teleBTC.provider.getBalance(signer2Address)

            expect(
                signer2NativeTokenBalanceAfter.sub(signer2NativeTokenBalanceBefore)
            ).to.be.closeTo(BigNumber.from(10).pow(18).mul(2), BigNumber.from(10).pow(15).mul(1))


        });

    });

    describe("#addCollateral", async () => {

        it("can't add collateral for a non locker account", async function () {

            await expect(
                lockers.addCollateral(
                    signer1Address,
                    1000
                )
            ).to.be.revertedWith("Lockers: account is not a locker")
        })


        it("reverts because of insufficient msg value", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            let lockerSigner2 = lockers.connect(signer2)

            await expect(
                lockerSigner2.addCollateral(
                    signer1Address,
                    10001,
                    {value: 10000}
                )
            ).to.be.revertedWith("Lockers: incompatible msg value")

        })

        it("adding collateral to the locker", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            let theLockerBefore = await lockers.lockersMapping(signer1Address)

            await lockerSigner1.addCollateral(
                signer1Address,
                10000,
                {value: 10000}
            )

            let theLockerAfter = await lockers.lockersMapping(signer1Address)

            expect(
                theLockerAfter[4].sub(theLockerBefore[4])
            ).to.equal(10000)

        })

    });

    describe("#removeCollateral", async () => {

        it("can't remove collateral for a non locker account", async function () {

            let lockerSigner1 = await lockers.connect(signer1)

            await expect(
                lockerSigner1.removeCollateral(
                    1000
                )
            ).to.be.revertedWith("Lockers: account is not a locker")
        })


        it("reverts because it's more than capacity", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);


            await expect(
                lockerSigner1.removeCollateral(
                    (minRequiredNativeTokenLockedAmount.div(2)).add(1)
                )
            ).to.be.revertedWith("Lockers: more than max removable collateral")

        })

        it("remove collateral successfully", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // TELEPORTER1,
                TELEPORTER1_PublicKeyHash,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            let theLockerBalanceBefore = await teleBTC.provider.getBalance(signer1Address)

            await lockerSigner1.removeCollateral(
                minRequiredNativeTokenLockedAmount.div(2)
            )

            let theLockerBalanceAfter = await teleBTC.provider.getBalance(signer1Address)

            expect(
                theLockerBalanceAfter.sub(theLockerBalanceBefore)
            ).to.be.closeTo(minRequiredNativeTokenLockedAmount.div(2), BigNumber.from(10).pow(15).mul(1))

        })

    });
})
