"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const func = async function (hre) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;
    const { deployer } = await getNamedAccounts();
    await deploy('Greeter', {
        from: deployer,
        log: true,
        args: ["Hello, Hardhat!"],
    });
};
exports.default = func;
func.tags = ['Greeter'];
