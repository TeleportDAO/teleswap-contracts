import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import verify from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const teleBTC = await deployments.get("TeleBTC")

    const theArgs = [
        teleBTC.address
    ]

    const deployedContract = await deploy("TokenBatchTransfer", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, 
            theArgs, 
            "contracts/erc20/TokenBatchTransfer.sol:TokenBatchTransfer")
    }
    
};

export default func;
func.tags = ["TokenBatchTransfer"];