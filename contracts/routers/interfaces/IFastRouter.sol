// SPDX-License-Identifier: <SPDX-License>
pragma solidity >=0.7.6;

interface IFastRouter {
    // read-only functions
    function owner() external view returns (address);
    function bitcoinFastPool() external view returns(address);
    function ccTransferRouter() external view returns(address);
    function getNeededConfirmations() external view returns(uint);

    // state-changing functions
    function changeOwner(address _owner) external;
    function setCCTransferRouter(address _ccTransferRouter) external;
    function fastTransfer(
        address receiver,
        uint amount,
        uint blockNumber
    ) external returns(bool);
    function addLiquidity(address user, uint wrappedBitcoinAmount) external returns(uint);
    function removeLiquidity(address user, uint fastPoolTokenAmount) external returns(uint);

}
