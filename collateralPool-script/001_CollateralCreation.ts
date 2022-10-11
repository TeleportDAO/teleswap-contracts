import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    log("CreateCollateralPoolWithFactory...")

    const collateralPoolFactoryContract = await deployments.get("CollateralPoolFactory")
    const collateralPoolFactoryFactory = await ethers.getContractFactory("CollateralPoolFactory")
    const collateralPoolFactoryInstance = await collateralPoolFactoryFactory.attach(
        collateralPoolFactoryContract.address
    )

    const erc20asLinkContract = await deployments.get("WETH")
    const erc20asLinkFactory = await ethers.getContractFactory("WETH")
    const erc20asLinkInstance = await erc20asLinkFactory.attach(
        erc20asLinkContract.address
    )

    const hasCollateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
        erc20asLinkContract.address
    )

    let collateralPoolAddress: any

    if (hasCollateralPoolAddress == "0x0000000000000000000000000000000000000000") {
        const createCollateralPoolTx = await collateralPoolFactoryInstance.createCollateralPool(
            erc20asLinkContract.address,
            15000
        )
    
        await createCollateralPoolTx.wait(1)

        // let theEvent: any

        // createCollateralPoolTxResult.events.forEach(
        //     (event: any) => {
        //         if (event["topic"] == "0x6e86e4d8eed057ac88a84132c45db161d6c5a1f32b997ed913edf0bef4fb47c2") {
        //             theEvent = event
        //         }
        // });

        // collateralPoolAddress = theEvent["collateralPool"]

        collateralPoolAddress = await collateralPoolFactoryInstance.getCollateralPoolByToken(
            erc20asLinkContract.address
        )
    
    } else {
        collateralPoolAddress = hasCollateralPoolAddress
    }
     
    
    const balanceOfDeployer = await erc20asLinkInstance.balanceOf(deployer) 

    const approveForCollateralPoolTx = await erc20asLinkInstance.approve(collateralPoolAddress, balanceOfDeployer.div(2))

    await approveForCollateralPoolTx.wait(1)

    const collateralPoolContract = await ethers.getContractFactory(
        "CollateralPool"
    );

    const collateralPoolInstance = await collateralPoolContract.attach(
        collateralPoolAddress
    );

    const addLiquidityTx = await collateralPoolInstance.addCollateral(
        deployer,
        balanceOfDeployer.div(2)
    )

    await addLiquidityTx.wait(1)

    log("CreateCollateralPoolWithFactory...")
};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
