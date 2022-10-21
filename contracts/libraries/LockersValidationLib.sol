// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.8.4;

import "../types/DataTypes.sol";

library LockersValidationLib {
    //TODO remove constants

    // Constants
    uint public constant ONE_HUNDRED_PERCENT = 10000;
    uint public constant HEALTH_FACTOR = 10000;
    uint public constant UPPER_HEALTH_FACTOR = 12000;
    uint public constant MAX_LOCKER_FEE = 10000;
    uint public constant NATIVE_TOKEN_DECIMAL = 18;
    address public constant NATIVE_TOKEN = address(1);

    // function validateInitialize (
    //     address _TeleportDAOToken,
    //     address _exchangeConnector,
    //     address _priceOracle,
    //     uint _minRequiredTDTLockedAmount,
    //     uint _minRequiredTNTLockedAmount,
    //     uint _collateralRatio,
    //     uint _liquidationRatio,
    //     uint _lockerPercentageFee,
    //     uint _priceWithDiscountRatio
    // ) external view {
    //     require(
    //         // _TeleportDAOToken != address(0) && _exchangeConnector != address(0) && _priceOracle != address(0) && _ccBurnRouter != address(0),
    //         _TeleportDAOToken != address(0) && _exchangeConnector != address(0) && _priceOracle != address(0) ,
    //         "Lockers: address is zero"
    //     );

    //     require(
    //         _minRequiredTDTLockedAmount != 0 || _minRequiredTNTLockedAmount != 0,
    //         "Lockers: amount is zero"
    //     );

    //     require(
    //         _collateralRatio >= _liquidationRatio && _liquidationRatio >= ONE_HUNDRED_PERCENT,
    //         "Lockers: problem in CR and LR"
    //     );

    //     require(
    //         _priceWithDiscountRatio <= ONE_HUNDRED_PERCENT,
    //         "Lockers: less than 100%"
    //     );
    // }

    function validateLockerPercentageFee(uint _lockerPercentageFee) external view{
        require(_lockerPercentageFee <= MAX_LOCKER_FEE, "Lockers: invalid locker fee");
    }
}




