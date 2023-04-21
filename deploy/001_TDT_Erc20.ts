import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  const tokenName = "TeleportDAOToken"
  const tokenSymbol = "TDT"

  await deploy("ERC20", {
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
func.tags = ["TeleportDAOToken"];
