import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const tokenName = "WrappedETH"
    const tokenSymbol = "WETH"

    await deploy("WETH", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            tokenName,
            tokenSymbol
        ],
    });
};

export default func;
func.tags = ["WETH", "BitcoinTestnet"];
