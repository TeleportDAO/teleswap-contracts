import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { ethers } from "hardhat";
import config from 'config';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const { deployments } = hre;

    const startingBlockHeight = config.get("starting_block_height");
    const protocolPercentageFee = config.get("cc_exchange.protocol_percentage_fee");
    const chainID = config.get("chain_id");
    const treasuryAddress = config.get("treasury");
    const bitcoinRelay = config.get("bitcoin_relay");

    const ccExchangeRouterLogic = await deployments.get("TeleOrdinalLogic");
    const ccExchangeRouterProxy = await deployments.get("TeleOrdinalProxy");
    const lockersProxy = await deployments.get("LockersProxy");
    const teleBTC = await deployments.get("TeleBTC");

    const ccExchangeRouterLogicFactory = await ethers.getContractFactory(
        "CcExchangeRouterLogic"
    );
    const ccExchangeRouterLogicInstance = await ccExchangeRouterLogicFactory.attach(
        ccExchangeRouterLogic.address
    );
    const ccExchangeRouterProxyInstance = await ccExchangeRouterLogicFactory.attach(
        ccExchangeRouterProxy.address
    );

    const _relayProxy = await ccExchangeRouterProxyInstance.relay();
    if (_relayProxy == "0x0000000000000000000000000000000000000000") {
        const initializeTxProxy = await ccExchangeRouterProxyInstance.initialize(
            startingBlockHeight,
            protocolPercentageFee,
            chainID,
            lockersProxy.address,
            bitcoinRelay,
            teleBTC.address,
            treasuryAddress
        );
        await initializeTxProxy.wait(1);
        console.log("Initialize CcExchangeRouterLogic (proxy): ", initializeTxProxy.hash);
    }

    const _relayLogic = await ccExchangeRouterLogicInstance.relay();
    if (_relayLogic == "0x0000000000000000000000000000000000000000") {
        const initializeTxLogic = await ccExchangeRouterLogicInstance.initialize(
            startingBlockHeight,
            protocolPercentageFee,
            chainID,
            lockersProxy.address,
            bitcoinRelay,
            teleBTC.address,
            treasuryAddress
        )
        await initializeTxLogic.wait(1);
        console.log("Initialize CcExchangeRouterLogic (logic): ", initializeTxLogic.hash);
    }

};

export default func;