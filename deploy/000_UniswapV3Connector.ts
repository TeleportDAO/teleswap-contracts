import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
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
        const deployedContract = await deploy("UniswapV3Connector", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: ["univ3", "0xc7BdBecE57a8021a9a2137eeA1474BF978832D69", "0xc7BdBecE57a8021a9a2137eeA1474BF978832D69", "0xc7BdBecE57a8021a9a2137eeA1474BF978832D69"]
        });

        if (
            network.name != "hardhat" &&
            process.env.ETHERSCAN_API_KEY &&
            process.env.VERIFY_OPTION == "1"
        ) {
            await verify(
                deployedContract.address,
                [],
                "contracts/swap_connectors/UniswapV3Connector.sol:UniswapV3Connector"
            );
        }
    }
};

export default func;
func.tags = ["TeleBTCLogic"];
