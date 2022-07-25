require('dotenv').config({path:"../../.env"});

import { assert, expect, use } from "chai";
import { deployments, ethers } from "hardhat";
import { Signer, BigNumber, BigNumberish, BytesLike } from "ethers";

import { UniswapConnector } from "../src/types/UniswapConnector";
import { UniswapConnector__factory } from "../src/types/factories/UniswapConnector__factory";
import { LiquidityPool } from "../src/types/LiquidityPool";
import { LiquidityPool__factory } from "../src/types/factories/LiquidityPool__factory";
import { LiquidityPoolFactory } from "../src/types/LiquidityPoolFactory";
import { LiquidityPoolFactory__factory } from "../src/types/factories/LiquidityPoolFactory__factory";
import { ExchangeRouter } from "../src/types/ExchangeRouter";
import { ExchangeRouter__factory } from "../src/types/factories/ExchangeRouter__factory";
import { ERC20 } from "../src/types/ERC20";
import { ERC20__factory } from "../src/types/factories/ERC20__factory";
import { WAVAX } from "../src/types/WAVAX";
import { WAVAX__factory } from "../src/types/factories/WAVAX__factory";

import { takeSnapshot, revertProvider } from "./block_utils";

describe("UniswapConnector", async () => {

    let snapshotId: any;

    // Constants
    let ZERO_ADDRESS = "0x0000000000000000000000000000000000000000";

    // Accounts
    let deployer: Signer;
    let signer1: Signer;
    let deployerAddress: string;

    // Contracts
    let uniswapConnector: UniswapConnector;
    let exchangeRouter: ExchangeRouter;
    let liquidityPool: LiquidityPool;
    let liquidityPoolFactory: LiquidityPoolFactory;
    let liquidityPool__factory: LiquidityPool__factory;
    let erc20: ERC20;
    let _erc20: ERC20;
    let WETH: WAVAX;

    // let liquidityPool__factory: LiquidityPool__factory;

    before(async () => {
        // Sets accounts
        [deployer, signer1] = await ethers.getSigners();
        deployerAddress = await deployer.getAddress();

        // Deploys WETH
        const WETHFactory = new WAVAX__factory(deployer);
        WETH = await WETHFactory.deploy(
            'Wrapped-Ethereum',
            'WETH'
        );

        // Deploys liquidityPoolFactory
        const liquidityPoolFactoryFactory = new LiquidityPoolFactory__factory(deployer);
        liquidityPoolFactory = await liquidityPoolFactoryFactory.deploy(
            deployerAddress
        );

        // Creates liquidityPool__factory object
        liquidityPool__factory = new LiquidityPool__factory(deployer);

        // Deploys exchangeRouter contract
        const exchangeRouterFactory = new ExchangeRouter__factory(deployer);
        exchangeRouter = await exchangeRouterFactory.deploy(
            liquidityPoolFactory.address,
            ZERO_ADDRESS // WETH
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
        let oldDeployerBalanceA: BigNumber;
        let oldDeployerBalanceB: BigNumber;
        let oldDeployerBalanceC: BigNumber;

        beforeEach("Adds liquidity to liquidity pool", async () => {
            // Takes snapshot before adding liquidity
            snapshotId = await takeSnapshot(deployer.provider);

            // Adds liquidity to liquidity pool
            let addedLiquidityA = 10000;
            let addedLiquidityB = 10000;
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
            let liquidityPoolAddress = await liquidityPoolFactory.getLiquidityPool(
                erc20.address,
                _erc20.address
            );

            // Loads liquidity pool
            liquidityPool = await liquidityPool__factory.attach(liquidityPoolAddress);

            // Records current reserves of teleBTC and TDT
            if (await liquidityPool.token0() == erc20.address) {
                [oldReserveA, oldReserveB] = await liquidityPool.getReserves();
            } else {
                [oldReserveB, oldReserveA] = await liquidityPool.getReserves()
            }

            // Records current tokens balances of deployer
            oldDeployerBalanceA = await erc20.balanceOf(deployerAddress);
            oldDeployerBalanceB = await _erc20.balanceOf(deployerAddress);
            // oldDeployerBalanceC = await WETH.balanceOf(deployerAddress);
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
                oldDeployerBalanceA.toNumber() - inputAmount
            );
            expect(newDeployerBalanceB).to.equal(
                oldDeployerBalanceB.add(outputAmount)
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
                oldDeployerBalanceA.toNumber() - inputAmount.toNumber()
            );
            expect(newDeployerBalanceB).to.equal(
                oldDeployerBalanceB.add(outputAmount)
            );
        })

        // it("Swaps fixed non-WETH for WETH", async function () {

        //     let inputAmount = 1000;
        //     let outputAmount = await exchangeRouter.getAmountOut(
        //         inputAmount,
        //         oldReserveA,
        //         oldReserveB
        //     );
        //     let path = [erc20.address, WETH.address];
        //     let to = deployerAddress;
        //     let deadline = 1000000;
        //     let isFixedToken = true;
            
        //     await erc20.approve(uniswapConnector.address, inputAmount);
        //     await expect(
        //         uniswapConnector.swap(
        //             inputAmount,
        //             outputAmount,
        //             path,
        //             to,
        //             deadline,
        //             isFixedToken
        //         )
        //     ).to.emit(uniswapConnector, 'Swap');

        //     // Records new balances of deployer
        //     let newDeployerBalanceA = await erc20.balanceOf(deployerAddress);
        //     let newDeployerBalanceC = await WETH.balanceOf(deployerAddress);

        //     // Checks deployer's tokens balances
        //     expect(newDeployerBalanceA.toNumber()).to.equal(
        //         oldDeployerBalanceA.toNumber() - inputAmount
        //     );
        //     expect(newDeployerBalanceC).to.equal(
        //         oldDeployerBalanceB.add(outputAmount)
        //     );
        // })

    });
});
