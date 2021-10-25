// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./IERC20.sol";

interface PEFI is IERC20 {
    function mint(address dest, uint256 amount) external;
    function setMinter(address _minterAddress) external;
}
