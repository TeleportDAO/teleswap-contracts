const { TeleportDaoPayment } = require("@teleportdao/bitcoin");


class ProofBuilder extends TeleportDaoPayment {

    async newGetTransferOpReturnData({
        chainId,
        appId,
        recipientAddress, // 20 bytes
        percentageFee, // 2 bytes in satoshi
        speed = 0, // 1 byte
        isExchange = false,
        exchangeTokenAddress = "0x0000000000000000000000000000000000000000", // 20 bytes
        outputAmount = 0, // 28 bytes
        deadline, // 4 bytes
        isFixedToken = false, // 1 byte
      }) {
        let chainIdHex = Number(chainId).toString(16).padStart(2, "0")
        let appIdHex = Number(appId).toString(16).padStart(4, "0")
        let recipientAddressHex = recipientAddress.replace("0x", "").toLowerCase().padStart(40, "0")
        let percentageFeeHex = Number((percentageFee * 100).toFixed(0))
          .toString(16)
          .padStart(4, "0")
        let speedHex = speed ? "01" : "00"
        let dataHex = chainIdHex + appIdHex + recipientAddressHex + percentageFeeHex + speedHex
    
        if (!isExchange) {
          if (dataHex.length !== 26 * 2) throw new Error("invalid data length")
          return dataHex
        }
    
        let exchangeTokenAddressHex = exchangeTokenAddress
          .replace("0x", "")
          .toLowerCase()
          .padStart(40, "0")
        let outputAmountHex = Number(outputAmount).toString(16).padStart(56, "0")
        let deadlineHex = Number(deadline).toString(16).padStart(8, "0")
        let isFixedTokenHex = isFixedToken ? "01" : "00"
    
        dataHex = dataHex + exchangeTokenAddressHex + outputAmountHex + deadlineHex + isFixedTokenHex
        if (dataHex.length !== 79 * 2) throw new Error("invalid data length")
        return dataHex
    }


    async newGetBitcoinToEthTargetOutputs({
        lockerAddress,
        amount,
        fullAmount = false,
        //-----------
        chainId,
        appId,
        recipientAddress, // 20 bytes
        percentageFee, // 2 bytes in satoshi
        speed = 0, // 1 byte
        isExchange = false,
        exchangeTokenAddress = "0x0000000000000000000000000000000000000000", // 20 bytes
        outputAmount = 0, // 28 bytes
        deadline = 0, // 4 bytes
        isFixedToken = false, // 1 byte
      }) {
        let dataHex = await this.newGetTransferOpReturnData({
          chainId,
          appId,
          recipientAddress,
          percentageFee,
          speed,
          isExchange,
          exchangeTokenAddress,
          outputAmount,
          deadline,
          isFixedToken,
        })
        let opTarget = this.transactionBuilder.getOpReturnTarget(dataHex)
        return fullAmount
          ? [opTarget]
          : [
              {
                address: lockerAddress,
                value: amount,
              },
              opTarget,
            ]
    }


    async newGetBitcoinToEthUnsignedPsbt({
        changeAddress,
        extendedUtxo,
        lockerAddress,
        amount,
        fullAmount = false,
        //-----------
        chainId,
        appId,
        recipientAddress, // 20 bytes
        percentageFee, // 2 bytes in satoshi
        speed = 0, // 1 byte
        isExchange = false,
        exchangeTokenAddress = "0x0000000000000000000000000000000000000000", // 20 bytes
        outputAmount = 0, // 28 bytes
        deadline = 0, // 4 bytes
        isFixedToken = false, // 1 byte
        feeSpeed = "normal",
      }) {
        let feeRate = await this.transactionBuilder._getFeeRate(feeSpeed)
        let targets = await this.newGetBitcoinToEthTargetOutputs({
          lockerAddress,
          amount,
          fullAmount,
          chainId,
          appId,
          recipientAddress,
          percentageFee,
          speed,
          isExchange,
          exchangeTokenAddress,
          outputAmount,
          deadline,
          isFixedToken,
        })

        console.log("10101010101010101101010")
        console.log(extendedUtxo)
        console.log(targets)
        console.log("10101010101010101101010")

        let unsignedTx = await this.transactionBuilder.processUnsignedTransaction({
          extendedUtxo,
          targets,
          changeAddress: fullAmount ? lockerAddress : changeAddress,
          feeRate,
          fullAmount,
        })

        return unsignedTx
    }
}

async function  mySignerFunc() {
    let myTdp = new ProofBuilder(
        "bitcoin_testnet"
        // "polygon_testnet"
        // "polygon"
    )

    myTdp.setAccountPrivateKeyByMnemonic(
        {
            mnemonic: "solution joy exercise wait plastic because laptop chase sting wealth excite snake fruit position bomb evoke witness agent absurd kite velvet invite subway imitate",
            index: 1,
            addressType: "p2wpkh"
        }
    )

    console.log("currentAccount")
    console.log(myTdp.currentAccount)

    console.log("currentAccountType")
    console.log(myTdp.currentAccountType)

    console.log("publicKey")
    console.log(myTdp.publicKey.toString("hex"))

    let utxos = await myTdp.getExtendedUtxo({
        address: myTdp.currentAccount,
        addressType: myTdp.currentAccountType,
        publicKey: myTdp.publicKey.toString("hex"),
    })

    console.log("utxos")
    console.log(utxos)

    // testnet: [
    //     {
    //       targetAddress: "0x5133cDF6423105d8356E8a1322909064f8ffed7b",
    //       bitcoinAddress: "2MzQA2boKkWPkooDkN9dKfqzFndSvjHw5kg",
    //     },
    //   ],

    let unsignedTx = await myTdp.newGetBitcoinToEthUnsignedPsbt({
        changeAddress: "tb1qwehm550le3px6mq6jrm40ctv7tmtrq2cx66csq",
        extendedUtxo: utxos,
        lockerAddress: "2MzQA2boKkWPkooDkN9dKfqzFndSvjHw5kg",
        amount: 0.000005,
        chainId: 137,
        appId: 1111,
        recipientAddress: "0x5364E3557572bd5D5903C0e9C21BE359F2Eac1dA",
        percentageFee: 1,
        isExchange: true,
        exchangeTokenAddress: "0x9c3C9283D3e44854697Cd22D3Faa240Cfb032889",
        outputAmount: 500000000000000000,
        deadline: 1702474093,
        isFixedToken: true,   
    })

    let theTx = await myTdp.signer.signPsbt(unsignedTx.unsignedTransaction)

    let sendResult = await myTdp.sendSignedPsbt(theTx)

    console.log(sendResult)
}

async function  myProof() {
    let myTdp = new ProofBuilder(
        "bitcoin_testnet",
        {
            api: {
              enabled: true,
              provider: "BlockStream",
            },
        }
    )

    myTdp.btcInterface.rpcProvider = myTdp.btcInterface.provider

    let theTxId = "aac911e055fd9a8776bc9e1bb8099b5f1235c9cd3ec0e59da59884213f73d498"

    let theProof = await myTdp.btcInterface.getRequestProof(
        {
            txId: theTxId
        }
    )
    
    console.log(theProof)

}

mySignerFunc()
// myProof()