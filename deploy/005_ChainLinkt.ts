import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { BigNumber, BigNumberish } from "ethers";
import verify from "../helper-functions"

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts, network} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const tokenName = "Chainlink"
    const tokenSymbol = "LINK"
    const initialSupply = BigNumber.from(10).pow(18).mul(100000)

    const deployedContract = await deploy("ERC20AsLink", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            tokenName,
            tokenSymbol,
            initialSupply
        ],
    });

    if (network.name != "hardhat" && process.env.ETHERSCAN_API_KEY && process.env.VERIFY_OPTION == "1") {
        await verify(deployedContract.address, [
        tokenName,
        tokenSymbol,
        initialSupply
        ], "contracts/erc20/ERC20AsLink.sol:ERC20AsLink")
    }
};

export default func;
func.tags = ["ERC20AsLink"];
