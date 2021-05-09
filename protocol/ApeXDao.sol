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
    
}