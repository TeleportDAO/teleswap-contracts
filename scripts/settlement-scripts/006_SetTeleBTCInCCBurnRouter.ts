import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import { BigNumber, BigNumberish } from "ethers";
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Set teleBTC in CC burn...")

    const teleBTC = await deployments.get("TeleBTC")
    const ccBurnRouter = await deployments.get("CCBurnRouter")

    const relayHelper = await deployments.get("RelayHelper")
    const ccBurnRouterFactory = await ethers.getContractFactory(
        "CCBurnRouter",
        {
            libraries: {
                RelayHelper: relayHelper.address
            }
        }
    );
    const ccBurnRouterInstance = await ccBurnRouterFactory.attach(
        ccBurnRouter.address
    );

    const checkTeleBTCInCCBurn = await ccBurnRouterInstance.teleBTC()

    if (checkTeleBTCInCCBurn != teleBTC.address ) {
        const setTeleBTCTx = await ccBurnRouterInstance.setTeleBTC(
            teleBTC.address
        )
    
        await setTeleBTCTx.wait(1)
        console.log("set telebtc in CC burn: ", setTeleBTCTx.hash)
    } else {
        console.log("telebtc is already settled in CC burn")
    }
    

};

export default func;
// func.tags = ["PriceOracle", "BitcoinTestnet"];
