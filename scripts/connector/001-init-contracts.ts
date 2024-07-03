import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import config from "config";
const logger = require("node-color-log");

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, network } = hre;
    const ZERO_ADD = "0x0000000000000000000000000000000000000000";

    if (network.name == "ethereum") {
        const ethConnectorLogic = await deployments.get("EthConnectorLogic");
        const ethConnectorProxy = await deployments.get("EthConnectorProxy");

        const polygonTeleBTC = config.get("polygon_teleBTC");
        const across = config.get("across");
        const wrappedNativeToken = config.get("wrapped_native_token");
        const targetChainId = config.get("target_chain_id");
        const sourceChainId = config.get("source_chain_id");

        logger
            .color("blue")
            .log("-------------------------------------------------");
        logger.color("blue").bold().log("Initialize EthConnector ...");

        const ethConnectorLogicFactory = await ethers.getContractFactory(
            "EthConnectorLogic"
        );
        const ethConnectorProxyInstance = await ethConnectorLogicFactory.attach(
            ethConnectorProxy.address
        );
        const lockersManagerLogicInstance = await ethConnectorLogicFactory.attach(
            ethConnectorLogic.address
        );

        let _wrappedNativeToken =
            await ethConnectorProxyInstance.wrappedNativeToken();
        if (_wrappedNativeToken == ZERO_ADD) {
            const initializeTx = await ethConnectorProxyInstance.initialize(
                polygonTeleBTC,
                across,
                wrappedNativeToken,
                targetChainId,
                sourceChainId
            );
            await initializeTx.wait(1);
            console.log("Initialized ethConnectorProxy: ", initializeTx.hash);
        } else {
            console.log("ethConnectorProxy is already initialized");
        }

        _wrappedNativeToken =
            await lockersManagerLogicInstance.wrappedNativeToken();
        if (_wrappedNativeToken == ZERO_ADD) {
            const initializeTx = await lockersManagerLogicInstance.initialize(
                polygonTeleBTC,
                across,
                wrappedNativeToken,
                targetChainId,
                sourceChainId
            );
            await initializeTx.wait(1);
            console.log("Initialized ethConnectorLogic: ", initializeTx.hash);
        } else {
            console.log("ethConnectorLogic is already initialized");
        }
    }
};

export default func;
