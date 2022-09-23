import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const collateralPoolFactory = await deploy("CollateralPoolFactory", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
    });

    log(`CollateralPoolFactory at ${collateralPoolFactory.address}`)
    if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
        await verify(
            collateralPoolFactory.address,
            []
        )
    }
};

export default func;
func.tags = ["CollateralPoolFactory", "BitcoinTestnet"];
