// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

interface ISwapAdapter {
    function swapExactTokensForTokens(
        address assetToSwapFrom,
        address assetToSwapTo,
        uint256 amountToSwap,
        uint256 minAmountOut,
        bool useEthPath
  ) external returns (uint256);
}
