import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('Greeter', {
    from: deployer,
    log: true,
    skipIfAlreadyDeployed: true,
    args: ["Hello, Hardhat!"],
  });
};

export default func;
func.tags = ['Greeter'];
