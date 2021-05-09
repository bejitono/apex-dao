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
    
    /* ========== Mutative Functions ========== */
    
    function _createPool(Pool memory pool) internal {
        pools[poolCount] = pool;
        poolInitialized[poolCount] = true;
        poolCount = poolCount.add(1);
        emit PoolCreated(poolCount - 1, pool.poolToken, pool.investmentToken);
    }
}