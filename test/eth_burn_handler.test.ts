const CC_BURN_REQUESTS = require('./test_fixtures/ccBurnRequests.json');
require('dotenv').config({path:"../../.env"});

import { expect } from "chai";
import { deployments, ethers, waffle } from "hardhat";
import { Signer, BigNumber } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Address } from "hardhat-deploy/types";
import { Contract } from "@ethersproject/contracts";

import { TeleBTCLogic } from "../src/types/TeleBTCLogic";
import { TeleBTCLogic__factory } from "../src/types/factories/TeleBTCLogic__factory";
import { TeleBTCProxy } from "../src/types/TeleBTCProxy";
import { TeleBTCProxy__factory } from "../src/types/factories/TeleBTCProxy__factory";
import { ERC20 } from "../src/types/ERC20";
import { Erc20__factory } from "../src/types/factories/Erc20__factory";

import { EthBurnHandlerProxy__factory } from "../src/types/factories/EthBurnHandlerProxy__factory";
import { EthBurnHandlerLogic__factory } from "../src/types/factories/EthBurnHandlerLogic__factory";

import { BurnRouterLib } from "../src/types/BurnRouterLib";
import { BurnRouterLib__factory } from "../src/types/factories/BurnRouterLib__factory";

import { BurnRouterProxy__factory } from "../src/types/factories/BurnRouterProxy__factory";
import { BurnRouterLogic__factory } from "../src/types/factories/BurnRouterLogic__factory";
import { BurnRouterLogicLibraryAddresses } from "../src/types/factories/BurnRouterLogic__factory";

import { takeSnapshot, revertProvider } from "./block_utils";
import { network } from "hardhat"

import Web3 from 'web3'
const abiUtils = new Web3().eth.abi
const web3 = new Web3();
const provider = waffle.provider;

describe("EthBurnHandler", async () => {
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
    let inputTokenSigner1: ERC20;
    let TeleBTCSigner1: TeleBTC;
    let EthBurnHandler: Contract;
    let EthBurnHandlerWithMockedAccross: Contract;
    let burnRouterLib: BurnRouterLib;
    let burnRouter: Contract;

    let exchangeToken: ERC20;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockLockers: MockContract;
    let mockExchangeConnector: MockContract;
    let mockAcross: MockContract;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let oneHundred = BigNumber.from(10).pow(8).mul(100)
    /*
        This one is set so that:
        userRequestedAmount * (1 - lockerFee / 10000 - PROTOCOL_PERCENTAGE_FEE / 10000) - BITCOIN_FEE = 100000000
    */
    let userRequestedAmount = BigNumber.from(100060030);
    let requestAmount = 100
    let telebtcAmount  = 100000000000
    let TRANSFER_DEADLINE = 20
    let PROTOCOL_PERCENTAGE_FEE = 5 // means 0.05%
    let SLASHER_PERCENTAGE_REWARD = 5 // means 0.05%
    let BITCOIN_FEE = 10000 // estimation of Bitcoin transaction fee in Satoshi
    let TREASURY = "0x0000000000000000000000000000000000000002";

    let LOCKER_TARGET_ADDRESS = ONE_ADDRESS;
    let LOCKER1_LOCKING_SCRIPT = '0x76a914748284390f9e263a4b766a75d0633c50426eb87587ac';

    let USER_SCRIPT_P2PKH = "0x12ab8dc588ca9d5787dde7eb29569da63c3a238c";
    let USER_SCRIPT_P2PKH_TYPE = 1; // P2PKH

    let USER_SCRIPT_P2WPKH = "0x751e76e8199196d454941c45d1b3a323f1433bd6";
    let USER_SCRIPT_P2WPKH_TYPE = 3; // P2WPKH

    
    before(async () => {

        [proxyAdmin, deployer, signer1, signer2, acrossSinger] = await ethers.getSigners();
        proxyAdminAddress = await proxyAdmin.getAddress();
        signer1Address = await signer1.getAddress();
        deployerAddress = await deployer.getAddress();
        acrossAddress = await acrossSinger.getAddress();

        // Mocks contracts
    
        const bitcoinRelay = await deployments.getArtifact(
            "IBitcoinRelay"
        );
        mockBitcoinRelay = await deployMockContract(
            deployer,
            bitcoinRelay.abi
        )

        const lockers = await deployments.getArtifact(
            "LockersLogic"
        );
        mockLockers = await deployMockContract(
            deployer,
            lockers.abi
        )

        const across = await deployments.getArtifact(
            "SpokePoolInterface"
        );
        mockAcross = await deployMockContract(
            deployer,
            across.abi
        )

        const exchangeConnector = await deployments.getArtifact(
            "UniswapV2Connector"
        );
        mockExchangeConnector = await deployMockContract(
            deployer,
            exchangeConnector.abi
        )

        // await mockExchangeConnector.mock.ccExchangeAndBurn
        //     .returns(100);

        // mock finalization parameter
        await mockBitcoinRelay.mock.finalizationParameter.returns(5);

        // Deploys contracts
        const teleBTCLogicFactory = new TeleBTCLogic__factory(deployer);
        const teleBTCLogic = await teleBTCLogicFactory.deploy();

        const teleBTCProxyFactory = new TeleBTCProxy__factory(deployer);
        const teleBTCProxy = await teleBTCProxyFactory.deploy(
            teleBTCLogic.address,    
            proxyAdminAddress,
            "0x"
        );
        
        teleBTC = await teleBTCLogic.attach(
            teleBTCProxy.address
        );

        await teleBTC.initialize(
            "TeleportDAO-BTC",
            "teleBTC"
        );

        burnRouter = await deployBurnRouter();
        
        await burnRouter.initialize(
            1,
            mockBitcoinRelay.address,
            mockLockers.address,
            TREASURY,
            teleBTC.address,
            TRANSFER_DEADLINE,
            PROTOCOL_PERCENTAGE_FEE,
            SLASHER_PERCENTAGE_REWARD,
            BITCOIN_FEE
        );
        
        EthBurnHandler = await deployEthBurnHandler();

        await EthBurnHandler.initialize(
            mockLockers.address,
            burnRouter.address,
            acrossAddress,
            acrossAddress,
            137
        );

        EthBurnHandlerWithMockedAccross = await deployEthBurnHandler();

        await EthBurnHandlerWithMockedAccross.initialize(
            mockLockers.address,
            burnRouter.address,
            signer1Address,
            signer1Address,
            137
        );

        // Deploys input token
        const erc20Factory = new Erc20__factory(deployer);
        inputToken = await erc20Factory.deploy(
            "TestToken",
            "TT",
            100000
        );
        inputTokenSigner1 = await inputToken.connect(signer1);

        // Mints TeleBTC for user
        await teleBTC.addMinter(signer1Address)
        TeleBTCSigner1 = await teleBTC.connect(signer1);

        await teleBTC.setMaxMintLimit(oneHundred.mul(2));
        await moveBlocks(2020)

        await TeleBTCSigner1.mint(signer1Address, oneHundred);

        // Sets mock contracts outputs
        let lastSubmittedHeight = 100;
        await setLockersIsLocker(true);
        await setLockersGetLockerTargetAddress();
        await setRelayLastSubmittedHeight(lastSubmittedHeight);
        await setSwap(true, [requestAmount, telebtcAmount])

        let protocolFee = Math.floor(telebtcAmount*PROTOCOL_PERCENTAGE_FEE/10000);
        let burntAmount: number;
        burntAmount = telebtcAmount - BITCOIN_FEE - protocolFee;

        await setLockersBurnReturn(burntAmount);

        // Connects signer1 and signer2 to EthBurnHandler
        // EthBurnHandlerSigner = await EthBurnHandler.connect(signer1);
        // EthBurnHandlerSigner = await EthBurnHandler.connect(signer2);
    });

    async function moveBlocks(amount: number) {
        for (let index = 0; index < amount; index++) {
          await network.provider.request({
            method: "evm_mine",
            params: [],
          })
        }
    }

    const deployTeleBTC = async (
        _signer?: Signer
    ): Promise<TeleBTC> => {
        const teleBTCFactory = new TeleBTC__factory(
            _signer || deployer
        );

        const teleBTC = await teleBTCFactory.deploy(
            "Teleport Wrapped BTC",
            "TeleBTC"
        );

        return teleBTC;
    };

    const parseSignatureToRSV = (signatureHex: string) => {
        // Ensure the hex string starts with '0x'
        if (!signatureHex.startsWith('0x')) {
          throw new Error('Signature must start with 0x')
        }
      
        // Convert the hex string to a Buffer
        const signatureBuffer = Buffer.from(signatureHex.slice(2), 'hex')
      
        // Check the length of the signature (should be 65 bytes)
        if (signatureBuffer.length !== 65) {
          throw new Error('Invalid signature length')
        }
      
        // Extract r, s, and v from the signature
        const r = `0x${signatureBuffer.subarray(0, 32).toString('hex')}`
        const s = `0x${signatureBuffer.subarray(32, 64).toString('hex')}`
        const v = signatureBuffer[64]
      
        return { r, s, v }
      }

    const deployBurnRouterLib = async (
        _signer?: Signer
    ): Promise<BurnRouterLib> => {
        const BurnRouterLibFactory = new BurnRouterLib__factory(
            _signer || deployer
        );

        const burnRouterLib = await BurnRouterLibFactory.deploy(
        );

        return burnRouterLib;
    };

    const deployBurnRouter = async (
        _signer?: Signer
    ): Promise<Contract> => {
        burnRouterLib = await deployBurnRouterLib()
        let linkLibraryAddresses: BurnRouterLogicLibraryAddresses;

        linkLibraryAddresses = {
            "contracts/libraries/BurnRouterLib.sol:BurnRouterLib": burnRouterLib.address,
        };

        // Deploys lockers logic
        const burnRouterLogicFactory = new BurnRouterLogic__factory(
            linkLibraryAddresses,
            _signer || deployer
        );

        const burnRouterLogic = await burnRouterLogicFactory.deploy();

        // Deploys lockers proxy
        const burnRouterProxyFactory = new BurnRouterProxy__factory(
            _signer || deployer
        );
        const burnRouterProxy = await burnRouterProxyFactory.deploy(
            burnRouterLogic.address,
            proxyAdminAddress,
            "0x"
        )

        return await burnRouterLogic.attach(
            burnRouterProxy.address
        );

    };

    const deployEthBurnHandler = async (
        _signer?: Signer
    ): Promise<Contract> => {
        const EthBurnHandlerLogicFactory = new EthBurnHandlerLogic__factory(
            _signer || deployer
        );

        const EthBurnHandlerLogic = await EthBurnHandlerLogicFactory.deploy();

        // Deploys lockers proxy
        const EthBurnHandlerProxyFactory = new EthBurnHandlerProxy__factory(
            _signer || deployer
        );
        const EthBurnHandlerProxy = await EthBurnHandlerProxyFactory.deploy(
            EthBurnHandlerLogic.address,
            proxyAdminAddress,
            "0x"
        )

        return await EthBurnHandlerLogic.attach(
            EthBurnHandlerProxy.address
        );

    };

    async function setLockersSlashIdleLockerReturn(): Promise<void> {
        await mockLockers.mock.slashIdleLocker
            .returns(true);
    }

    async function setLockersSlashThiefLockerReturn(): Promise<void> {
        await mockLockers.mock.slashThiefLocker
            .returns(true);
    }

    async function setLockersIsLocker(isLocker: boolean): Promise<void> {
        await mockLockers.mock.isLocker
            .returns(isLocker);
    }

    async function setLockersGetLockerTargetAddress(): Promise<void> {
        await mockLockers.mock.getLockerTargetAddress
            .returns(LOCKER_TARGET_ADDRESS);
    }

    async function setLockersBurnReturn(burntAmount: number): Promise<void> {
        await mockLockers.mock.burn
            .returns(burntAmount);
    }

    async function setRelayLastSubmittedHeight(blockNumber: number): Promise<void> {
        await mockBitcoinRelay.mock.lastSubmittedHeight.returns(blockNumber);
    }

    async function setRelayCheckTxProofReturn(isFinal: boolean, relayFee?: number): Promise<void> {
        await mockBitcoinRelay.mock.getBlockHeaderFee.returns(relayFee || 0); // Fee of relay
        await mockBitcoinRelay.mock.checkTxProof
            .returns(isFinal);
    }

    async function setSwap(result: boolean, amounts: number[]): Promise<void> {
        await mockExchangeConnector.mock.swap
            .returns(result, amounts);
    }

    async function mintTeleBTCForTest(): Promise<void> {
        let TeleBTCSigner1 = await teleBTC.connect(signer1)
        await TeleBTCSigner1.mint(signer1Address, oneHundred);
    }

    async function sendBurnRequest(
        burnReqBlockNumber: number,
        _userRequestedAmount: BigNumber,
        USER_SCRIPT: any,
        USER_SCRIPT_TYPE: any
    ): Promise<number> {
        // Gives allowance to EthBurnHandler
        await TeleBTCSigner1.approve(
            EthBurnHandler.address,
            _userRequestedAmount
        );

        // Sets mock contracts outputs
        await setRelayLastSubmittedHeight(burnReqBlockNumber);
        await setLockersIsLocker(true);
        let _burntAmount: number;
        let protocolFee = Math.floor(_userRequestedAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
        _burntAmount = _userRequestedAmount.toNumber() - protocolFee;
        await setLockersBurnReturn(_burntAmount);
        let burntAmount = _burntAmount * (_burntAmount - BITCOIN_FEE) / _burntAmount; 
        // first burntAmount should have been
        // burntAmount - lockerFee but in this case we have assumed lockerFee = 0

        await setLockersGetLockerTargetAddress();

        // Burns eleBTC
        await EthBurnHandlerSigner.ccBurn(
            _userRequestedAmount,
            USER_SCRIPT,
            USER_SCRIPT_TYPE,
            LOCKER1_LOCKING_SCRIPT
        );

        return burntAmount;
    }

    async function provideProof(burnReqBlockNumber: number) {

        // Set mocks contracts outputs
        await setRelayCheckTxProofReturn(true);
        await setLockersIsLocker(true);

        let burntAmount: number;
        let protocolFee = Math.floor(userRequestedAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
        burntAmount = userRequestedAmount.toNumber() - BITCOIN_FEE - protocolFee;
        await setLockersBurnReturn(burntAmount);

        await setLockersGetLockerTargetAddress();

        // Provide proof that the locker has paid the burnt amount to the user(s)
        await expect(
            await EthBurnHandlerSigner.burnProof(
                CC_BURN_REQUESTS.burnProof_valid.version,
                CC_BURN_REQUESTS.burnProof_valid.vin,
                CC_BURN_REQUESTS.burnProof_valid.vout,
                CC_BURN_REQUESTS.burnProof_valid.locktime,
                burnReqBlockNumber,
                CC_BURN_REQUESTS.burnProof_valid.intermediateNodes,
                1,
                LOCKER1_LOCKING_SCRIPT,
                [0],
                [0]
            )
        ).to.emit(EthBurnHandler, "PaidCCBurn")
    }

    describe("#setters", async () => {

        beforeEach(async () => {
            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        //write test setEthConnectorProxy and getEthConnectorProxy
        it("should set and get the EthConnectorProxy", async () => {
            await EthBurnHandler.setEthConnectorProxy(mockExchangeConnector.address);
            expect(await EthBurnHandler.ethConnectorProxy()).to.equal(mockExchangeConnector.address);
        });

        //write test setEthConnectorProxy that only owner can change
        it("should not set the EthConnectorProxy if not owner", async () => {
            await expect(EthBurnHandler.connect(signer1).setEthConnectorProxy(mockExchangeConnector.address)).to.be.revertedWith("Ownable: caller is not the owner");
        });

        //write test setLockerProxy and getLockerProxy
        it("should set and get the LockerProxy", async () => {
            await EthBurnHandler.setLockersProxy(mockLockers.address);
            expect(await EthBurnHandler.lockersProxy()).to.equal(mockLockers.address);
        });

        //write test setLockerProxy that only owner can change
        it("should not set the LockerProxy if not owner", async () => {
            await expect(EthBurnHandler.connect(signer1).setLockersProxy(mockLockers.address)).to.be.revertedWith("Ownable: caller is not the owner");
        });

        //write test setBurnRouter and getBurnRouter

        it("should set and get the BurnRouter", async () => {
            await EthBurnHandler.setBurnRouterProxy(burnRouter.address);
            expect(await EthBurnHandler.burnRouterProxy()).to.equal(burnRouter.address);
        });

        //write test setBurnRouter that only owner can change
        it("should not set the BurnRouter if not owner", async () => {
            await expect(EthBurnHandler.connect(signer1).setBurnRouterProxy(burnRouter.address)).to.be.revertedWith("Ownable: caller is not the owner");
        });

        //write test setAcross and getAcross
        it("should set and get the Across", async () => {
            await EthBurnHandler.setAcross(mockAcross.address);
            expect(await EthBurnHandler.across()).to.equal(mockAcross.address);
        });

        //write test setAcross that only owner can change  
        it("should not set the Across if not owner", async () => {
            await expect(EthBurnHandler.connect(signer1).setAcross(mockAcross.address)).to.be.revertedWith("Ownable: caller is not the owner");
        });

        //write test setAcrossV3 and getAcrossV3
        it("should set and get the AcrossV3", async () => {
            await EthBurnHandler.setAcrossV3(mockAcross.address);
            expect(await EthBurnHandler.acrossV3()).to.equal(mockAcross.address);
        });

        //write test setAcrossV3 that only owner can change
        it("should not set the AcrossV3 if not owner", async () => {
            await expect(EthBurnHandler.connect(signer1).setAcrossV3(mockAcross.address)).to.be.revertedWith("Ownable: caller is not the owner");
        });


    });

    describe("#Handle across message", async () => {

        let protocolFee = Math.floor(telebtcAmount*PROTOCOL_PERCENTAGE_FEE/10000);

        beforeEach(async () => {
            // Sends teleBTC to burnRouter (since we mock swap)
            await TeleBTCSigner1.transfer(
                burnRouter.address,
                protocolFee
            );

            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });
        //write test for handle across message that across signer can call
        it("should handle across message", async () => {

            let burntAmount: number;
            burntAmount = telebtcAmount - BITCOIN_FEE - protocolFee;

            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes',
                'uint'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                0
            ])

            await setLockersBurnReturn(burntAmount);
            
            await inputToken.transfer(
                EthBurnHandler.address,
                requestAmount
            );
            
            await expect(
                EthBurnHandler.connect(acrossSinger).handleV3AcrossMessage(
                    inputToken.address,
                    requestAmount,
                    signer1Address,
                    message
                )
            ).to.emit(EthBurnHandler, "NewBurn").withArgs(
                signer1Address,
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                requestAmount,
                inputToken.address,
                LOCKER_TARGET_ADDRESS,
                0
            );
            //TODO with args
        });

        //write test when handle across message that only across signer can call
        it("should not handle across message if not across", async () => {

            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes',
                'uint'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                0
            ])

            await expect(
                EthBurnHandler.connect(signer1).handleV3AcrossMessage(
                    inputToken.address,
                    requestAmount,
                    signer1Address,
                    message
                )
            ).to.be.revertedWith("PolyConnectorLogic: not acrossV3");
        });

         //write test when message exchangeForBtcAcross is equal to test    
        it("should not handle across message if purpose is not exchangeForBtcAcross", async () => {

            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes',
                'uint'
            ], [
                "test",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                0
            ])

            await expect(
                EthBurnHandler.connect(acrossSinger).handleV3AcrossMessage(
                    inputToken.address,
                    requestAmount,
                    signer1Address,
                    message
                )
            ).to.not.emit(EthBurnHandler, "NewBurn");
        });

        //write test that fail if ccExchangeAndBurn fails
        it("should not handle across message if ccExchangeAndBurn fails", async () => {
            await setLockersIsLocker(false);

            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes',
                'uint'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                0
            ])

            await setSwap(false, [requestAmount, telebtcAmount])

            await expect(
                EthBurnHandler.connect(acrossSinger).handleV3AcrossMessage(
                    inputToken.address,
                    requestAmount,
                    signer1Address,
                    message
                )
            ).to.emit(EthBurnHandler, "FailedBurn").withArgs(
                signer1Address,
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                requestAmount,
                inputToken.address
            );
        });
    });

    describe("#Handle Failed CcExchangeAndBurn ", async () => {
        let protocolFee = Math.floor(telebtcAmount*PROTOCOL_PERCENTAGE_FEE/10000);
        beforeEach(async () => {
            // Sends teleBTC to burnRouter (since we mock swap)
            await TeleBTCSigner1.transfer(
                burnRouter.address,
                protocolFee
            );

            snapshotId = await takeSnapshot(signer1.provider);
        });

        afterEach(async () => {
            await revertProvider(signer1.provider, snapshotId);
        });

        it("can re do fail cc exchange", async () => {
            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes',
                'uint'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                0
            ])

            await setSwap(false, [requestAmount, telebtcAmount])

            await EthBurnHandler.connect(acrossSinger).handleV3AcrossMessage(
                inputToken.address,
                requestAmount,
                signer1Address,
                message
            )
        
            await expect(
                await EthBurnHandler.failedReqs(signer1Address, inputToken.address)
            ).to.equal(BigNumber.from(requestAmount))

            await inputToken.transfer(
                EthBurnHandler.address,
                requestAmount
            );

            let reDoMessage = abiUtils.encodeParameters([
                'address',
                'uint256', 
                'address',
                'uint256',
                'bytes',
                'uint',
                'bytes',
                'address[]'
            ], [
                inputToken.address,
                requestAmount,
                mockExchangeConnector.address,
                telebtcAmount,
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                [inputToken.address, teleBTC.address]
            ])

            
            let messageHex = await web3.utils.soliditySha3(
                {
                    type: 'bytes',
                    value: reDoMessage
                }
            )
            if (messageHex != null) {
                // let messageToSign = await web3.utils.soliditySha3(
                //     {
                //         type: 'string',
                //         value: "\x19Ethereum Signed Message:\n32"
                //     },
                //     {
                //         type: 'bytes32',
                //         value: messageHex
                //     }
                // );
                // console.log("message to sign: ", messageToSign)
                let signature
                let rsv
                signature = await signer1.signMessage(ethers.utils.arrayify(messageHex))
                rsv = await parseSignatureToRSV(signature) 
                await setSwap(true, [requestAmount, telebtcAmount])

                await expect(
                    EthBurnHandler.connect(signer1).reDoFailedCcExchangeAndBurn(
                        reDoMessage,
                        rsv.v,
                        rsv.r,
                        rsv.s
                    )
                ).to.emit(EthBurnHandler, "NewBurn").withArgs(
                    signer1Address,
                    USER_SCRIPT_P2PKH,
                    USER_SCRIPT_P2PKH_TYPE,
                    requestAmount,
                    inputToken.address,
                    LOCKER_TARGET_ADDRESS,
                    0
                );

                await expect(
                    await EthBurnHandler.failedReqs(signer1Address, inputToken.address)
                ).to.equal(0)
            }
        
        });

        it("fail re do fail cc exchange because amount is greater than available", async () => {
            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT
            ])

            await setSwap(false, [requestAmount, telebtcAmount])

            await EthBurnHandler.connect(acrossSinger).handleV3AcrossMessage(
                inputToken.address,
                requestAmount,
                signer1Address,
                message
            )

            await inputToken.transfer(
                EthBurnHandler.address,
                requestAmount
            );

            let reDoMessage = abiUtils.encodeParameters([
                'address',
                'uint256', 
                'address',
                'uint256',
                'bytes',
                'uint',
                'bytes',
                'address[]'
            ], [
                inputToken.address,
                requestAmount + 1,
                mockExchangeConnector.address,
                telebtcAmount,
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                [inputToken.address, teleBTC.address]
            ])

            
            let messageHex = await web3.utils.soliditySha3(
                {
                    type: 'bytes',
                    value: reDoMessage
                }
            )
            if (messageHex != null) {
                let signature
                let rsv
                signature = await signer1.signMessage(ethers.utils.arrayify(messageHex))
                rsv = await parseSignatureToRSV(signature) 
                await setSwap(true, [requestAmount, telebtcAmount])

                await expect(
                    EthBurnHandler.connect(signer1).reDoFailedCcExchangeAndBurn(
                        reDoMessage,
                        rsv.v,
                        rsv.r,
                        rsv.s
                    )
                ).to.be.revertedWith("PolygonConnectorLogic: low balance")
            }
        
        });

        it("fail re do fail cc exchange because amount is zero", async () => {
            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT
            ])

            await setSwap(false, [requestAmount, telebtcAmount])

            await EthBurnHandler.connect(acrossSinger).handleV3AcrossMessage(
                inputToken.address,
                requestAmount,
                signer1Address,
                message
            )

            await inputToken.transfer(
                EthBurnHandler.address,
                requestAmount
            );

            let reDoMessage = abiUtils.encodeParameters([
                'address',
                'uint256', 
                'address',
                'uint256',
                'bytes',
                'uint',
                'bytes',
                'address[]'
            ], [
                inputToken.address,
                0,
                mockExchangeConnector.address,
                telebtcAmount,
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                [inputToken.address, teleBTC.address]
            ])

            
            let messageHex = await web3.utils.soliditySha3(
                {
                    type: 'bytes',
                    value: reDoMessage
                }
            )
            if (messageHex != null) {
                let signature
                let rsv
                signature = await signer1.signMessage(ethers.utils.arrayify(messageHex))
                rsv = await parseSignatureToRSV(signature) 
                await setSwap(true, [requestAmount, telebtcAmount])

                await expect(
                    EthBurnHandler.connect(signer1).reDoFailedCcExchangeAndBurn(
                        reDoMessage,
                        rsv.v,
                        rsv.r,
                        rsv.s
                    )
                ).to.be.revertedWith("PolygonConnectorLogic: low balance")
            }
        
        });

        it("can re do fail cc exchange with less than request amount", async () => {
            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT
            ])

            await setSwap(false, [requestAmount, telebtcAmount])

            await EthBurnHandler.connect(acrossSinger).handleV3AcrossMessage(
                inputToken.address,
                requestAmount,
                signer1Address,
                message
            )
        
            await expect(
                await EthBurnHandler.failedReqs(signer1Address, inputToken.address)
            ).to.equal(BigNumber.from(requestAmount))

            await inputToken.transfer(
                EthBurnHandler.address,
                requestAmount
            );

            let reDoMessage = abiUtils.encodeParameters([
                'address',
                'uint256', 
                'address',
                'uint256',
                'bytes',
                'uint',
                'bytes',
                'address[]'
            ], [
                inputToken.address,
                requestAmount - 10,
                mockExchangeConnector.address,
                telebtcAmount,
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT,
                [inputToken.address, teleBTC.address]
            ])

            
            let messageHex = await web3.utils.soliditySha3(
                {
                    type: 'bytes',
                    value: reDoMessage
                }
            )
            if (messageHex != null) {
                // let messageToSign = await web3.utils.soliditySha3(
                //     {
                //         type: 'string',
                //         value: "\x19Ethereum Signed Message:\n32"
                //     },
                //     {
                //         type: 'bytes32',
                //         value: messageHex
                //     }
                // );
                // console.log("message to sign: ", messageToSign)
                let signature
                let rsv
                signature = await signer1.signMessage(ethers.utils.arrayify(messageHex))
                rsv = await parseSignatureToRSV(signature) 
                await setSwap(true, [requestAmount, telebtcAmount])

                await expect(
                    EthBurnHandler.connect(signer1).reDoFailedCcExchangeAndBurn(
                        reDoMessage,
                        rsv.v,
                        rsv.r,
                        rsv.s
                    )
                ).to.emit(EthBurnHandler, "NewBurn").withArgs(
                    signer1Address,
                    USER_SCRIPT_P2PKH,
                    USER_SCRIPT_P2PKH_TYPE,
                    requestAmount - 10,
                    inputToken.address,
                    LOCKER_TARGET_ADDRESS,
                    0
                );

                await expect(
                    await EthBurnHandler.failedReqs(signer1Address, inputToken.address)
                ).to.equal(10)
            }
        });

        // it("can withdraw Funds To Eth", async () => {
        //     let message = abiUtils.encodeParameters([
        //         'string',
        //         'uint',
        //         'address',
        //         'address',
        //         'uint',
        //         'address[]',
        //         'bytes',
        //         'uint',
        //         'bytes'
        //     ], [
        //         "exchangeForBtcAcross",
        //         "1",
        //         signer1Address,
        //         mockExchangeConnector.address,
        //         telebtcAmount,
        //         [inputToken.address, teleBTC.address],
        //         USER_SCRIPT_P2PKH,
        //         USER_SCRIPT_P2PKH_TYPE,
        //         LOCKER1_LOCKING_SCRIPT
        //     ])

        //     await setSwap(false, [requestAmount, telebtcAmount])
        //     await mockAcross.mock.deposit.returns()
        //     await EthBurnHandlerWithMockedAccross.connect(signer1).handleV3AcrossMessage(
        //         inputToken.address,
        //         requestAmount,
        //         signer1Address,
        //         message
        //     )
            
        //     await expect(
        //         await EthBurnHandlerWithMockedAccross.failedReqs(signer1Address, inputToken.address)
        //     ).to.equal(BigNumber.from(requestAmount))

        //     await inputToken.transfer(
        //         EthBurnHandlerWithMockedAccross.address,
        //         requestAmount
        //     );

        //     let reDoMessage = abiUtils.encodeParameters([
        //         'address',
        //         'uint',
        //         'int64'
        //     ], [
        //         inputToken.address,
        //         requestAmount,
        //         1000
        //     ])

            
        //     let messageHex = await web3.utils.soliditySha3(
        //         {
        //             type: 'bytes',
        //             value: reDoMessage
        //         }
        //     )
        //     if (messageHex != null) {
        //         let signature
        //         let rsv
        //         signature = await signer1.signMessage(ethers.utils.arrayify(messageHex))
        //         rsv = await parseSignatureToRSV(signature) 
        //         await setSwap(true, [requestAmount, telebtcAmount])
                
        //         await EthBurnHandlerWithMockedAccross.connect(signer1).withdrawFundsToEth(
        //             reDoMessage,
        //             rsv.v,
        //             rsv.r,
        //             rsv.s
        //         )

        //         await expect(
        //             await EthBurnHandlerWithMockedAccross.failedReqs(signer1Address, inputToken.address)
        //         ).to.equal(0)
        //     }
        
        // });

        it("can't withdraw Funds To Eth if amount is zero", async () => {
            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT
            ])

            await setSwap(false, [requestAmount, telebtcAmount])
            await mockAcross.mock.deposit.returns()
            await EthBurnHandlerWithMockedAccross.connect(signer1).handleV3AcrossMessage(
                inputToken.address,
                requestAmount,
                signer1Address,
                message
            )
            
            await expect(
                await EthBurnHandlerWithMockedAccross.failedReqs(signer1Address, inputToken.address)
            ).to.equal(BigNumber.from(requestAmount))

            await inputToken.transfer(
                EthBurnHandlerWithMockedAccross.address,
                requestAmount
            );

            let reDoMessage = abiUtils.encodeParameters([
                'address',
                'uint',
                'int64'
            ], [
                inputToken.address,
                0,
                1000
            ])

            
            let messageHex = await web3.utils.soliditySha3(
                {
                    type: 'bytes',
                    value: reDoMessage
                }
            )
            if (messageHex != null) {
                let signature
                let rsv
                signature = await signer1.signMessage(ethers.utils.arrayify(messageHex))
                rsv = await parseSignatureToRSV(signature) 
                await setSwap(true, [requestAmount, telebtcAmount])
                
                await expect (
                    EthBurnHandlerWithMockedAccross.connect(signer1).withdrawFundsToEth(
                        reDoMessage,
                        rsv.v,
                        rsv.r,
                        rsv.s
                    )
                ).to.be.revertedWith("PolygonConnectorLogic: low balance")
            }
        
        });

        it("can't withdraw Funds To Eth if amount is greater than user request amount", async () => {
            let message = abiUtils.encodeParameters([
                'string',
                'uint',
                'address',
                'address',
                'uint',
                'address[]',
                'bytes',
                'uint',
                'bytes'
            ], [
                "exchangeForBtcAcross",
                "1",
                signer1Address,
                mockExchangeConnector.address,
                telebtcAmount,
                [inputToken.address, teleBTC.address],
                USER_SCRIPT_P2PKH,
                USER_SCRIPT_P2PKH_TYPE,
                LOCKER1_LOCKING_SCRIPT
            ])

            await setSwap(false, [requestAmount, telebtcAmount])
            await mockAcross.mock.deposit.returns()
            await EthBurnHandlerWithMockedAccross.connect(signer1).handleV3AcrossMessage(
                inputToken.address,
                requestAmount,
                signer1Address,
                message
            )
            
            await expect(
                await EthBurnHandlerWithMockedAccross.failedReqs(signer1Address, inputToken.address)
            ).to.equal(BigNumber.from(requestAmount))

            await inputToken.transfer(
                EthBurnHandlerWithMockedAccross.address,
                requestAmount
            );

            let reDoMessage = abiUtils.encodeParameters([
                'address',
                'uint',
                'int64'
            ], [
                inputToken.address,
                requestAmount + 1,
                1000
            ])

            
            let messageHex = await web3.utils.soliditySha3(
                {
                    type: 'bytes',
                    value: reDoMessage
                }
            )
            if (messageHex != null) {
                let signature
                let rsv
                signature = await signer1.signMessage(ethers.utils.arrayify(messageHex))
                rsv = await parseSignatureToRSV(signature) 
                await setSwap(true, [requestAmount, telebtcAmount])
                
                await expect (
                    EthBurnHandlerWithMockedAccross.connect(signer1).withdrawFundsToEth(
                        reDoMessage,
                        rsv.v,
                        rsv.r,
                        rsv.s
                    )
                ).to.be.revertedWith("PolygonConnectorLogic: low balance")
            }
        
        });

        // it("can withdraw Funds To Eth if amount is less than user request amount", async () => {
        //     let message = abiUtils.encodeParameters([
        //         'string',
        //         'uint',
        //         'address',
        //         'address',
        //         'uint',
        //         'address[]',
        //         'bytes',
        //         'uint',
        //         'bytes'
        //     ], [
        //         "exchangeForBtcAcross",
        //         "1",
        //         signer1Address,
        //         mockExchangeConnector.address,
        //         telebtcAmount,
        //         [inputToken.address, teleBTC.address],
        //         USER_SCRIPT_P2PKH,
        //         USER_SCRIPT_P2PKH_TYPE,
        //         LOCKER1_LOCKING_SCRIPT
        //     ])

        //     await setSwap(false, [requestAmount, telebtcAmount])
        //     await mockAcross.mock.deposit.returns()
        //     await EthBurnHandlerWithMockedAccross.connect(signer1).handleV3AcrossMessage(
        //         inputToken.address,
        //         requestAmount,
        //         signer1Address,
        //         message
        //     )
            
        //     await expect(
        //         await EthBurnHandlerWithMockedAccross.failedReqs(signer1Address, inputToken.address)
        //     ).to.equal(BigNumber.from(requestAmount))

        //     await inputToken.transfer(
        //         EthBurnHandlerWithMockedAccross.address,
        //         requestAmount
        //     );

        //     let reDoMessage = abiUtils.encodeParameters([
        //         'address',
        //         'uint',
        //         'int64'
        //     ], [
        //         inputToken.address,
        //         requestAmount - 10,
        //         1000
        //     ])

            
        //     let messageHex = await web3.utils.soliditySha3(
        //         {
        //             type: 'bytes',
        //             value: reDoMessage
        //         }
        //     )
        //     if (messageHex != null) {
        //         let signature
        //         let rsv
        //         signature = await signer1.signMessage(ethers.utils.arrayify(messageHex))
        //         rsv = await parseSignatureToRSV(signature) 
        //         await setSwap(true, [requestAmount, telebtcAmount])
                
        //         await EthBurnHandlerWithMockedAccross.connect(signer1).withdrawFundsToEth(
        //             reDoMessage,
        //             rsv.v,
        //             rsv.r,
        //             rsv.s
        //         )

        //         await expect(
        //             await EthBurnHandlerWithMockedAccross.failedReqs(signer1Address, inputToken.address)
        //         ).to.equal(10)
        //     }
        // });

    });

    describe("#Handle emergencyWithdraw", async () => {
        //write test that handle emergency withdraw
        it("should handle emergency withdraw token", async () => {
            await inputToken.transfer(
                EthBurnHandler.address,
                requestAmount
            );

            await expect (
                await inputToken.balanceOf(EthBurnHandler.address)
            ).to.be.equal(requestAmount)

            await EthBurnHandler.emergencyWithdraw(
                inputToken.address,
                signer1Address,
                requestAmount
            )

            await expect (
                await inputToken.balanceOf(EthBurnHandler.address)
            ).to.be.equal(0)

            await expect (
                await inputToken.balanceOf(signer1Address)
            ).to.be.equal(requestAmount)

        });

        it("should handle emergency withdraw eth", async () => {
            let tx = {
                to: EthBurnHandler.address,
                value: 100
            };
            await signer1.sendTransaction(tx);

            let beforeBalance = await signer1.getBalance()
            beforeBalance.add(100)

            await expect (
                await provider.getBalance(EthBurnHandler.address)
            ).to.be.equal(100)

            await EthBurnHandler.emergencyWithdraw(
                "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
                signer1Address,
                100
            )

        });

        // write test that only owner can emergency withdraw
        it("should not handle emergency withdraw if not owner", async () => {
            await expect (
                EthBurnHandler.connect(signer1).emergencyWithdraw(
                    inputToken.address,
                    signer1Address,
                    requestAmount
                )
            ).to.be.revertedWith("Ownable: caller is not the owner")
        });
    });

});