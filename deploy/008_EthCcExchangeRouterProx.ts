import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions"

import * as dotenv from "dotenv";
dotenv.config();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const ccExchangeRouterLogic = await deployments.get("EthCcExchangeRouterLogic")

    const deployedContract = await deploy("EthCcExchangeRouterProxy", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            ccExchangeRouterLogic.address,
            deployer,
            "0x"
        ],
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(
            deployedContract.address, 
            [
                ccExchangeRouterLogic.address,
                deployer,
                "0x"
            ], 
            "contracts/routers/EthCcExchangeRouterProxy.sol:EthCcExchangeRouterProxy"
        )
    }
};

export default func;
func.tags = ["EthCcExchangeRouterProxy"];
