
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;



import "./IERC20.sol";


interface PenguinNests is IERC20 {
    function enter(uint256 _amount) external;
    function currentExchangeRate() external view returns(uint256);
}
