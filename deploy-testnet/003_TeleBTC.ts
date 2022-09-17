import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import verify from "../helper-functions";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy, log} = deployments;
    const { deployer } = await getNamedAccounts();

    const tokenName = "TeleBitcoin"
    const tokenSymbol = "TBTC"

    const teleBTC = await deploy("TeleBTC", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            tokenName,
            tokenSymbol
        ],
    });

    log(`TeleBTC at ${teleBTC.address}`)
    if (process.env.ETHERSCAN_API_KEY) {
      await verify(
            teleBTC.address,
            [
              tokenName,
              tokenSymbol
            ]
        )
    }
};

export default func;
func.tags = ["TeleBTC", "BitcoinTestnet"];
