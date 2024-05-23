import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";

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
        const tokenName = "TeleportSystemToken";
        const tokenSymbol = "TST";

        await deploy("ERC20", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [tokenName, tokenSymbol],
        });
    }
};

export default func;
func.tags = ["TeleportSystemToken"];
