require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
import { Address } from "hardhat-deploy/types";

import {TeleBTC} from "../src/types/TeleBTC";
import {TeleBTC__factory} from "../src/types/factories/TeleBTC__factory";
import {CCBurnRouter} from "../src/types/CCBurnRouter";
import {CCBurnRouter__factory} from "../src/types/factories/CCBurnRouter__factory";

import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";

describe("CCBurnRouter", async () => {
    let snapshotId: any;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let signer2: Signer;
    let deployerAddress: Address;
    let signer1Address: Address;
    let signer2Address: Address;

    // Contracts
    let teleBTC: TeleBTC;
    let ccBurnRouter: CCBurnRouter;

    // Mock contracts
    let mockBitcoinRelay: MockContract;
    let mockLockers: MockContract;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
    let ONE_ADDRESS = "0x0000000000000000000000000000000000000011";
    let ten = BigNumber.from(10).pow(8).mul(10)
    let oneHundred = BigNumber.from(10).pow(8).mul(100)
    /*
        This one is set so that:
        userRequestAmount * (1 - lockerFee / 10000 - PROTOCOL_PERCENTAGE_FEE / 10000) - BITCOIN_FEE = 100000000
    */
    let userRequestAmount = BigNumber.from(100060030);
    let TRANSFER_DEADLINE = 20
    let PROTOCOL_PERCENTAGE_FEE = 5 // means 0.05%
    let SLASHER_PERCENTAGE_REWARD = 5 // means 0.05%
    let BITCOIN_FEE = 10000 // estimation of Bitcoin transaction fee in Satoshi

    let btcPublicKey = "03789ed0bb717d88f7d321a368d905e7430207ebbd82bd342cf11ae157a7ace5fd"
    let btcAddress = "mmPPsxXdtqgHFrxZdtFCtkwhHynGTiTsVh"
    let userPubKeyHash = "0x4062c8aeed4f81c2d73ff854a2957021191e20b6"
    let btcSegwitDecodedAddress = "0x751e76e8199196d454941c45d1b3a323f1433bd6"

    // A user sends tokens to the locker
    let btcUserVersion =  "0x02000000"
    let btcUserVin = "0x01df4a990ad3c3a225862465bb660f06d445914a038ada819ace235afb9f23cff30200000000feffffff"
    let btcUserVout = "0x0200e1f505000000001976a9144062c8aeed4f81c2d73ff854a2957021191e20b688ac984f42060100000016001447ef833107e0ad9998f8711813075ac62ec1104b"
    let btcUserLocktime = "0x00000000"
    let btcUserInterMediateNodes = "0x7451e7cd7a5afcd93d5a3f84e4d7976fb3bd771dc6aeab416d818ea1d72c0476"

    // The locker sends tokens to another wallet
    let btcLockerVersion =  "0x02000000"
    let btcLockerVin = "0x017b1eabe0209b1fe794124575ef807057c77ada2138ae4fa8d6c4de0398a14f3f000000004241044d05240cfbd8a2786eda9dadd520c1609b8593ff8641018d57703d02ba687cf2f187f0cee2221c3afb1b5ff7888caced2423916b61444666ca1216f26181398cffffffff"
    let btcLockerVout = "0x0200e1f505000000001976a9144062c8aeed4f81c2d73ff854a2957021191e20b688ac984f42060100000016001447ef833107e0ad9998f8711813075ac62ec1104b"
    let btcLockerLocktime = "0x00000000"
    let btcLockerInterMediateNodes = "0x7451e7cd7a5afcd93d5a3f84e4d7976fb3bd771dc6aeab416d818ea1d72c0476"
    let lockerRedeemScript = "0x044d05240cfbd8a2786eda9dadd520c1609b8593ff8641018d57703d02ba687cf2f187f0cee2221c3afb1b5ff7888caced2423916b61444666ca1216f26181398c"

    before(async () => {

        [deployer, signer1, signer2] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress()
        signer1Address = await signer1.getAddress()
        signer2Address = await signer2.getAddress()

        // read block headers from file

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

        ccBurnRouter = await deployCCBurnRouter();

        teleBTC = await deployTeleBTC()

        await ccBurnRouter.setTeleBTC(teleBTC.address)

        // await teleBTC.setCCBurnRouter(ccBurnRouter.address)
    });

    beforeEach("deploy a new cc exchange router", async () => {
        snapshotId = await takeSnapshot(signer1.provider);
    });

    afterEach(async () => {
        await revertProvider(signer1.provider, snapshotId);
    });

    const deployTeleBTC = async (
        _signer?: Signer
    ): Promise<TeleBTC> => {
        const teleBTCFactory = new TeleBTC__factory(
            _signer || deployer
        );

        const teleBTC = await teleBTCFactory.deploy(
            "Teleport Wrapped BTC",
            "TeleBTC",
            // ONE_ADDRESS,
            // ONE_ADDRESS,
            // ccBurnRouter.address
        );

        return teleBTC;
    };

    const deployCCBurnRouter = async (
        _signer?: Signer
    ): Promise<CCBurnRouter> => {
        const ccBurnRouterFactory = new CCBurnRouter__factory(
            _signer || deployer
        );


        const ccBurnRouter = await ccBurnRouterFactory.deploy(
            mockBitcoinRelay.address,
            mockLockers.address,
            ONE_ADDRESS,
            TRANSFER_DEADLINE,
            PROTOCOL_PERCENTAGE_FEE,
            SLASHER_PERCENTAGE_REWARD,
            BITCOIN_FEE
        );

        return ccBurnRouter;
    };

    async function setLockersReturn(): Promise<void> {
        // await mockLockers.mock.redeemScriptHash
        //     .returns(ONE_ADDRESS);
    }

    async function setLockersSlashLockerReturn(): Promise<void> {
        await mockLockers.mock.slashLocker
            .returns(true);
    }

    async function setLockersIsLockerReturn(isLocker: boolean): Promise<void> {
        await mockLockers.mock.isLocker
            .returns(isLocker);
    }

    async function setLockersGetLockerRedeemScriptReturn(lockerRedeemScript: string): Promise<void> {
        await mockLockers.mock.getLockerRedeemScript
            .returns(lockerRedeemScript);
    }

    async function setLockersGetLockerTargetAddressReturn(lockerTargetAddress: string): Promise<void> {
        await mockLockers.mock.getLockerTargetAddress
            .returns(lockerTargetAddress);
    }

    async function setLockersBurnReturn(burntAmount: number): Promise<void> {
        await mockLockers.mock.burn
            .returns(burntAmount);
    }

    async function setRelayLastSubmittedHeightReturn(theBlockNumber: BigNumber): Promise<void> {
        await mockBitcoinRelay.mock.lastSubmittedHeight
            .returns(theBlockNumber);
    }

    async function setRelayCheckTxProofReturn(isFinal: boolean): Promise<void> {
        await mockBitcoinRelay.mock.getBlockHeaderFee.returns(0); // Fee of relay
        await mockBitcoinRelay.mock.checkTxProof
            .returns(isFinal);
    }

    async function mintTeleBTCForTest(): Promise<void> {
        let TeleBTCSigner1 = await teleBTC.connect(signer1)
        await TeleBTCSigner1.mintTestToken();
    }

    async function sendBurnRequest(theBlockNumber: BigNumber, _userRequestAmount: BigNumber): Promise<void> {
        // Give the allowance to ccBurnRouter contract to burn
        let TeleBTCSigner1 = await teleBTC.connect(signer1)
        await TeleBTCSigner1.approve(
            ccBurnRouter.address,
            _userRequestAmount
        )

        expect(
            await teleBTC.allowance(signer1Address, ccBurnRouter.address)
        ).to.equal(_userRequestAmount)

        let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

        // Set mock contracts outputs
        await setRelayLastSubmittedHeightReturn(theBlockNumber);
        await setLockersIsLockerReturn(true);
        await setLockersReturn();

        let burntAmount: number;
        let protocolFee = Math.floor(_userRequestAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
        burntAmount = _userRequestAmount.toNumber() - BITCOIN_FEE - protocolFee;
        await setLockersBurnReturn(burntAmount);
        await setLockersReturn();

        let lockerTargetAddress = ONE_ADDRESS
        await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

        // Burn some test tokens using ccBurn
        await expect(
            ccBurnRouterSigner1.ccBurn(
                _userRequestAmount,
                userPubKeyHash,
                true,
                false,
                userPubKeyHash
            )
        ).to.emit(ccBurnRouter, "CCBurn")
    }

    async function provideProof(theBlockNumber: BigNumber) {
        let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)
        await setLockersReturn();

        // Get the locker target address
        // let lockerTargetAddress = await mockLockers.redeemScriptHash();
        let lockerTargetAddress = ONE_ADDRESS

        // Set mock contracts outputs
        await setRelayCheckTxProofReturn(true);
        await setLockersIsLockerReturn(true);

        let burntAmount: number;
        let protocolFee = Math.floor(userRequestAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
        burntAmount = userRequestAmount.toNumber() - BITCOIN_FEE - protocolFee;
        await setLockersBurnReturn(burntAmount);
        await setLockersReturn();

        await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

        // Provide proof that the locker has paid the burnt amount to the user(s)
        await expect(
            ccBurnRouterSigner2.burnProof(
                btcUserVersion,
                btcUserVin,
                btcUserVout,
                btcUserLocktime,
                theBlockNumber,
                btcUserInterMediateNodes,
                1,
                lockerTargetAddress,
                0,
                0
            )
        ).to.emit(ccBurnRouter, "PaidCCBurn")
    }

    describe("#ccBurn", async () => {

        it("burning TeleBTC by ccBurn function (is script hash and non-segwit)", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await TeleBTCSigner1.mintTestToken()

            expect(
                await TeleBTCSigner1.balanceOf(signer1Address)
            ).to.equal(oneHundred)

            // Give the allowance to the ccBurnRouter so that it could burn tokens
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                userRequestAmount
            )

            expect(
                await teleBTC.allowance(signer1Address, ccBurnRouter.address)
            ).to.equal(userRequestAmount)

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(theBlockNumber);
            await setLockersIsLockerReturn(true);

            let burntAmount: number;
            let protocolFee = Math.floor(userRequestAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
            burntAmount = userRequestAmount.toNumber() - BITCOIN_FEE - protocolFee;
            await setLockersBurnReturn(burntAmount);
            await setLockersReturn();

            let lockerTargetAddress = ONE_ADDRESS
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);


            // let totalSupplyBefore = await TeleBTCSigner1.totalSupply();

            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    userRequestAmount,
                    userPubKeyHash,
                    true,
                    false,
                    userPubKeyHash
                )
            ).to.emit(ccBurnRouter, "CCBurn")

            // let totalSupplyAfter = await TeleBTCSigner1.totalSupply();

            // Get the burn request that has been saved in the contract
            let theBurnRequest = await ccBurnRouter.burnRequests(lockerTargetAddress, 0);

            expect(
                theBurnRequest.amount
            ).to.equal(userRequestAmount)
            // // Difference of total supply of tokens should be user input amount minus fees
            // expect(
            //     totalSupplyBefore.sub(totalSupplyAfter)
            // ).to.equal(theBurnRequest.remainedAmount);

        })

        // it("ccBurn function works if user Bitcoin address is script hash and is segwit", async function () {
        // })

        it("ccBurn function works if user Bitcoin address is not script hash and is segwit", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Give the allowance to the ccBurnRouter so that it could burn tokens
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                userRequestAmount
            )

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(theBlockNumber);
            await setLockersIsLockerReturn(true);

            let burntAmount: number;
            let protocolFee = Math.floor(userRequestAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
            burntAmount = userRequestAmount.toNumber() - BITCOIN_FEE - protocolFee;
            await setLockersBurnReturn(burntAmount);
            await setLockersReturn();

            let lockerTargetAddress = ONE_ADDRESS
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            // let totalSupplyBefore = await TeleBTCSigner1.totalSupply();

            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    userRequestAmount,
                    btcSegwitDecodedAddress,
                    true,
                    true,
                    userPubKeyHash
                )
            ).to.emit(ccBurnRouter, "CCBurn")

            // let totalSupplyAfter = await TeleBTCSigner1.totalSupply();

            // Get the burn request that has been saved in the contract
            let theBurnRequest = await ccBurnRouter.burnRequests(lockerTargetAddress, 0);

            expect(
                theBurnRequest.amount
            ).to.equal(userRequestAmount)
            // // Difference of total supply of tokens should be user input amount minus fees
            // expect(
            //     totalSupplyBefore.sub(totalSupplyAfter)
            // ).to.equal(theBurnRequest.remainedAmount);
        })

        it("ccBurn function reverts if enough allowance is not given", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Give the allowance to the ccBurnRouter so that it could burn tokens
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                userRequestAmount.div(2)
            )

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(theBlockNumber);
            await setLockersIsLockerReturn(true);

            let burntAmount: number;
            let protocolFee = Math.floor(userRequestAmount.toNumber()*PROTOCOL_PERCENTAGE_FEE/10000);
            burntAmount = userRequestAmount.toNumber() - BITCOIN_FEE - protocolFee;
            await setLockersBurnReturn(burntAmount);
            await setLockersReturn();

            let lockerTargetAddress = ONE_ADDRESS
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    userRequestAmount,
                    userPubKeyHash,
                    true,
                    false,
                    userPubKeyHash
                )
            ).to.revertedWith("ERC20: transfer amount exceeds allowance")
        })

        it("ccBurn function reverts if input locker address is not a valid locker", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            let TeleBTCSigner1 = await teleBTC.connect(signer1)

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Give the allowance to the ccBurnRouter so that it could burn tokens
            await TeleBTCSigner1.approve(
                ccBurnRouter.address,
                userRequestAmount
            )

            let ccBurnRouterSigner1 = await ccBurnRouter.connect(signer1)

            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(theBlockNumber);
            await setLockersReturn();
            await setLockersIsLockerReturn(false);
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            // Burn some test tokens using ccBurn
            await expect(
                ccBurnRouterSigner1.ccBurn(
                    userRequestAmount,
                    userPubKeyHash,
                    true,
                    false,
                    userPubKeyHash
                )
            ).to.revertedWith("CCBurnRouter: locker address is not valid")
        })

    });

    describe("#burnProof", async () => {

        it("Providing the btc transfer proof by burnProof function", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, userRequestAmount);

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLockerReturn(true);
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcUserVersion,
                    btcUserVin,
                    btcUserVout,
                    btcUserLocktime,
                    theBlockNumber.add(5),
                    btcUserInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    0,
                    0
                )
            ).to.emit(ccBurnRouter, "PaidCCBurn")
        })

        it("Reverts if index range is not correct (wrong start or end index)", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, userRequestAmount);

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLockerReturn(true);
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            // Should revert
            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcUserVersion,
                    btcUserVin,
                    btcUserVout,
                    btcUserLocktime,
                    theBlockNumber.add(5),
                    btcUserInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    1,
                    0
                )
            ).to.revertedWith("CCBurnRouter: burnProof wrong index input")

            // Should revert with a wrong end index
            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcUserVersion,
                    btcUserVin,
                    btcUserVout,
                    btcUserLocktime,
                    theBlockNumber.add(5),
                    btcUserInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    0,
                    1
                )
            ).to.revertedWith("CCBurnRouter: burnProof wrong index input")
        })

        it("Reverts if locker is not valid", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, userRequestAmount);

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLockerReturn(false);
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            // Should revert
            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcUserVersion,
                    btcUserVin,
                    btcUserVout,
                    btcUserLocktime,
                    theBlockNumber.add(5),
                    btcUserInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    0,
                    0
                )
            ).to.revertedWith("CCBurnRouter: locker address is not valid")
        })

        it("Reverts if locker's tx has not been finalized on relay", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, userRequestAmount);

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(false);
            await setLockersIsLockerReturn(true);
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            // Should revert
            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcUserVersion,
                    btcUserVin,
                    btcUserVout,
                    btcUserLocktime,
                    theBlockNumber.add(5),
                    btcUserInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    0,
                    0
                )
            ).to.revertedWith("CCBurnRouter: transaction has not finalized yet");
        })

        it("Reverts if provided tx doesn't exist", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, userRequestAmount);

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLockerReturn(true);
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            // Should revert with a wrong start index
            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcUserVersion,
                    btcUserVin,
                    "0000",
                    btcUserLocktime,
                    theBlockNumber.add(5),
                    btcUserInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    0,
                    0
                )
            ).to.reverted
        })

        it("Doesn't accept proof if the paid amount is not exact", async function () {
            let wrongUserRequestAmount = BigNumber.from(100080000)
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, wrongUserRequestAmount);

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLockerReturn(true);
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);

            // Should revert with a wrong start index
            await expect(
                ccBurnRouterSigner2.burnProof(
                    btcUserVersion,
                    btcUserVin,
                    btcUserVout,
                    btcUserLocktime,
                    theBlockNumber.add(5),
                    btcUserInterMediateNodes,
                    1,
                    lockerTargetAddress,
                    0,
                    0
                )
            ).to.not.emit(ccBurnRouter, "PaidCCBurn");
        })
    });

    describe("#disputeBurn", async () => {

        it("Couldn't disputeBurn since lockers have paid before hand", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, userRequestAmount);

            // Locker pays the burnt amount and provides proof
            await provideProof(theBlockNumber.add(5));

            // Set mock contracts outputs
            await setRelayLastSubmittedHeightReturn(theBlockNumber);
            await setLockersIsLockerReturn(true);
            await setLockersSlashLockerReturn();

            // Locker will not get slashed because it has paid the burnt amount to the user
            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    lockerTargetAddress,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: request has been paid before")
        })

        it("Reverts when deadline hasn't reached", async function () {
            let thisBlockNumber = BigNumber.from(await signer1.provider?.getBlockNumber())

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(thisBlockNumber.add(5), userRequestAmount);

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setLockersIsLockerReturn(true);

            // Locker will not get slashed because the deadline of transfer has not reached
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    lockerTargetAddress,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: payback deadline has not passed yet")
        })

        it("Reverts if the locker is not valid", async function () {
            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(theBlockNumber, userRequestAmount);

            // Locker pays the burnt amount and provides proof
            await provideProof(theBlockNumber.add(5));

            // Set mock contracts outputs
            await setLockersIsLockerReturn(false);

            // Reverts cuz locker address was not valid
            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)
            await expect(
                ccBurnRouterSigner2.disputeBurn(
                    lockerTargetAddress,
                    [0]
                )
            ).to.revertedWith("CCBurnRouter: locker address is not valid")
        })

        it("Otherwise goes through", async function () {
            let thisBlockNumber = BigNumber.from(await signer1.provider?.getBlockNumber())

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            // Mint TeleBTC for test
            await mintTeleBTCForTest();

            // Send a burn request
            await sendBurnRequest(thisBlockNumber, userRequestAmount);

            // Set the last height for relay so that it shows the deadline has passed
            await setRelayLastSubmittedHeightReturn(thisBlockNumber.add(23));
            await setLockersSlashLockerReturn();

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setLockersIsLockerReturn(true);

            // Locker will not get slashed because the deadline of transfer has not reached
            expect(
                await ccBurnRouterSigner2.disputeBurn(
                    lockerTargetAddress,
                    [0]
                )
            );
        })

    });

    describe("#disputeLocker", async () => {

        it("Dispute the locker who has spent its BTC (without getting a burn request)", async function () {

            let thisBlockNumber = await signer1.provider?.getBlockNumber()
            let theBlockNumber = BigNumber.from(thisBlockNumber).sub(5)

            // Find the locker target address
            await setLockersReturn();
            // let lockerTargetAddress = await mockLockers.redeemScriptHash();
            let lockerTargetAddress = ONE_ADDRESS

            let ccBurnRouterSigner2 = await ccBurnRouter.connect(signer2)

            // Set mock contracts outputs
            await setRelayCheckTxProofReturn(true);
            await setLockersIsLockerReturn(true);
            await setLockersGetLockerRedeemScriptReturn(lockerRedeemScript);
            await setRelayLastSubmittedHeightReturn(theBlockNumber.add(30));
            await setLockersGetLockerTargetAddressReturn(lockerTargetAddress);
            await setLockersSlashLockerReturn();

            await expect(
                ccBurnRouterSigner2.disputeLocker(
                    lockerTargetAddress,
                    0,
                    btcLockerVersion,
                    btcLockerVin,
                    btcLockerVout,
                    btcLockerLocktime,
                    theBlockNumber,
                    btcLockerInterMediateNodes,
                    1
                )
            ).to.emit(ccBurnRouter, "LockerDispute")
        })
    });
});