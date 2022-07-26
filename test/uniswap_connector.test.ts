import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "ethers";
import { Signer, BigNumber } from "ethers";

import { UniswapConnector } from "../src/types/UniswapConnector";
import { UniswapConnector__factory } from "../src/types/factories/UniswapConnector__factory";
import { LiquidityPool } from "../src/types/LiquidityPool";
import { LiquidityPool__factory } from "../src/types/factories/LiquidityPool__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";
import { WAVAX } from "../src/types/WAVAX";
import { WAVAX__factory } from "../src/types/factories/WAVAX__factory";

import { takeSnapshot, revertProvider } from "./block_utils";

describe("UniswapConnector", async () => {

    let snapshotId: any;

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let deployerAddress: string;
    let signer1Address: string;

    // Contracts
    let uniswapConnector: UniswapConnector;
    let exchangeRouter: Contract;
    let liquidityPoolAB: LiquidityPool; // non-WETH/non-WETH
    let liquidityPoolCD: LiquidityPool; // non-WETH/WETH
    let liquidityPoolFactory: Contract;
    let liquidityPool__factory: LiquidityPool__factory;
    let erc20: ERC20;
    let _erc20: ERC20;
    let WETH: WAVAX;

    // let liquidityPool__factory: LiquidityPool__factory;

    before(async () => {
        // Sets accounts
        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();
        signer1Address = await signer1.getAddress();

        // Deploys WETH
        const WETHFactory = new WAVAX__factory(deployer);
        WETH = await WETHFactory.deploy(
            'Wrapped-Ethereum',
            'WETH'
        );

        // Deploys liquidityPoolFactory
        const liquidityPoolFactoryFactory = await ethers.getContractFactory("LiquidityPoolFactory");
        liquidityPoolFactory = await liquidityPoolFactoryFactory.deploy(
            deployerAddress
        );

        // Creates liquidityPool__factory object
        liquidityPool__factory = new LiquidityPool__factory(deployer);

        // Deploys exchangeRouter contract
        const exchangeRouterFactory = await ethers.getContractFactory("ExchangeRouter");
        exchangeRouter = await exchangeRouterFactory.deploy(
            liquidityPoolFactory.address,
            WETH.address // WETH
        );

        // Deploys exchangeRouter contract
        const uniswapConnectorFactory = new UniswapConnector__factory(deployer);
        uniswapConnector = await uniswapConnectorFactory.deploy(
            "Uniswap-Connector",
            exchangeRouter.address,
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

    });

    describe("#swap", async () => {
        let oldReserveA: BigNumber;
        let oldReserveB: BigNumber;
        let oldReserveC: BigNumber;
        let oldReserveD: BigNumber;
        let oldDeployerBalanceERC20: BigNumber;
        let oldDeployerBalance_ERC20: BigNumber;
        let oldSigner1BalanceETH: BigNumber;

        beforeEach("Adds liquidity to liquidity pool", async () => {
            // Takes snapshot before adding liquidity
            snapshotId = await takeSnapshot(deployer.provider);

            // Adds liquidity to liquidity pool
            let addedLiquidityA = 10000; // erc20
            let addedLiquidityB = 10000; // _erc20
            let addedLiquidityC = 10000; // erc20
            let addedLiquidityD = 10000; // WETH

            // Adds liquidity for non-WETH/non-WETH pool
            await erc20.approve(exchangeRouter.address, addedLiquidityA);
            await _erc20.approve(exchangeRouter.address, addedLiquidityB);
            await exchangeRouter.addLiquidity(
                erc20.address,
                _erc20.address,
                addedLiquidityA,
                addedLiquidityB,
                0, // Minimum added liquidity for first token
                0, // Minimum added liquidity for second token
                deployerAddress,
                1000000000, // Long deadline
            );
            let liquidityPoolABAddress = await liquidityPoolFactory.getLiquidityPool(
                erc20.address,
                _erc20.address
            );

            // Loads liquidity pool
            liquidityPoolAB = await liquidityPool__factory.attach(liquidityPoolABAddress);

            // Records current reserves of teleBTC and TDT
            if (await liquidityPoolAB.token0() == erc20.address) {
                [oldReserveA, oldReserveB] = await liquidityPoolAB.getReserves();
            } else {
                [oldReserveB, oldReserveA] = await liquidityPoolAB.getReserves()
            }

            // Adds liquidity for non-WETH/WETH pool
            await erc20.approve(exchangeRouter.address, addedLiquidityA);
            
            await exchangeRouter.addLiquidityAVAX(
                erc20.address,
                addedLiquidityC,
                0, // Minimum added liquidity for first token
                0, // Minimum added liquidity for second token
                deployerAddress,
                1000000000, // Long deadline
                {value: addedLiquidityD}
            );
            let liquidityPoolCDAddress = await liquidityPoolFactory.getLiquidityPool(
                erc20.address,
                WETH.address,
            );

            // Loads liquidity pool
            liquidityPoolCD = await liquidityPool__factory.attach(liquidityPoolCDAddress);

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

        afterEach(async () => {
            // Reverts the state to the beginning
            await revertProvider(deployer.provider, snapshotId);
        });

        it("Swaps fixed non-WETH for non-WETH", async function () {

            let inputAmount = 1000;
            let outputAmount = await exchangeRouter.getAmountOut(
                inputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 1000000;
            let isFixedToken = true;
            
            await erc20.approve(uniswapConnector.address, inputAmount);
            await expect(
                uniswapConnector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.emit(uniswapConnector, 'Swap');

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
            let inputAmount = await exchangeRouter.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 1000000;
            let isFixedToken = false;
            
            await erc20.approve(uniswapConnector.address, inputAmount);
            await expect(
                uniswapConnector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.emit(uniswapConnector, 'Swap');

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
            let outputAmount = await exchangeRouter.getAmountOut(
                inputAmount,
                oldReserveC,
                oldReserveD
            );
            let path = [erc20.address, WETH.address];
            let to = signer1Address;
            let deadline = 1000000;
            let isFixedToken = true;
            await erc20.approve(uniswapConnector.address, inputAmount);
            await expect(
                uniswapConnector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.emit(uniswapConnector, 'Swap');

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
            let inputAmount = await exchangeRouter.getAmountIn(
                outputAmount,
                oldReserveC,
                oldReserveD
            );
            let path = [erc20.address, WETH.address];
            let to = signer1Address;
            let deadline = 1000000;
            let isFixedToken = false;
            
            await erc20.approve(uniswapConnector.address, inputAmount);
            await expect(
                uniswapConnector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.emit(uniswapConnector, 'Swap');

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
            let inputAmount = await exchangeRouter.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 1000000;
            let isFixedToken = true;
            
            await erc20.approve(uniswapConnector.address, inputAmount);
            await expect(
                uniswapConnector.swap(
                    inputAmount,
                    outputAmount*2,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.not.emit(uniswapConnector, 'Swap');
        })

        it("Should not exchange since input amount is not enough", async function () {

            let outputAmount = 1000;
            let inputAmount = await exchangeRouter.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 1000000;
            let isFixedToken = false;
            
            await erc20.approve(uniswapConnector.address, inputAmount);
            await expect(
                uniswapConnector.swap(
                    Math.floor(inputAmount.toNumber()/2),
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.not.emit(uniswapConnector, 'Swap');
        })

        it("Should not exchange since deadline has passed", async function () {

            let outputAmount = 1000;
            let inputAmount = await exchangeRouter.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, _erc20.address];
            let to = deployerAddress;
            let deadline = 0;
            let isFixedToken = true;
            
            await erc20.approve(uniswapConnector.address, inputAmount);
            await expect(
                uniswapConnector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.not.emit(uniswapConnector, 'Swap');
        })

        it("Should not exchange since liquidity pool doesn't exist", async function () {

            let outputAmount = 1000;
            let inputAmount = await exchangeRouter.getAmountIn(
                outputAmount,
                oldReserveA,
                oldReserveB
            );
            let path = [erc20.address, deployerAddress];
            let to = deployerAddress;
            let deadline = 0;
            let isFixedToken = true;
            
            await erc20.approve(uniswapConnector.address, inputAmount);
            await expect(
                uniswapConnector.swap(
                    inputAmount,
                    outputAmount,
                    path,
                    to,
                    deadline,
                    isFixedToken
                )
            ).to.not.emit(uniswapConnector, 'Swap');
        })

    });
});
