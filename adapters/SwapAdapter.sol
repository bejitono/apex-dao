// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "../dependencies/IERC20.sol";
import "../dependencies/IUniswapV2Router.sol";
import "../dependencies/SafeERC20.sol";
import "../dependencies/SafeMath.sol";
import "./ISwapAdapter.sol";

contract SwapAdapter is ISwapAdapter {
    
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address public immutable WETH_ADDRESS;
    IUniswapV2Router public immutable SWAP_ROUTER;
    
    
    event Swapped(address fromAsset, address toAsset, uint256 fromAmount, uint256 receivedAmount);
    
    constructor(
        address _wethAddress,
        IUniswapV2Router _swapRouter
    ) {
        WETH_ADDRESS = _wethAddress;
        SWAP_ROUTER = _swapRouter;
    }
    
    /**
    * @dev Swaps an exact `amountToSwap` of an asset to another
    * @param assetToSwapFrom Origin asset
    * @param assetToSwapTo Destination asset
    * @param amountToSwap Exact amount of `assetToSwapFrom` to be swapped
    * @param minAmountOut the min amount of `assetToSwapTo` to be received from the swap
    * @return the amount received from the swap
    */
    function swapExactTokensForTokens(
        address assetToSwapFrom,
        address assetToSwapTo,
        uint256 amountToSwap,
        uint256 minAmountOut,
        bool useEthPath
    ) external override returns (uint256) {
    // Approves the transfer for the swap. Approves for 0 first to comply with tokens that implement the anti frontrunning approval fix.
    IERC20(assetToSwapFrom).safeApprove(address(SWAP_ROUTER), 0);
    IERC20(assetToSwapFrom).safeApprove(address(SWAP_ROUTER), amountToSwap);

    address[] memory path;
    if (useEthPath) {
      path = new address[](3);
      path[0] = assetToSwapFrom;
      path[1] = WETH_ADDRESS;
      path[2] = assetToSwapTo;
    } else {
      path = new address[](2);
      path[0] = assetToSwapFrom;
      path[1] = assetToSwapTo;
    }
    uint256[] memory amounts =
      SWAP_ROUTER.swapExactTokensForTokens(
        amountToSwap,
        minAmountOut,
        path,
        address(this),
        block.timestamp
      );

    emit Swapped(assetToSwapFrom, assetToSwapTo, amounts[0], amounts[amounts.length - 1]);

    return amounts[amounts.length - 1];
  }
}
