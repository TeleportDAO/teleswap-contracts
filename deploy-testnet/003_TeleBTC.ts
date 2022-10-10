import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions"
import {developmentChains} from "../helper-hardhat-config"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const tokenName = "TeleBitcoin"
    const tokenSymbol = "TBTC"

    const theArgs = [
        tokenName,
        tokenSymbol
    ]

    const teleBTC = await deploy("TeleBTC", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs,
    });


    // log(`TeleBTC at ${teleBTC.address}`)
    // if (!developmentChains.includes(network.name) && process.env.ETHERSCAN_API_KEY) {
    //     await verify(
    //         teleBTC.address,
    //         theArgs
    //     )
    // }
};

export default func;
func.tags = ["TeleBTC", "BitcoinTestnet"];
