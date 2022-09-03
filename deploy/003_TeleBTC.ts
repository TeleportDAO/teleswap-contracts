import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const tokenName = "TeleBitcoin"
    const tokenSymbol = "TBTC"

    await deploy("TeleBTC", {
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
func.tags = ["TeleBTC", "BitcoinMainnet"];
