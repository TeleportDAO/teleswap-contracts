import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;

    const startingBlockHeight = config.get("starting_block_height");
    const protocolPercentageFee = config.get("cc_transfer.protocol_percentage_fee");
    const chainId = config.get("chain_id");
    const appId = config.get("cc_transfer.app_id");
    const treasuryAddress = config.get("treasury");
    const bitcoinRelay = config.get("bitcoin_relay");

    const ccTransferRouterLogic = await deployments.get("TeleOrdinalLogic");
    const ccTransferRouterProxy = await deployments.get("TeleOrdinalProxy");
    const lockersProxy = await deployments.get("LockersProxy");
    const teleBTC = await deployments.get("TeleBTC");

    const ccTransferRouterLogicFactory = await ethers.getContractFactory(
        "CcTransferRouterLogic"
    );
    const ccTransferRouterLogicInstance = await ccTransferRouterLogicFactory.attach(
        ccTransferRouterLogic.address
    );
    const ccTransferRouterProxyInstance = await ccTransferRouterLogicFactory.attach(
        ccTransferRouterProxy.address
    );

    const _relayProxy = await ccTransferRouterProxyInstance.relay();
    if (_relayProxy == "0x0000000000000000000000000000000000000000") {
        const initializeTxProxy = await ccTransferRouterProxyInstance.initialize(
            startingBlockHeight,
            protocolPercentageFee,
            chainId,
            appId,
            bitcoinRelay,
            lockersProxy.address,
            teleBTC.address,
            treasuryAddress
        );
        await initializeTxProxy.wait(1);
        console.log("Initialize CcTransferRouterLogic (proxy): ", initializeTxProxy.hash);
    }

    const _relayLogic = await ccTransferRouterLogicInstance.relay();
    if (_relayLogic == "0x0000000000000000000000000000000000000000") {
        const initializeTxLogic = await ccTransferRouterLogicInstance.initialize(
            startingBlockHeight,
            protocolPercentageFee,
            chainId,
            appId,
            bitcoinRelay,
            lockersProxy.address,
            teleBTC.address,
            treasuryAddress
        )
        await initializeTxLogic.wait(1);
        console.log("Initialize CcTransferRouterLogic (logic): ", initializeTxLogic.hash);
    }

};

export default func;