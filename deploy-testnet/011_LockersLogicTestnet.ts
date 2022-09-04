import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const lockersLib = await deploy("LockersLib", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
    })

    await deploy("LockersLogicTestnet", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        libraries: {
            "LockersLib": lockersLib.address
        },
    });
};

export default func;
func.tags = ["LockersLogic", "BitcoinTestnet"];
