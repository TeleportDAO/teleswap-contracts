import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import verify from "../helper-functions";
import config from "config";

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
        const polyConnectorLogic = await deployments.get("PolyConnectorLogic");

        const deployedContract = await deploy("PolyConnectorProxy", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [polyConnectorLogic.address, proxyAdmin, "0x"],
        });

        if (
            network.name != "hardhat" &&
            process.env.ETHERSCAN_API_KEY &&
            process.env.VERIFY_OPTION == "1"
        ) {
            await verify(
                deployedContract.address,
                [polyConnectorLogic.address, proxyAdmin, "0x"],
                "contracts/connectors/PolyConnectorProxy.sol:PolyConnectorProxy"
            );
        }
    }
};

export default func;
func.tags = ["PolyConnectorProxy"];
