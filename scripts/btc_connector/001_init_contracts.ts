import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { ethers } from "hardhat";
import config from "config";
const logger = require("node-color-log");

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments, network } = hre;
    const ZERO_ADD = "0x0000000000000000000000000000000000000000";

    const polygonTeleBTC = config.get("polygon_teleBTC");
    const across = config.get("across");
    const wrappedNativeToken = config.get("wrapped_native_token");
    const targetChainId = config.get("target_chain_id");
    const sourceChainId = config.get("source_chain_id");

    if (network.name == "polygon") {
        const lockersManagerProxy = await deployments.get(
            "LockersManagerProxy"
        );
        const burnRouterProxy = await deployments.get("BurnRouterProxy");
        const polyConnectorLogic = await deployments.get("PolyConnectorLogic");
        const polyConnectorProxy = await deployments.get("PolyConnectorProxy");
        const across = config.get("across");

        logger
            .color("blue")
            .log("-------------------------------------------------");
        logger.color("blue").bold().log("Initialize PolyConnector ...");
        const polyConnectorLogicFactory = await ethers.getContractFactory(
            "PolyConnectorLogic"
        );
        const polyConnectorProxyInstance =
            await polyConnectorLogicFactory.attach(polyConnectorLogic.address);
        const polyConnectorLogicInstance =
            await polyConnectorLogicFactory.attach(polyConnectorProxy.address);

        let _across = await polyConnectorProxyInstance.across();
        if (_across == ZERO_ADD) {
            const initializeTx = await polyConnectorProxyInstance.initialize(
                lockersManagerProxy.address,
                burnRouterProxy.address,
                across
            );
            await initializeTx.wait(1);
            console.log("Initialized PolyConnectorProxy: ", initializeTx.hash);
        } else {
            console.log("PolyConnectorProxy is already initialized");
        }

        let _acrossLogic = await polyConnectorLogicInstance.across();
        if (_acrossLogic == ZERO_ADD) {
            const initializeTx = await polyConnectorLogicInstance.initialize(
                lockersManagerProxy.address,
                burnRouterProxy.address,
                across
            );
            await initializeTx.wait(1);
            console.log("Initialized PolyConnectorLogic: ", initializeTx.hash);
        } else {
            console.log("PolyConnectorLogic is already initialized");
        }
    } else {
        const ethConnectorLogic = await deployments.get("EthConnectorLogic");
        const ethConnectorProxy = await deployments.get("EthConnectorProxy");
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
        const lockersManagerLogicInstance =
            await ethConnectorLogicFactory.attach(ethConnectorLogic.address);

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
