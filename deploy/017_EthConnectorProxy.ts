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
        (network.name != "amoy" &&
            network.name != "polygon" &&
            network.name != "bsc" &&
            network.name != "bsc_testnet")
    ) {
        const proxyAdmin = config.get("proxy_admin");
        const ethConnectorLogic = await deployments.get("EthConnectorLogic");

        const deployedContract = await deploy("EthConnectorProxy", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [ethConnectorLogic.address, proxyAdmin, "0x"],
        });

        if (
            network.name != "hardhat" &&
            process.env.ETHERSCAN_API_KEY &&
            process.env.VERIFY_OPTION == "1"
        ) {
            await verify(
                deployedContract.address,
                [ethConnectorLogic.address, proxyAdmin, "0x"],
                "contracts/routers/EthConnectorProxy.sol:EthConnectorProxy"
            );
        }
    }
};

export default func;
func.tags = ["EthConnectorProxy"];
