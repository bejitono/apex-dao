 // SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "../dependencies/IERC20.sol";
import "../dependencies/ReentrancyGuard.sol";
import "../dependencies/SafeERC20.sol";
import "../dependencies/SafeMath.sol";
import "../adapters/SwapAdapter.sol";


contract ApeXDao is ReentrancyGuard {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Pool {
        address poolToken;
        uint256 poolBalance;
        address investmentToken;
        uint256 investmentBalance;
        uint256 executionThreshold;
        State state;
        // TODO: add time limit, e.g. periodFinish
    }
    
    enum State {
        open,
        readyToDeploy,
        deployed,
        liquidated,
        canceled
    }

    /* ============ Events ============ */
    
    event PoolStateChanged(uint256 indexed poolId, State indexed state);
    event PoolCreated(uint256 indexed poolId, address indexed poolToken, address indexed investmentToken);
    event StakeAdded(uint256 indexed poolId, address indexed user, uint256 amount);
    event StakeWithdrawn(uint256 indexed poolId, address indexed user, uint256 amount);

    /* ============ Modifiers ============ */
    
    modifier onlyInitialized(uint256 poolId) {
        require(poolInitialized[poolId], "Pool does not exist");
        _;
    }

    /* ============ State Variables ============ */
    
    ISwapAdapter swapAdapter;
    
    uint256 public poolCount;
    mapping (uint256 => Pool) public pools;
    mapping (uint256 => bool) public poolInitialized;
    // User address => Pool ID => User balance
    mapping (address => mapping (uint256 => uint256)) private userPoolBalances;
    mapping (address => bool) poolTokenWhitelist; // TODO: handle whitelisting, add only wETH for now and add admin functions to update
    
    /* ============ Constructor ============ */
    
    /**
     * Set state variables
     *
     * @param _swapAdapter Swap adapter handling swaps
     */
    constructor(ISwapAdapter _swapAdapter) {
        swapAdapter = _swapAdapter;
    }
    
    /* ============ External Functions ============ */
    
    /** 
     * @notice Creates a new pool
     * @param poolToken The address of the token that is pooled
     * @param investmentToken The address of the token that will be invested in
     * @param executionThreshold The threshold amount at which the pool will deploy the pooled assets
     * @return The pool Id for the newly created pool
     */
    function createPool(
        address poolToken,
        address investmentToken,
        uint256 executionThreshold
    ) external nonReentrant returns (uint256) {
        require(poolToken != address(0), "Token address can not be zero");
        require(investmentToken != address(0), "Token address can not be zero");
        require(executionThreshold > 0, "Threshold must be higher than 0");
        
        Pool memory pool = Pool({
            poolToken: poolToken,
            poolBalance: 0,
            investmentToken: investmentToken,
            investmentBalance: 0,
            executionThreshold: executionThreshold,
            state: State.open
        });
        
        _createPool(pool);
        return poolCount - 1;
    }
    
    function stake(uint256 poolId, uint256 amount) external nonReentrant onlyInitialized(poolId) {
        Pool storage pool = pools[poolId];
        
        require(amount > 0, "Cannot stake 0");
        require(pool.state == State.open, "Pool has been deployed or canceled");
        
        _addStake(pool, poolId, msg.sender, amount);
        _updateStateIfNeeded(pool, poolId);
    }
    
    function withdrawStake(uint256 poolId, uint256 amount) external nonReentrant onlyInitialized(poolId) {
        Pool storage pool = pools[poolId];
        
        require(amount > 0, "Cannot withdraw 0");
        require(pool.state == State.open, "Pool has been deployed or canceled");
        require(userPoolBalances[msg.sender][poolId] >= amount, "User has insufficient balance");
        require(pool.poolBalance >= amount, "Pool has insufficient balance");

        _withdrawStake(pool, poolId, msg.sender, amount);
    }
    
    function deploy(uint256 poolId) external nonReentrant onlyInitialized(poolId) {
        Pool storage pool = pools[poolId];
        
        require(pool.poolBalance > 0, "Cannot deploy pool balance of 0");
        require(pool.poolBalance >= pool.executionThreshold, "Threshold has not been reached yet");
        require(pool.state == State.readyToDeploy, "Pool is not ready to be deployed");
        
        _deploy(pool, poolId);
    }
    
    /**
   * For now this liquidates the entire pool
   */
    function liquidate(uint256 poolId) external nonReentrant onlyInitialized(poolId) {
        Pool storage pool = pools[poolId];
        
        // TODO: check for conditions that allow liquidation
        // if (block.timestamp >= pool.periodFinish) { };
        require(pool.state == State.deployed, "Pool has not been deployed yet");
        require(pool.investmentBalance > 0, "Pool has no invested assets to liquidate");
        
        _liquidate(pool, poolId);
    }
    
    function withdrawLiquidatedAssets(uint256 poolId) external nonReentrant onlyInitialized(poolId) {
        Pool storage pool = pools[poolId];
        uint256 liquidatedAmount = userPoolBalances[msg.sender][poolId];
        
        require(pool.state == State.liquidated, "Pool has not been liquidated yet");
        require(pool.poolBalance >= liquidatedAmount, "Pool has insufficient balance");
        require(liquidatedAmount > 0, "User has not assets to withdraw");
        
        _withdrawStake(pool, poolId, msg.sender, liquidatedAmount);
    }
    
    /* ============ External Getters ============ */
    
    function getPoolToken(uint256 poolId) external view onlyInitialized(poolId) returns (address) {
        return pools[poolId].poolToken;
    }
    
    function getPoolBalance(uint256 poolId) external view onlyInitialized(poolId) returns (uint256) {
        return pools[poolId].poolBalance;
    }
    
    function getPoolThreshold(uint256 poolId) public view onlyInitialized(poolId) returns (uint256) {
        return pools[poolId].executionThreshold;
    }
    
    function getPoolState(uint256 poolId) external view onlyInitialized(poolId) returns (State) {
        return pools[poolId].state;
    }
    
    function checkPoolIsInitialized(uint256 poolId) external view returns (bool) {
        return poolInitialized[poolId];
    }
    
    function getPoolCount() external view returns (uint256) {
        return poolCount;
    }
    
    /* ========== Mutative Functions ========== */
    
    function _createPool(Pool memory pool) internal {
        pools[poolCount] = pool;
        poolInitialized[poolCount] = true;
        poolCount = poolCount.add(1);
        emit PoolCreated(poolCount - 1, pool.poolToken, pool.investmentToken);
    }
    
    function _addStake(Pool storage pool, uint256 poolId, address user, uint256 amount) internal {
        IERC20(pool.poolToken).safeTransferFrom(user, address(this), amount);
        pool.poolBalance = pool.poolBalance.add(amount);
        userPoolBalances[user][poolId] = userPoolBalances[user][poolId].add(amount);
        emit StakeAdded(poolId, user, amount);
    }
    
    function _withdrawStake(Pool storage pool, uint256 poolId, address user, uint256 amount) internal {
        IERC20(pool.poolToken).safeTransfer(user, amount);
        pool.poolBalance = pool.poolBalance.sub(amount);
        userPoolBalances[user][poolId] = userPoolBalances[user][poolId].sub(amount);
        emit StakeWithdrawn(poolId, user, amount);
    }
    
    function _deploy(Pool storage pool, uint256 poolId) internal {
        uint256 investedAmount = swapAdapter.swapExactTokensForTokens(
            pool.poolToken,
            pool.investmentToken,
            pool.poolBalance,
            0, // TODO: Check conventional way of adding minAmountOut
            false
        );
        pool.investmentBalance = investedAmount;
        pool.poolBalance = 0;
        pool.state = State.deployed;
        emit PoolStateChanged(poolId, pool.state);
    }
    
    function _liquidate(Pool storage pool, uint256 poolId) internal {
        // TODO: Liquidate assets
        pool.investmentBalance = 0;
        // pool.poolBalance = liquidatedAmount;
        pool.state = State.liquidated;
        emit PoolStateChanged(poolId, pool.state);
    }
    
    function _updateStateIfNeeded(Pool storage pool, uint256 poolId) internal {
        if (pool.poolBalance >= pool.executionThreshold) {
            pool.state = State.readyToDeploy;
            emit PoolStateChanged(poolId, pool.state);
        }
    }
}