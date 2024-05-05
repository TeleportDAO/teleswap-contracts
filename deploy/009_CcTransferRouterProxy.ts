import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import verify from "../helper-functions";
import config from "config";

import * as dotenv from "dotenv";
dotenv.config();

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    if (
        network.name == "hardhat" ||
        network.name == "amoy" ||
        network.name == "polygon" ||
        network.name == "bsc" ||
        network.name == "bsc_testnet"
    ) {
        const proxyAdmin = config.get("proxy_admin");
        const ccTransferRouterLogic = await deployments.get(
            "CcTransferRouterLogic"
        );

        const deployedContract = await deploy("CcTransferRouterProxy", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [ccTransferRouterLogic.address, proxyAdmin, "0x"],
        });

        if (
            network.name != "hardhat" &&
            process.env.ETHERSCAN_API_KEY &&
            process.env.VERIFY_OPTION == "1"
        ) {
            await verify(
                deployedContract.address,
                [ccTransferRouterLogic.address, proxyAdmin, "0x"],
                "contracts/routers/CcTransferRouterProxy.sol:CcTransferRouterProxy"
            );
        }
    }
};

export default func;
func.tags = ["CcTransferRouterProxy"];
