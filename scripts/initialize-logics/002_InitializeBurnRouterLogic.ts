import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;

    const startingBlockHeight = config.get("starting_block_height");
    const protocolPercentageFee = config.get("cc_burn.protocol_percentage_fee");
    const slasherPercentageReward = config.get("cc_burn.slasher_percentage_reward");
    const bitcoinFee = config.get("cc_burn.bitcoin_fee");
    const treasuryAddress = config.get("treasury");
    const transferDeadLine = config.get("cc_burn.transfer_deadLine");
    const bitcoinRelay = config.get("bitcoin_relay");

    const burnRouterLib = await deployments.get("BurnRouterLib");
    const burnRouterLogic = await deployments.get("BurnRouterLogic");
    const burnRouterProxy = await deployments.get("BurnRouterProxy");
    const lockersProxy = await deployments.get("LockersProxy");
    const teleBTC = await deployments.get("TeleBTC");

    const burnRouterLogicFactory = await ethers.getContractFactory(
        "BurnRouterLogic",
        {
            libraries: {
                BurnRouterLib: burnRouterLib.address
            }
        }
    );
    const burnRouterLogicInstance = await burnRouterLogicFactory.attach(
        burnRouterLogic.address
    );
    const burnRouterProxyInstance = await burnRouterLogicFactory.attach(
        burnRouterProxy.address
    );

    const _relayProxy = await burnRouterProxyInstance.relay();
    if (_relayProxy == "0x0000000000000000000000000000000000000000") {
        const initializeTxProxy = await burnRouterProxyInstance.initialize(
            startingBlockHeight,
            bitcoinRelay,
            lockersProxy.address,
            treasuryAddress,
            teleBTC.address,
            transferDeadLine,
            protocolPercentageFee,
            slasherPercentageReward,
            bitcoinFee
        )
        await initializeTxProxy.wait(1);
        console.log("Initialize BurnRouterLogic (proxy): ", initializeTxProxy.hash);
    }

    const _relayLogic = await burnRouterLogicInstance.relay();
    if (_relayLogic == "0x0000000000000000000000000000000000000000") {
        const initializeTxLogic = await burnRouterLogicInstance.initialize(
            startingBlockHeight,
            bitcoinRelay,
            lockersProxy.address,
            treasuryAddress,
            teleBTC.address,
            transferDeadLine,
            protocolPercentageFee,
            slasherPercentageReward,
            bitcoinFee
        )
        await initializeTxLogic.wait(1);
        console.log("Initialize BurnRouterLogic (logic): ", initializeTxLogic.hash);
    }

};

export default func;