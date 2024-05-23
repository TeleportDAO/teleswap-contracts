<<<<<<< HEAD
// const CC_BURN_REQUESTS = require('./test_fixtures/ccBurnRequests.json');
// require('dotenv').config({path:"../../.env"});

// import { expect } from "chai";
// import { deployments, ethers, waffle } from "hardhat";
// import { Signer, BigNumber } from "ethers";
// import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
// import { Address } from "hardhat-deploy/types";
// import { Contract } from "@ethersproject/contracts";

// import { TeleBTCLogic } from "../src/types/TeleBTCLogic";
// import { TeleBTCLogic__factory } from "../src/types/factories/TeleBTCLogic__factory";
// import { TeleBTCProxy } from "../src/types/TeleBTCProxy";
// import { TeleBTCProxy__factory } from "../src/types/factories/TeleBTCProxy__factory";
// import { ERC20 } from "../src/types/ERC20";
// import { Erc20__factory } from "../src/types/factories/Erc20__factory";

// import { EthConnectorProxy__factory } from "../src/types/factories/EthConnectorProxy__factory";
// import { EthConnectorLogic__factory } from "../src/types/factories/EthConnectorLogic__factory";
// import { EthConnectorLogicLibraryAddresses } from "../src/types/factories/EthConnectorLogic__factory";

// import { AddressLib } from "../src/types/AddressLib"
// import { AddressLib__factory } from "../src/types/factories/AddressLib__factory"

// import { BurnRouterLib } from "../src/types/BurnRouterLib";
// import { BurnRouterLib__factory } from "../src/types/factories/BurnRouterLib__factory";

// import { BurnRouterProxy__factory } from "../src/types/factories/BurnRouterProxy__factory";
// import { BurnRouterLogic__factory } from "../src/types/factories/BurnRouterLogic__factory";
// import { BurnRouterLogicLibraryAddresses } from "../src/types/factories/BurnRouterLogic__factory";

// import { takeSnapshot, revertProvider } from "./block_utils";
// import { network } from "hardhat"

// import Web3 from 'web3'
// const abiUtils = new Web3().eth.abi
// const web3 = new Web3();
// const provider = waffle.provider;

// describe("EthConnector", async () => {
//     let snapshotId: any;

//     // Accounts
//     let proxyAdmin: Signer;
//     let deployer: Signer;
//     let signer1: Signer;
//     let signer2: Signer;
//     let acrossSinger: Signer;
//     let signer1Address: Address;
//     let deployerAddress: Address;
//     let proxyAdminAddress: Address;
//     let acrossAddress: Address;

//     // Contracts
//     let teleBTC: TeleBTC;
//     let inputToken: ERC20;
//     let inputTokenSigner1: ERC20;
//     let wrappedNativeToken: ERC20;
//     let polygonToken: ERC20;
//     let TeleBTCSigner1: TeleBTC;
//     let EthConnector: Contract;
//     let EthConnectorWithMockedAccross: Contract;
//     let burnRouterLib: BurnRouterLib;
//     let addressLib: AddressLib;
//     let burnRouter: Contract;

//     let exchangeToken: ERC20;

//     // Mock contracts
//     let mockAddress: MockContract;
//     let mockLockers: MockContract;
//     let mockExchangeConnector: MockContract;
//     let mockAcross: MockContract;

//     // Constants
//     let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
//     let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
//     let ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"
//     let oneHundred = BigNumber.from(10).pow(8).mul(100)
//     /*
//         This one is set so that:
//         userRequestedAmount * (1 - lockerFee / 10000 - PROTOCOL_PERCENTAGE_FEE / 10000) - BITCOIN_FEE = 100000000
//     */
//     let userRequestedAmount = BigNumber.from(100060030);
//     let requestAmount = 100
//     let telebtcAmount  = 100000000000
//     let TRANSFER_DEADLINE = 20
//     let PROTOCOL_PERCENTAGE_FEE = 5 // means 0.05%
//     let SLASHER_PERCENTAGE_REWARD = 5 // means 0.05%
//     let RELAYER_FEE = 10000 // estimation of Bitcoin transaction fee in Satoshi
//     let TREASURY = "0x0000000000000000000000000000000000000002";

//     let LOCKER_TARGET_ADDRESS = ONE_ADDRESS;
//     let LOCKER1_LOCKING_SCRIPT = '0x76a914748284390f9e263a4b766a75d0633c50426eb87587ac';

//     let USER_SCRIPT_P2PKH = "0x12ab8dc588ca9d5787dde7eb29569da63c3a238c";
//     let USER_SCRIPT_P2PKH_TYPE = 1; // P2PKH

//     let USER_SCRIPT_P2WPKH = "0x751e76e8199196d454941c45d1b3a323f1433bd6";
//     let USER_SCRIPT_P2WPKH_TYPE = 3; // P2WPKH

    
//     before(async () => {

//         [proxyAdmin, deployer, signer1, signer2, acrossSinger] = await ethers.getSigners();
//         proxyAdminAddress = await proxyAdmin.getAddress();
//         signer1Address = await signer1.getAddress();
//         deployerAddress = await deployer.getAddress();
//         acrossAddress = await acrossSinger.getAddress();

//         // Mocks contracts
//         // const AddressContract = await deployments.getArtifact(
//         //     "AddressTest"
//         // );
        
//         // mockAddress = await deployMockContract(
//         //     deployer,
//         //     AddressContract.abi
//         // )

//         const across = await deployments.getArtifact(
//             "SpokePoolInterface"
//         );
//         mockAcross = await deployMockContract(
//             deployer,
//             across.abi
//         )

//         // Deploys contracts
//         teleBTC = await deployTeleBTC()

//         await teleBTC.initialize(
//             "TeleportDAO-BTC",
//             "teleBTC"
//         );

//         // Deploys input token
//         const erc20Factory = new Erc20__factory(deployer);
//         inputToken = await erc20Factory.deploy(
//             "TestToken",
//             "TT",
//             100000
//         );

//         polygonToken = await erc20Factory.deploy(
//             "PolygonTestToken",
//             "PTT",
//             100000
//         );

//         // Deploys wrapped native token
//         wrappedNativeToken = await erc20Factory.deploy(
//             "WrappedEth",
//             "WETH",
//             100000
//         );
        
//         EthConnector = await deployEthConnector();

//         await EthConnector.initialize(
//             teleBTC.address,
//             mockAcross.address,
//             wrappedNativeToken.address,
//             137
//         );

//         // Mints TeleBTC for user
//         await teleBTC.addMinter(signer1Address)
//         TeleBTCSigner1 = await teleBTC.connect(signer1);

//         await teleBTC.setMaxMintLimit(oneHundred.mul(2));
//         await moveBlocks(2020)

//         //mock function
//         // await mockAddress.mock.functionCallWithValue.returns("0x")
//         await mockAcross.mock.deposit.returns()
//     });

//     async function moveBlocks(amount: number) {
//         for (let index = 0; index < amount; index++) {
//           await network.provider.request({
//             method: "evm_mine",
//             params: [],
//           })
//         }
//     }

//     const deployTeleBTC = async (
//         _signer?: Signer
//     ): Promise<TeleBTC> => {
//         const teleBTCLogicFactory = new TeleBTCLogic__factory(deployer);
//         const teleBTCLogic = await teleBTCLogicFactory.deploy();

//         const teleBTCProxyFactory = new TeleBTCProxy__factory(deployer);
//         const teleBTCProxy = await teleBTCProxyFactory.deploy(
//             teleBTCLogic.address,    
//             proxyAdminAddress,
//             "0x"
//         );

//         return await teleBTCLogic.attach(
//             teleBTCProxy.address
//         );;
//     };

//     const deployAddressLib = async (
//         _signer?: Signer
//     ): Promise<AddressLib> => {
//         const AddressLibFactory = new AddressLib__factory(
//             _signer || deployer
//         );

//         const AddressLib = await AddressLibFactory.deploy(
//         );

//         return AddressLib;
//     };

//     const deployEthConnector = async (
//         _signer?: Signer
//     ): Promise<Contract> => {
//         addressLib = await deployAddressLib()
//         let linkLibraryAddresses: EthConnectorLogicLibraryAddresses;

//         linkLibraryAddresses = {
//             "contracts/libraries/AddressLib.sol:AddressLib": addressLib.address,
//         };

//         // Deploys lockers logic
//         const ethConnectorLogicFactory = new EthConnectorLogic__factory(
//             // linkLibraryAddresses,
//             _signer || deployer
//         );

//         const ethConnectorLogic = await ethConnectorLogicFactory.deploy();

//         // Deploys lockers proxy
//         const ethConnectorProxyFactory = new EthConnectorProxy__factory(
//             _signer || deployer
//         );
//         const ethConnectorProxy = await ethConnectorProxyFactory.deploy(
//             ethConnectorLogic.address,
//             proxyAdminAddress,
//             "0x"
//         )

//         return await ethConnectorLogic.attach(
//             ethConnectorProxy.address
//         );

//     };

//     async function mintTeleBTCForTest(): Promise<void> {
//         let TeleBTCSigner1 = await teleBTC.connect(signer1)
//         await TeleBTCSigner1.mint(signer1Address, oneHundred);
//     }

//     describe("#setters", async () => {

//         beforeEach(async () => {
//             snapshotId = await takeSnapshot(signer1.provider);
//         });

//         afterEach(async () => {
//             await revertProvider(signer1.provider, snapshotId);
//         });

//         it("should set and get the min amount", async () => {
//             await EthConnector.setMinAmount(inputToken.address, requestAmount);
//             expect(await EthConnector.minAmounts(inputToken.address)).to.equal(requestAmount);
//         });

//         it("should not set the min amount if not owner", async () => {
//             await expect(EthConnector.connect(signer1).setMinAmount(inputToken.address, requestAmount)).to.be.revertedWith("Ownable: caller is not the owner");
//         });

//         it("should set and get the MinModifier", async () => {
//             await EthConnector.setMinModifier(9000);
//             expect(await EthConnector.minModifier()).to.equal(9000);
//         });

//         it("should not set the MinModifier if not owner", async () => {
//             await expect(EthConnector.connect(signer1).setMinModifier(9000)).to.be.revertedWith("Ownable: caller is not the owner");
//         });

//         it("should set and get the Across", async () => {
//             await EthConnector.setAcross(ONE_ADDRESS);
//             expect(await EthConnector.across()).to.equal(ONE_ADDRESS);
//         });

//         it("should not set the Across if not owner", async () => {
//             await expect(EthConnector.connect(signer1).setAcross(ONE_ADDRESS)).to.be.revertedWith("Ownable: caller is not the owner");
//         });

//         it("should set and get the PolygonConnectorProxy", async () => {
//             await EthConnector.setPolygonConnectorProxy(ONE_ADDRESS);
//             expect(await EthConnector.polygonConnectorProxy()).to.equal(ONE_ADDRESS);
//         });

//         it("should not set the PolygonConnectorProxy if not owner", async () => {
//             await expect(EthConnector.connect(signer1).setPolygonConnectorProxy(ONE_ADDRESS)).to.be.revertedWith("Ownable: caller is not the owner");
//         });

//         it("should set and get the PolygonTeleBTC", async () => {
//             await EthConnector.setPolygonTeleBTC(ONE_ADDRESS);
//             expect(await EthConnector.polygonTeleBTC()).to.equal(ONE_ADDRESS);
//         });

//         it("should not set the PolygonTeleBTC if not owner", async () => {
//             await expect(EthConnector.connect(signer1).setPolygonTeleBTC(ONE_ADDRESS)).to.be.revertedWith("Ownable: caller is not the owner");
//         });

//         it("should set and get the WrappedNativeToken", async () => {
//             await EthConnector.setWrappedNativeToken(ONE_ADDRESS);
//             expect(await EthConnector.wrappedNativeToken()).to.equal(ONE_ADDRESS);
//         });

//         it("should not set the WrappedNativeToken if not owner", async () => {
//             await expect(EthConnector.connect(signer1).setWrappedNativeToken(ONE_ADDRESS)).to.be.revertedWith("Ownable: caller is not the owner");
//         });

//         it("can't set addresses to zero address", async () => {
//             await expect(EthConnector.setMinAmount(ZERO_ADDRESS, requestAmount)).to.be.revertedWith("ZeroAddress()");
//             await expect(EthConnector.setAcross(ZERO_ADDRESS)).to.be.revertedWith("ZeroAddress()");
//             await expect(EthConnector.setPolygonConnectorProxy(ZERO_ADDRESS)).to.be.revertedWith("ZeroAddress()");
//             await expect(EthConnector.setPolygonTeleBTC(ZERO_ADDRESS)).to.be.revertedWith("ZeroAddress()");
//             await expect(EthConnector.setWrappedNativeToken(ZERO_ADDRESS)).to.be.revertedWith("ZeroAddress()");
//         });
//     });

//     describe("#Handle across message", async () => {

//         beforeEach(async () => {
//             await EthConnector.setMinAmount(inputToken.address, 100)
//             await EthConnector.setMinAmount(ETH_ADDRESS, 100)
//             await inputToken.approve(EthConnector.address, requestAmount)
//             await wrappedNativeToken.approve(EthConnector.address, requestAmount)
//             snapshotId = await takeSnapshot(signer1.provider);
//         });

//         afterEach(async () => {
//             await revertProvider(signer1.provider, snapshotId);
//         });

//         ////// _checkRequest test start
//         it("fails because token is not supported", async () => {
//             await EthConnector.setMinAmount(inputToken.address, 0)
//             await expect(
//                 EthConnector.exchangeForBtcAcross(
//                     inputToken.address,
//                     ONE_ADDRESS,
//                     [requestAmount, telebtcAmount],
//                     [polygonToken.address, teleBTC.address],
//                     USER_SCRIPT_P2PKH,
//                     USER_SCRIPT_P2PKH_TYPE,
//                     LOCKER_TARGET_ADDRESS,
//                     RELAYER_FEE,
//                     0
//                 )
//             ).to.be.revertedWith("EthManagerLogic: token not supported");
//         });

//         it("fails because token amount is not sufficient", async () => {
//             await expect(
//                 EthConnector.exchangeForBtcAcross(
//                     inputToken.address,
//                     ONE_ADDRESS,
//                     [90, telebtcAmount],
//                     [polygonToken.address, teleBTC.address],
//                     USER_SCRIPT_P2PKH,
//                     USER_SCRIPT_P2PKH_TYPE,
//                     LOCKER_TARGET_ADDRESS,
//                     RELAYER_FEE,
//                     0
//                 )
//             ).to.be.revertedWith("EthManagerLogic: low amount");
//         });

//         it("fails because last token of path is not telebtc", async () => {
//             await expect(
//                 EthConnector.exchangeForBtcAcross(
//                     inputToken.address,
//                     ONE_ADDRESS,
//                     [requestAmount, telebtcAmount],
//                     [polygonToken.address, inputToken.address],
//                     USER_SCRIPT_P2PKH,
//                     USER_SCRIPT_P2PKH_TYPE,
//                     LOCKER_TARGET_ADDRESS,
//                     RELAYER_FEE,
//                     0
//                 )
//             ).to.be.revertedWith("EthManagerLogic: invalid path");
//         });

//         it("fails because amounts list length is greater than 2", async () => {
//             await expect(
//                 EthConnector.exchangeForBtcAcross(
//                     inputToken.address,
//                     ONE_ADDRESS,
//                     [requestAmount, telebtcAmount, 100],
//                     [polygonToken.address, teleBTC.address],
//                     USER_SCRIPT_P2PKH,
//                     USER_SCRIPT_P2PKH_TYPE,
//                     LOCKER_TARGET_ADDRESS,
//                     RELAYER_FEE,
//                     0
//                 )
//             ).to.be.revertedWith("EthManagerLogic: wrong amounts");
//         });
//         ////// _checkRequest test end

//         ////// _sendMsgUsingAcross test start
//         it("fails because amount is incorrect (ETH)", async () => {
//             await expect(
//                 EthConnector.exchangeForBtcAcross(
//                     ETH_ADDRESS,
//                     ONE_ADDRESS,
//                     [requestAmount, telebtcAmount],
//                     [polygonToken.address, teleBTC.address],
//                     USER_SCRIPT_P2PKH,
//                     USER_SCRIPT_P2PKH_TYPE,
//                     LOCKER_TARGET_ADDRESS,
//                     RELAYER_FEE,
//                     0
//                 )
//             ).to.be.revertedWith("EthManagerLogic: wrong value");
//         });
//         ////// _sendMsgUsingAcross test end


//         it("Handle exchangeForBtcAcross (TOKEN)", async () => {
//             let message = await abiUtils.encodeParameters([
//                 'string',
//                 'uint',
//                 'address',
//                 'address',
//                 'uint',
//                 'address[]',
//                 'bytes',
//                 'uint',
//                 'bytes',
//                 'uint'
//             ], [
//                 "exchangeForBtcAcross",
//                 0,
//                 deployerAddress,
//                 ONE_ADDRESS, 
//                 telebtcAmount,
//                 [polygonToken.address, teleBTC.address], 
//                 USER_SCRIPT_P2PKH,
//                 USER_SCRIPT_P2PKH_TYPE,
//                 LOCKER_TARGET_ADDRESS,
//                 0
//             ])

//             await expect(
//                 EthConnector.exchangeForBtcAcross(
//                     inputToken.address,
//                     ONE_ADDRESS,
//                     [requestAmount, telebtcAmount],
//                     [polygonToken.address, teleBTC.address],
//                     USER_SCRIPT_P2PKH,
//                     USER_SCRIPT_P2PKH_TYPE,
//                     LOCKER_TARGET_ADDRESS,
//                     RELAYER_FEE,
//                     0
//                 )
//             ).to.emit(EthConnector, 'MsgSent').withArgs(
//                 "0",
//                 "putBidAcross",
//                 message,
//                 inputToken.address,
//                 requestAmount
//             );
//         });

//         it("Handle exchangeForBtcAcross (ETH)", async () => {
//             let message = await abiUtils.encodeParameters([
//                 'string',
//                 'uint',
//                 'address',
//                 'address',
//                 'uint',
//                 'address[]',
//                 'bytes',
//                 'uint',
//                 'bytes',
//                 'uint'
//             ], [
//                 "exchangeForBtcAcross",
//                 0,
//                 deployerAddress,
//                 ONE_ADDRESS, 
//                 telebtcAmount,
//                 [polygonToken.address, teleBTC.address], 
//                 USER_SCRIPT_P2PKH,
//                 USER_SCRIPT_P2PKH_TYPE,
//                 LOCKER_TARGET_ADDRESS,
//                 0
//             ])

//             await expect(
//                 EthConnector.exchangeForBtcAcross(
//                     ETH_ADDRESS,
//                     ONE_ADDRESS,
//                     [requestAmount, telebtcAmount],
//                     [polygonToken.address, teleBTC.address],
//                     USER_SCRIPT_P2PKH,
//                     USER_SCRIPT_P2PKH_TYPE,
//                     LOCKER_TARGET_ADDRESS,
//                     RELAYER_FEE,
//                     0,
//                     {
//                         value: requestAmount
//                     }
//                 )
//             ).to.emit(EthConnector, 'MsgSent').withArgs(
//                 "0",
//                 "putBidAcross",
//                 message,
//                 ETH_ADDRESS,
//                 requestAmount
//             );
//         });

//         it("fails because amount is incorrect (TOKEN)", async () => {
//             await expect(
//                 EthConnector.exchangeForBtcAcross(
//                     inputToken.address,
//                     ONE_ADDRESS,
//                     [requestAmount, telebtcAmount],
//                     [polygonToken.address, teleBTC.address],
//                     USER_SCRIPT_P2PKH,
//                     USER_SCRIPT_P2PKH_TYPE,
//                     LOCKER_TARGET_ADDRESS,
//                     RELAYER_FEE,
//                     0,
//                     {
//                         value: requestAmount
//                     }
//                 )
//             ).to.be.revertedWith("EthManagerLogic: wrong value");
//         });
      
//     });

//     describe("#Handle emergencyWithdraw", async () => {
//         //write test that handle emergency withdraw
//         it("should handle emergency withdraw token", async () => {
//             await inputToken.transfer(
//                 EthConnector.address,
//                 requestAmount
//             );

//             await expect (
//                 await inputToken.balanceOf(EthConnector.address)
//             ).to.be.equal(requestAmount)

//             await EthConnector.emergencyWithdraw(
//                 inputToken.address,
//                 signer1Address,
//                 requestAmount
//             )

//             await expect (
//                 await inputToken.balanceOf(EthConnector.address)
//             ).to.be.equal(0)

//             await expect (
//                 await inputToken.balanceOf(signer1Address)
//             ).to.be.equal(requestAmount)

//         });

//         it("should handle emergency withdraw eth", async () => {
//             let tx = {
//                 to: EthConnector.address,
//                 value: 100
//             };
//             await signer1.sendTransaction(tx);

//             let beforeBalance = await signer1.getBalance()
//             beforeBalance.add(100)

//             await expect (
//                 await provider.getBalance(EthConnector.address)
//             ).to.be.equal(100)

//             await EthConnector.emergencyWithdraw(
//                 "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
//                 signer1Address,
//                 100
//             )

//         });

//         // write test that only owner can emergency withdraw
//         it("should not handle emergency withdraw if not owner", async () => {
//             await expect (
//                 EthConnector.connect(signer1).emergencyWithdraw(
//                     inputToken.address,
//                     signer1Address,
//                     requestAmount
//                 )
//             ).to.be.revertedWith("Ownable: caller is not the owner")
//         });
//     });


// });
=======
require("dotenv").config({ path: "../../.env" });

import { expect } from "chai";
import { deployments, ethers, waffle } from "hardhat";
import { Signer, BigNumber } from "ethers";
import {
    deployMockContract,
    MockContract,
} from "@ethereum-waffle/mock-contract";
import { Address } from "hardhat-deploy/types";
import { Contract } from "@ethersproject/contracts";
import { TeleBTCLogic } from "../src/types/TeleBTCLogic";
import { TeleBTCLogic__factory } from "../src/types/factories/TeleBTCLogic__factory";
import { TeleBTCProxy } from "../src/types/TeleBTCProxy";
import { TeleBTCProxy__factory } from "../src/types/factories/TeleBTCProxy__factory";
import { ERC20 } from "../src/types/ERC20";
import { Erc20__factory } from "../src/types/factories/Erc20__factory";
import { EthConnectorProxy__factory } from "../src/types/factories/EthConnectorProxy__factory";
import { EthConnectorLogic__factory } from "../src/types/factories/EthConnectorLogic__factory";
import { takeSnapshot, revertProvider } from "./block_utils";
import { network } from "hardhat";

import Web3 from "web3";
const abiUtils = new Web3().eth.abi;
const web3 = new Web3();
const provider = waffle.provider;

describe("EthConnector", async () => {
    let snapshotId: any;

    // Accounts
    let proxyAdmin: Signer;
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let acrossSinger: Signer;
    let signer1Address: Address;
    let deployerAddress: Address;
    let proxyAdminAddress: Address;
    let acrossAddress: Address;

    // Contracts
    let teleBTC: TeleBTC;
    let inputToken: ERC20;
    let wrappedNativeToken: ERC20;
    let polygonToken: ERC20;
    let EthConnector: Contract;

    // Mock contracts
    let mockAcross: MockContract;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
    let oneHundred = BigNumber.from(10).pow(8).mul(100);
    /*
        This one is set so that:
        userRequestedAmount * (1 - lockerFee / 10000 - PROTOCOL_PERCENTAGE_FEE / 10000) - BITCOIN_FEE = 100000000
    */
    let requestAmount = 100;
    let telebtcAmount = 100000000000;
    let RELAYER_FEE = 10000; // estimation of Bitcoin transaction fee in Satoshi

    let LOCKER_TARGET_ADDRESS = ONE_ADDRESS;

    let USER_SCRIPT_P2PKH = "0x12ab8dc588ca9d5787dde7eb29569da63c3a238c";
    let USER_SCRIPT_P2PKH_TYPE = 1; // P2PKH

    before(async () => {
        [proxyAdmin, deployer, signer1, signer2, acrossSinger] =
            await ethers.getSigners();
        proxyAdminAddress = await proxyAdmin.getAddress();
        signer1Address = await signer1.getAddress();
        deployerAddress = await deployer.getAddress();
        acrossAddress = await acrossSinger.getAddress();

        const across = await deployments.getArtifact("SpokePoolInterface");
        mockAcross = await deployMockContract(deployer, across.abi);

        // Deploys contracts
        teleBTC = await deployTeleBTC();

        await teleBTC.initialize("TeleportDAO-BTC", "teleBTC");

        // Deploys input token
        const erc20Factory = new Erc20__factory(deployer);
        inputToken = await erc20Factory.deploy("TestToken", "TT", 100000);

        polygonToken = await erc20Factory.deploy(
            "PolygonTestToken",
            "PTT",
            100000
        );

        // Deploys wrapped native token
        wrappedNativeToken = await erc20Factory.deploy(
            "WrappedEth",
            "WETH",
            100000
        );

        EthConnector = await deployEthConnector();

        await EthConnector.initialize(
            teleBTC.address,
            mockAcross.address,
            wrappedNativeToken.address,
            137,
            1
        );

        // Mints TeleBTC for user
        await teleBTC.addMinter(signer1Address);

        await teleBTC.setMaxMintLimit(oneHundred.mul(2));
        await moveBlocks(2020);

        //mock function
        // await mockAddress.mock.functionCallWithValue.returns("0x")
        await mockAcross.mock.deposit.returns();
    });

    async function moveBlocks(amount: number) {
        for (let index = 0; index < amount; index++) {
            await network.provider.request({
                method: "evm_mine",
                params: [],
            });
        }
    }

    const deployTeleBTC = async (_signer?: Signer): Promise<TeleBTC> => {
        const teleBTCLogicFactory = new TeleBTCLogic__factory(deployer);
        const teleBTCLogic = await teleBTCLogicFactory.deploy();

        const teleBTCProxyFactory = new TeleBTCProxy__factory(deployer);
        const teleBTCProxy = await teleBTCProxyFactory.deploy(
            teleBTCLogic.address,
            proxyAdminAddress,
            "0x"
        );

        return await teleBTCLogic.attach(teleBTCProxy.address);
    };

    const deployEthConnector = async (_signer?: Signer): Promise<Contract> => {

        // Deploys lockers logic
        const ethConnectorLogicFactory = new EthConnectorLogic__factory(
            _signer || deployer
        );

        const ethConnectorLogic = await ethConnectorLogicFactory.deploy();

        // Deploys lockers proxy
        const ethConnectorProxyFactory = new EthConnectorProxy__factory(
            _signer || deployer
        );
        const ethConnectorProxy = await ethConnectorProxyFactory.deploy(
            ethConnectorLogic.address,
            proxyAdminAddress,
            "0x"
        );

        return await ethConnectorLogic.attach(ethConnectorProxy.address);
    };

    describe("#setters", async () => {
        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("should set and get the Across", async () => {
            await EthConnector.setAcross(ONE_ADDRESS);
            expect(await EthConnector.across()).to.equal(ONE_ADDRESS);
        });

        it("should not set the Across if not owner", async () => {
            await expect(
                EthConnector.connect(signer1).setAcross(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("should set and get the TargetChainConnectorProxy", async () => {
            await EthConnector.setTargetChainConnectorProxy(ONE_ADDRESS);
            expect(await EthConnector.targetChainConnectorProxy()).to.equal(
                ONE_ADDRESS
            );
        });

        it("should not set the TargetChainConnectorProxy if not owner", async () => {
            await expect(
                EthConnector.connect(signer1).setTargetChainConnectorProxy(
                    ONE_ADDRESS
                )
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("should set and get the TargetChainTeleBTC", async () => {
            await EthConnector.setTargetChainTeleBTC(ONE_ADDRESS);
            expect(await EthConnector.targetChainTeleBTC()).to.equal(ONE_ADDRESS);
        });

        it("should not set the TargetChainTeleBTC if not owner", async () => {
            await expect(
                EthConnector.connect(signer1).setTargetChainTeleBTC(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("should set and get the WrappedNativeToken", async () => {
            await EthConnector.setWrappedNativeToken(ONE_ADDRESS);
            expect(await EthConnector.wrappedNativeToken()).to.equal(
                ONE_ADDRESS
            );
        });

        it("should not set the WrappedNativeToken if not owner", async () => {
            await expect(
                EthConnector.connect(signer1).setWrappedNativeToken(ONE_ADDRESS)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("can't set addresses to zero address", async () => {
            await expect(
                EthConnector.setAcross(ZERO_ADDRESS)
            ).to.be.revertedWith("ZeroAddress");
            await expect(
                EthConnector.setTargetChainConnectorProxy(ZERO_ADDRESS)
            ).to.be.revertedWith("ZeroAddress");
            await expect(
                EthConnector.setTargetChainTeleBTC(ZERO_ADDRESS)
            ).to.be.revertedWith("ZeroAddress");
            await expect(
                EthConnector.setWrappedNativeToken(ZERO_ADDRESS)
            ).to.be.revertedWith("ZeroAddress");
        });
    });

    describe("#Handle across message", async () => {
        beforeEach(async () => {
            await inputToken.approve(EthConnector.address, requestAmount);
            await wrappedNativeToken.approve(
                EthConnector.address,
                requestAmount
            );
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("fails because last token of path is not telebtc", async () => {
            await expect(
                EthConnector.swapAndUnwrap(
                    inputToken.address,
                    ONE_ADDRESS,
                    [requestAmount, telebtcAmount],
                    true,
                    [polygonToken.address, inputToken.address],
                    { 
                        userScript: USER_SCRIPT_P2PKH,
                        scriptType: USER_SCRIPT_P2PKH_TYPE,
                        lockerLockingScript: LOCKER_TARGET_ADDRESS
                    },
                    RELAYER_FEE,
                    0
                )
            ).to.be.revertedWith("EthManagerLogic: invalid path");
        });

        it("fails because amounts list length is greater than 2", async () => {
            await expect(
                EthConnector.swapAndUnwrap(
                    inputToken.address,
                    ONE_ADDRESS,
                    [requestAmount, telebtcAmount, 100],
                    true,
                    [polygonToken.address, teleBTC.address],
                    { 
                        userScript: USER_SCRIPT_P2PKH,
                        scriptType: USER_SCRIPT_P2PKH_TYPE,
                        lockerLockingScript: LOCKER_TARGET_ADDRESS
                    },
                    RELAYER_FEE,
                    0
                )
            ).to.be.revertedWith("EthManagerLogic: wrong amounts");
        });
        ////// _checkRequest test end

        ////// _sendMsgUsingAcross test start
        it("fails because amount is incorrect (ETH)", async () => {
            await expect(
                EthConnector.swapAndUnwrap(
                    ETH_ADDRESS,
                    ONE_ADDRESS,
                    [requestAmount, telebtcAmount],
                    true,
                    [polygonToken.address, teleBTC.address],
                    { 
                        userScript: USER_SCRIPT_P2PKH,
                        scriptType: USER_SCRIPT_P2PKH_TYPE,
                        lockerLockingScript: LOCKER_TARGET_ADDRESS
                    },
                    RELAYER_FEE,
                    0
                )
            ).to.be.revertedWith("EthManagerLogic: wrong value");
        });
        ////// _sendMsgUsingAcross test end

        it("Handle swapAndUnwrap (TOKEN)", async () => {
            let message = await abiUtils.encodeParameters(
                [
                    "string",
                    "uint",
                    "uint",
                    "address",
                    "address",
                    "uint",
                    "bool",
                    "address[]",
                    {
                        "UserAndLockerScript": {
                            "userScript": "bytes",
                            "scriptType": "uint",
                            "lockerLockingScript": "bytes"
                        }
                    },
                    "uint"
                ],
                [
                    "swapAndUnwrap",
                    0,
                    1,
                    deployerAddress,
                    ONE_ADDRESS,
                    telebtcAmount,
                    true,
                    [polygonToken.address, teleBTC.address],
                    { 
                        "userScript": USER_SCRIPT_P2PKH,
                        "scriptType": USER_SCRIPT_P2PKH_TYPE,
                        "lockerLockingScript": LOCKER_TARGET_ADDRESS
                    },
                    0
                ]
            );

            await expect(
                EthConnector.swapAndUnwrap(
                    inputToken.address,
                    ONE_ADDRESS,
                    [requestAmount, telebtcAmount],
                    true,
                    [polygonToken.address, teleBTC.address],
                    { 
                        userScript: USER_SCRIPT_P2PKH,
                        scriptType: USER_SCRIPT_P2PKH_TYPE,
                        lockerLockingScript: LOCKER_TARGET_ADDRESS
                    },
                    RELAYER_FEE,
                    0
                )
            )
                .to.emit(EthConnector, "MsgSent")
                .withArgs(
                    "0",
                    message,
                    inputToken.address,
                    requestAmount
                );
        });

        it("Handle swapAndUnwrap (ETH)", async () => {
            let message = await abiUtils.encodeParameters(
                [
                    "string",
                    "uint",
                    "uint",
                    "address",
                    "address",
                    "uint",
                    "bool",
                    "address[]",
                    {
                        "UserAndLockerScript": {
                            "userScript": "bytes",
                            "scriptType": "uint",
                            "lockerLockingScript": "bytes"
                        }
                    },
                    "uint"
                ],
                [
                    "swapAndUnwrap",
                    0,
                    1,
                    deployerAddress,
                    ONE_ADDRESS,
                    telebtcAmount,
                    true,
                    [polygonToken.address, teleBTC.address],
                    { 
                        "userScript": USER_SCRIPT_P2PKH,
                        "scriptType": USER_SCRIPT_P2PKH_TYPE,
                        "lockerLockingScript": LOCKER_TARGET_ADDRESS
                    },
                    0,
                ]
            );

            await expect(
                EthConnector.swapAndUnwrap(
                    ETH_ADDRESS,
                    ONE_ADDRESS,
                    [requestAmount, telebtcAmount],
                    true,
                    [polygonToken.address, teleBTC.address],
                    { 
                        userScript: USER_SCRIPT_P2PKH,
                        scriptType: USER_SCRIPT_P2PKH_TYPE,
                        lockerLockingScript: LOCKER_TARGET_ADDRESS
                    },
                    RELAYER_FEE,
                    0,
                    {
                        value: requestAmount,
                    }
                )
            )
                .to.emit(EthConnector, "MsgSent")
                .withArgs(
                    "0",
                    message,
                    ETH_ADDRESS,
                    requestAmount
                );
        });

        it("fails because amount is incorrect (TOKEN)", async () => {
            await expect(
                EthConnector.swapAndUnwrap(
                    inputToken.address,
                    ONE_ADDRESS,
                    [requestAmount, telebtcAmount],
                    true,
                    [polygonToken.address, teleBTC.address],
                    { 
                        userScript: USER_SCRIPT_P2PKH,
                        scriptType: USER_SCRIPT_P2PKH_TYPE,
                        lockerLockingScript: LOCKER_TARGET_ADDRESS
                    },
                    RELAYER_FEE,
                    0,
                    {
                        value: requestAmount,
                    }
                )
            ).to.be.revertedWith("EthManagerLogic: wrong value");
        });
    });

    describe("#Handle emergencyWithdraw", async () => {
        //write test that handle emergency withdraw
        it("should handle emergency withdraw token", async () => {
            await inputToken.transfer(EthConnector.address, requestAmount);

            await expect(
                await inputToken.balanceOf(EthConnector.address)
            ).to.be.equal(requestAmount);

            await EthConnector.emergencyWithdraw(
                inputToken.address,
                signer1Address,
                requestAmount
            );

            await expect(
                await inputToken.balanceOf(EthConnector.address)
            ).to.be.equal(0);

            await expect(
                await inputToken.balanceOf(signer1Address)
            ).to.be.equal(requestAmount);
        });

        it("should handle emergency withdraw eth", async () => {
            let tx = {
                to: EthConnector.address,
                value: 100,
            };
            await signer1.sendTransaction(tx);

            let beforeBalance = await signer1.getBalance();
            beforeBalance.add(100);

            await expect(
                await provider.getBalance(EthConnector.address)
            ).to.be.equal(100);

            await EthConnector.emergencyWithdraw(
                "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
                signer1Address,
                100
            );
        });

        // write test that only owner can emergency withdraw
        it("should not handle emergency withdraw if not owner", async () => {
            await expect(
                EthConnector.connect(signer1).emergencyWithdraw(
                    inputToken.address,
                    signer1Address,
                    requestAmount
                )
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });
    });
});
>>>>>>> dev
