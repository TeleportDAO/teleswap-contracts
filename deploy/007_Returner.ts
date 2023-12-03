import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import verify from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts, network } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();

    const teleBTC = await deployments.get("TeleBTCProxy")

    const theArgs = [
        ["WMATIC"],
        ["0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889"],
        teleBTC.address
    ]

    const deployedContract = await deploy("Returner", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: theArgs
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, 
            theArgs, 
            "contracts/erc20/Returner.sol:Returner")
    }
    
};

export default func;
func.tags = ["TokenBatchTransfer"];