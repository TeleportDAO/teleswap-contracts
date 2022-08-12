// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LockersStorageStructure.sol";
import "hardhat/console.sol";

contract LockersProxy is LockersStorageStructure {

    constructor(
        address _lockersLogic
    ) {
        lockersLogic = _lockersLogic;
    }

    function updateLogic(address _newLogic) external onlyOwner {
        lockersLogic = _newLogic;
    }

    function initialize(
        address _TeleportDAOToken,
        address _exchangeConnector,
        address _priceOracle,
        uint _minRequiredTDTLockedAmount,
        uint _minRequiredTNTLockedAmount,
        uint _collateralRatio,
        uint _liquidationRatio,
        uint _lockerPercentageFee
    ) public initializer {

        OwnableUpgradeable.__Ownable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
        PausableUpgradeable.__Pausable_init();

        TeleportDAOToken = _TeleportDAOToken;
        exchangeConnector = _exchangeConnector;
        priceOracle = _priceOracle;
        minRequiredTDTLockedAmount = _minRequiredTDTLockedAmount;
        minRequiredTNTLockedAmount = _minRequiredTNTLockedAmount;
        collateralRatio = _collateralRatio;
        liquidationRatio = _liquidationRatio;
        lockerPercentageFee = _lockerPercentageFee;
    }

    fallback() external payable {
        address opr = lockersLogic;
        require(opr != address(0));
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), opr, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}
}
