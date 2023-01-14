export interface networkConfigItem {
    ethUsdPriceFeed?: string
    blockConfirmations?: number
  }
  
  export interface networkConfigInfo {
    [key: string]: networkConfigItem
  }
  
  export const networkConfig: networkConfigInfo = {
    localhost: {},
    hardhat: {},
    // Price Feed Address, values can be obtained at https://docs.chain.link/docs/reference-contracts
    // Default one is ETH/USD contract on Kovan
    kovan: {
      blockConfirmations: 6,
    },
  }
  
  export const developmentChains = ["hardhat", "localhost"]
  export const deployFile = "deployments/"
  export const privateKey = "b773c1f5b19f93a2df58ef2773837fa6d8663d85f39dee40cce03231f201470f"