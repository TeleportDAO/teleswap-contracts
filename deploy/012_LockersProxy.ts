import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { ethers, network } from 'hardhat';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const lockersLogic = await deployments.get("LockersLogic")

    await deploy("LockersProxy", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            lockersLogic.address,
            deployer,
            "0x"
        ],
    });
};

export default func;
func.tags = ["LockersProxy", "BitcoinMainnet"];
