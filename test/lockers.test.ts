require('dotenv').config({path:"../../.env"});

import { expect } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Contract } from "@ethersproject/contracts";
import { Address } from "hardhat-deploy/types";

import { LockersProxy__factory } from "../src/types/factories/LockersProxy__factory";

import { LockersLogic__factory } from "../src/types/factories/LockersLogic__factory";
import { LockersLogicLibraryAddresses } from "../src/types/factories/LockersLogic__factory";

import { LockersLib } from "../src/types/LockersLib";
import { LockersLib__factory } from "../src/types/factories/LockersLib__factory";

import { TeleBTC } from "../src/types/TeleBTC";
import { TeleBTC__factory } from "../src/types/factories/TeleBTC__factory";
import { ERC20 } from "../src/types/ERC20";
import { Erc20__factory } from "../src/types/factories/Erc20__factory";


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
    const INACTIVATION_DELAY = 10000;

    // Bitcoin public key (32 bytes)
    let LOCKER1 = '0x03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd';
    let LOCKER1_PUBKEY__HASH = '0x4062c8aeed4f81c2d73ff854a2957021191e20b6';

    let LOCKER_RESCUE_SCRIPT_P2PKH = "0x12ab8dc588ca9d5787dde7eb29569da63c3a238c";
    let LOCKER_RESCUE_SCRIPT_P2PKH_TYPE = 1; // P2PKH

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
    let lockersLib: LockersLib;
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
            "BurnRouterLogic"
        );
        mockCCBurnRouter = await deployMockContract(
            deployer,
            ccBurnRouterContract.abi
        );

        // Deploys lockers contract
        lockers = await deployLockers();
        lockers2 = await deployLockers();

        teleBTC = await deployTeleBTC()

        // Initializes lockers proxy
        await lockers.initialize(
            teleBTC.address,
            teleportDAOToken.address,
            mockExchangeConnector.address,
            mockPriceOracle.address,
            ccBurnSimulatorAddress,
            minRequiredTDTLockedAmount,
            minRequiredNativeTokenLockedAmount,
            collateralRatio,
            liquidationRatio,
            LOCKER_PERCENTAGE_FEE,
            PRICE_WITH_DISCOUNT_RATIO
        )

        // Sets ccBurnRouter address
        // await lockers.setCCBurnRouter(ccBurnSimulatorAddress)

        await teleBTC.addMinter(deployerAddress)

        await teleBTC.addMinter(lockers.address)
        await teleBTC.addBurner(lockers.address)

        // lockersAsAdmin = await lockers.connect(proxyAdmin)

        // await lockers.setTeleBTC(teleBTC.address)

    });

    beforeEach(async () => {
        // Takes snapshot
        snapshotId = await takeSnapshot(deployer.provider);
    });

    afterEach(async () => {
        // Reverts the state
        await revertProvider(deployer.provider, snapshotId);
    });

    async function getTimestamp(): Promise<number> {
        let lastBlockNumber = await ethers.provider.getBlockNumber();
        let lastBlock = await ethers.provider.getBlock(lastBlockNumber);
        return lastBlock.timestamp;
    }

    const deployTelePortDaoToken = async (
        _signer?: Signer
    ): Promise<ERC20> => {
        const erc20Factory = new Erc20__factory(
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

    const deployLockersLib = async (
        _signer?: Signer
    ): Promise<LockersLib> => {
        const LockersLibFactory = new LockersLib__factory(
            _signer || deployer
        );

        const lockersLib = await LockersLibFactory.deploy(
        );

        return lockersLib;
    };


    const deployLockers = async (
        _signer?: Signer
    ): Promise<Contract> => {

        lockersLib = await deployLockersLib()

        let linkLibraryAddresses: LockersLogicLibraryAddresses;

        linkLibraryAddresses = {
            "contracts/libraries/LockersLib.sol:LockersLib": lockersLib.address,
        };

        // Deploys lockers logic
        const lockersLogicFactory = new LockersLogic__factory(
            linkLibraryAddresses,
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
                    teleBTC.address,
                    teleportDAOToken.address,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    ONE_ADDRESS,
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
                    teleBTC.address,
                    ZERO_ADDRESS,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    ONE_ADDRESS,
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
                    teleBTC.address,
                    teleportDAOToken.address,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    ONE_ADDRESS,
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
                    teleBTC.address,
                    teleportDAOToken.address,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    ONE_ADDRESS,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    liquidationRatio,
                    collateralRatio,
                    LOCKER_PERCENTAGE_FEE,
                    PRICE_WITH_DISCOUNT_RATIO
                )
            ).to.be.revertedWith("Lockers: must CR > LR")
        })

        it("initialize cant be called with Price discount greater than 100%", async function () {
            await expect(
                lockers2.initialize(
                    teleBTC.address,
                    teleportDAOToken.address,
                    mockExchangeConnector.address,
                    mockPriceOracle.address,
                    ONE_ADDRESS,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    collateralRatio,
                    liquidationRatio,
                    LOCKER_PERCENTAGE_FEE,
                    PRICE_WITH_DISCOUNT_RATIO + 10000
                )
            ).to.be.revertedWith("Lockers: less than 100%")
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

            await expect(
                await lockers.addMinter(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "MinterAdded"
            ).withArgs(ONE_ADDRESS);
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

            await expect(
                await lockers.removeMinter(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "MinterRemoved"
            ).withArgs(ONE_ADDRESS);
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

            await expect(
                await lockers.addBurner(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "BurnerAdded"
            ).withArgs(ONE_ADDRESS);
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

            await expect(
                await lockers.removeBurner(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "BurnerRemoved"
            ).withArgs(ONE_ADDRESS);
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

            // await expect(
            //     lockerSigner1.selfRemoveLocker()
            // ).to.be.revertedWith("Pausable: paused")

            await expect(
                lockerSigner1.slashIdleLocker(
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
            ).to.be.revertedWith("Lockers: input address is not a valid locker")

        });

    });

    describe("#setTeleportDAOToken",async () => {

        it("non owners can't call setTeleportDAOToken", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setTeleportDAOToken(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setTeleportDAOToken", async function () {

            await expect(
                lockers.setTeleportDAOToken(
                    ZERO_ADDRESS
                )
            ).to.be.revertedWith("Lockers: address is zero")

            await expect(
                await lockers.setTeleportDAOToken(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "NewTeleportDAOToken"
            ).withArgs(teleportDAOToken.address, ONE_ADDRESS);

            expect(
                await lockers.TeleportDAOToken()
            ).to.equal(ONE_ADDRESS)
        })
    })

    describe("#setLockerPercentageFee",async () => {

        it("non owners can't call setLockerPercentageFee", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setLockerPercentageFee(
                    2100
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setLockerPercentageFee", async function () {

            await expect(
                await lockers.setLockerPercentageFee(
                    2100
                )
            ).to.emit(
                lockers, "NewLockerPercentageFee"
            ).withArgs(LOCKER_PERCENTAGE_FEE, 2100);

            expect(
                await lockers.lockerPercentageFee()
            ).to.equal(2100)
        })
    })

    describe("#setPriceWithDiscountRatio",async () => {

        it("non owners can't call setPriceWithDiscountRatio", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setPriceWithDiscountRatio(
                    2100
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setPriceWithDiscountRatio", async function () {

            await expect(
                await lockers.setPriceWithDiscountRatio(
                    2100
                )
            ).to.emit(
                lockers, "NewPriceWithDiscountRatio"
            ).withArgs(PRICE_WITH_DISCOUNT_RATIO, 2100);

            expect(
                await lockers.priceWithDiscountRatio()
            ).to.equal(2100)
        })
    })

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

            await expect(
                await lockers.setMinRequiredTDTLockedAmount(
                    REQUIRED_LOCKED_AMOUNT + 55
                )
            ).to.emit(
                lockers, "NewMinRequiredTDTLockedAmount"
            ).withArgs(minRequiredTDTLockedAmount, REQUIRED_LOCKED_AMOUNT + 55);

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

            await expect(
                await lockers.setMinRequiredTNTLockedAmount(
                    REQUIRED_LOCKED_AMOUNT + 55
                )
            ).to.emit(
                lockers, "NewMinRequiredTNTLockedAmount"
            ).withArgs(minRequiredNativeTokenLockedAmount, REQUIRED_LOCKED_AMOUNT + 55);


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

            await expect(
                await lockers.setPriceOracle(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "NewPriceOracle"
            ).withArgs(mockPriceOracle.address, ONE_ADDRESS);


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

            await expect(
                await lockers.setCCBurnRouter(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "NewCCBurnRouter"
            ).withArgs(ccBurnSimulatorAddress, ONE_ADDRESS);

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

            await expect(
                await lockers.setExchangeConnector(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "NewExchangeConnector"
            ).withArgs(mockExchangeConnector.address, ONE_ADDRESS);

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

            await expect(
                await lockers.setTeleBTC(
                    ONE_ADDRESS
                )
            ).to.emit(
                lockers, "NewTeleBTC"
            ).withArgs(teleBTC.address, ONE_ADDRESS);

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

            await expect(
                await lockers.setCollateralRatio(
                    21000
                )
            ).to.emit(
                lockers, "NewCollateralRatio"
            ).withArgs(collateralRatio, 21000);

            expect(
                await lockers.collateralRatio()
            ).to.equal(21000)
        })
    })

    describe("#setLiquidationRatio",async () => {

        it("non owners can't call setLiquidationRatio", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.setLiquidationRatio(
                    1234
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        })

        it("only owner can call setLiquidationRatio", async function () {

            await expect(
                await lockers.setLiquidationRatio(
                    19000
                )
            ).to.emit(
                lockers, "NewLiquidationRatio"
            ).withArgs(liquidationRatio, 19000);

            expect(
                await lockers.liquidationRatio()
            ).to.equal(19000)
        })
    })

    describe("#requestToBecomeLocker", async () => {

        it("setting low TeleportDao token", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // LOCKER1,
                    LOCKER1_PUBKEY__HASH,
                    minRequiredTDTLockedAmount.sub(1),
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("Lockers: low TDT")
        })

        it("not approving TeleportDao token", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // LOCKER1,
                    LOCKER1_PUBKEY__HASH,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("ERC20: transfer amount exceeds balance")
        })

        it("low message value", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // LOCKER1,
                    LOCKER1_PUBKEY__HASH,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount.sub(10)}
                )
            ).to.be.revertedWith("Lockers: low TNT")
        })

        it("successful request to become locker", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                await lockerSigner1.requestToBecomeLocker(
                    // LOCKER1,
                    LOCKER1_PUBKEY__HASH,
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
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await expect(
                lockerSigner1.requestToBecomeLocker(
                    // LOCKER1,
                    LOCKER1_PUBKEY__HASH,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("Lockers: is candidate")

        })


        it("a redeem script hash can't be used twice", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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
                    // LOCKER1,
                    LOCKER1_PUBKEY__HASH,
                    minRequiredTDTLockedAmount,
                    minRequiredNativeTokenLockedAmount,
                    LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                    LOCKER_RESCUE_SCRIPT_P2PKH,
                    {value: minRequiredNativeTokenLockedAmount}
                )
            ).to.be.revertedWith("Lockers: used locking script")

        })

    });

    describe("#revokeRequest", async () => {

        it("trying to revoke a non existing request", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.revokeRequest()
            ).to.be.revertedWith("Lockers: no req")
        })

        it("successful revoke", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            expect(
                await lockers.totalNumberOfCandidates()
            ).to.equal(0)

            expect(
                await lockers.totalNumberOfLockers()
            ).to.equal(1)

            expect(
                await lockers.getNumberOfLockers()
            ).to.equal(1)

            let theLockerMapping = await lockers.lockersMapping(signer1Address)
            expect(
                theLockerMapping[0]
            ).to.equal(LOCKER1_PUBKEY__HASH)

            expect(
                await lockers.getLockerTargetAddress(
                    LOCKER1_PUBKEY__HASH
                )
            ).to.equal(signer1Address)

            expect(
                await lockers.isLocker(
                    LOCKER1_PUBKEY__HASH
                )
            ).to.equal(true)

            expect(
                await lockers.getLockerLockingScript(
                    signer1Address
                )
            ).to.equal(LOCKER1_PUBKEY__HASH)
        })

    });

    describe("#requestInactivation", async () => {

        it("trying to request to remove a non existing locker", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestInactivation()
            ).to.be.revertedWith("Lockers: input address is not a valid locker")
        })

        it("successfully request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await expect(
                await lockerSigner1.requestInactivation()
            ).to.emit(lockers, "RequestInactivateLocker")

            await expect(
                lockerSigner1.requestInactivation()
            ).to.be.revertedWith("Lockers: locker has already requested")
        })

    });

    describe("#requestActivation", async () => {

        it("trying to activate a non existing locker", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.requestActivation()
            ).to.be.revertedWith("Lockers: input address is not a valid locker")
        })

        it("successfully request to be activated", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await expect(
                await lockerSigner1.requestInactivation()
            ).to.emit(lockers, "RequestInactivateLocker")

            await expect(
                lockerSigner1.requestActivation()
            ).to.emit(lockers, "ActivateLocker")
        })

    });

    describe("#selfRemoveLocker", async () => {

        it("a non-existing locker can't be removed", async function () {

            let lockerSigner1 = await lockers.connect(signer1)

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Lockers: no locker")
        })

        it("can't remove a locker if it doesn't request to be removed", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Lockers: still active")
        })

        it("the locker can't be removed because netMinted is not zero", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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

            await lockerSigner2.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, 1000);

            await lockerSigner1.requestInactivation();

            // Forwards block.timestamp to inactivate locker
            let lastBlockTimestamp = await getTimestamp();
            await advanceBlockWithTime(deployer.provider, lastBlockTimestamp + INACTIVATION_DELAY);

            await expect(
                lockerSigner1.selfRemoveLocker()
            ).to.be.revertedWith("Lockers: 0 net minted")
        })

        it("the locker is removed successfully", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await lockers.addLocker(signer1Address)

            await lockerSigner1.requestInactivation()

            // Forwards block.timestamp to inactivate locker
            let lastBlockTimestamp = await getTimestamp();
            await advanceBlockWithTime(deployer.provider, lastBlockTimestamp + INACTIVATION_DELAY);

            await expect(
                await lockerSigner1.selfRemoveLocker()
            ).to.emit(lockers, "LockerRemoved")

            expect(
                await lockers.totalNumberOfLockers()
            ).to.equal(0)
        })

    });


    describe("#slashIdleLocker", async () => {

        it("only cc burn can call slash locker function", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.slashIdleLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    btcAmountToSlash,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Lockers: message sender is not ccBurn")
        })

        it("slash locker reverts when the target address is not locker", async function () {
            let lockerCCBurnSimulator = lockers.connect(ccBurnSimulator)

            await expect(
                lockerCCBurnSimulator.slashIdleLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    btcAmountToSlash,
                    ccBurnSimulatorAddress
                )
            ).to.be.revertedWith("Lockers: input address is not a valid locker")
        })

        it("can't slash more than collateral", async function () {

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
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await expect(
                await lockerCCBurnSigner.slashIdleLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    10000,
                    ccBurnSimulatorAddress
                )
            ).to.emit(lockerCCBurnSigner, "LockerSlashed")

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
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )

            await expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await expect(
                await lockerCCBurnSigner.slashIdleLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    10000,
                    ccBurnSimulatorAddress
                )
            ).to.emit(lockers, "LockerSlashed")

        })

    });

    describe("#slashTheifLocker", async () => {

        it("only cc burn can call slash locker function", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.slashThiefLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    btcAmountToSlash
                )
            ).to.be.revertedWith("Lockers: message sender is not ccBurn")
        })

        it("slash locker reverts when the target address is not locker", async function () {
            let lockerCCBurnSimulator = lockers.connect(ccBurnSimulator)

            await expect(
                lockerCCBurnSimulator.slashThiefLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    btcAmountToSlash
                )
            ).to.be.revertedWith("Lockers: input address is not a valid locker")
        })

        it("cc burn can slash a locker", async function () {

            let TNTAmount = 10000;
            let TeleBTCAmount = 1000;
            // Initialize mock contract (how much TNT locker should be penalized)
            await mockPriceOracle.mock.equivalentOutputAmount.returns(TNTAmount)

            // Signer 1 becomes a locker
            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)
            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)
            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)
            let lockerSigner1 = lockers.connect(signer1)
            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )
            await expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            // Locker mints some TeleBTC and gets BTC on Bitcoin
            await lockers.addMinter(signer1Address);
            await lockerSigner1.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, TeleBTCAmount);

            // ccBurn calls to slash the locker
            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await expect(
                await lockerCCBurnSigner.slashThiefLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    TeleBTCAmount
                )
            ).to.emit(lockers, "LockerSlashed")

        })
    });

    describe("#buySlashedCollateralOfLocker", async () => {

        it("reverts when the target address is not locker", async function () {
            let lockerSigner1 = lockers.connect(signer1)

            await expect(
                lockerSigner1.buySlashedCollateralOfLocker(
                    signer1Address,
                    10
                )
            ).to.be.revertedWith("Lockers: input address is not a valid locker")
        })

        it("not enough slashed amount to buy", async function () {

            let TNTAmount = 10000;
            let TeleBTCAmount = 1000;
            // Initialize mock contract (how much TNT locker should be penalized)
            await mockPriceOracle.mock.equivalentOutputAmount.returns(TNTAmount)

            // Signer 1 becomes a locker
            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)
            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)
            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)
            let lockerSigner1 = lockers.connect(signer1)
            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )
            await expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            // Locker mints some TeleBTC and gets BTC on Bitcoin
            await lockers.addMinter(signer1Address);
            await lockerSigner1.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, TeleBTCAmount);

            // ccBurn calls to slash the locker
            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await expect(
                await lockerCCBurnSigner.slashThiefLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    TeleBTCAmount
                )
            ).to.emit(lockerCCBurnSigner, "LockerSlashed")
            

            // Someone buys slashed collateral with discount
            let lockerSigner2 = lockers.connect(signer2)
            await expect(
                lockerSigner2.buySlashedCollateralOfLocker(
                    signer1Address,
                    TNTAmount * liquidationRatio + 1
                )
            ).to.be.revertedWith("Lockers: not enough slashed collateral to buy")

        })

        it("can't slash because needed BTC is more than existing", async function () {

            let TNTAmount = 10000;
            let TeleBTCAmount = 1000;
            // Initialize mock contract (how much TNT locker should be penalized)
            await mockPriceOracle.mock.equivalentOutputAmount.returns(TNTAmount)

            // Signer 1 becomes a locker
            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)
            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)
            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)
            let lockerSigner1 = lockers.connect(signer1)
            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )
            await expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            // Locker mints some TeleBTC and gets BTC on Bitcoin
            await lockers.addMinter(signer1Address);
            await lockerSigner1.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, TeleBTCAmount);

            // ccBurn calls to slash the locker
            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(minRequiredNativeTokenLockedAmount.div(5))

            await expect(
                await lockerCCBurnSigner.slashThiefLocker(
                    signer1Address,
                    0,
                    deployerAddress,
                    TeleBTCAmount
                )
            ).to.emit(lockerCCBurnSigner, "LockerSlashed")

            // Someone buys slashed collateral with discount
            let lockerSigner2 = lockers.connect(signer2)
            await expect(
                lockerSigner2.buySlashedCollateralOfLocker(
                    signer1Address,
                    BigNumber.from(10).pow(18).mul(1)
                )
            ).to.be.reverted;

        })

        it("can buy slashing amount", async function () {

            let TNTAmount = 10000;
            let TeleBTCAmount = 1000;
            // Initialize mock contract (how much TNT locker should be penalized)
            await mockPriceOracle.mock.equivalentOutputAmount.returns(TNTAmount)

            // Signer 1 becomes a locker
            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)
            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)
            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)
            let lockerSigner1 = lockers.connect(signer1)
            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            )
            await expect(
                await lockers.addLocker(signer1Address)
            ).to.emit(lockers, "LockerAdded")

            // Locker mints some TeleBTC and gets BTC on Bitcoin
            await lockers.addMinter(signer1Address);
            await lockerSigner1.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, TeleBTCAmount);

            // ccBurn calls to slash the locker
            let lockerCCBurnSigner = await lockers.connect(ccBurnSimulator)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(minRequiredNativeTokenLockedAmount.div(5))

            await lockerCCBurnSigner.slashThiefLocker(
                signer1Address,
                0,
                deployerAddress,
                TeleBTCAmount
            );

            let theLocker = await lockers.lockersMapping(signer1Address)

            expect(
                theLocker[6]
            ).to.equal(TeleBTCAmount)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(TeleBTCAmount)

            await teleBTC.mint(signer2Address, 10000000)

            let teleBTCSigner2 = await teleBTC.connect(signer2);

            await teleBTCSigner2.approve(lockers.address, 1 + TeleBTCAmount*95/100) // add 1 bcz of precision loss

            // Someone buys slashed collateral with discount
            let lockerSigner2 = lockers.connect(signer2)
            await expect(
                await lockerSigner2.buySlashedCollateralOfLocker(
                    signer1Address,
                    BigNumber.from(10).pow(18).mul(1)
                )
            ).to.emit(lockers, "LockerSlashedCollateralSold")

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
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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

            await lockerSigner2.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, amount);

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
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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
                lockerSigner2.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, 5001)
            ).to.be.revertedWith("Lockers: insufficient capacity")

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
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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

            await lockerSigner2.mint(LOCKER1_PUBKEY__HASH, signer2Address, 1000)

            let theLockerMapping = await lockers.lockersMapping(signer1Address);

            expect(
                theLockerMapping[5]
            ).to.equal(1000);

            await teleBTC.mint(signer2Address, 10000000)

            let teleBTCSigner2 = teleBTC.connect(signer2)

            amount = 900;
            let lockerFee = Math.floor(amount*LOCKER_PERCENTAGE_FEE/10000);

            await teleBTCSigner2.approve(lockers.address, amount);

            await lockerSigner2.burn(LOCKER1_PUBKEY__HASH, amount);

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
            ).to.be.revertedWith("Lockers: input address is not a valid locker")
        })

        it("can't liquidate because it's above liquidation ratio", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await lockerSigner2.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, 5000000);

            await expect(
                lockerSigner2.liquidateLocker(signer1Address, 5000)
            ).to.be.revertedWith("Lockers: is healthy")

        });

        it("can't liquidate because it's above the liquidated amount", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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
            await lockerSigner2.mint(LOCKER1_PUBKEY__HASH, ONE_ADDRESS, 25000000);

            await mockPriceOracle.mock.equivalentOutputAmount.returns(7000000);

            await expect(
                lockerSigner2.liquidateLocker(
                    signer1Address,
                    BigNumber.from(10).pow(18).mul(3)
                )
            ).to.be.revertedWith("Lockers: not enough collateral to buy")

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
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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
            await lockerSigner2.mint(LOCKER1_PUBKEY__HASH, signer2Address, 25000000);


            let teleBTCSigner2 = await teleBTC.connect(signer2);

            await teleBTCSigner2.approve(lockers.address, 13300000 + 1) // add 1 bcz of precision loss

            let signer2NativeTokenBalanceBefore = await teleBTC.provider.getBalance(signer2Address)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(7000000);

            await expect(
                await lockerSigner2.liquidateLocker(
                    signer1Address,
                    BigNumber.from(10).pow(18).mul(2)
                )
            ).to.emit(lockerSigner2, "LockerLiquidated")
            

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
                    10000,
                    {value: 10000}
                )
            ).to.be.revertedWith("Lockers: no locker");
        })


        it("reverts because of insufficient msg value", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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
            ).to.be.revertedWith("Lockers: msg value")

        })

        it("adding collateral to the locker", async function () {

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            let theLockerBefore = await lockers.lockersMapping(signer1Address)

            await expect(
                await lockerSigner1.addCollateral(
                    signer1Address,
                    10000,
                    {value: 10000}
                )
            ).to.emit(lockerSigner1, "CollateralAdded")
            

            let theLockerAfter = await lockers.lockersMapping(signer1Address)

            expect(
                theLockerAfter[4].sub(theLockerBefore[4])
            ).to.equal(10000)

        })

    });

    describe("#priceOfOneUnitOfCollateralInBTC", async () => {
        it("return what price oracle returned", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

            let lockerSigner1 = await lockers.connect(signer1)

            expect(
                await lockerSigner1.priceOfOneUnitOfCollateralInBTC()
            ).to.equal(10000)
        })
    })

    describe("#mint", async () => {

        it("only owner can call renounceOwnership", async function () {
            await expect(
                lockers.connect(signer1).renounceOwnership()
            ).to.be.revertedWith("Ownable: caller is not the owner")

            await lockers.renounceOwnership()
        })


        it("can't mint because receipt is zero address", async function () {

            await lockers.setCCBurnRouter(mockCCBurnRouter.address);
            await mockCCBurnRouter.mock.ccBurn.returns(8000);

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
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

            await expect (
                lockerSigner2.mint(LOCKER1_PUBKEY__HASH, ZERO_ADDRESS, 25000000)
            ).to.be.revertedWith("Lockers: address is zero")
        })

        it("can't mint since locker is inactive", async function () {

            await lockers.setCCBurnRouter(mockCCBurnRouter.address);
            await mockCCBurnRouter.mock.ccBurn.returns(8000);

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000000);

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            await lockerSigner1.requestInactivation();

            expect(
                await lockers.isLockerActive(signer1Address)
            ).to.equal(true)

            let lastBlockTimestamp = await getTimestamp();
            await advanceBlockWithTime(deployer.provider, lastBlockTimestamp + INACTIVATION_DELAY + 10);
            

            await lockers.addMinter(signer2Address);

            let lockerSigner2 = lockers.connect(signer2)

            await mockPriceOracle.mock.equivalentOutputAmount.returns(50000000);

            await expect (
                lockerSigner2.mint(LOCKER1_PUBKEY__HASH, signer2Address, 25000000)
            ).to.be.revertedWith("Lockers: not active")
        })
        
    })

    describe("#removeCollateral", async () => {

        it("can't remove collateral for a non locker account", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

            let lockerSigner1 = await lockers.connect(signer1)

            await expect(
                lockerSigner1.removeCollateral(
                    1000
                )
            ).to.be.revertedWith("Lockers: no locker")
        })

        it("reverts because it's more than capacity", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            // Forwards block.timestamp to inactivate locker
            let lastBlockTimestamp = await getTimestamp();
            await advanceBlockWithTime(deployer.provider, lastBlockTimestamp + INACTIVATION_DELAY);

            await expect(
                lockerSigner1.removeCollateral(
                    (minRequiredNativeTokenLockedAmount.div(2)).add(1)
                )
            ).to.be.revertedWith("Lockers: still active")

        })


        it("reverts because it's more than capacity", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            // inactivate the locker
            await lockerSigner1.requestInactivation();

            // Forwards block.timestamp to inactivate locker
            let lastBlockTimestamp = await getTimestamp();
            await advanceBlockWithTime(deployer.provider, lastBlockTimestamp + INACTIVATION_DELAY);

            await expect(
                lockerSigner1.removeCollateral(
                    (minRequiredNativeTokenLockedAmount.div(2)).add(1)
                )
            ).to.be.revertedWith("Lockers: more than max removable collateral")

        })

        it("reverts because it becomes below the min required collateral", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount,
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount}
            );

            await lockers.addLocker(signer1Address);

            // inactivate the locker
            await lockerSigner1.requestInactivation();
            
            // Forwards block.timestamp to inactivate locker
            let lastBlockTimestamp = await getTimestamp();
            await advanceBlockWithTime(deployer.provider, lastBlockTimestamp + INACTIVATION_DELAY);

            await expect(
                lockerSigner1.removeCollateral(minRequiredNativeTokenLockedAmount.div(2))
            ).to.be.revertedWith("Lockers: less than min collateral")
        })

        it("remove collateral successfully", async function () {

            await mockPriceOracle.mock.equivalentOutputAmount.returns(10000)

            await teleportDAOToken.transfer(signer1Address, minRequiredTDTLockedAmount)

            let teleportDAOTokenSigner1 = teleportDAOToken.connect(signer1)

            await teleportDAOTokenSigner1.approve(lockers.address, minRequiredTDTLockedAmount)

            let lockerSigner1 = lockers.connect(signer1)

            await lockerSigner1.requestToBecomeLocker(
                // LOCKER1,
                LOCKER1_PUBKEY__HASH,
                minRequiredTDTLockedAmount,
                minRequiredNativeTokenLockedAmount.mul(2),
                LOCKER_RESCUE_SCRIPT_P2PKH_TYPE,
                LOCKER_RESCUE_SCRIPT_P2PKH,
                {value: minRequiredNativeTokenLockedAmount.mul(2)}
            );

            await lockers.addLocker(signer1Address);

            let theLockerBalanceBefore = await teleBTC.provider.getBalance(signer1Address);

            // inactivate the locker
            await lockerSigner1.requestInactivation();
            
            // Forwards block.timestamp to inactivate locker
            let lastBlockTimestamp = await getTimestamp();
            await advanceBlockWithTime(deployer.provider, lastBlockTimestamp + INACTIVATION_DELAY);

            await expect(
                await lockerSigner1.removeCollateral(
                    minRequiredNativeTokenLockedAmount.div(2)
                )
            ).to.emit(lockerSigner1, "CollateralRemoved")

            
            let theLockerBalanceAfter = await teleBTC.provider.getBalance(signer1Address)

            expect(
                theLockerBalanceAfter.sub(theLockerBalanceBefore)
            ).to.be.closeTo(minRequiredNativeTokenLockedAmount.div(2), BigNumber.from(10).pow(15).mul(1))

        })

    });
})
