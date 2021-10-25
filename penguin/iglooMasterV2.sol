// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;


import "./safeErc20.sol";
import "./IglooStrategyStorage.sol";
import "./IStakingRewards.sol";
import "./PenguinNests.sol";
import "./IRewarder.sol";
import "./IPefi.sol";
 



// The IglooMaster is the master of PEFI. He can make PEFI and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once PEFI is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract IglooMaster is Ownable {
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many shares the user currently has
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of PEFIs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPEFIPerShare) / ACC_PEFI_PRECISION - user.rewardDebt
        //
        // Whenever a user harvest from a pool, here's what happens:
        //   1. The pool's `accPEFIPerShare` gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 poolToken; // Address of LP token contract.
        IRewarder rewarder; // Address of rewarder for pool
        IIglooStrategy strategy; // Address of strategy for pool
        uint256 allocPoint; // How many allocation points assigned to this pool. PEFIs to distribute per block.
        uint256 lastRewardTime; // Last block number that PEFIs distribution occurs.
        uint256 accPEFIPerShare; // Accumulated PEFIs per share, times ACC_PEFI_PRECISION. See below.
        uint16 withdrawFeeBP; // Withdrawal fee in basis points
        uint256 totalShares; //total number of shares in the pool
        uint256 lpPerShare; //number of LP tokens per share, times ACC_PEFI_PRECISION
    }

    // The PEFI TOKEN!
    PEFI public immutable pefi;
    // The timestamp when PEFI mining starts.
    uint256 public startTime;
    //development endowment
    address public dev;
    //nest address
    address public nest;
    //nest allocator -- processes fees to go to nest
    address public nestAllocatorAddress;
    //performance fee address -- receives performance fees from strategies
    address public performanceFeeAddress;
    // amount of PEFI emitted per second
    uint256 public pefiEmissionPerSecond;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    //allocations to dev and nest addresses, expressed in BIPS
    uint256 public devMintBips = 1000;
    uint256 public nestMintBips = 500;
    //when a withdrawal occurs and a nonzero fee is charged, nestSplitBips * fee / 10,000 goes to the nestAllocatorAddress
    //the remainder of the fee is distributed to all the other penguins still in the igloo
    uint256 public nestSplitBips = 5000;
    //default value for ipefiDistributionBips, if the user has not manually set it
    uint256 public defaultIpefiDistributionBips;
    //whether the onlyApprovedContractOrEOA is turned on or off
    bool public onlyApprovedContractOrEOAStatus;

    uint256 public constant PEFI_MAX_SUPPLY = 23e6 * 1e18;
    uint256 internal constant ACC_PEFI_PRECISION = 1e18;
    uint256 internal constant MAX_BIPS = 10000;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    //mappping for tracking contracts approved to build on top of this one
    mapping(address => bool) public approvedContracts;
    //when a user harvests, ipefiDistributionBips / 10,000 of it is distributed as ipefi, with the remainder distributed as pefi
    mapping(address => uint256) public ipefiDistributionBips;
    //checks if a user has ever manually set their own ipefiDistributionBips. if not the default value is used.
    mapping(address => bool) public ipefiDistributionBipsSet;
    //tracks historic deposits of each address. deposits[pid][user] is the total deposits for that user to that igloo
    mapping(uint256 => mapping(address => uint256)) public deposits;
    //tracks historic withdrawals of each address. deposits[pid][user] is the total withdrawals for that user from that igloo
    mapping(uint256 => mapping(address => uint256)) public withdrawals;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 indexed pid, uint256 amountIPEFI, uint256 amountPEFI);
    event DevSet(address indexed oldAddress, address indexed newAddress);
    event NestSet(address indexed oldAddress, address indexed newAddress);
    event NestAllocatorAddressSet(address indexed oldAddress, address indexed newAddress);
    event PerformanceFeeAddressSet(address indexed oldAddress, address indexed newAddress);

    /**
     * @notice Throws if called by smart contract
     */
    modifier onlyApprovedContractOrEOA() {
        if (onlyApprovedContractOrEOAStatus) {
            require(tx.origin == msg.sender || approvedContracts[msg.sender], "IglooMaster::onlyApprovedContractOrEOA");
        }
        _;
    }

    constructor(
        PEFI _pefi,
        uint256 _startTime,
        address _dev,
        address _nest,
        address _nestAllocatorAddress,
        address _performanceFeeAddress,
        uint256 _pefiEmissionPerSecond 
    ) {
        require(_startTime > block.timestamp, "must start in future");
        pefi = _pefi;
        startTime = _startTime;
        dev = _dev;
        nest = _nest;
        nestAllocatorAddress = _nestAllocatorAddress;
        pefiEmissionPerSecond = _pefiEmissionPerSecond;
        emit DevSet(address(0), _dev);
        emit NestSet(address(0), _nest);
        emit NestAllocatorAddressSet(address(0), _nestAllocatorAddress);
        emit PerformanceFeeAddressSet(address(0), _performanceFeeAddress);
    }

    //VIEW FUNCTIONS
    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see total pending reward in PEFI on frontend.
    function totalPendingPEFI(uint256 pid, address penguin) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][penguin];
        uint256 accPEFIPerShare = pool.accPEFIPerShare;
        uint256 poolShares = pool.totalShares;
        if (block.timestamp > pool.lastRewardTime && poolShares != 0) {
            uint256 pefiReward = (reward(pool.lastRewardTime, block.timestamp) * pool.allocPoint) / totalAllocPoint;
            uint256 toDev = (pefiReward * devMintBips) / MAX_BIPS;
            uint256 toNest = (pefiReward * nestMintBips) / MAX_BIPS;
            uint256 finalReward = pefiReward - (toDev + toNest);
            accPEFIPerShare = accPEFIPerShare + (
                (finalReward * ACC_PEFI_PRECISION) / poolShares
            );
        }
        return ((user.amount * accPEFIPerShare) / ACC_PEFI_PRECISION) - user.rewardDebt;
    }

    // similar to totalPendingPEFI, but takes ipefiDistributionBips into account 
    function pendingPEFI(uint256 pid, address user) public view returns (uint256) {
        uint256 totalPending = totalPendingPEFI(pid, user);
        uint256 ipefiBips = ipefiDistributionBipsByUser(user);
        uint256 pefiReward = (totalPending * (MAX_BIPS - ipefiBips)) / MAX_BIPS;
        return pefiReward;
    }

    // similar to totalPendingPEFI, but takes ipefiDistributionBips and conversion to ipefi into account
    function pendingIPEFI(uint256 pid, address user) public view returns (uint256) {
        uint256 totalPending = totalPendingPEFI(pid, user);
        uint256 ipefiBips = ipefiDistributionBipsByUser(user);
        uint256 pefiAmount = (totalPending * ipefiBips) / MAX_BIPS;
        uint256 ipefiReward = (pefiAmount * 1e18) / PenguinNests(nest).currentExchangeRate();
        return ipefiReward;
    }

    // View function to see total pending reward in PEFI and IPEFI on frontend.
    function pendingRewards(uint256 pid, address user) public view returns (uint256, uint256) {
        return (pendingPEFI(pid, user), pendingIPEFI(pid, user));
    }

    // view function to get all pending rewards, from IglooMaster, Strategy, and Rewarder
    function pendingTokens(uint256 pid, address user) external view 
        returns (address[] memory, uint256[] memory) {
        uint256 pefiAmount = totalPendingPEFI(pid, user);
        (address[] memory strategyTokens, uint256[] memory strategyRewards) = 
            poolInfo[pid].strategy.pendingTokens(pid, user, pefiAmount);
        address[] memory rewarderTokens;
        uint256[] memory rewarderRewards;
        if (address(poolInfo[pid].rewarder) != address(0)) {
            (rewarderTokens, rewarderRewards) = 
                poolInfo[pid].rewarder.pendingTokens(pid, user, pefiAmount);
        }
        //default number of rewards for just PEFI and IPEFI
        uint256 rewardsLength = 2; 
        for (uint256 i = 0; i < rewarderTokens.length; i++) {
            rewardsLength += 1;
        }
        for (uint256 j = 0; j < strategyTokens.length; j++) {
            if (strategyTokens[j] != address(0)) {
                rewardsLength += 1;
            }
        }
        address[] memory _rewardTokens = new address[](rewardsLength);
        uint256[] memory _pendingAmounts = new uint256[](rewardsLength);
        _rewardTokens[0] = address(pefi);
        _rewardTokens[1] = address(nest);
        (_pendingAmounts[0], _pendingAmounts[1]) = pendingRewards(pid, user);
        for (uint256 k = 0; k < rewarderTokens.length; k++) {
            _rewardTokens[k + 2] = rewarderTokens[k];
            _pendingAmounts[k + 2] = rewarderRewards[k];
        }
        for (uint256 m = 0; m < strategyTokens.length; m++) {
            if (strategyTokens[m] != address(0)) {
                _rewardTokens[m + 2 + rewarderTokens.length] = strategyTokens[m];
                _pendingAmounts[m + 2 + rewarderRewards.length] = strategyRewards[m];                
            }
        }
        return(_rewardTokens, _pendingAmounts);
    }

    // Return reward over the period _from to _to.
    function reward(uint256 _lastRewardTime, uint256 _currentTime) public view returns (uint256) {
        return ((_currentTime - _lastRewardTime) * pefiEmissionPerSecond);
    }

    //convenience function to get the yearly emission of PEFI at the current emission rate
    function pefiPerYear() public view returns(uint256) {
        //31536000 = seconds per year = 365 * 24 * 60 * 60
        return (pefiEmissionPerSecond * 31536000);
    }

    //convenience function to get the yearly emission of PEFI at the current emission rate, to a given igloo
    function pefiPerYearToIgloo(uint256 pid) public view returns(uint256) {
        return ((pefiPerYear() * poolInfo[pid].allocPoint) / totalAllocPoint);
    }

    //convenience function to get the yearly emission of PEFI at the current emission rate, to the nest
    function pefiPerYearToNest() public view returns(uint256) {
        return ((pefiPerYear() * nestMintBips) / MAX_BIPS);
    }

    //fetches nest simple APY at current PEFI emission rate. returned value is multiplier *scaled up by ACC_PEFI_PRECISION*
    function nestAPY() public view returns(uint256) {
        uint256 pefiInNest = pefi.balanceOf(nest);
        return (pefiPerYearToNest() * ACC_PEFI_PRECISION) / pefiInNest;
    }

    //convenience function to get the total number of shares in an igloo
    function totalShares(uint256 pid) public view returns(uint256) {
        return poolInfo[pid].totalShares;
    }

    //convenience function to get the total amount of LP tokens in an igloo
    function totalLP(uint256 pid) public view returns(uint256) {
        return (poolInfo[pid].lpPerShare * totalShares(pid) / ACC_PEFI_PRECISION);
    }

    //convenience function to get the shares of a single user in an igloo
    function userShares(uint256 pid, address user) public view returns(uint256) {
        return userInfo[pid][user].amount;
    }

    //returns user profits in LP (returns zero in the event that user has losses due to previous withdrawal fees)
    function profitInLP(uint256 pid, address userAddress) public view returns(uint256) {
        UserInfo storage user = userInfo[pid][userAddress];
        PoolInfo storage pool = poolInfo[pid];
        uint256 userDeposits = deposits[pid][userAddress];
        uint256 userWithdrawals = withdrawals[pid][userAddress];
        uint256 lpFromShares = (user.amount * pool.lpPerShare) / ACC_PEFI_PRECISION;
        uint256 totalAssets = userWithdrawals + lpFromShares;
        if(totalAssets >= userDeposits) {
            return (totalAssets - userDeposits);
        } else {
            return 0;
        }
    }

    //function for fetching the current ipefiDistributionBips of a user
    function ipefiDistributionBipsByUser(address user) public view returns (uint256) {
        uint256 ipefiBips = ipefiDistributionBipsSet[user] ? ipefiDistributionBips[user] : defaultIpefiDistributionBips;
        return ipefiBips;
    }

    //WRITE FUNCTIONS
    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    function updatePool(uint256 pid) public {
        PoolInfo storage pool = poolInfo[pid];
        if (block.timestamp > pool.lastRewardTime) {
            uint256 poolShares = pool.totalShares;
            if (poolShares == 0 || pool.allocPoint == 0) {
                pool.lastRewardTime = block.timestamp;
                return;
            }
            uint256 pefiReward = (reward(pool.lastRewardTime, block.timestamp) * pool.allocPoint) / totalAllocPoint;
            pool.lastRewardTime = block.timestamp;
            if (pefiReward > 0) {
                uint256 toDev = (pefiReward * devMintBips) / MAX_BIPS;
                uint256 toNest = (pefiReward * nestMintBips) / MAX_BIPS;
                uint256 finalReward = pefiReward - (toDev + toNest);
                pool.accPEFIPerShare = pool.accPEFIPerShare + (
                    (finalReward * ACC_PEFI_PRECISION) / poolShares
                );
                require((pefi.totalSupply() + pefiReward) <= PEFI_MAX_SUPPLY, "mint would exceed max supply");
                pefi.mint(dev, toDev);
                pefi.mint(nest, toNest);
                pefi.mint(address(this), finalReward);
            }
        }
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    /// @notice Deposit LP tokens to IglooMaster for PEFI allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function deposit(uint256 pid, uint256 amount, address to) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        if (amount > 0) {
            UserInfo storage user = userInfo[pid][to];
            //find number of new shares from amount
            uint256 newShares = (amount * ACC_PEFI_PRECISION) / pool.lpPerShare;

            //transfer tokens directly to strategy
            pool.poolToken.safeTransferFrom(
                address(msg.sender),
                address(pool.strategy),
                amount
            );
            //tell strategy to deposit newly transferred tokens and process update
            pool.strategy.deposit(msg.sender, to, amount, newShares);

            //track new shares
            pool.totalShares = pool.totalShares + newShares;
            user.amount = user.amount + newShares;
            user.rewardDebt = user.rewardDebt + ((newShares * pool.accPEFIPerShare) / ACC_PEFI_PRECISION);
            //track deposit for profit tracking
            deposits[pid][to] += amount;

            //rewarder logic
            IRewarder _rewarder = pool.rewarder;
            if (address(_rewarder) != address(0)) {
                _rewarder.onPefiReward(pid, msg.sender, to, 0, user.amount);
            }
            emit Deposit(msg.sender, pid, amount, to);
        }
    }

    /// @notice Withdraw LP tokens from IglooMaster.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amountShares amount of shares to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdraw(uint256 pid, uint256 amountShares, address to) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amountShares, "withdraw: not good");

        if (amountShares > 0) {
            //find amount of LP tokens from shares
            uint256 lpFromShares = (amountShares * pool.lpPerShare) / ACC_PEFI_PRECISION;

            if (pool.withdrawFeeBP > 0 && pool.totalShares > amountShares) {
                uint256 withdrawFee = (lpFromShares * pool.withdrawFeeBP) / MAX_BIPS;
                uint256 lpToSend = (lpFromShares - withdrawFee);
                //track withdrawal for profit tracking
                withdrawals[pid][to] += lpToSend;
                //tell strategy to withdraw lpTokens, send to 'to', and process update
                pool.strategy.withdraw(msg.sender, to, lpToSend, amountShares);
                if(nestSplitBips > 0) {
                    uint256 amountToNest = (withdrawFee * nestSplitBips) / MAX_BIPS;
                    //tell strategy to withdraw lpTokens, send to the nest allocator, and process update
                    pool.strategy.withdraw(msg.sender, nestAllocatorAddress, amountToNest, 0);
                    //adjust this down by amount sent to nest, for proper redistribution tracking
                    withdrawFee = withdrawFee - amountToNest;
                }
                //increase price per share based on redistributed LP amount
                pool.lpPerShare = pool.lpPerShare + ((withdrawFee * ACC_PEFI_PRECISION) / (pool.totalShares - amountShares));
            } else {
                //track withdrawal for profit tracking
                withdrawals[pid][to] += lpFromShares;
                //tell strategy to withdraw lpTokens, send to 'to', and process update
                pool.strategy.withdraw(msg.sender, to, lpFromShares, amountShares);
            }

            //track removed shares
            user.amount = user.amount - amountShares;
            uint256 rewardDebtOfShares = ((amountShares * pool.accPEFIPerShare) / ACC_PEFI_PRECISION);
            uint256 userRewardDebt = user.rewardDebt;
            user.rewardDebt = (userRewardDebt >= rewardDebtOfShares) ? 
                (userRewardDebt - rewardDebtOfShares) : 0;
            pool.totalShares = pool.totalShares - amountShares;

            //rewarder logic
            IRewarder _rewarder = pool.rewarder;
            if (address(_rewarder) != address(0)) {
                _rewarder.onPefiReward(pid, msg.sender, to, 0, user.amount);
            }

            emit Withdraw(msg.sender, pid, amountShares, to);
        }
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of PEFI rewards.
    function harvest(uint256 pid, address to) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];

        //find all time PEFI rewards for all of user's shares
        uint256 accumulatedPefi = (user.amount * pool.accPEFIPerShare) / ACC_PEFI_PRECISION;
        //subtract out the rewards they have already been entitled to
        uint256 pendingPefi = accumulatedPefi - user.rewardDebt;
        //update user reward debt
        user.rewardDebt = accumulatedPefi;

        uint256 pefiToSend;
        uint256 ipefiToSend;
        //handle PEFI rewards
        if (pendingPefi != 0) {
            uint256 toIPEFI;
            uint256 ipefiBips = ipefiDistributionBipsByUser(to);
            //split to IPEFI & send to 'to'
            if (ipefiBips > 0) {
                toIPEFI = (pendingPefi * ipefiBips) / MAX_BIPS;
                pefi.approve(nest, toIPEFI);
                PenguinNests(nest).enter(toIPEFI);
                IERC20 ipefi = IERC20(nest);
                ipefiToSend = ipefi.balanceOf(address(this));
                ipefi.safeTransfer(to, ipefiToSend);
            }
            //send remainder as PEFI
            pefiToSend = (pendingPefi - toIPEFI);
            if (pefiToSend > 0) {
                safePEFITransfer(to, pefiToSend);
            }
        }

        //call strategy to update
        pool.strategy.withdraw(msg.sender, to, 0, 0);

        //rewarder logic
        IRewarder _rewarder = poolInfo[pid].rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onPefiReward(pid, msg.sender, to, pendingPefi, user.amount);
        }

        emit Harvest(msg.sender, pid, ipefiToSend, pefiToSend);
    }

    /// @notice Withdraw LP tokens from IglooMaster.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amountShares amount of shares to withdraw.
    /// @param to Receiver of the LP tokens.
    function withdrawAndHarvest(uint256 pid, uint256 amountShares, address to) external onlyApprovedContractOrEOA {
        updatePool(pid);
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        require(user.amount >= amountShares, "withdraw: not good");

        //find all time PEFI rewards for all of user's shares
        uint256 accumulatedPefi = (user.amount * pool.accPEFIPerShare) / ACC_PEFI_PRECISION;
        //subtract out the rewards they have already been entitled to
        uint256 pendingPefi = accumulatedPefi - user.rewardDebt;
        //find amount of LP tokens from shares
        uint256 lpFromShares = (amountShares * pool.lpPerShare) / ACC_PEFI_PRECISION;

        if (pool.withdrawFeeBP > 0 && pool.totalShares > amountShares) {
            uint256 withdrawFee = (lpFromShares * pool.withdrawFeeBP) / MAX_BIPS;
            uint256 lpToSend = (lpFromShares - withdrawFee);
            //track withdrawal for profit tracking
            withdrawals[pid][to] += lpToSend;
            //tell strategy to withdraw lpTokens, send to 'to', and process update
            pool.strategy.withdraw(msg.sender, to, lpToSend, amountShares);
            if(nestSplitBips > 0) {
                uint256 amountToNest = (withdrawFee * nestSplitBips) / MAX_BIPS;
                //tell strategy to withdraw lpTokens, send to the nest allocator, and process update
                pool.strategy.withdraw(msg.sender, nestAllocatorAddress, amountToNest, 0);
                //adjust this down by amount sent to nest, for proper redistribution tracking
                withdrawFee = withdrawFee - amountToNest;
            }
            //increase price per share based on redistributed LP amount
            pool.lpPerShare = pool.lpPerShare + ((withdrawFee * ACC_PEFI_PRECISION) / (pool.totalShares - amountShares));
        } else {
            //track withdrawal for profit tracking
            withdrawals[pid][to] += lpFromShares;
            //tell strategy to withdraw lpTokens, send to 'to', and process update
            pool.strategy.withdraw(msg.sender, to, lpFromShares, amountShares);
        }

        //track removed shares
        user.amount = user.amount - amountShares;
        uint256 rewardDebtOfShares = ((amountShares * pool.accPEFIPerShare) / ACC_PEFI_PRECISION);
        user.rewardDebt = accumulatedPefi - rewardDebtOfShares;
        pool.totalShares = pool.totalShares - amountShares;

        uint256 pefiToSend;
        uint256 ipefiToSend;
        //handle PEFI rewards
        if (pendingPefi != 0) {
            uint256 toIPEFI;
            uint256 ipefiBips = ipefiDistributionBipsByUser(to);
            //split to IPEFI & send to 'to'
            if (ipefiBips > 0) {
                toIPEFI = (pendingPefi * ipefiBips) / MAX_BIPS;
                pefi.approve(nest, toIPEFI);
                PenguinNests(nest).enter(toIPEFI);
                IERC20 ipefi = IERC20(nest);
                ipefiToSend = ipefi.balanceOf(address(this));
                ipefi.safeTransfer(to, ipefiToSend);
            }
            //send remainder as PEFI
            pefiToSend = (pendingPefi - toIPEFI);
            if (pefiToSend > 0) {
                safePEFITransfer(to, pefiToSend);
            }
        }

        //rewarder logic
        IRewarder _rewarder = poolInfo[pid].rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onPefiReward(pid, msg.sender, to, pendingPefi, user.amount);
        }

        emit Withdraw(msg.sender, pid, amountShares, to);
        emit Harvest(msg.sender, pid, ipefiToSend, pefiToSend);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) external onlyApprovedContractOrEOA {
        //skip pool update
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 amountShares = user.amount;
        //find amount of LP tokens from shares
        uint256 lpFromShares = (amountShares * pool.lpPerShare) / ACC_PEFI_PRECISION;

        if (pool.withdrawFeeBP > 0 && pool.totalShares > amountShares) {
            uint256 withdrawFee = (lpFromShares * pool.withdrawFeeBP) / MAX_BIPS;
            uint256 lpToSend = (lpFromShares - withdrawFee);
            //track withdrawal for profit tracking
            withdrawals[pid][to] += lpToSend;
            //tell strategy to withdraw lpTokens, send to 'to', and process update
            pool.strategy.withdraw(msg.sender, to, lpToSend, amountShares);
            if(nestSplitBips > 0) {
                uint256 amountToNest = (withdrawFee * nestSplitBips) / MAX_BIPS;
                //tell strategy to withdraw lpTokens, send to the nest allocator, and process update
                pool.strategy.withdraw(msg.sender, nestAllocatorAddress, amountToNest, 0);
                //adjust this down by amount sent to nest, for proper redistribution tracking
                withdrawFee = withdrawFee - amountToNest;
            }
            //increase price per share based on redistributed LP amount
            pool.lpPerShare = pool.lpPerShare + ((withdrawFee * ACC_PEFI_PRECISION) / (pool.totalShares - amountShares));
        } else {
            //track withdrawal for profit tracking
            withdrawals[pid][to] += lpFromShares;
            //tell strategy to withdraw lpTokens, send to 'to', and process update
            pool.strategy.withdraw(msg.sender, to, lpFromShares, amountShares);
        }

        //track removed shares
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalShares = pool.totalShares - amountShares;

        //rewarder logic
        IRewarder _rewarder = pool.rewarder;
        if (address(_rewarder) != address(0)) {
            _rewarder.onPefiReward(pid, msg.sender, to, 0, 0);
        }

        emit EmergencyWithdraw(msg.sender, pid, amountShares, to);
    }

    //set your own personal ipefiDistributionBips
    function setIpefiDistributionBips(uint256 _ipefiDistributionBips) external {
        require(_ipefiDistributionBips <= MAX_BIPS, "input too high");
        //track if user has ever set their own ipefiDistributionBips
        if (!ipefiDistributionBipsSet[msg.sender]) {
            ipefiDistributionBipsSet[msg.sender] = true;
        }
        ipefiDistributionBips[msg.sender] = _ipefiDistributionBips;   
    }

    //OWNER-ONLY FUNCTIONS
    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// @param _allocPoint AP of the new pool.
    /// @param _withdrawFeeBP withdrawal fee of the pool.
    /// @param _poolToken Address of the LP ERC-20 token.
    /// @param _withUpdate True if massUpdatePools should be called prior to pool updates.
    /// @param _rewarder Address of the rewarder delegate.
    function add(uint256 _allocPoint, uint16 _withdrawFeeBP, IERC20 _poolToken, bool _withUpdate, IRewarder _rewarder, IIglooStrategy _strategy) 
        external onlyOwner {
        require(
            _withdrawFeeBP <= 1000,
            "add: withdrawal fee input too high"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime =
            block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                poolToken: _poolToken,
                rewarder: _rewarder,
                strategy: _strategy,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accPEFIPerShare: 0,
                withdrawFeeBP: _withdrawFeeBP,
                totalShares: 0,
                lpPerShare: ACC_PEFI_PRECISION
            })
        );
    }

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
    ) external onlyOwner {
        require(
            _withdrawFeeBP <= 1000,
            "set: withdrawal fee input too high"
        );
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = (totalAllocPoint - poolInfo[_pid].allocPoint) + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].withdrawFeeBP = _withdrawFeeBP;
        if (overwrite) { poolInfo[_pid].rewarder = _rewarder; }
    }

    //used to migrate an igloo from using one strategy to another
    function migrateStrategy(uint256 pid, IIglooStrategy newStrategy) external onlyOwner {
        PoolInfo storage pool = poolInfo[pid];
        //migrate funds from old strategy to new one
        pool.strategy.migrate(address(newStrategy));
        //update strategy in storage
        pool.strategy = newStrategy;
        newStrategy.onMigration();
    }

    //used in emergencies, or if setup of an igloo fails
    function setStrategy(uint256 pid, IIglooStrategy newStrategy, bool transferOwnership, address newOwner) 
        external onlyOwner {
        PoolInfo storage pool = poolInfo[pid];
        if (transferOwnership) {
            pool.strategy.transferOwnership(newOwner);
        }
        pool.strategy = newStrategy;
    }

    function manualMint(address dest, uint256 amount) external onlyOwner {
        require((pefi.totalSupply() + amount) <= PEFI_MAX_SUPPLY, "mint would exceed max supply");
        pefi.mint(dest, amount);
    }

    function transferMinter(address newMinter) external onlyOwner {
        require(newMinter != address(0));
        pefi.setMinter(newMinter);
    }

    function setDev(address _dev) external onlyOwner {
        require(_dev != address(0));
        emit DevSet(dev, _dev);
        dev = _dev;
    }

    function setNest(address _nest) external onlyOwner {
        require(_nest != address(0));
        emit NestSet(nest, _nest);
        nest = _nest;
    }

    function setNestAllocatorAddress(address _nestAllocatorAddress) external onlyOwner {
        require(_nestAllocatorAddress != address(0));
        emit NestAllocatorAddressSet(nestAllocatorAddress, _nestAllocatorAddress);
        nestAllocatorAddress = _nestAllocatorAddress;
    }

    function setPerfomanceFeeAddress(address _performanceFeeAddress) external onlyOwner {
        require(_performanceFeeAddress != address(0));
        emit PerformanceFeeAddressSet(performanceFeeAddress, _performanceFeeAddress);
        performanceFeeAddress = _performanceFeeAddress;
    }

    function setDevMintBips(uint256 _devMintBips) external onlyOwner {
        require(_devMintBips + nestMintBips <= MAX_BIPS, "combined dev & nest splits too high");
        devMintBips = _devMintBips;
    }

    function setNestMintBips(uint256 _nestMintBips) external onlyOwner {
        require(_nestMintBips + devMintBips <= MAX_BIPS, "combined dev & nest splits too high");
        nestMintBips = _nestMintBips;
    }

    function setNestSplitBips(uint256 _nestSplitBips) external onlyOwner {
        require(_nestSplitBips <= MAX_BIPS);
        nestSplitBips = _nestSplitBips;
    }

    function setPefiEmission(uint256 newPefiEmissionPerSecond, bool withUpdate) external onlyOwner {
        if (withUpdate) {
            massUpdatePools();
        }
        pefiEmissionPerSecond = newPefiEmissionPerSecond;
    }

    function setDefaultIpefiDistributionBips(uint256 _defaultIpefiDistributionBips) external onlyOwner {
        require(_defaultIpefiDistributionBips <= MAX_BIPS);
        defaultIpefiDistributionBips = _defaultIpefiDistributionBips;   
    }

    //ACCESS CONTROL FUNCTIONS
    function modifyApprovedContracts(address[] calldata contracts, bool[] calldata statuses) external onlyOwner {
        require(contracts.length == statuses.length, "input length mismatch");
        for (uint256 i = 0; i < contracts.length; i++) {
            approvedContracts[contracts[i]] = statuses[i];
        }
    }

    function setOnlyApprovedContractOrEOAStatus(bool newStatus) external onlyOwner {
        onlyApprovedContractOrEOAStatus = newStatus;
    }

    //STRATEGY MANAGEMENT FUNCTIONS
    function inCaseTokensGetStuck(uint256 pid, IERC20 token, address to, uint256 amount) external onlyOwner {
        IIglooStrategy strat = poolInfo[pid].strategy;
        strat.inCaseTokensGetStuck(token, to, amount);
    }

    function setAllowances(uint256 pid) external onlyOwner {
        IIglooStrategy strat = poolInfo[pid].strategy;
        strat.setAllowances();
    }

    function revokeAllowance(uint256 pid, address token, address spender) external onlyOwner {
        IIglooStrategy strat = poolInfo[pid].strategy;
        strat.revokeAllowance(token, spender);
    }

    function setPerformanceFeeBips(uint256 pid, uint256 newPerformanceFeeBips) external onlyOwner {
        IIglooStrategy strat = poolInfo[pid].strategy;
        strat.setPerformanceFeeBips(newPerformanceFeeBips);
    }

    //STRATEGY-ONLY FUNCTIONS
    //an autocompounding strategy calls this function to account for new LP tokens that it earns
    function accountAddedLP(uint256 pid, uint256 amount) external {
        PoolInfo storage pool = poolInfo[pid];
        require(msg.sender == address(pool.strategy), "only callable by strategy contract");
        pool.lpPerShare = pool.lpPerShare + ((amount * ACC_PEFI_PRECISION) / pool.totalShares);
    }


    //INTERNAL FUNCTIONS
    // Safe PEFI transfer function, just in case if rounding error causes pool to not have enough PEFIs.
    function safePEFITransfer(address _to, uint256 _amount) internal {
        uint256 pefiBal = pefi.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > pefiBal) {
            transferSuccess = pefi.transfer(_to, pefiBal);
        } else {
            transferSuccess = pefi.transfer(_to, _amount);
        }
        require(transferSuccess, "safePEFITransfer: transfer failed");
    }
}