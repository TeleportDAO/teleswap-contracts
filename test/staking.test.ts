// // const BitcoinRelay = artifacts.require("BitcoinRelay");
// require('dotenv').config({path:"../../.env"});

// import { assert, expect, use } from "chai";
// import { deployments, ethers } from "hardhat";
// import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";
// import { deployMockContract, MockContract } from "@ethereum-waffle/mock-contract";
// import { Contract } from "@ethersproject/contracts";
// import { Address } from "hardhat-deploy/types";

// import { solidity } from "ethereum-waffle";

// import { isBytesLike } from "ethers/lib/utils";

// import {ERC20} from "../src/types/ERC20";
// import {ERC20__factory} from "../src/types/factories/ERC20__factory";
// import {WrappedToken} from "../src/types/WrappedToken";
// import {WrappedToken__factory} from "../src/types/factories/WrappedToken__factory";
// import {Staking} from "../src/types/Staking";
// import {Staking__factory} from "../src/types/factories/Staking__factory";

// import { advanceBlockWithTime, takeSnapshot, revertProvider } from "./block_utils";
// import { exec } from "child_process";


// describe("Staking", async () => {
//     let snapshotId: any;

//     let deployer: Signer;
//     let signer1: Signer;
//     let signer2: Signer;
//     let deployerAddress: Address;
//     let signer1Address: Address;
//     let signer2Address: Address;

//     let WrappedBTC: WrappedToken;
//     let TeleportDAOToken: ERC20;

//     let staking: Staking;
//     let stakingAddress: Address;

//     let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";
//     let telePortTokenInitialSupply = BigNumber.from(10).pow(18).mul(10000)
//     let ten = BigNumber.from(10).pow(18).mul(10)
//     let oneHundred = BigNumber.from(10).pow(18).mul(100)

//     let name = "InstantPoolToken"
//     let symbol = "IPT"
//     let instantFee = 5 // means 5%

//     before(async () => {

//         [deployer, signer1, signer2] = await ethers.getSigners();
//         deployerAddress = await deployer.getAddress()
//         signer1Address = await signer1.getAddress()
//         signer2Address = await signer2.getAddress()

//         // read block headers from file
//         TeleportDAOToken = await deployTelePortDaoToken()

//     });

//     beforeEach("deploy a new cc exchange router", async () => {
//         snapshotId = await takeSnapshot(signer1.provider);

//         staking = await deployStaking();
//     });

//     afterEach(async () => {
//         await revertProvider(signer1.provider, snapshotId);
//     });


//     const deployStaking = async (
//         _signer?: Signer
//     ): Promise<Staking> => {
//         const stakingFactory = new Staking__factory(
//             _signer || deployer
//         );

//         const staking = await stakingFactory.deploy(
//             TeleportDAOToken.address
//         );

//         return staking;
//     };

//     const deployTelePortDaoToken = async (
//         _signer?: Signer
//     ): Promise<ERC20> => {
//         const erc20Factory = new ERC20__factory(
//             _signer || deployer
//         );

//         const wrappedToken = await erc20Factory.deploy(
//             "WrappedBTC",
//             "TBTC",
//             telePortTokenInitialSupply
//         );

//         return wrappedToken;
//     };


//     describe("#stake", async () => {

//         let theTestMintedAmount = oneHundred

//         it("staking TDT token in the staking contract", async function () {

//             await TeleportDAOToken.transfer(signer1Address, theTestMintedAmount)

//             expect(
//                 await TeleportDAOToken.balanceOf(signer1Address)
//             ).to.equal(theTestMintedAmount)

//             let TeleportDAOTokenSigner1 = await TeleportDAOToken.connect(signer1)

//             let stakingSigner1 = await staking.connect(signer1)

//             await TeleportDAOTokenSigner1.approve(
//                 staking.address,
//                 theTestMintedAmount
//             )

//             expect(
//                 await TeleportDAOToken.allowance(
//                     signer1Address,
//                     staking.address
//                 )
//             ).to.equal(theTestMintedAmount)

//             expect(
//                 await stakingSigner1.stake(
//                     signer1Address,
//                     theTestMintedAmount
//                 )
//             ).to.emit(staking, "Stake")

//             expect(
//                 await staking.stakedAmount(signer1Address)
//             ).to.equal(theTestMintedAmount)

//         })

//     });

//     describe("#unstake", async () => {

//         let theTestMintedAmount = oneHundred

//         it("user tries to un-stake as another user", async function () {

//             await TeleportDAOToken.transfer(signer1Address, theTestMintedAmount)

//             let TeleportDAOTokenSigner1 = await TeleportDAOToken.connect(signer1)

//             let stakingSigner1 = await staking.connect(signer1)

//             await TeleportDAOTokenSigner1.approve(
//                 staking.address,
//                 theTestMintedAmount
//             )

//             await stakingSigner1.stake(
//                 signer1Address,
//                 theTestMintedAmount
//             )

//             await expect(
//                 stakingSigner1.unstake(
//                     signer2Address,
//                     theTestMintedAmount
//                 )
//             ).to.revertedWith("message sender is not correct")
//         })

//         it("user tries to un-stake more the their staking amount", async function () {

//             await TeleportDAOToken.transfer(signer1Address, theTestMintedAmount)

//             let TeleportDAOTokenSigner1 = await TeleportDAOToken.connect(signer1)

//             let stakingSigner1 = await staking.connect(signer1)

//             await TeleportDAOTokenSigner1.approve(
//                 staking.address,
//                 theTestMintedAmount
//             )

//             await stakingSigner1.stake(
//                 signer1Address,
//                 theTestMintedAmount
//             )

//             await expect(
//                 stakingSigner1.unstake(
//                     signer1Address,
//                     theTestMintedAmount.add(10)
//                 )
//             ).to.revertedWith("balance is not enough")
//         })


//         it("user un-stakes successfully", async function () {

//             await TeleportDAOToken.transfer(signer1Address, theTestMintedAmount)

//             let TeleportDAOTokenSigner1 = await TeleportDAOToken.connect(signer1)

//             let stakingSigner1 = await staking.connect(signer1)

//             await TeleportDAOTokenSigner1.approve(
//                 staking.address,
//                 theTestMintedAmount
//             )

//             await stakingSigner1.stake(
//                 signer1Address,
//                 theTestMintedAmount
//             )

//             expect(
//                 await TeleportDAOToken.balanceOf(signer1Address)
//             ).to.equal(0)

//             await expect(
//                 stakingSigner1.unstake(
//                     signer1Address,
//                     theTestMintedAmount
//                 )
//             ).to.emit(staking, "Unstake")

//             expect(
//                 await TeleportDAOToken.balanceOf(signer1Address)
//             ).to.equal(theTestMintedAmount)


//             expect(
//                 await staking.stakedAmount(signer1Address)
//             ).to.equal(0)
//         })

//     });

//     describe("#claimReward", async () => {

//         let theTestMintedAmount = oneHundred

//         it("user tries to claim their reward", async function () {

//             await TeleportDAOToken.transfer(signer1Address, theTestMintedAmount)

//             let TeleportDAOTokenSigner1 = await TeleportDAOToken.connect(signer1)

//             let stakingSigner1 = await staking.connect(signer1)

//             await TeleportDAOTokenSigner1.approve(
//                 staking.address,
//                 theTestMintedAmount
//             )

//             await stakingSigner1.stake(
//                 signer1Address,
//                 theTestMintedAmount
//             )

//             // FIXME: why the reward in all scenarios is 0 ?!
//             await stakingSigner1.claimReward(signer1Address)
//         })

//     });
// });