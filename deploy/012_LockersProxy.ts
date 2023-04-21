import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers, network } from 'hardhat';
import verify from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const lockersLogic = await deployments.get("LockersLogic")

    const deployedContract = await deploy("LockersProxy", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            lockersLogic.address,
            deployer,
            "0x"
        ],
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, [
            lockersLogic.address,
            deployer,
            "0x"
        ], "contracts/lockers/LockersProxy.sol:LockersProxy")
    }
};

export default func;
func.tags = ["LockersProxy"];
