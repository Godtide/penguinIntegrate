 // SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;


import "./safeErc20.sol";
import "./IglooStrategyStorage.sol";
import "./IStakingRewards.sol";
import "./IRewarder.sol";
 
 
 interface IglooMaster  {
  

    //VIEW FUNCTIONS
    function poolLength() external view returns (uint256);

    // View function to see total pending reward in PEFI on frontend.
    function totalPendingPEFI(uint256 pid, address penguin) external view returns (uint256);

    // similar to totalPendingPEFI, but takes ipefiDistributionBips into account 
    function pendingPEFI(uint256 pid, address user) external view returns (uint256);

    // similar to totalPendingPEFI, but takes ipefiDistributionBips and conversion to ipefi into account
    function pendingIPEFI(uint256 pid, address user) external view returns (uint256);

    // View function to see total pending reward in PEFI and IPEFI on frontend.
    function pendingRewards(uint256 pid, address user) external view returns (uint256, uint256);
    // view function to get all pending rewards, from IglooMaster, Strategy, and Rewarder
    function pendingTokens(uint256 pid, address user) external view 
        returns (address[] memory, uint256[] memory);

    // Return reward over the period _from to _to.
    function reward(uint256 _lastRewardTime, uint256 _currentTime) external view returns (uint256);

    //convenience function to get the yearly emission of PEFI at the current emission rate
    function pefiPerYear()external view returns(uint256);

    //convenience function to get the yearly emission of PEFI at the current emission rate, to a given igloo
    function pefiPerYearToIgloo(uint256 pid) external view returns(uint256) ;

    //convenience function to get the yearly emission of PEFI at the current emission rate, to the nest
    function pefiPerYearToNest() external view returns(uint256);

    //fetches nest simple APY at current PEFI emission rate. returned value is multiplier *scaled up by ACC_PEFI_PRECISION*
    function nestAPY() external view returns(uint256) ;

    //convenience function to get the total number of shares in an igloo
    function totalShares(uint256 pid) external view returns(uint256);

    //convenience function to get the total amount of LP tokens in an igloo
    function totalLP(uint256 pid) external view returns(uint256);
    //convenience function to get the shares of a single user in an igloo
    function userShares(uint256 pid, address user) external view returns(uint256);
    //returns user profits in LP (returns zero in the event that user has losses due to previous withdrawal fees)
    function profitInLP(uint256 pid, address userAddress) external view returns(uint256);

    //function for fetching the current ipefiDistributionBips of a user
    function ipefiDistributionBipsByUser(address user) external;

    //WRITE FUNCTIONS
    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    function updatePool(uint256 pid) external;
    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() external;

    /// @notice Deposit LP tokens to IglooMaster for PEFI allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 pid, uint256 amount, address to) external;

    /// @notice Withdraw LP tokens from IglooMaster.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amountShares amount of shares to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 pid, uint256 amountShares, address to) external;

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of PEFI rewards.
    function harvest(uint256 pid, address to) external;
    /// @notice Withdraw LP tokens from IglooMaster.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amountShares amount of shares to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdrawAndHarvest(uint256 pid, uint256 amountShares, address to) external ;

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) external;

    //set your own personal ipefiDistributionBips
    function setIpefiDistributionBips(uint256 _ipefiDistributionBips) external;

    //OWNER-ONLY FUNCTIONS
    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// @param _allocPoint AP of the new pool.
    /// @param _withdrawFeeBP withdrawal fee of the pool.
    /// @param _poolToken Address of the LP ERC-20 token.
    /// @param _withUpdate True if massUpdatePools should be called prior to pool updates.
    /// @param _rewarder Address of the rewarder delegate.
    function add(uint256 _allocPoint, uint16 _withdrawFeeBP, IERC20 _poolToken, bool _withUpdate, IRewarder _rewarder, IIglooStrategy _strategy) 
        external;
    /// @notice Update the given pool's PEFI allocation point, withdrawal fee, and `IRewarder` contract. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    /// @param _withdrawFeeBP New withdrawal fee of the pool.
    /// @param _rewarder Address of the rewarder delegate.
    /// @param _withUpdate True if massUpdatePools should be called prior to pool updates.
    /// @param overwrite True if _rewarder should be `set`. Otherwise `_rewarder` is ignored.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint16 _withdrawFeeBP,
        IRewarder _rewarder,
        bool _withUpdate,
        bool overwrite
    ) external;
    //used to migrate an igloo from using one strategy to another
    function migrateStrategy(uint256 pid, IIglooStrategy newStrategy) external;

    // used in emergencies, or if setup of an igloo fails
    function setStrategy(uint256 pid, IIglooStrategy newStrategy, bool transferOwnership, address newOwner) 
        external;

    function manualMint(address dest, uint256 amount) external;

    function transferMinter(address newMinter) external  ;
    function setDev(address _dev) external ;
    function setNest(address _nest) external ;

    function setNestAllocatorAddress(address _nestAllocatorAddress) external;

    function setPerfomanceFeeAddress(address _performanceFeeAddress) external;

    function setDevMintBips(uint256 _devMintBips) external;    

    function setNestMintBips(uint256 _nestMintBips) external;

    function setNestSplitBips(uint256 _nestSplitBips) external ;

    function setPefiEmission(uint256 newPefiEmissionPerSecond, bool withUpdate) external ;

    function setDefaultIpefiDistributionBips(uint256 _defaultIpefiDistributionBips) external  ;

}
    

