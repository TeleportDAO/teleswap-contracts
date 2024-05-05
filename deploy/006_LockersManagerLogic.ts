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
        const lockersManagerLib = await deploy("LockersManagerLib", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
        });

        const deployedContract = await deploy("LockersManagerLogic", {
            from: deployer,
            log: true,
            skipIfAlreadyDeployed: true,
            libraries: {
                LockersManagerLib: lockersManagerLib.address,
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
                "contracts/lockers/LockersManagerLogic.sol:LockersManagerLogic"
            );
        }
    }
};

export default func;
func.tags = ["LockersManagerLogic"];
