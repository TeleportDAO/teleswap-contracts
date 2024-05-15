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
