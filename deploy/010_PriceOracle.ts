import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const acceptableDelay = 1000;
    const tdtToken = await deployments.get("ERC20")

    await deploy("PriceOracle", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            acceptableDelay,
            tdtToken.address
        ],
    });
};

export default func;
func.tags = ["PriceOracle", "BitcoinMainnet"];
