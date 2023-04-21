import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import verify from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const tokenName = "teleBTC"
    const tokenSymbol = "TELEBTC"

    const theArgs = [
        tokenName,
        tokenSymbol
    ]

    const deployedContract = await deploy("TeleBTC", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, [
        tokenName,
        tokenSymbol,
        ], "contracts/erc20/TeleBTC.sol:TeleBTC")
    }
    
};

export default func;
func.tags = ["TeleBTC"];
