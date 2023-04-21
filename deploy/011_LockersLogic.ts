import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import verify from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const lockersLib = await deploy("LockersLib", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
    })

    const deployedContract = await deploy("LockersLogic", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        libraries: {
            "LockersLib": lockersLib.address
        },
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, [], "contracts/lockers/LockersLogic.sol:LockersLogic")
    }
};

export default func;
func.tags = ["LockersLogic"];
