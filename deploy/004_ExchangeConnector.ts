import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import config from "config";
import verify from "../helper-functions";

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
        const connectorName = "QuickswapV2";
        const uniswapV2Router02 = config.get("uniswap_v2_router_02");

        const deployedContract = await deploy("UniswapV2Connector", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [connectorName, uniswapV2Router02],
        });

        if (
            network.name != "hardhat" &&
            process.env.ETHERSCAN_API_KEY &&
            process.env.VERIFY_OPTION == "1"
        ) {
            await verify(
                deployedContract.address,
                [connectorName, uniswapV2Router02],
                "contracts/swap_connectors/UniswapV2Connector.sol:UniswapV2Connector"
            );
        }
    }
};

export default func;
func.tags = ["UniswapV2Connector"];
