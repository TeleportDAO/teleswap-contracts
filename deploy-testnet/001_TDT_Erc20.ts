import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';
import { BigNumber, BigNumberish } from "ethers";
import verify from "../helper-functions";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts, network} = hre;
  const {deploy, log} = deployments;
  const { deployer } = await getNamedAccounts();

  const tokenName = "TeleportDAOToken"
  const tokenSymbol = "TDT"
  const initialSupply = BigNumber.from(10).pow(18).mul(10000)

  const erc20 = await deploy("ERC20", {
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
func.tags = ["TeleportDAOToken", "BitcoinTestnet"];
