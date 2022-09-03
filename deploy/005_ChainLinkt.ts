import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { BigNumber, BigNumberish } from "ethers";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;
    const { deployer } = await getNamedAccounts();

    const tokenName = "Chainlink"
    const tokenSymbol = "LINK"
    const initialSupply = BigNumber.from(10).pow(18).mul(1000)

    await deploy("ERC20AsLink", {
        from: deployer,
        log: true,
        skipIfAlreadyDeployed: true,
        args: [
            tokenName,
            tokenSymbol,
            initialSupply
        ],
    });
};

export default func;
func.tags = ["ERC20AsLink", "BitcoinMainnet"];
