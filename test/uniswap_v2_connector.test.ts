import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { Signer, BigNumber } from "ethers";

import { UniswapV2Connector } from "../src/types/UniswapV2Connector";
import { UniswapV2Connector__factory } from "../src/types/factories/UniswapV2Connector__factory";
import { UniswapV2Pair } from "../src/types/UniswapV2Pair";
import { UniswapV2Pair__factory } from "../src/types/factories/UniswapV2Pair__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";
import { WETH } from "../src/types/WETH";
import { WETH__factory } from "../src/types/factories/WETH__factory";

import { takeSnapshot, revertProvider } from "./block_utils";

describe("UniswapV2Connector", async () => {

    let snapshotId: any;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let deployerAddress: string;
    let signer1Address: string;

    // Contracts
    let uniswapV2Connector: UniswapV2Connector;
    let uniswapV2Router02: Contract;
    let liquidityPoolAB: UniswapV2Pair; // non-WETH/non-WETH
    let liquidityPoolCD: UniswapV2Pair; // non-WETH/WETH
    let uniswapV2Factory: Contract;
    let uniswapV2Pair__factory: UniswapV2Pair__factory;
    let erc20: ERC20;
    let _erc20: ERC20;
    let WETH: WETH;

    // Variables
    let oldReserveA: BigNumber;
    let oldReserveB: BigNumber;
    let oldReserveC: BigNumber;
    let oldReserveD: BigNumber;
    let oldDeployerBalanceERC20: BigNumber;
    let oldDeployerBalance_ERC20: BigNumber;
    let oldSigner1BalanceETH: BigNumber;

    before(async () => {
        // Sets accounts
        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();

        // Deploys WETH
        const WETHFactory = new WETH__factory(deployer);
        WETH = await WETHFactory.deploy(
            'Wrapped-Ethereum',
            'WETH'
        );

        // Deploys uniswapV2Factory
        const uniswapV2FactoryFactory = await ethers.getContractFactory("UniswapV2Factory");
        uniswapV2Factory = await uniswapV2FactoryFactory.deploy(
            deployerAddress
        );

        // Creates uniswapV2Pair__factory object
        uniswapV2Pair__factory = new UniswapV2Pair__factory(deployer);

        // Deploys uniswapV2Router02 contract
        const uniswapV2Router02Factory = await ethers.getContractFactory("UniswapV2Router02");
        uniswapV2Router02 = await uniswapV2Router02Factory.deploy(
            uniswapV2Factory.address,
            WETH.address // WETH
        );

        // Deploys exchange connector contract
        const uniswapV2ConnectorFactory = new UniswapV2Connector__factory(deployer);
        uniswapV2Connector = await uniswapV2ConnectorFactory.deploy(
            "Uniswap-Connector",
            uniswapV2Router02.address,
            WETH.address
        );

        // Deploys erc20 token
        const erc20Factory = new ERC20__factory(deployer);
        erc20 = await erc20Factory.deploy(
            "TestToken",
            "TT",
            100000
        );
        _erc20 = await erc20Factory.deploy(
            "AnotherTestToken",
            "ATT",
            100000
        );

        // Adding liquidity to pools

        // Adds liquidity to liquidity pool
        let addedLiquidityA = 10000; // erc20
        let addedLiquidityB = 10000; // _erc20
        let addedLiquidityC = 10000; // erc20
        let addedLiquidityD = 10000; // WETH

        // Adds liquidity for non-WETH/non-WETH pool
        await erc20.approve(uniswapV2Router02.address, addedLiquidityA);
        await _erc20.approve(uniswapV2Router02.address, addedLiquidityB);
        await uniswapV2Router02.addLiquidity(
            erc20.address,
            _erc20.address,
            addedLiquidityA,
            addedLiquidityB,
            0, // Minimum added liquidity for first token
            0, // Minimum added liquidity for second token
            deployerAddress,
            10000000000000, // Long deadline
        );
        let liquidityPoolABAddress = await uniswapV2Factory.getPair(
            erc20.address,
            _erc20.address
        );

        // Loads liquidity pool
        liquidityPoolAB = await uniswapV2Pair__factory.attach(liquidityPoolABAddress);

        // Records current reserves of teleBTC and TDT
        if (await liquidityPoolAB.token0() == erc20.address) {
            [oldReserveA, oldReserveB] = await liquidityPoolAB.getReserves();
        } else {
            [oldReserveB, oldReserveA] = await liquidityPoolAB.getReserves()
        }

        // Adds liquidity for non-WETH/WETH pool
        await erc20.approve(uniswapV2Router02.address, addedLiquidityA);

        await uniswapV2Router02.addLiquidityETH(
            erc20.address,
            addedLiquidityC,
            0, // Minimum added liquidity for first token
            0, // Minimum added liquidity for second token
            deployerAddress,
            10000000000000, // Long deadline
            {value: addedLiquidityD}
        );
        let liquidityPoolCDAddress = await uniswapV2Factory.getPair(
            erc20.address,
            WETH.address,
        );

        // Loads liquidity pool
        liquidityPoolCD = await uniswapV2Pair__factory.attach(liquidityPoolCDAddress);

        // Records current reserves of teleBTC and TDT
        if (await liquidityPoolCD.token0() == erc20.address) {
            [oldReserveC, oldReserveD] = await liquidityPoolCD.getReserves();
        } else {
            [oldReserveD, oldReserveC] = await liquidityPoolCD.getReserves()
        }

        // Records current tokens balances of deployer
        oldDeployerBalanceERC20 = await erc20.balanceOf(deployerAddress);
        oldDeployerBalance_ERC20 = await _erc20.balanceOf(deployerAddress);
        oldSigner1BalanceETH = await signer1.getBalance();

    });

    describe("#getInputAmount", async () => {

        it("Finds needed input amount", async function () {
            let outputAmount = 1000;
            let inputAmount = await uniswapV2Router02.getAmountIn(
                outputAmount,
                oldReserveC,
                oldReserveD
            );

            await expect(
                uniswapV2Connector.getInputAmount(
                    outputAmount,
                    erc20.address,
                    _erc20.address
                )
            ).to.not.reverted;
        })

        it("Returns false since liquidity pool does not exist", async function () {
            let outputAmount = 1000;

            await expect(
                uniswapV2Connector.getInputAmount(
                    outputAmount,
                    deployerAddress,
                    _erc20.address
                )
            ).to.not.reverted;
        })
    });

    describe("#getOutputAmount", async () => {

        it("Finds output amount", async function () {
            let inputAmount = 1000;
            let outputAmount = await uniswapV2Router02.getAmountOut(
                inputAmount,
                oldReserveC,
                oldReserveD
            );

            await expect(
                uniswapV2Connector.getOutputAmount(
                    inputAmount,
                    erc20.address,
                    _erc20.address
                )
            ).to.not.reverted;
        })

        it("Returns false since liquidity pool does not exist", async function () {
            let inputAmount = 1000;

            await expect(
                uniswapV2Connector.getInputAmount(
                    inputAmount,
                    deployerAddress,
                    _erc20.address
                )
            ).to.not.reverted;
        })
    });

    describe("#swap", async () => {

        beforeEach("Adds liquidity to liquidity pool", async () => {
            // Takes snapshot before adding liquidity
            snapshotId = await takeSnapshot(deployer.provider);
        });

        afterEach(async () => {
            // Reverts the state to the beginning
            await revertProvider(deployer.provider, snapshotId);
        });

        it("Swaps fixed non-WETH for non-WETH", async function () {

            let inputAmount = 1000;
            let outputAmount = await uniswapV2Router02.getAmountOut(
                inputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 10000000000000;
            let isFixedToken = true;

            await erc20.approve(uniswapV2Connector.address, inputAmount);
            await expect(
                uniswapV2Connector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.emit(uniswapV2Connector, 'Swap');

            // Records new balances of deployer
            let newDeployerBalanceA = await erc20.balanceOf(deployerAddress);
            let newDeployerBalanceB = await _erc20.balanceOf(deployerAddress);

            // Checks deployer's tokens balances
            expect(newDeployerBalanceA.toNumber()).to.equal(
                oldDeployerBalanceERC20.toNumber() - inputAmount
            );
            expect(newDeployerBalanceB).to.equal(
                oldDeployerBalance_ERC20.add(outputAmount)
            );
        })

        it("Swaps non-WETH for fixed non-WETH", async function () {

            let outputAmount = 1000;
            let inputAmount = await uniswapV2Router02.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 10000000000000;
            let isFixedToken = false;

            await erc20.approve(uniswapV2Connector.address, inputAmount);
            await expect(
                uniswapV2Connector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.emit(uniswapV2Connector, 'Swap');

            // Records new balances of deployer
            let newDeployerBalanceA = await erc20.balanceOf(deployerAddress);
            let newDeployerBalanceB = await _erc20.balanceOf(deployerAddress);

            // Checks deployer's tokens balances
            expect(newDeployerBalanceA.toNumber()).to.equal(
                oldDeployerBalanceERC20.toNumber() - inputAmount.toNumber()
            );
            expect(newDeployerBalanceB).to.equal(
                oldDeployerBalance_ERC20.add(outputAmount)
            );
        })

        it("Swaps fixed non-WETH for WETH", async function () {

            let inputAmount = 1000;
            let outputAmount = await uniswapV2Router02.getAmountOut(
                inputAmount,
                oldReserveC,
                oldReserveD
            );
            let path = [erc20.address, WETH.address];
            let to = signer1Address;
            let deadline = 10000000000000;
            let isFixedToken = true;
            await erc20.approve(uniswapV2Connector.address, inputAmount);
            await expect(
                uniswapV2Connector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.emit(uniswapV2Connector, 'Swap');

            // Records new balances of deployer
            let newDeployerBalanceC = await erc20.balanceOf(deployerAddress);
            let newSigner1BalanceETH = await signer1.getBalance();

            // Checks deployer's tokens balances
            expect(newDeployerBalanceC.toNumber()).to.equal(
                oldDeployerBalanceERC20.toNumber() - inputAmount
            );
            expect(newSigner1BalanceETH).to.equal(
                oldSigner1BalanceETH.add(outputAmount)
            );
        })

        it("Swaps non-WETH for fixed WETH", async function () {

            let outputAmount = 1000;
            let inputAmount = await uniswapV2Router02.getAmountIn(
                outputAmount,
                oldReserveC,
                oldReserveD
            );
            let path = [erc20.address, WETH.address];
            let to = signer1Address;
            let deadline = 10000000000000;
            let isFixedToken = false;

            await erc20.approve(uniswapV2Connector.address, inputAmount);
            await expect(
                uniswapV2Connector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.emit(uniswapV2Connector, 'Swap');

            // Records new balances of deployer
            let newDeployerBalanceC = await erc20.balanceOf(deployerAddress);
            let newSigner1BalanceETH = await signer1.getBalance();

            // Checks deployer's tokens balances
            expect(newDeployerBalanceC.toNumber()).to.equal(
                oldDeployerBalanceERC20.toNumber() - inputAmount.toNumber()
            );
            expect(newSigner1BalanceETH).to.equal(
                oldSigner1BalanceETH.add(outputAmount)
            );
        })

        it("Should not exchange since expected output amount is high", async function () {

            let outputAmount = 1000;
            let inputAmount = await uniswapV2Router02.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 10000000000000;
            let isFixedToken = true;

            await erc20.approve(uniswapV2Connector.address, inputAmount);
            await expect(
                uniswapV2Connector.swap(
                    inputAmount,
                    outputAmount*2,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.not.emit(uniswapV2Connector, 'Swap');
        })

        it("Should not exchange since input amount is not enough", async function () {

            let outputAmount = 1000;
            let inputAmount = await uniswapV2Router02.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 10000000000000;
            let isFixedToken = false;

            await erc20.approve(uniswapV2Connector.address, inputAmount);
            await expect(
                uniswapV2Connector.swap(
                    Math.floor(inputAmount.toNumber()/2),
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.not.emit(uniswapV2Connector, 'Swap');
        })

        it("Should not exchange since deadline has passed", async function () {

            let outputAmount = 1000;
            let inputAmount = await uniswapV2Router02.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 0;
            let isFixedToken = true;

            await erc20.approve(uniswapV2Connector.address, inputAmount);
            await expect(
                uniswapV2Connector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.not.emit(uniswapV2Connector, 'Swap');
        })

        it("Should not exchange since liquidity pool doesn't exist", async function () {

            let outputAmount = 1000;
            let inputAmount = await uniswapV2Router02.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, deployerAddress];
            let to = deployerAddress;
            let deadline = 0;
            let isFixedToken = true;

            await erc20.approve(uniswapV2Connector.address, inputAmount);
            await expect(
                uniswapV2Connector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.not.emit(uniswapV2Connector, 'Swap');
        })

    });
});
