// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;


import "./safeErc20.sol";
import "./IIglooMasterV2.sol";


 contract StrategyPefiUsdcPgnl {
  
    using SafeERC20 for IERC20;

    IglooMaster public _iglooMaster = IglooMaster(0x256040dc7b3CECF73a759634fc68aA60EA0D68CB);
    uint256 public immutable pid;
    // Uint256 public immutable strategyPoolId = 24; 


    constructor(
      uint256 _pid
        )      
    {
        pid = _pid;
    }

    function deposit( uint256 amount) external {
        _iglooMaster.deposit(pid, amount,  address(this));
    }


    function withdraw(uint256 amountShares) external {
         _iglooMaster.withdraw(pid, amountShares,  address(this));
    }


    function harvest()  external {
        _iglooMaster.harvest(pid, address(this));
            }


    function withdrawAndHarvest(uint256 amountShares) external  {
         _iglooMaster.withdrawAndHarvest(pid, amountShares, address(this));
            }
}
