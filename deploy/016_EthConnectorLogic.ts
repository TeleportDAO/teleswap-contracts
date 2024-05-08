import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import verify from "../helper-functions";

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
        const deployedContract = await deploy("EthConnectorLogic", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [],
        });

        if (
            network.name != "hardhat" &&
            process.env.ETHERSCAN_API_KEY &&
            process.env.VERIFY_OPTION == "1"
        ) {
            await verify(
                deployedContract.address,
                [],
                "contracts/connectors/EthConnectorLogic.sol:EthConnectorLogic"
            );
        }
    }
};

export default func;
func.tags = ["EthConnectorLogic"];
