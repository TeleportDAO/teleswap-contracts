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
        const lockersManagerLogic = await deployments.get(
            "LockersManagerLogic"
        );

        const deployedContract = await deploy("LockersManagerProxy", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            args: [lockersManagerLogic.address, proxyAdmin, "0x"],
        });

        if (
            network.name != "hardhat" &&
            process.env.ETHERSCAN_API_KEY &&
            process.env.VERIFY_OPTION == "1"
        ) {
            await verify(
                deployedContract.address,
                [lockersManagerLogic.address, proxyAdmin, "0x"],
                "contracts/lockers/LockersManagerProxy.sol:LockersManagerProxy"
            );
        }
    }
};

export default func;
func.tags = ["LockersManagerProxy"];
