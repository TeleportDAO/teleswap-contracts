import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import verify from "../../helper-functions";

require("dotenv").config({ path: "../config/temp.env" });

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const ccExchangeRouterLib = await deploy("CcExchangeRouterLib", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
    });

    const deployedContract = await deploy("CcExchangeRouterLogic", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [],
        libraries: {
            CcExchangeRouterLib: ccExchangeRouterLib.address,
        },
    });

    if (
        network.name != "hardhat" &&
        process.env.ETHERSCAN_API_KEY &&
        process.env.VERIFY_OPTION == "1"
    ) {
        await verify(
            deployedContract.address,
            [],
            "contracts/routers/CcExchangeRouterLogic.sol:CcExchangeRouterLogic"
        );
    }
};

export default func;
func.tags = ["btc"];
