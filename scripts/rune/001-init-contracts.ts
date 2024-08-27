import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config';
const logger = require('node-color-log');

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;
    const ZERO_ADD = "0x0000000000000000000000000000000000000000";

    const runeRouterProxy = await deployments.get("RuneRouterProxy");
    const runeRouterLogic = await deployments.get("RuneRouterLogic");
    const runeRouterLib = await deployments.get("RuneRouterLib");

    const startingBlockNumber = config.get("starting_block_number");
    const protocolPercentageFee = config.get("protocol_percentage_fee");
    const chainId = config.get("chain_id");
    const treasury = config.get("treasury");
    const locker = config.get("locker");
    const lockerLockingScript = config.get("lockerLockingScript");
    const lockerScriptType = config.get("lockerScriptType");
    const teleporter = config.get("teleporter");
    const relay = config.get("bitcoin_relay");

    logger.color('blue').log("-------------------------------------------------")
    logger.color('blue').bold().log("Initialize RuneRouterLogic ...")

    const runeRouterLogicFactory = await ethers.getContractFactory(
        "RuneRouterLogic",
        {
            libraries: {
                RuneRouterLib: runeRouterLib.address
            }
        }
    );
    const runeRouterProxyInstance = await runeRouterLogicFactory.attach(
        runeRouterProxy.address
    );
    const runeRouterLogicInstance = await runeRouterLogicFactory.attach(
        runeRouterLogic.address
    );

    let _relay = await runeRouterProxyInstance.relay();
    if (_relay == ZERO_ADD) {
        const initializeTx = await runeRouterProxyInstance.initialize(
            startingBlockNumber,
            protocolPercentageFee,
            chainId,
            relay,
            locker,
            lockerLockingScript,
            lockerScriptType,
            teleporter,
            treasury
        )
        await initializeTx.wait(1)
        console.log("Initialized RuneRouterProxy: ", initializeTx.hash)
    } else {
        console.log("RuneRouterProxy is already initialized")
    }

    let _teleBtcLogic = await runeRouterLogicInstance.relay()
    if (_teleBtcLogic == ZERO_ADD) {
        const initializeTx = await runeRouterLogicInstance.initialize(
            startingBlockNumber,
            protocolPercentageFee,
            chainId,
            relay,
            locker,
            lockerLockingScript,
            lockerScriptType,
            teleporter,
            treasury
        )
        await initializeTx.wait(1)
        console.log("Initialized RuneRouterLogic: ", initializeTx.hash)
    } else {
        console.log("RuneRouterLogic is already initialized")
    }

};

export default func;