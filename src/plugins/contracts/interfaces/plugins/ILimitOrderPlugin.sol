// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import '../../libraries/EpochLibrary.sol';

interface ILimitOrderPlugin {
  error ZeroLiquidity();
  error InRange();
  error CrossedRange();
  error Filled();
  error NotFilled();
  error NotPoolManagerToken();

  event Place(address indexed owner, Epoch indexed epoch, int24 tickLower, bool zeroForOne, uint128 liquidity);

  event Fill(Epoch indexed epoch, int24 tickLower, bool zeroForOne);

  event Kill(address indexed owner, Epoch indexed epoch, int24 tickLower, bool zeroForOne, uint128 liquidity);

  event Withdraw(address indexed owner, Epoch indexed epoch, uint128 liquidity);

  function place(int24 tickLower, bool zeroForOne, uint128 liquidity) external;

  function kill(int24 tickLower, bool zeroForOne, address to) external returns (uint256 amount0, uint256 amount1);

  function withdraw(int24 tickLower, bool zeroForOne, address to) external returns (uint256 amount0, uint256 amount1);
}
