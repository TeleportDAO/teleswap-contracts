import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import verify from "../helper-functions";
import config from 'config';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const proxyAdmin = config.get("proxy_admin");
    const lockersLogic = await deployments.get("LockersLogic")

    const deployedContract = await deploy("LockersProxy", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            lockersLogic.address,
            proxyAdmin,
            "0x"
        ],
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(
            deployedContract.address, 
            [
                lockersLogic.address,
                proxyAdmin,
                "0x"
            ], 
            "contracts/lockers/LockersProxy.sol:LockersProxy"
        )
    }
};

export default func;
func.tags = ["LockersProxy"];
