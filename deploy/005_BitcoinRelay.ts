import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    // FIXME: setting the following parameters
    const genesisHeader // bytes
    const height // uint256
    const periodStart // bytes32

    const tbtToken = await deployments.get("ERC20")
    const exchangeRouter = await deployments.get("ExchangeRouter")

    await deploy("BitcoinRelay", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            genesisHeader,
            height,
            periodStart,
            tbtToken.address,
            exchangeRouter.address
        ],
    });
};

export default func;
func.tags = ["BitcoinRelay"];
